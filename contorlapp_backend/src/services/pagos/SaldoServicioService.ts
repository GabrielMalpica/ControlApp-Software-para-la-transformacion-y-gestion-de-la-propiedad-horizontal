import {
  CanalPago,
  EstadoSaldoServicio,
  OrigenVerificacionPago,
  Prisma,
  type PagoCobro,
  type PrismaClient,
  type SaldoServicio,
} from "@prisma/client";
import crypto from "crypto";
import { z } from "zod";
import { commerceHttpError, type CommerceActor } from "../CommerceAccessService";
import { buildWooUrl, wooFetch } from "../wooFetch";
import { PedidoNoConfirmableError } from "./errors";
import type { ConfirmadorPagoContexto, PagoService } from "./PagoService";
import { montoACobrarWoo, serializarCobroWoo } from "./PagoWooService";

type TransactionClient = Prisma.TransactionClient;
type WooMeta = { key?: string; value?: unknown };
type WooDireccion = {
  first_name?: string;
  last_name?: string;
  email?: string;
  phone?: string;
  address_1?: string;
  address_2?: string;
  city?: string;
  state?: string;
};

export type WooOrdenSaldo = {
  id: number;
  status: string;
  total?: string;
  order_key?: string;
  payment_method?: string;
  billing?: WooDireccion;
  shipping?: WooDireccion;
  meta_data?: WooMeta[];
  line_items?: Array<{ name?: string; meta_data?: WooMeta[] }>;
};

type ReservaClmk = { estado?: string };

export const OrdenTiendaDTO = z.object({
  wooOrderId: z.coerce.string().regex(/^\d{1,12}$/, "La orden no es valida"),
  orderKey: z.string().trim().min(1).max(100),
});

export const ConsultarMoraDTO = z
  .object({
    correo: z.string().trim().max(200).optional(),
    telefono: z.string().trim().max(40).optional(),
    // Pedido ya creado sin poder verificar (el servidor no respondio): si el
    // cliente estaba en mora, queda como incidencia en la lista.
    wooOrderId: z.coerce.string().regex(/^\d{1,12}$/).optional(),
  })
  .refine((d) => Boolean(d.correo || d.telefono), "Falta el correo o el telefono");

export const ResolverSaldoDTO = z.object({
  motivo: z.string().trim().min(5, "Cuenta brevemente como se pago").max(300),
});

export const ListarMoraDTO = z.object({
  estado: z.enum(["PENDIENTE", "PAGADO", "PAGADO_POR_FUERA", "TODOS"]).default("PENDIENTE"),
  q: z.string().trim().max(100).optional(),
  pagina: z.coerce.number().int().min(1).default(1),
  porPagina: z.coerce.number().int().min(1).max(100).default(30),
});

// Estados de la orden de Woo en los que aun no se ha pagado nada.
const ORDEN_SIN_PAGAR = new Set(["pending", "failed", "on-hold", "pago-ocr", "cancelled", "refunded", "checkout-draft", "trash"]);
// Contra reembolso cobra todo en el sitio y el credito de conjunto se factura
// a fin de mes: ninguno deja un saldo que cobrar aqui.
const METODOS_SIN_SALDO = new Set(["cod", "conjunto_credito"]);
const RESERVA_ACTIVA = new Set(["pendiente", "confirmada", "en_curso"]);

export function normalizarCorreo(valor: unknown): string | null {
  const correo = String(valor ?? "").trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo) ? correo.slice(0, 200) : null;
}

/** Ultimos 10 digitos (celular colombiano sin +57); null si es muy corto. */
export function normalizarTelefono(valor: unknown): string | null {
  const digitos = String(valor ?? "").replace(/\D/g, "");
  if (digitos.length < 7) return null;
  return digitos.slice(-10);
}

function redondear(valor: number) {
  return Math.round(valor * 100) / 100;
}

function pesos(valor: number | Prisma.Decimal) {
  return `$${Number(valor).toLocaleString("es-CO")}`;
}

function meta(lista: WooMeta[] | undefined, clave: string) {
  return lista?.find((m) => m.key === clave)?.value;
}

/**
 * Cuanto falta por pagar de una orden ya pagada con anticipo. El backend lo
 * calcula de la orden misma (total - anticipo); ni la app ni WordPress mandan
 * el monto. Sin anticipo, sin pagar, o con un metodo que cobra el resto por
 * otra via, no hay saldo.
 */
