import {
  CanalPago,
  EstadoCobro,
  OrigenVerificacionPago,
  Prisma,
  type PagoCobro,
  type PrismaClient,
} from "@prisma/client";
import crypto from "crypto";
import {
  crearCobroFactus,
  consultarCobroFactus,
  isFactusPayConfigured,
  FACTUS_MONTO_MIN_COP,
  FACTUS_MONTO_MAX_COP,
  type FactusCollection,
} from "./FactusPayClient";
import { detalleErrorPagos, FactusPayError, PedidoNoConfirmableError } from "./errors";
import { siguienteEsperaMs, VIGENCIA_QR_POR_DEFECTO_MS } from "./backoff";
import { datosPagador, fechaFactus } from "./datosRecaudo";

type TransactionClient = Prisma.TransactionClient;

// Cuando el recaudo todavia no tiene QR (status "started"), Factus lo genera
// casi de inmediato: conviene reconsultar pronto en vez de esperar el primer
// escalon del backoff normal.
const VERIFICACION_INMEDIATA_MS = 2_000;
// Cuanto dura el reclamo de un cobro mientras se consulta a Factus (lo usan
// el worker y el webhook para no consultar el mismo cobro a la vez).
const RECLAMO_MS = 30_000;

export const ESTADOS_ACTIVOS: EstadoCobro[] = [EstadoCobro.CREADO, EstadoCobro.PENDIENTE, EstadoCobro.VENCIDO];
export const ESTADOS_TERMINALES: EstadoCobro[] = [
  EstadoCobro.PAGADO,
  EstadoCobro.FALLIDO,
  EstadoCobro.ABANDONADO,
  EstadoCobro.PAGADO_HUERFANO,
  EstadoCobro.PAGADO_DUPLICADO,
  EstadoCobro.DISCREPANCIA,
  EstadoCobro.ERROR,
  EstadoCobro.DEVUELTO,
  EstadoCobro.RESUELTO,
];
// Terminales sin dinero recibido: solo una respuesta "paid" de Factus los
// reabre (ver reabrirYVerificar).
export const ESTADOS_REABRIBLES: EstadoCobro[] = [EstadoCobro.ABANDONADO, EstadoCobro.FALLIDO, EstadoCobro.ERROR];

export type CrearCobroInput = {
  canal: CanalPago;
  montoEsperado: number;
  pedidoAppId?: number;
  wooOrderId?: string;
  usuarioId?: string;
  // Obligatorio en el canal SALDO_SERVICIO: el saldo que paga el cobro.
  saldoServicioId?: number;
  referencePrefix?: string;
};

export type ConfirmadorPagoContexto = {
  cobroId: number;
  canal: CanalPago;
  pedidoAppId: number | null;
  wooOrderId: string | null;
  usuarioId: string | null;
  saldoServicioId: number | null;
  montoEsperado: Prisma.Decimal;
  referenceCode: string;
};

/**
 * Aplica en el dominio del pedido (o de la orden de WooCommerce) el pago que
 * Factus ya confirmo, DENTRO de la misma transaccion que cierra el cobro.
 * Si el pedido ya no puede confirmarse (por ejemplo, esta CANCELADO), debe
 * lanzar PedidoNoConfirmableError -no un error generico- para que PagoService
 * marque el cobro como huerfano en vez de reintentar indefinidamente.
 */
export type ConfirmadorPago = (tx: TransactionClient, contexto: ConfirmadorPagoContexto) => Promise<void>;

/**
 * Se llama DESPUES de que la transaccion de ConfirmadorPago ya cerro (cobro
 * y pedido/orden ya quedaron en PAGADO de forma durable). Aqui van los
 * avisos de red -notificar al cliente, reflejar el pago en WooCommerce- que
 * no deben decidir si el pago se confirma o no: si fallan, el cobro sigue
 * PAGADO igual y el worker los reintenta (ver pendienteSincronizarWoo). Puede
 * correr mas de una vez para el mismo cobro: debe ser idempotente.
 */
export type PosConfirmacionPago = (cobro: PagoCobro) => Promise<void>;

/**
 * Se llama cuando Factus reporta un cobro como fallido/rechazado (nunca hubo
 * dinero de por medio). Cada canal decide que hacer -avisar al cliente,
 * reflejar "failed" en WooCommerce-; enteramente best-effort, sin cola de
 * reintentos como PosConfirmacionPago.
 */
export type PosFalloPago = (cobro: PagoCobro) => Promise<void>;

/** Aviso best-effort de que un cobro quedo en un estado que requiere revision
 * manual (huerfano, duplicado o con un monto distinto al esperado). */
