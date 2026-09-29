import { CanalPago, EstadoCobro, Prisma, type PagoCobro, type PrismaClient } from "@prisma/client";
import crypto from "crypto";
import {
  crearCobroFactus,
  consultarCobroFactus,
  isFactusPayConfigured,
  FACTUS_MONTO_MIN_COP,
  FACTUS_MONTO_MAX_COP,
  type FactusCollection,
} from "./FactusPayClient";
import { FactusPayError, PedidoNoConfirmableError } from "./errors";
import { siguienteEsperaMs } from "./backoff";

type TransactionClient = Prisma.TransactionClient;

// No documentado por Factus: cuanto dura un QR. Se usa como referencia local
// para mostrar "vencido" en la UI y ofrecer un QR nuevo; el cobro se sigue
// verificando igual (ver backoff.ts) porque Factus no ofrece anularlo.
const EXPIRA_LOCAL_MIN = Number(process.env.FACTUS_PAY_EXPIRA_MIN ?? 30);
// Cuando el recaudo todavia no tiene QR (status "started"), Factus lo genera
// casi de inmediato: conviene reconsultar pronto en vez de esperar el primer
// escalon del backoff normal.
const VERIFICACION_INMEDIATA_MS = 2_000;

const ESTADOS_ACTIVOS: EstadoCobro[] = [EstadoCobro.CREADO, EstadoCobro.PENDIENTE, EstadoCobro.VENCIDO];
const ESTADOS_TERMINALES: EstadoCobro[] = [
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

export type CrearCobroInput = {
  canal: CanalPago;
  montoEsperado: number;
  pedidoAppId?: number;
  wooOrderId?: string;
  usuarioId?: string;
  referencePrefix?: string;
};

export type ConfirmadorPagoContexto = {
  cobroId: number;
  pedidoAppId: number | null;
  wooOrderId: string | null;
  usuarioId: string | null;
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
 * PAGADO igual (best-effort, ver PagoService.ejecutarPosConfirmacion).
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
 */
export class PagoService {
  private confirmadores = new Map<CanalPago, ConfirmadorPago>();
  private posConfirmaciones = new Map<CanalPago, PosConfirmacionPago>();
  private posFallos = new Map<CanalPago, PosFalloPago>();
  private alertador: AlertadorAccionManual | null = null;

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
        montoEsperado: new Prisma.Decimal(monto),
        estado: EstadoCobro.CREADO,
        expiraLocalEn: new Date(ahora.getTime() + EXPIRA_LOCAL_MIN * 60_000),
        proximaVerificacion: ahora,
      },
    });
    await this.registrarEvento(this.prisma, cobro.id, "CREADO", null, EstadoCobro.CREADO, { montoEsperado: monto });

    return this.crearEnFactusYAplicar(cobro);
  }

  private async buscarCobroVigente(
    input: { pedidoAppId?: number; wooOrderId?: string },
    monto: number,
  ): Promise<PagoCobro | null> {
    return this.prisma.pagoCobro.findFirst({
      where: {
        ...(input.pedidoAppId ? { pedidoAppId: input.pedidoAppId } : { wooOrderId: input.wooOrderId }),
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
      await this.registrarFalloConsulta(cobro, error);
      throw error;
    }
    return this.aplicarRespuestaFactus(cobro, remoto);
  }

  /**
   * Fuerza una consulta a Factus ahora mismo (usada por el boton "Ya pague"
   * y por el worker de conciliacion). No hace nada si el cobro ya esta en un
   * estado terminal.
   */
  async verificarCobro(cobroId: number): Promise<PagoCobro> {
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
      return this.registrarFalloConsulta(cobro, error);
    }
    return this.aplicarRespuestaFactus(cobro, remoto);
  }

  /**
   * Para la conciliacion: Factus dice que un cobro esta pagado aunque aqui
   * quedo ABANDONADO o FALLIDO (estados terminales que verificarCobro ya no
   * consulta). Lo reabre y lo verifica de nuevo por el camino normal.
   */
  async reabrirYVerificar(cobroId: number): Promise<PagoCobro> {
    await this.prisma.pagoCobro.updateMany({
      where: { id: cobroId, estado: { in: [EstadoCobro.ABANDONADO, EstadoCobro.FALLIDO] } },
      data: { estado: EstadoCobro.PENDIENTE },
    });
    await this.registrarEvento(this.prisma, cobroId, "ACCION_MANUAL", null, EstadoCobro.PENDIENTE, {
      motivo: "conciliacion: Factus reporta el recaudo pagado",
    });
    return this.verificarCobro(cobroId);
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

    const lockedUntil = new Date(ahora.getTime() + 30_000);
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
        await this.verificarCobro(id);
      } catch (error) {
        errores++;
        console.error("[pagos] fallo al verificar un cobro", {
          cobroId: id,
          name: error instanceof Error ? error.name : "Error",
        });
      }
    }
    await this.reintentarPosConfirmaciones();
    return { procesados: ids.length, errores };
  }

  /**
   * Reintenta los avisos posteriores (reflejar el pago en WooCommerce,
   * notificar) de los cobros que ya quedaron PAGADO pero cuyo aviso fallo
   * (pendienteSincronizarWoo). El dinero y el pedido ya estan bien; esto solo
   * pone al dia a la tienda. Espera 60 s entre intentos del mismo cobro.
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
      if (!hook) continue;
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

  private async aplicarRespuestaFactus(cobroActual: PagoCobro, remoto: FactusCollection): Promise<PagoCobro> {
    if (remoto.status === "paid") {
      return this.confirmarPago(cobroActual, remoto);
    }

    if (remoto.status === "failed" || remoto.status === "rejected") {
      const actualizado = await this.prisma.pagoCobro.update({
        where: { id: cobroActual.id },
        data: {
          estado: EstadoCobro.FALLIDO,
          estadoProveedor: remoto.status,
          montoProveedor: new Prisma.Decimal(remoto.amount),
          qrBase64: remoto.qr ?? cobroActual.qrBase64,
          proximaVerificacion: null,
          lockedUntil: null,
          intentosVerificacion: { increment: 1 },
        },
      });
      await this.registrarEvento(this.prisma, cobroActual.id, "CAMBIO_ESTADO", cobroActual.estado, EstadoCobro.FALLIDO, {
        estadoProveedor: remoto.status,
      });
      await this.ejecutarPosFallo(actualizado);
      return actualizado;
    }

    // "started" o "ready": sigue pendiente de pago.
    const ahora = new Date();
    const edadMs = ahora.getTime() - cobroActual.creadoEn.getTime();
    const espera = !remoto.qr ? VERIFICACION_INMEDIATA_MS : siguienteEsperaMs(edadMs);
    const vencidoLocal = cobroActual.expiraLocalEn != null && ahora > cobroActual.expiraLocalEn;

    const nuevoEstado =
      espera == null ? EstadoCobro.ABANDONADO : vencidoLocal ? EstadoCobro.VENCIDO : EstadoCobro.PENDIENTE;
    const proximaVerificacion = espera == null ? null : new Date(ahora.getTime() + espera);

    const actualizado = await this.prisma.pagoCobro.update({
      where: { id: cobroActual.id },
      data: {
        estado: nuevoEstado,
        estadoProveedor: remoto.status,
        montoProveedor: new Prisma.Decimal(remoto.amount),
        qrBase64: remoto.qr ?? cobroActual.qrBase64,
        proximaVerificacion,
        lockedUntil: null,
        intentosVerificacion: { increment: 1 },
      },
    });
    await this.registrarEvento(
      this.prisma,
      cobroActual.id,
      nuevoEstado !== cobroActual.estado ? "CAMBIO_ESTADO" : "CONSULTA",
      cobroActual.estado,
      nuevoEstado,
      { estadoProveedor: remoto.status },
    );
    return actualizado;
  }

  private async confirmarPago(cobroActual: PagoCobro, remoto: FactusCollection): Promise<PagoCobro> {
    const montoProveedor = new Prisma.Decimal(remoto.amount);
    if (!montoProveedor.equals(cobroActual.montoEsperado)) {
      const actualizado = await this.prisma.pagoCobro.update({
        where: { id: cobroActual.id },
        data: {
          estado: EstadoCobro.DISCREPANCIA,
          estadoProveedor: remoto.status,
          montoProveedor,
          qrBase64: remoto.qr ?? cobroActual.qrBase64,
          proximaVerificacion: null,
          lockedUntil: null,
        },
      });
      await this.registrarEvento(this.prisma, cobroActual.id, "CAMBIO_ESTADO", cobroActual.estado, EstadoCobro.DISCREPANCIA, {
        motivo: "monto_distinto",
        montoEsperado: cobroActual.montoEsperado.toString(),
        montoProveedor: montoProveedor.toString(),
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
    // juntan aqui y se disparan best-effort despues de que la transaccion
    // ya cerro (ver el bloque final de este metodo).
    let avisoAccionManual: string | null = null;

    const resultado = await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${claveLock})::bigint)`;

      const claim = await tx.pagoCobro.updateMany({
        where: { id: cobroActual.id, estado: { notIn: ESTADOS_TERMINALES } },
        data: {
          estado: EstadoCobro.PAGADO,
          estadoProveedor: remoto.status,
          montoProveedor,
          qrBase64: remoto.qr ?? cobroActual.qrBase64,
          pagadoDetectadoEn: new Date(),
          proximaVerificacion: null,
          lockedUntil: null,
        },
      });
      const actualizado = await tx.pagoCobro.findUniqueOrThrow({ where: { id: cobroActual.id } });
      // Otro proceso ya resolvio este mismo cobro (worker + "Ya pague" a la vez).
      if (claim.count === 0) return actualizado;

      await this.registrarEvento(tx, cobroActual.id, "CAMBIO_ESTADO", cobroActual.estado, EstadoCobro.PAGADO, {
        estadoProveedor: remoto.status,
      });

      const otroPagado = cobroActual.pedidoAppId
        ? await tx.pagoCobro.findFirst({
            where: { id: { not: cobroActual.id }, estado: EstadoCobro.PAGADO, pedidoAppId: cobroActual.pedidoAppId },
          })
        : cobroActual.wooOrderId
          ? await tx.pagoCobro.findFirst({
              where: { id: { not: cobroActual.id }, estado: EstadoCobro.PAGADO, wooOrderId: cobroActual.wooOrderId },
            })
          : null;
      if (otroPagado) {
        const duplicado = await tx.pagoCobro.update({
          where: { id: cobroActual.id },
          data: { estado: EstadoCobro.PAGADO_DUPLICADO },
        });
        await this.registrarEvento(tx, cobroActual.id, "CAMBIO_ESTADO", EstadoCobro.PAGADO, EstadoCobro.PAGADO_DUPLICADO, {
          otroCobroId: otroPagado.id,
        });
        avisoAccionManual = `Pago duplicado: el pedido ya estaba pagado por el cobro ${otroPagado.referenceCode}`;
        return duplicado;
      }

      const confirmador = this.confirmadores.get(cobroActual.canal);
      if (!confirmador) return actualizado;

      try {
        await confirmador(tx, {
          cobroId: cobroActual.id,
          pedidoAppId: cobroActual.pedidoAppId,
          wooOrderId: cobroActual.wooOrderId,
          usuarioId: cobroActual.usuarioId,
          montoEsperado: cobroActual.montoEsperado,
          referenceCode: cobroActual.referenceCode,
        });
        await this.registrarEvento(tx, cobroActual.id, "CONFIRMACION_PEDIDO", null, null, { ok: true });
      } catch (error) {
        if (error instanceof PedidoNoConfirmableError) {
          const huerfano = await tx.pagoCobro.update({
            where: { id: cobroActual.id },
            data: { estado: EstadoCobro.PAGADO_HUERFANO },
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

      return actualizado;
    });

    if (avisoAccionManual) {
      await this.avisarAccionManual(resultado, avisoAccionManual);
    } else if (resultado.estado === EstadoCobro.PAGADO) {
      await this.ejecutarPosConfirmacion(resultado);
    }
    return resultado;
  }

  /** Ver PosConfirmacionPago: corre solo si el pago quedo realmente
   * confirmado (no duplicado ni huerfano), best-effort. */
  private async ejecutarPosConfirmacion(cobro: PagoCobro) {
    const hook = this.posConfirmaciones.get(cobro.canal);
    if (!hook) return;
    try {
      await hook(cobro);
    } catch (error) {
      console.error("[pagos] fallo el aviso posterior a la confirmacion del pago", {
        cobroId: cobro.id,
        name: error instanceof Error ? error.name : "Error",
      });
      // El pago ya esta confirmado; el worker reintenta el aviso.
      await this.prisma.pagoCobro
        .update({ where: { id: cobro.id }, data: { pendienteSincronizarWoo: true } })
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

  private async registrarFalloConsulta(cobro: PagoCobro, error: unknown): Promise<PagoCobro> {
    const ahora = new Date();
    const edadMs = ahora.getTime() - cobro.creadoEn.getTime();
    const esRateLimit = error instanceof FactusPayError && error.status === 429;
    const espera = siguienteEsperaMs(edadMs);
    const proximaVerificacion =
      espera == null ? null : new Date(ahora.getTime() + (esRateLimit ? espera * 2 : espera));

    const actualizado = await this.prisma.pagoCobro.update({
      where: { id: cobro.id },
      data: {
        intentosVerificacion: { increment: 1 },
        proximaVerificacion,
        estado: espera == null ? EstadoCobro.ABANDONADO : cobro.estado,
        lockedUntil: null,
      },
    });
    await this.registrarEvento(this.prisma, cobro.id, "ERROR", cobro.estado, actualizado.estado, {
      error: this.mensajeError(error),
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

  private async registrarEvento(
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