export function calcularSaldoOrden(orden: WooOrdenSaldo):
  | { saldo: number; pagadoAntes: number; total: number }
  | { saldo: 0; motivo: string } {
  if (ORDEN_SIN_PAGAR.has(orden.status)) return { saldo: 0, motivo: `la orden esta en estado "${orden.status}"` };
  if (METODOS_SIN_SALDO.has(String(orden.payment_method ?? ""))) {
    return { saldo: 0, motivo: "el metodo de pago cobra el resto por otra via" };
  }
  const total = Number(orden.total);
  if (!Number.isFinite(total) || total <= 0) return { saldo: 0, motivo: "la orden no tiene total" };
  const { monto, anticipo } = montoACobrarWoo(orden);
  if (!anticipo) return { saldo: 0, motivo: "la orden se pago completa" };
  const saldo = redondear(total - monto);
  if (saldo < 1) return { saldo: 0, motivo: "no queda saldo" };
  return { saldo, pagadoAntes: monto, total };
}

/** El servicio termino: ninguna reserva sigue activa y al menos una se completo. */
export function serviciosTerminados(reservas: ReservaClmk[]) {
  if (reservas.length === 0) return false;
  if (reservas.some((r) => RESERVA_ACTIVA.has(String(r.estado)))) return false;
  return reservas.some((r) => r.estado === "completada");
}

function datosCliente(orden: WooOrdenSaldo) {
  const b = orden.billing ?? {};
  const s = orden.shipping ?? {};
  const nombre = [b.first_name || s.first_name, b.last_name || s.last_name].filter(Boolean).join(" ").trim();
  const direccion = [b.address_1 || s.address_1, b.address_2 || s.address_2, b.city || s.city, b.state || s.state]
    .map((parte) => String(parte ?? "").trim())
    .filter(Boolean)
    .join(", ");
  const servicios = (orden.line_items ?? [])
    .filter((item) => meta(item.meta_data, "Fecha del servicio"))
    .map((item) => String(item.name ?? "").trim())
    .filter(Boolean)
    .join(", ");
  return {
    nombre: nombre.slice(0, 200),
    correo: normalizarCorreo(b.email),
    telefono: normalizarTelefono(b.phone || s.phone),
    direccion: direccion.slice(0, 300) || null,
    servicios: servicios.slice(0, 300) || "Servicio",
  };
}

type Identidad = { usuarioId?: string | null; correo?: unknown; telefono?: unknown };

/** Saldos pendientes de una persona: por su cuenta, su correo o su telefono. */
export async function saldosPendientesDe(prisma: Pick<PrismaClient, "saldoServicio">, identidad: Identidad) {
  const correo = normalizarCorreo(identidad.correo);
  const telefono = normalizarTelefono(identidad.telefono);
  const quien: Prisma.SaldoServicioWhereInput[] = [];
  if (identidad.usuarioId) quien.push({ usuarioId: identidad.usuarioId });
  if (correo) quien.push({ clienteCorreo: correo });
  if (telefono) quien.push({ clienteTelefono: telefono });
  if (quien.length === 0) return [];
  return prisma.saldoServicio.findMany({
    where: { estado: EstadoSaldoServicio.PENDIENTE, OR: quien },
    orderBy: { servicioTerminadoEn: "asc" },
  });
}

/**
 * Antes de crear un pedido en la app: con un saldo pendiente (por su cuenta,
 * su correo o su telefono, venga de la app o de la tienda) no se puede pedir.
 */
export async function asegurarSinMora(prisma: Pick<PrismaClient, "saldoServicio" | "usuario">, usuarioId: string) {
  const usuario = await prisma.usuario.findUnique({
    where: { id: usuarioId },
    select: { id: true, correo: true, telefono: true },
  });
  if (!usuario) return;
  const pendientes = await saldosPendientesDe(prisma, {
    usuarioId: usuario.id,
    correo: usuario.correo,
    telefono: usuario.telefono?.toString(),
  });
  if (pendientes.length === 0) return;
  const total = pendientes.reduce((suma, s) => suma + Number(s.montoSaldo), 0);
  throw commerceHttpError(
    409,
    `Tienes un saldo pendiente de ${pesos(total)} por un servicio que ya te prestamos. ` +
      "Págalo en Mis saldos para seguir haciendo pedidos.",
  );
}