export type AlertadorAccionManual = (cobro: PagoCobro, motivo: string) => Promise<void>;

/** Cuanto esperar para volver a consultar un cobro pendiente (null = dejar
 * de consultarlo). Ver SaludPagosService.esperaSegunModo. */
export type CalendarioVerificacion = (cobro: PagoCobro, ahora: Date) => number | null;

export function generarReferenceCode(prefijo = "CA"): string {
  const limpio = prefijo.replace(/[^A-Za-z0-9]/g, "").slice(0, 10) || "CA";
  return `${limpio}-${crypto.randomUUID().replace(/-/g, "")}`.slice(0, 100);
}

/**
 * Nucleo de pagos: crea y consulta recaudos en Factus, y es el unico lugar
 * que decide cuando un cobro pasa a PAGADO. No conoce las reglas de un
 * pedido ni de una orden de WooCommerce -eso lo resuelve el confirmador que
 * cada canal registra con registrarConfirmador- para que esta clase se
 * pueda probar y operar sin esas dependencias.
 *
 * Varias vias consultan el mismo cobro a la vez (worker, "Ya pague",
 * webhook, conciliacion), asi que toda escritura de estado es condicional al
 * estado de origen: una respuesta vieja de Factus ("ready") nunca pisa un
 * cobro que otra via ya confirmo.
 */
export class PagoService {
  private confirmadores = new Map<CanalPago, ConfirmadorPago>();
  private posConfirmaciones = new Map<CanalPago, PosConfirmacionPago>();
  private posFallos = new Map<CanalPago, PosFalloPago>();
  private alertador: AlertadorAccionManual | null = null;
  private calendario: CalendarioVerificacion = (cobro, ahora) =>
    siguienteEsperaMs(ahora.getTime() - cobro.creadoEn.getTime());

  constructor(private prisma: PrismaClient) {}

  registrarConfirmador(canal: CanalPago, handler: ConfirmadorPago) {
    this.confirmadores.set(canal, handler);
  }

  registrarPosConfirmacion(canal: CanalPago, handler: PosConfirmacionPago) {
    this.posConfirmaciones.set(canal, handler);
  }

  registrarPosFallo(canal: CanalPago, handler: PosFalloPago) {
    this.posFallos.set(canal, handler);
  }

  registrarAlertador(handler: AlertadorAccionManual) {
    this.alertador = handler;
  }

  /** Reemplaza el backoff de siempre (p. ej. por el calendario disperso del
   * modo webhook, ver services/pagos/wiring.ts). */
  registrarCalendario(calendario: CalendarioVerificacion) {
    this.calendario = calendario;
  }

  async obtenerCobro(cobroId: number) {
    return this.prisma.pagoCobro.findUnique({ where: { id: cobroId } });
  }

  /**
   * Punto de entrada del checkout: crea un cobro nuevo en Factus, o
   * devuelve uno vigente si ya existe uno para el mismo pedido/orden y el
   * mismo monto (sin volver a consultar a Factus: el worker lo mantiene al
   * dia en segundo plano).
   */
  async crearCobro(input: CrearCobroInput): Promise<PagoCobro> {
    if (!isFactusPayConfigured()) {
      throw new FactusPayError("El pago automatico no esta disponible en este momento", 503);
    }
    if (!input.pedidoAppId && !input.wooOrderId) {
      throw new FactusPayError("Falta asociar el cobro a un pedido o a una orden", 500);
    }
    if ((input.canal === CanalPago.SALDO_SERVICIO) !== Boolean(input.saldoServicioId)) {
      throw new FactusPayError("Un cobro de saldo debe ir asociado a su saldo (y solo ese)", 500);
    }

    const monto = Math.round(input.montoEsperado * 100) / 100;
    if (monto < FACTUS_MONTO_MIN_COP || monto > FACTUS_MONTO_MAX_COP) {
      throw new FactusPayError(
        `El monto a cobrar debe estar entre $${FACTUS_MONTO_MIN_COP.toLocaleString("es-CO")} y ` +
          `$${FACTUS_MONTO_MAX_COP.toLocaleString("es-CO")} COP`,
        422,
      );
    }

    const vigente = await this.buscarCobroVigente(input, monto);
    if (vigente) return vigente;

    const ahora = new Date();
    const cobro = await this.prisma.pagoCobro.create({
      data: {
        referenceCode: generarReferenceCode(input.referencePrefix),
        canal: input.canal,
        pedidoAppId: input.pedidoAppId ?? null,
        wooOrderId: input.wooOrderId ?? null,
        usuarioId: input.usuarioId ?? null,
        saldoServicioId: input.saldoServicioId ?? null,
        montoEsperado: new Prisma.Decimal(monto),
        estado: EstadoCobro.CREADO,
        // Hasta cuando la app muestra el QR como vigente (y no ofrece otro):
        // la vigencia por defecto de Factus hasta que informe `qr_expires_at`
        // (ver datosRemotos). Un QR "vencido" en la app debe estarlo tambien
        // en Factus: si no, el cliente podria pagar dos codigos.
        expiraLocalEn: new Date(ahora.getTime() + VIGENCIA_QR_POR_DEFECTO_MS),
        // La primera consulta la hace este mismo request (crearEnFactusYAplicar),
        // que deja agendada la siguiente; el worker solo lo toma si el proceso
        // se cae antes de terminar.
        proximaVerificacion: new Date(ahora.getTime() + 30_000),
      },
    });
    await this.registrarEvento(this.prisma, cobro.id, "CREADO", null, EstadoCobro.CREADO, { montoEsperado: monto });

    return this.crearEnFactusYAplicar(cobro);
  }

  private async buscarCobroVigente(
    input: { canal: CanalPago; pedidoAppId?: number; wooOrderId?: string; saldoServicioId?: number },
    monto: number,
  ): Promise<PagoCobro | null> {
    // El cobro del saldo y el del pedido (anticipo) son de la misma orden pero
    // no se reemplazan entre si.
    const porDuenio: Prisma.PagoCobroWhereInput = input.saldoServicioId
      ? { saldoServicioId: input.saldoServicioId }
      : {
          ...(input.pedidoAppId ? { pedidoAppId: input.pedidoAppId } : { wooOrderId: input.wooOrderId }),
          canal: { not: CanalPago.SALDO_SERVICIO },
        };
    return this.prisma.pagoCobro.findFirst({
      where: {
        ...porDuenio,
        estado: { in: ESTADOS_ACTIVOS },
        expiraLocalEn: { gt: new Date() },
        montoEsperado: new Prisma.Decimal(monto),
      },
      orderBy: { creadoEn: "desc" },
    });
  }

  private async crearEnFactusYAplicar(cobro: PagoCobro): Promise<PagoCobro> {
    let remoto: FactusCollection;
    try {
      remoto = await crearCobroFactus(cobro.referenceCode, Number(cobro.montoEsperado));
    } catch (error) {
      await this.registrarFalloConsulta(cobro, error, OrigenVerificacionPago.USUARIO);
      throw error;
    }
    return this.aplicarRespuestaFactus(cobro, remoto, OrigenVerificacionPago.USUARIO);
  }