/**
 * Saldos de servicios pagados con anticipo: nacen cuando el servicio termina,
 * se pagan con un recaudo nuevo de Factus (canal SALDO_SERVICIO) y, mientras
 * estan pendientes, el cliente no puede hacer pedidos nuevos ni en la app ni
 * en la tienda. Todas las reglas (cuanto se debe, quien debe, si puede pedir)
 * se deciden aqui, en el servidor.
 */
export class SaldoServicioService {
  constructor(
    private prisma: PrismaClient,
    private pagos: Pick<PagoService, "crearCobro" | "verificarCobro">,
    private avisos: {
      notificarUsuario(input: {
        usuarioId: string;
        tipo: string;
        titulo: string;
        mensaje: string;
        referenciaTipo: string;
        referenciaId: number;
      }): Promise<unknown>;
      alertarEquipo(titulo: string, mensaje: string): Promise<unknown>;
    },
  ) {}

  private async leerOrden(wooOrderId: string) {
    return wooFetch<WooOrdenSaldo>(
      buildWooUrl("rest", `/orders/${wooOrderId}`, {
        _fields: "id,status,total,order_key,payment_method,billing,shipping,meta_data,line_items",
      }),
      {},
      { requireAuth: true, timeoutMs: 8_000, failureMessage: "No pudimos consultar la orden en la tienda" },
    );
  }

  private async leerReservas(wooOrderId: string) {
    return wooFetch<ReservaClmk[]>(
      buildWooUrl("clmk", "/reservas", { order_id: wooOrderId, por_pagina: 100 }),
      {},
      { requireAuth: true, timeoutMs: 8_000, failureMessage: "No pudimos consultar las reservas del servicio" },
    );
  }

  private mismaClave(a: string, b: string) {
    const ha = crypto.createHash("sha256").update(a).digest();
    const hb = crypto.createHash("sha256").update(b).digest();
    return crypto.timingSafeEqual(ha, hb);
  }

  /* ------------------------------ nacimiento ------------------------------ */

  /**
   * Lo llama el plugin de la tienda cuando una reserva pasa a "completada".
   * Relee la orden y las reservas (no confia en lo que diga WordPress), y si
   * el servicio termino y queda saldo, lo registra (una vez por orden) y avisa
   * al cliente en la app. El correo lo manda WordPress con lo que se devuelve.
   */
  async registrarServicioTerminado(payload: unknown) {
    const dto = OrdenTiendaDTO.parse(payload);
    const orden = await this.leerOrden(dto.wooOrderId);
    if (!orden.order_key || !this.mismaClave(orden.order_key, dto.orderKey)) {
      throw commerceHttpError(403, "La orden no coincide con la clave enviada");
    }

    const existente = await this.prisma.saldoServicio.findUnique({ where: { wooOrderId: dto.wooOrderId } });
    if (existente) return { saldo: this.serializarParaTienda(existente), creado: false };

    const reservas = await this.leerReservas(dto.wooOrderId);
    if (!serviciosTerminados(Array.isArray(reservas) ? reservas : [])) {
      return { saldo: null, creado: false, motivo: "El servicio todavia no ha terminado" };
    }

    const calculo = calcularSaldoOrden(orden);
    if (!("pagadoAntes" in calculo)) return { saldo: null, creado: false, motivo: calculo.motivo };

    const pedido = await this.prisma.pedidoApp.findUnique({
      where: { wooOrderId: dto.wooOrderId },
      select: { id: true, usuario: { select: { id: true, nombre: true, correo: true, telefono: true } } },
    });
    const cliente = datosCliente(orden);

    let saldo: SaldoServicio;
    try {
      saldo = await this.prisma.saldoServicio.create({
        data: {
          wooOrderId: dto.wooOrderId,
          pedidoAppId: pedido?.id ?? null,
          usuarioId: pedido?.usuario.id ?? null,
          clienteNombre: cliente.nombre || pedido?.usuario.nombre || "Cliente",
          clienteCorreo: cliente.correo ?? normalizarCorreo(pedido?.usuario.correo),
          clienteTelefono: cliente.telefono ?? normalizarTelefono(pedido?.usuario.telefono?.toString()),
          clienteDireccion: cliente.direccion,
          servicios: cliente.servicios,
          totalOrden: new Prisma.Decimal(calculo.total),
          pagadoAntes: new Prisma.Decimal(calculo.pagadoAntes),
          montoSaldo: new Prisma.Decimal(calculo.saldo),
          servicioTerminadoEn: new Date(),
        },
      });
    } catch (error) {
      // Dos avisos de "servicio terminado" a la vez: gana el primero.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        const ganador = await this.prisma.saldoServicio.findUniqueOrThrow({ where: { wooOrderId: dto.wooOrderId } });
        return { saldo: this.serializarParaTienda(ganador), creado: false };
      }
      throw error;
    }