  /**
   * Consulta a Factus ahora mismo y aplica lo que responda. La usan el worker,
   * el boton "Ya pague", el webhook y la conciliacion (`origen` queda en la
   * bitacora). No hace nada si el cobro ya esta en un estado terminal: asi
   * "Ya pague" sobre un cobro que el webhook ya confirmo responde sin llamar
   * a Factus.
   */
  async verificarCobro(
    cobroId: number,
    origen: OrigenVerificacionPago = OrigenVerificacionPago.WORKER,
  ): Promise<PagoCobro> {
    const cobro = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroId } });
    if (ESTADOS_TERMINALES.includes(cobro.estado)) return cobro;

    let remoto: FactusCollection | null;
    try {
      remoto = await consultarCobroFactus(cobro.referenceCode);
      if (!remoto) {
        // Nunca llego a crearse en Factus (por ejemplo, el proceso se cayo
        // justo despues de insertar localmente). El POST es idempotente por
        // reference_code, asi que reintentarlo es seguro.
        remoto = await crearCobroFactus(cobro.referenceCode, Number(cobro.montoEsperado));
      }
    } catch (error) {
      return this.registrarFalloConsulta(cobro, error, origen);
    }
    return this.aplicarRespuestaFactus(cobro, remoto, origen);
  }

  /**
   * La conciliacion (o el webhook) dice que un cobro esta pagado aunque aqui
   * quedo ABANDONADO, FALLIDO o ERROR (terminales que verificarCobro ya no
   * consulta). Consulta a Factus y SOLO si la API responde "paid" lo reabre
   * y lo confirma por el camino normal; si no, lo deja como estaba -un aviso
   * falso no reabre nada ni repite el aviso de pago fallido-.
   */
  async reabrirYVerificar(
    cobroId: number,
    origen: OrigenVerificacionPago = OrigenVerificacionPago.CONCILIACION,
  ): Promise<PagoCobro> {
    const actual = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroId } });
    if (!ESTADOS_REABRIBLES.includes(actual.estado)) return this.verificarCobro(cobroId, origen);

    let remoto: FactusCollection | null;
    try {
      remoto = await consultarCobroFactus(actual.referenceCode);
    } catch (error) {
      await this.registrarEvento(this.prisma, cobroId, "ERROR", actual.estado, actual.estado, {
        error: this.mensajeError(error),
        origen,
      });
      return actual;
    }
    if (!remoto || remoto.status !== "paid") {
      await this.registrarEvento(this.prisma, cobroId, "CONSULTA", actual.estado, actual.estado, {
        estadoProveedor: remoto?.status ?? "no_existe",
        origen,
      });
      return actual;
    }

    const reabierto = await this.prisma.pagoCobro.updateMany({
      where: { id: cobroId, estado: actual.estado },
      data: { estado: EstadoCobro.PENDIENTE },
    });
    if (reabierto.count === 0) return this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroId } });
    await this.registrarEvento(this.prisma, cobroId, "ACCION_MANUAL", actual.estado, EstadoCobro.PENDIENTE, {
      motivo:
        origen === OrigenVerificacionPago.WEBHOOK
          ? "webhook: Factus confirma el recaudo pagado"
          : "conciliacion: Factus confirma el recaudo pagado",
      origen,
    });
    const pendiente = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroId } });
    return this.aplicarRespuestaFactus(pendiente, remoto, origen);
  }

  /**
   * Reclama un cobro activo por un momento para consultarlo sin que otra via
   * (worker, otra entrega del webhook) lo consulte a la vez. false si ya
   * esta reclamado o ya no esta activo.
   */
  async reclamarParaVerificar(cobroId: number): Promise<boolean> {
    const ahora = new Date();
    const res = await this.prisma.pagoCobro.updateMany({
      where: {
        id: cobroId,
        estado: { in: ESTADOS_ACTIVOS },
        OR: [{ lockedUntil: null }, { lockedUntil: { lt: ahora } }],
      },
      data: { lockedUntil: new Date(ahora.getTime() + RECLAMO_MS) },
    });
    return res.count > 0;
  }

  /**
   * Cierra un cobro pendiente cuyo QR ya vencio sin pago (la conciliacion lo
   * llama despues de una ultima consulta). Si Factus lo cobra igual, el
   * webhook o la conciliacion lo reabren por reabrirYVerificar.
   */
  async cerrarVencido(cobroId: number, motivo: string): Promise<boolean> {
    const actual = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroId } });
    const res = await this.prisma.pagoCobro.updateMany({
      where: { id: cobroId, estado: { in: ESTADOS_ACTIVOS } },
      data: { estado: EstadoCobro.ABANDONADO, proximaVerificacion: null, lockedUntil: null },
    });
    if (res.count === 0) return false;
    await this.registrarEvento(this.prisma, cobroId, "CAMBIO_ESTADO", actual.estado, EstadoCobro.ABANDONADO, {
      motivo,
      origen: OrigenVerificacionPago.CONCILIACION,
    });
    return true;
  }

  /** Suelta el reclamo de reclamarParaVerificar cuando la consulta fallo
   * con un error inesperado (si termina bien, la propia escritura lo suelta). */
  async liberarReclamo(cobroId: number): Promise<void> {
    await this.prisma.pagoCobro.updateMany({
      where: { id: cobroId, lockedUntil: { not: null } },
      data: { lockedUntil: null },
    });
  }

  /** Toma hasta `limite` cobros listos para verificar y marca un lock corto
   * para que otra instancia del worker no los tome al mismo tiempo. */
  async reclamarPendientes(limite: number): Promise<number[]> {
    const ahora = new Date();
    const candidatos = await this.prisma.pagoCobro.findMany({
      where: {
        estado: { in: ESTADOS_ACTIVOS },
        proximaVerificacion: { lte: ahora },
        OR: [{ lockedUntil: null }, { lockedUntil: { lt: ahora } }],
      },
      orderBy: { proximaVerificacion: "asc" },
      take: limite,
      select: { id: true },
    });
    const ids = candidatos.map((c) => c.id);
    if (!ids.length) return [];

    const lockedUntil = new Date(ahora.getTime() + RECLAMO_MS);
    await this.prisma.pagoCobro.updateMany({
      where: { id: { in: ids }, OR: [{ lockedUntil: null }, { lockedUntil: { lt: ahora } }] },
      data: { lockedUntil },
    });
    return ids;
  }

  /** Llamado por PagoReconciler en cada vuelta. */
  async procesarPendientes(limite = 20): Promise<{ procesados: number; errores: number }> {
    const ids = await this.reclamarPendientes(limite);
    let errores = 0;
    for (const id of ids) {
      try {
        await this.verificarCobro(id, OrigenVerificacionPago.WORKER);
      } catch (error) {
        errores++;
        console.error("[pagos] fallo al verificar un cobro", { cobroId: id, ...detalleErrorPagos(error) });
      }
    }
    await this.reintentarPosConfirmaciones();
    return { procesados: ids.length, errores };
  }

  /**
   * Reintenta los avisos posteriores (reflejar el pago en WooCommerce,
   * notificar) de los cobros que ya quedaron PAGADO pero cuyos avisos no
   * terminaron (pendienteSincronizarWoo): porque fallaron o porque el
   * proceso se cayo justo despues de confirmar. El dinero y el pedido ya
   * estan bien; esto solo pone al dia lo demas. Espera 60 s entre intentos.
   */
  async reintentarPosConfirmaciones(limite = 10): Promise<void> {
    const cobros = await this.prisma.pagoCobro.findMany({
      where: {
        estado: EstadoCobro.PAGADO,
        pendienteSincronizarWoo: true,
        actualizadoEn: { lt: new Date(Date.now() - 60_000) },
      },
      orderBy: { actualizadoEn: "asc" },
      take: limite,
    });
    for (const cobro of cobros as PagoCobro[]) {
      const hook = this.posConfirmaciones.get(cobro.canal);
      if (!hook) {
        await this.prisma.pagoCobro.update({ where: { id: cobro.id }, data: { pendienteSincronizarWoo: false } });
        continue;
      }
      try {
        await hook(cobro);
        await this.prisma.pagoCobro.update({ where: { id: cobro.id }, data: { pendienteSincronizarWoo: false } });
        await this.registrarEvento(this.prisma, cobro.id, "SYNC_WOO", null, null, { ok: true, reintento: true });
      } catch (error) {
        // Se toca actualizadoEn para respetar la espera entre intentos.
        await this.prisma.pagoCobro.update({
          where: { id: cobro.id },
          data: { intentosVerificacion: { increment: 1 } },
        });
        console.error("[pagos] reintento de sincronizacion fallido", {
          cobroId: cobro.id,
          name: error instanceof Error ? error.name : "Error",
        });
      }
    }
  }

  async obtenerCobroPorReferencia(referenceCode: string) {
    return this.prisma.pagoCobro.findUnique({ where: { referenceCode } });
  }

  /**
   * Deja un cobro ya PAGADO como huerfano cuando el canal detecta, DESPUES de
   * confirmarlo, que la orden/pedido no se puede marcar pagado (por ejemplo,
   * una orden de WooCommerce cancelada). Genera la alerta de revision manual.
   */
  async marcarHuerfano(cobroId: number, motivo: string): Promise<PagoCobro> {
    const res = await this.prisma.pagoCobro.updateMany({
      where: { id: cobroId, estado: EstadoCobro.PAGADO },
      data: { estado: EstadoCobro.PAGADO_HUERFANO, pendienteSincronizarWoo: false },
    });
    const cobro = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroId } });
    if (res.count > 0) {
      await this.registrarEvento(this.prisma, cobroId, "CAMBIO_ESTADO", EstadoCobro.PAGADO, EstadoCobro.PAGADO_HUERFANO, {
        motivo,
      });
      await this.avisarAccionManual(cobro, motivo);
    }
    return cobro;
  }

  /** Lo que Factus informa del recaudo y se guarda en cualquier respuesta. */
  private datosRemotos(cobroActual: PagoCobro, remoto: FactusCollection, origen: OrigenVerificacionPago) {
    const qrExpiraEn = fechaFactus(remoto.qr_expires_at) ?? cobroActual.qrExpiraEn;
    return {
      estadoProveedor: remoto.status,
      montoProveedor: new Prisma.Decimal(remoto.amount),
      qrBase64: remoto.qr ?? cobroActual.qrBase64,
      qrExpiraEn,
      // La vigencia que ve el cliente es la real de Factus cuando se conoce.
      expiraLocalEn: qrExpiraEn ?? cobroActual.expiraLocalEn,
      brebKey: remoto.breb_key ?? cobroActual.brebKey,
      ...datosPagador(remoto.payer),
      ultimaVerificacionEn: new Date(),
      ultimaVerificacionOrigen: origen,
    };
  }

  private async aplicarRespuestaFactus(
    cobroActual: PagoCobro,
    remoto: FactusCollection,
    origen: OrigenVerificacionPago,
  ): Promise<PagoCobro> {
    if (remoto.status === "paid") {
      return this.confirmarPago(cobroActual, remoto, origen);
    }

    if (remoto.status === "failed" || remoto.status === "rejected") {
      const res = await this.prisma.pagoCobro.updateMany({
        where: { id: cobroActual.id, estado: { in: ESTADOS_ACTIVOS } },
        data: {
          ...this.datosRemotos(cobroActual, remoto, origen),
          estado: EstadoCobro.FALLIDO,
          proximaVerificacion: null,
          lockedUntil: null,
          intentosVerificacion: { increment: 1 },
        },
      });
      const actualizado = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroActual.id } });
      // Otra via ya lo cerro mientras se consultaba (p. ej. lo confirmo).
      if (res.count === 0) return actualizado;
      await this.registrarEvento(this.prisma, cobroActual.id, "CAMBIO_ESTADO", cobroActual.estado, EstadoCobro.FALLIDO, {
        estadoProveedor: remoto.status,
        origen,
      });
      await this.ejecutarPosFallo(actualizado);
      return actualizado;
    }

    // "started" o "ready": sigue pendiente de pago.
    const ahora = new Date();
    const datos = this.datosRemotos(cobroActual, remoto, origen);
    const conDatos = { ...cobroActual, qrExpiraEn: datos.qrExpiraEn, expiraLocalEn: datos.expiraLocalEn };
    const espera = !remoto.qr ? VERIFICACION_INMEDIATA_MS : this.calendario(conDatos, ahora);
    const vencidoLocal = conDatos.expiraLocalEn != null && ahora > conDatos.expiraLocalEn;

    const nuevoEstado =
      espera == null ? EstadoCobro.ABANDONADO : vencidoLocal ? EstadoCobro.VENCIDO : EstadoCobro.PENDIENTE;
    const proximaVerificacion = espera == null ? null : new Date(ahora.getTime() + espera);

    const res = await this.prisma.pagoCobro.updateMany({
      where: { id: cobroActual.id, estado: { in: ESTADOS_ACTIVOS } },
      data: {
        ...datos,
        estado: nuevoEstado,
        proximaVerificacion,
        lockedUntil: null,
        intentosVerificacion: { increment: 1 },
      },
    });
    const actualizado = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroActual.id } });
    if (res.count === 0) return actualizado;
    await this.registrarEvento(
      this.prisma,
      cobroActual.id,
      nuevoEstado !== cobroActual.estado ? "CAMBIO_ESTADO" : "CONSULTA",
      cobroActual.estado,
      nuevoEstado,
      { estadoProveedor: remoto.status, origen },
    );
    return actualizado;
  }

  private async confirmarPago(
    cobroActual: PagoCobro,
    remoto: FactusCollection,
    origen: OrigenVerificacionPago,
  ): Promise<PagoCobro> {
    const montoProveedor = new Prisma.Decimal(remoto.amount);
    if (!montoProveedor.equals(cobroActual.montoEsperado)) {
      const res = await this.prisma.pagoCobro.updateMany({
        where: { id: cobroActual.id, estado: { notIn: ESTADOS_TERMINALES } },
        data: {
          ...this.datosRemotos(cobroActual, remoto, origen),
          estado: EstadoCobro.DISCREPANCIA,
          proximaVerificacion: null,
          lockedUntil: null,
        },
      });
      const actualizado = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobroActual.id } });
      if (res.count === 0) return actualizado;
      await this.registrarEvento(this.prisma, cobroActual.id, "CAMBIO_ESTADO", cobroActual.estado, EstadoCobro.DISCREPANCIA, {
        motivo: "monto_distinto",
        montoEsperado: cobroActual.montoEsperado.toString(),
        montoProveedor: montoProveedor.toString(),
        origen,
      });
      await this.avisarAccionManual(actualizado, "El monto que confirmo Factus no coincide con el del pedido");
      return actualizado;
    }

    // Clave logica del pedido/orden: sirve de candado para que, si dos
    // cobros del mismo pedido se pagan casi al tiempo, la deteccion de
    // duplicado de abajo sea confiable (sin esto, dos transacciones
    // concurrentes podrian no verse entre si hasta que ambas ya confirmaron).
    const claveLock = cobroActual.pedidoAppId
      ? `pedido:${cobroActual.pedidoAppId}`
      : cobroActual.wooOrderId
        ? `woo:${cobroActual.wooOrderId}`
        : `cobro:${cobroActual.id}`;

    // Los avisos de red (notificar, reflejar en Woo) NO van dentro de la
    // transaccion: solo decidirian mas lento, no si el pago se confirma. Se
    // disparan despues de que la transaccion cerro; lo que si queda dentro
    // es la marca de que faltan (pendienteSincronizarWoo), para que una
    // caida justo despues del commit no los pierda.
    let avisoAccionManual: string | null = null;
    // Solo la via que gano el claim corre los avisos: las demas (worker,
    // "Ya pague" y webhook a la vez) encuentran el cobro ya PAGADO y no
    // deben notificar otra vez.
    let confirmadoAqui = false;

    const resultado = await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${claveLock})::bigint)`;

      const claim = await tx.pagoCobro.updateMany({
        where: { id: cobroActual.id, estado: { notIn: ESTADOS_TERMINALES } },
        data: {
          ...this.datosRemotos(cobroActual, remoto, origen),
          estado: EstadoCobro.PAGADO,
          pagadoDetectadoEn: new Date(),
          origenConfirmacion: origen,
          pendienteSincronizarWoo: this.posConfirmaciones.has(cobroActual.canal),
          proximaVerificacion: null,
          lockedUntil: null,
        },
      });
      const actualizado = await tx.pagoCobro.findUniqueOrThrow({ where: { id: cobroActual.id } });
      // Otra via ya resolvio este mismo cobro (worker + "Ya pague" + webhook a la vez).
      if (claim.count === 0) return actualizado;

      await this.registrarEvento(tx, cobroActual.id, "CAMBIO_ESTADO", cobroActual.estado, EstadoCobro.PAGADO, {
        estadoProveedor: remoto.status,
        origen,
      });

      // Duplicado = otro cobro PAGADO por lo mismo: el mismo saldo, o el mismo
      // pedido/orden sin contar el saldo (anticipo + saldo es lo normal).
      const otroPagado = cobroActual.saldoServicioId
        ? await tx.pagoCobro.findFirst({
            where: { id: { not: cobroActual.id }, estado: EstadoCobro.PAGADO, saldoServicioId: cobroActual.saldoServicioId },
          })
        : cobroActual.pedidoAppId
          ? await tx.pagoCobro.findFirst({
              where: {
                id: { not: cobroActual.id },
                estado: EstadoCobro.PAGADO,
                pedidoAppId: cobroActual.pedidoAppId,
                canal: { not: CanalPago.SALDO_SERVICIO },
              },
            })
          : cobroActual.wooOrderId
            ? await tx.pagoCobro.findFirst({
                where: {
                  id: { not: cobroActual.id },
                  estado: EstadoCobro.PAGADO,
                  wooOrderId: cobroActual.wooOrderId,
                  canal: { not: CanalPago.SALDO_SERVICIO },
                },
              })
            : null;
      if (otroPagado) {
        const duplicado = await tx.pagoCobro.update({
          where: { id: cobroActual.id },
          data: { estado: EstadoCobro.PAGADO_DUPLICADO, pendienteSincronizarWoo: false },
        });
        await this.registrarEvento(tx, cobroActual.id, "CAMBIO_ESTADO", EstadoCobro.PAGADO, EstadoCobro.PAGADO_DUPLICADO, {
          otroCobroId: otroPagado.id,
        });
        avisoAccionManual = `Pago duplicado: el pedido ya estaba pagado por el cobro ${otroPagado.referenceCode}`;
        return duplicado;
      }

      const confirmador = this.confirmadores.get(cobroActual.canal);
      if (!confirmador) {
        confirmadoAqui = true;
        return actualizado;
      }

      try {
        await confirmador(tx, {
          cobroId: cobroActual.id,
          canal: cobroActual.canal,
          pedidoAppId: cobroActual.pedidoAppId,
          wooOrderId: cobroActual.wooOrderId,
          usuarioId: cobroActual.usuarioId,
          saldoServicioId: cobroActual.saldoServicioId,
          montoEsperado: cobroActual.montoEsperado,
          referenceCode: cobroActual.referenceCode,
        });
        await this.registrarEvento(tx, cobroActual.id, "CONFIRMACION_PEDIDO", null, null, { ok: true });
      } catch (error) {
        if (error instanceof PedidoNoConfirmableError) {
          const huerfano = await tx.pagoCobro.update({
            where: { id: cobroActual.id },
            data: { estado: EstadoCobro.PAGADO_HUERFANO, pendienteSincronizarWoo: false },
          });
          await this.registrarEvento(
            tx,
            cobroActual.id,
            "CAMBIO_ESTADO",
            EstadoCobro.PAGADO,
            EstadoCobro.PAGADO_HUERFANO,
            { motivo: error.message },
          );
          avisoAccionManual = `Factus confirmo el pago pero el pedido ya no puede confirmarse: ${error.message}`;
          return huerfano;
        }
        // Fallo real (DB, red, etc.): se revierte toda la transaccion, el
        // cobro queda como estaba antes y el worker lo reintenta.
        throw error;
      }

      confirmadoAqui = true;
      return actualizado;
    });

    if (avisoAccionManual) {
      await this.avisarAccionManual(resultado, avisoAccionManual);
    } else if (confirmadoAqui && resultado.pendienteSincronizarWoo) {
      await this.ejecutarPosConfirmacion(resultado);
      return this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: resultado.id } });
    }
    return resultado;
  }

  /** Ver PosConfirmacionPago: corre solo si el pago quedo realmente
   * confirmado (no duplicado ni huerfano). Si termina bien apaga la marca de
   * avisos pendientes; si falla, la deja y el worker reintenta. */
  private async ejecutarPosConfirmacion(cobro: PagoCobro) {
    const hook = this.posConfirmaciones.get(cobro.canal);
    if (!hook) return;
    try {
      await hook(cobro);
      await this.prisma.pagoCobro.updateMany({
        where: { id: cobro.id, pendienteSincronizarWoo: true },
        data: { pendienteSincronizarWoo: false },
      });
    } catch (error) {
      console.error("[pagos] fallo el aviso posterior a la confirmacion del pago", {
        cobroId: cobro.id,
        name: error instanceof Error ? error.name : "Error",
      });
      // El pago ya esta confirmado; el worker reintenta el aviso (la marca ya
      // quedo puesta en la transaccion; esto solo renueva actualizadoEn).
      await this.prisma.pagoCobro
        .updateMany({
          where: { id: cobro.id, estado: EstadoCobro.PAGADO },
          data: { pendienteSincronizarWoo: true },
        })
        .catch(() => undefined);
    }
  }

  /** Ver PosFalloPago. A diferencia de ejecutarPosConfirmacion, un fallo aqui
   * no queda marcado para reintento: no hay dinero de por medio y el cliente
   * de todas formas puede generar un cobro nuevo. */
  private async ejecutarPosFallo(cobro: PagoCobro) {
    const hook = this.posFallos.get(cobro.canal);
    if (!hook) return;
    try {
      await hook(cobro);
    } catch (error) {
      console.error("[pagos] fallo el aviso de pago fallido", {
        cobroId: cobro.id,
        name: error instanceof Error ? error.name : "Error",
      });
    }
  }

  private async registrarFalloConsulta(
    cobro: PagoCobro,
    error: unknown,
    origen: OrigenVerificacionPago,
  ): Promise<PagoCobro> {
    const ahora = new Date();
    const edadMs = ahora.getTime() - cobro.creadoEn.getTime();
    const esRateLimit = error instanceof FactusPayError && error.status === 429;
    const espera = siguienteEsperaMs(edadMs);
    const proximaVerificacion =
      espera == null ? null : new Date(ahora.getTime() + (esRateLimit ? espera * 2 : espera));

    // Condicional: si otra via ya cerro el cobro mientras esta consulta
    // fallaba, no se le cambia nada (antes se reescribia el estado leido al
    // principio y podia devolver un PAGADO a pendiente).
    const res = await this.prisma.pagoCobro.updateMany({
      where: { id: cobro.id, estado: { in: ESTADOS_ACTIVOS } },
      data: {
        intentosVerificacion: { increment: 1 },
        proximaVerificacion,
        ...(espera == null ? { estado: EstadoCobro.ABANDONADO } : {}),
        lockedUntil: null,
        ultimaVerificacionEn: ahora,
        ultimaVerificacionOrigen: origen,
      },
    });
    const actualizado = await this.prisma.pagoCobro.findUniqueOrThrow({ where: { id: cobro.id } });
    if (res.count === 0) return actualizado;
    await this.registrarEvento(this.prisma, cobro.id, "ERROR", cobro.estado, actualizado.estado, {
      error: this.mensajeError(error),
      origen,
    });
    return actualizado;
  }

  private async avisarAccionManual(cobro: PagoCobro, motivo: string) {
    if (!this.alertador) return;
    try {
      await this.alertador(cobro, motivo);
    } catch (error) {
      // Best-effort: el estado del cobro ya quedo guardado.
      console.error("[pagos] no se pudo avisar la accion manual", {
        cobroId: cobro.id,
        name: error instanceof Error ? error.name : "Error",
      });
    }
  }

  async registrarEvento(
    client: PrismaClient | TransactionClient,
    cobroId: number,
    tipo: string,
    estadoAnterior: EstadoCobro | null,
    estadoNuevo: EstadoCobro | null,
    payload: Prisma.InputJsonObject,
  ) {
    await client.pagoEvento.create({
      data: { cobroId, tipo, estadoAnterior, estadoNuevo, payload },
    });
  }

  private mensajeError(error: unknown): string {
    if (error instanceof FactusPayError) return `${error.status}: ${error.message}`;
    return error instanceof Error ? error.message : String(error);
  }
}