    if (saldo.usuarioId) {
      await this.avisos
        .notificarUsuario({
          usuarioId: saldo.usuarioId,
          tipo: "saldo_servicio_pendiente",
          titulo: "Tienes un saldo pendiente",
          mensaje:
            `Terminamos tu servicio (${saldo.servicios}). Paga el saldo de ${pesos(saldo.montoSaldo)} ` +
            "para seguir haciendo pedidos.",
          referenciaTipo: "SaldoServicio",
          referenciaId: saldo.id,
        })
        .then(() => this.prisma.saldoServicio.update({ where: { id: saldo.id }, data: { clienteAvisadoEn: new Date() } }))
        .catch(() => undefined);
    }
    return { saldo: this.serializarParaTienda(saldo), creado: true };
  }

  /* ------------------------------- bloqueo -------------------------------- */

  /**
   * Checkout de la tienda: ¿este correo/telefono debe algo? Solo devuelve a
   * WordPress lo necesario para decidir y mostrar (nunca datos del cliente):
   * WordPress solo ofrece el enlace de pago si la orden es de la cuenta que
   * esta comprando.
   */
  async consultarMoraTienda(payload: unknown) {
    const dto = ConsultarMoraDTO.parse(payload);
    const pendientes = await saldosPendientesDe(this.prisma, { correo: dto.correo, telefono: dto.telefono });
    if (dto.wooOrderId && pendientes.length > 0) {
      await this.prisma.saldoServicioIncidencia.createMany({
        data: pendientes.map((s) => ({ saldoServicioId: s.id, wooOrderId: dto.wooOrderId! })),
        skipDuplicates: true,
      });
      await this.avisos
        .alertarEquipo(
          `Pedido de la tienda de un cliente en mora (orden #${dto.wooOrderId})`,
          "Se hizo sin poder verificar la mora al momento. Revisalo en Clientes en mora.",
        )
        .catch(() => undefined);
    }
    return {
      enMora: pendientes.length > 0,
      total: pendientes.reduce((suma, s) => suma + Number(s.montoSaldo), 0),
      saldos: pendientes.map((s) => ({ wooOrderId: s.wooOrderId, montoSaldo: Number(s.montoSaldo) })),
    };
  }

  /* -------------------------------- pagar --------------------------------- */

  private async ultimoCobro(saldoId: number) {
    return this.prisma.pagoCobro.findFirst({ where: { saldoServicioId: saldoId }, orderBy: { creadoEn: "desc" } });
  }

  private async crearCobro(saldo: SaldoServicio) {
    if (saldo.estado !== EstadoSaldoServicio.PENDIENTE) {
      throw commerceHttpError(409, "Este saldo ya esta pagado");
    }
    // El monto sale del saldo registrado, nunca de la solicitud.
    return this.pagos.crearCobro({
      canal: CanalPago.SALDO_SERVICIO,
      montoEsperado: Number(saldo.montoSaldo),
      saldoServicioId: saldo.id,
      wooOrderId: saldo.wooOrderId,
      usuarioId: saldo.usuarioId ?? undefined,
      referencePrefix: "SA",
    });
  }

  private async saldoDeOrden(wooOrderId: string) {
    const saldo = await this.prisma.saldoServicio.findUnique({ where: { wooOrderId } });
    if (!saldo) throw commerceHttpError(404, "Esta orden no tiene saldo pendiente");
    return saldo;
  }

  /** Pagina "Pagar saldo" de la tienda (WordPress ya valido la clave del pedido). */
  async obtenerParaTienda(payload: unknown) {
    const { wooOrderId } = OrdenTiendaDTO.parse(payload);
    const saldo = await this.saldoDeOrden(wooOrderId);
    const cobro = await this.ultimoCobro(saldo.id);
    return { saldo: this.serializarParaTienda(saldo), cobro: cobro ? serializarCobroWoo(cobro) : null };
  }

  async cobrarParaTienda(payload: unknown) {
    const { wooOrderId } = OrdenTiendaDTO.parse(payload);
    const saldo = await this.saldoDeOrden(wooOrderId);
    const cobro = await this.crearCobro(saldo);
    return { saldo: this.serializarParaTienda(saldo), cobro: serializarCobroWoo(cobro) };
  }

  /** Saldos de una cuenta de la app: los suyos o los de su correo. */
  private async delUsuario(userId: string) {
    const usuario = await this.prisma.usuario.findUnique({ where: { id: userId }, select: { id: true, correo: true } });
    if (!usuario) throw commerceHttpError(404, "Usuario no encontrado");
    const correo = normalizarCorreo(usuario.correo);
    return { usuario, quien: [{ usuarioId: usuario.id }, ...(correo ? [{ clienteCorreo: correo }] : [])] };
  }

  async listarMios(userId: string) {
    const { quien } = await this.delUsuario(userId);
    const saldos = await this.prisma.saldoServicio.findMany({
      where: { OR: quien },
      orderBy: [{ estado: "asc" }, { servicioTerminadoEn: "desc" }],
      take: 30,
    });
    return saldos.map((s) => this.serializarParaApp(s, null));
  }

  private async mio(userId: string, saldoId: number) {
    const { quien } = await this.delUsuario(userId);
    // Uno ajeno responde como inexistente.
    const saldo = await this.prisma.saldoServicio.findFirst({ where: { id: saldoId, OR: quien } });
    if (!saldo) throw commerceHttpError(404, "Saldo no encontrado");
    return saldo;
  }

  async obtenerMio(userId: string, saldoId: number) {
    const saldo = await this.mio(userId, saldoId);
    return this.serializarParaApp(saldo, await this.ultimoCobro(saldo.id));
  }

  async pagarMio(userId: string, saldoId: number) {
    const saldo = await this.mio(userId, saldoId);
    return this.serializarParaApp(saldo, await this.crearCobro(saldo));
  }

  async verificarMio(userId: string, saldoId: number) {
    const saldo = await this.mio(userId, saldoId);
    const cobro = await this.ultimoCobro(saldo.id);
    if (!cobro) throw commerceHttpError(404, "Todavia no has generado el codigo para pagar este saldo");
    const actualizado = await this.pagos.verificarCobro(cobro.id, OrigenVerificacionPago.USUARIO);
    const saldoActual = await this.prisma.saldoServicio.findUniqueOrThrow({ where: { id: saldo.id } });
    return this.serializarParaApp(saldoActual, actualizado);
  }

  /* ----------------------- confirmacion (PagoService) ---------------------- */

  /**
   * Dentro de la transaccion que cierra el cobro: el saldo pasa a PAGADO solo
   * si seguia pendiente y el monto es el registrado. Si alguien ya lo marco
   * pagado por fuera, el dinero que llego queda como huerfano para revisar.
   */
  async confirmarEnDominio(tx: TransactionClient, contexto: ConfirmadorPagoContexto): Promise<void> {
    if (!contexto.saldoServicioId) throw new PedidoNoConfirmableError("el cobro no tiene saldo asociado");
    const saldo = await tx.saldoServicio.findUnique({ where: { id: contexto.saldoServicioId } });
    if (!saldo) throw new PedidoNoConfirmableError(`el saldo #${contexto.saldoServicioId} ya no existe`);
    if (!new Prisma.Decimal(saldo.montoSaldo).equals(contexto.montoEsperado)) {
      throw new PedidoNoConfirmableError(
        `el cobro es por ${contexto.montoEsperado.toString()} y el saldo es de ${saldo.montoSaldo.toString()}`,
      );
    }
    const claim = await tx.saldoServicio.updateMany({
      where: { id: saldo.id, estado: EstadoSaldoServicio.PENDIENTE },
      data: { estado: EstadoSaldoServicio.PAGADO, pagadoEn: new Date(), cobroPagoId: contexto.cobroId },
    });
    if (claim.count === 0) {
      throw new PedidoNoConfirmableError(`el saldo de la orden #${saldo.wooOrderId} ya estaba ${saldo.estado}`);
    }
  }

  /** Despues de confirmar: nota y marca en la orden de Woo, y aviso al cliente
   * (una vez). Lanza si Woo falla, para que PagoService lo reintente. */
  async posConfirmacion(cobro: PagoCobro): Promise<void> {
    if (!cobro.saldoServicioId) return;
    const saldo = await this.prisma.saldoServicio.findUnique({ where: { id: cobro.saldoServicioId } });
    if (!saldo) return;
    await this.reflejarEnTienda(
      saldo.wooOrderId,
      "pagado",
      `Saldo de ${pesos(saldo.montoSaldo)} pagado por Factus Pay (referencia ${cobro.referenceCode}). El pedido quedo pagado completo.`,
    );
    const claim = await this.prisma.pagoCobro.updateMany({
      where: { id: cobro.id, clienteNotificadoEn: null },
      data: { clienteNotificadoEn: new Date() },
    });
    if (claim.count > 0 && saldo.usuarioId) {
      await this.avisos
        .notificarUsuario({
          usuarioId: saldo.usuarioId,
          tipo: "saldo_servicio_pagado",
          titulo: "Saldo pagado",
          mensaje: `Recibimos el pago de ${pesos(saldo.montoSaldo)}. Ya puedes seguir haciendo pedidos.`,
          referenciaTipo: "SaldoServicio",
          referenciaId: saldo.id,
        })
        .catch(() => undefined);
    }
  }

  private async reflejarEnTienda(wooOrderId: string, estado: string, nota: string) {
    await wooFetch(
      buildWooUrl("rest", `/orders/${wooOrderId}`),
      { method: "PUT", body: JSON.stringify({ meta_data: [{ key: "_cfp_saldo_estado", value: estado }] }) },
      { requireAuth: true, timeoutMs: 8_000 },
    );
    await wooFetch(
      buildWooUrl("rest", `/orders/${wooOrderId}/notes`),
      { method: "POST", body: JSON.stringify({ note: nota, customer_note: false }) },
      { requireAuth: true, timeoutMs: 8_000 },
    ).catch(() => undefined);
  }

  /* -------------------------------- panel --------------------------------- */

  async listarMora(query: unknown) {
    const f = ListarMoraDTO.parse(query);
    const filtros: Prisma.SaldoServicioWhereInput[] = [];
    if (f.estado !== "TODOS") filtros.push({ estado: f.estado });
    if (f.q) {
      filtros.push({
        OR: [
          { clienteNombre: { contains: f.q, mode: "insensitive" } },
          { clienteCorreo: { contains: f.q.toLowerCase() } },
          { clienteTelefono: { contains: f.q.replace(/\D/g, "") || f.q } },
          { wooOrderId: f.q },
          { usuarioId: f.q },
        ],
      });
    }
    const where: Prisma.SaldoServicioWhereInput = { AND: filtros };
    const [total, filas, totalPendiente] = await Promise.all([
      this.prisma.saldoServicio.count({ where }),
      this.prisma.saldoServicio.findMany({
        where,
        orderBy: { servicioTerminadoEn: "asc" },
        skip: (f.pagina - 1) * f.porPagina,
        take: f.porPagina,
        include: { incidencias: { select: { wooOrderId: true, creadoEn: true } } },
      }),
      this.prisma.saldoServicio.aggregate({
        where: { estado: EstadoSaldoServicio.PENDIENTE },
        _sum: { montoSaldo: true },
        _count: true,
      }),
    ]);
    const ahora = Date.now();
    return {
      total,
      pagina: f.pagina,
      porPagina: f.porPagina,
      resumen: {
        clientesEnMora: totalPendiente._count,
        montoPendiente: Number(totalPendiente._sum.montoSaldo ?? 0),
      },
      items: filas.map((s) => ({
        id: s.id,
        estado: s.estado,
        canal: s.pedidoAppId ? "app" : "tienda",
        wooOrderId: s.wooOrderId,
        pedidoAppId: s.pedidoAppId,
        // En la app el id de la cuenta es el documento de la persona.
        documento: s.usuarioId,
        nombre: s.clienteNombre,
        correo: s.clienteCorreo,
        telefono: s.clienteTelefono,
        direccion: s.clienteDireccion,
        servicios: s.servicios,
        totalOrden: Number(s.totalOrden),
        pagadoAntes: Number(s.pagadoAntes),
        montoSaldo: Number(s.montoSaldo),
        servicioTerminadoEn: s.servicioTerminadoEn,
        diasEnMora:
          s.estado === EstadoSaldoServicio.PENDIENTE
            ? Math.floor((ahora - s.servicioTerminadoEn.getTime()) / 86_400_000)
            : null,
        pagadoEn: s.pagadoEn,
        resueltoPorNombre: s.resueltoPorNombre,
        resolucionMotivo: s.resolucionMotivo,
        pedidosEnMora: s.incidencias.map((i) => ({ wooOrderId: i.wooOrderId, creadoEn: i.creadoEn })),
      })),
    };
  }

  /**
   * Pago hecho por fuera (efectivo, transferencia directa): lo registra una
   * persona con un motivo. No mueve dinero; solo cierra el saldo y levanta el
   * bloqueo. Si habia un QR vigente y lo pagan despues, ese pago queda como
   * huerfano para revisar (ver confirmarEnDominio).
   */
  async resolverPorFuera(actor: CommerceActor, saldoId: number, payload: unknown) {
    const { motivo } = ResolverSaldoDTO.parse(payload);
    const claim = await this.prisma.saldoServicio.updateMany({
      where: { id: saldoId, estado: EstadoSaldoServicio.PENDIENTE },
      data: {
        estado: EstadoSaldoServicio.PAGADO_POR_FUERA,
        pagadoEn: new Date(),
        resueltoPorId: actor.id,
        resueltoPorNombre: actor.nombre,
        resolucionMotivo: motivo,
      },
    });
    const saldo = await this.prisma.saldoServicio.findUnique({ where: { id: saldoId } });
    if (!saldo) throw commerceHttpError(404, "Saldo no encontrado");
    if (claim.count === 0) throw commerceHttpError(409, "Este saldo ya no esta pendiente");

    await this.reflejarEnTienda(
      saldo.wooOrderId,
      "pagado_por_fuera",
      `Saldo de ${pesos(saldo.montoSaldo)} registrado como pagado por fuera por ${actor.nombre}: ${motivo}`,
    ).catch((error) => {
      console.error("[saldos] no se pudo reflejar el pago por fuera en Woo", {
        saldoId,
        name: error instanceof Error ? error.name : "Error",
      });
    });
    if (saldo.usuarioId) {
      await this.avisos
        .notificarUsuario({
          usuarioId: saldo.usuarioId,
          tipo: "saldo_servicio_pagado",
          titulo: "Saldo registrado como pagado",
          mensaje: `Registramos el pago de tu saldo de ${pesos(saldo.montoSaldo)}. Ya puedes seguir haciendo pedidos.`,
          referenciaTipo: "SaldoServicio",
          referenciaId: saldo.id,
        })
        .catch(() => undefined);
    }
    const vivo = await this.prisma.pagoCobro.findFirst({
      where: { saldoServicioId: saldo.id, estado: { in: ["CREADO", "PENDIENTE"] } },
      select: { id: true },
    });
    return { id: saldo.id, estado: saldo.estado, habiaCodigoVigente: Boolean(vivo) };
  }

  /* ---------------------------- serializacion ----------------------------- */

  /** Lo que ve WordPress: montos y estado, nunca datos del cliente. */
  serializarParaTienda(saldo: SaldoServicio) {
    return {
      id: saldo.id,
      wooOrderId: saldo.wooOrderId,
      estado: saldo.estado,
      totalOrden: Number(saldo.totalOrden),
      pagadoAntes: Number(saldo.pagadoAntes),
      montoSaldo: Number(saldo.montoSaldo),
      servicios: saldo.servicios,
      servicioTerminadoEn: saldo.servicioTerminadoEn,
    };
  }

  serializarParaApp(saldo: SaldoServicio, cobro: PagoCobro | null) {
    return {
      ...this.serializarParaTienda(saldo),
      pedidoAppId: saldo.pedidoAppId,
      pagadoEn: saldo.pagadoEn,
      cobro: cobro
        ? {
            id: cobro.id,
            canal: cobro.canal,
            referenceCode: cobro.referenceCode,
            estado: cobro.estado,
            estadoProveedor: cobro.estadoProveedor,
            montoEsperado: Number(cobro.montoEsperado),
            moneda: cobro.moneda,
            qrBase64: cobro.qrBase64,
            brebKey: cobro.brebKey,
            expiraLocalEn: cobro.expiraLocalEn,
            creadoEn: cobro.creadoEn,
            actualizadoEn: cobro.actualizadoEn,
          }
        : null,
    };
  }
}
