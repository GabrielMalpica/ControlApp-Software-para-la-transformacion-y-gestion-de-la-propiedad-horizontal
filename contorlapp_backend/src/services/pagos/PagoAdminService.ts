import { CanalPago, EstadoCobro, Prisma, type PagoCobro, type PrismaClient } from "@prisma/client";
import { z } from "zod";
import { commerceHttpError, type CommerceActor } from "../CommerceAccessService";

// Cobros que necesitan que una persona decida (dinero recibido que no se
// pudo aplicar solo).
export const ESTADOS_REQUIEREN_ACCION: EstadoCobro[] = [
  EstadoCobro.PAGADO_HUERFANO,
  EstadoCobro.PAGADO_DUPLICADO,
  EstadoCobro.DISCREPANCIA,
];

export const ListarPagosDTO = z.object({
  canal: z.nativeEnum(CanalPago).optional(),
  estado: z.nativeEnum(EstadoCobro).optional(),
  requierenAccion: z
    .enum(["true", "false"])
    .transform((v) => v === "true")
    .optional(),
  desde: z.coerce.date().optional(),
  hasta: z.coerce.date().optional(),
  q: z.string().trim().max(100).optional(),
  pagina: z.coerce.number().int().min(1).default(1),
  porPagina: z.coerce.number().int().min(1).max(100).default(25),
});

export const ResolverPagoDTO = z.object({
  accion: z.enum(["DEVUELTO", "RESUELTO"]),
  motivo: z.string().trim().min(5, "Explica brevemente que se hizo").max(500),
});

export const ReporteRecaudoDTO = z.object({
  desde: z.coerce.date(),
  hasta: z.coerce.date(),
  agrupar: z.enum(["dia", "canal"]).default("dia"),
});

/** Consultas y acciones del equipo (gerente / jefe de operaciones) sobre los cobros. */
export class PagoAdminService {
  constructor(private prisma: PrismaClient) {}

  /**
   * Cobros de la empresa del actor: los de pedidos de sus conjuntos, mas los
   * de la tienda web sin pedido en la app (no pertenecen a un conjunto).
   */
  private alcance(actor: CommerceActor): Prisma.PagoCobroWhereInput {
    if (!actor.empresaId) throw commerceHttpError(403, "Tu usuario no esta asociado a una empresa");
    return {
      OR: [{ pedidoApp: { conjunto: { empresaId: actor.empresaId } } }, { pedidoAppId: null }],
    };
  }

  private serializar(cobro: PagoCobro & { pedidoApp?: { id: number; conjunto: { nombre: string } | null } | null }) {
    return {
      id: cobro.id,
      referenceCode: cobro.referenceCode,
      canal: cobro.canal,
      estado: cobro.estado,
      estadoProveedor: cobro.estadoProveedor,
      montoEsperado: Number(cobro.montoEsperado),
      montoProveedor: cobro.montoProveedor == null ? null : Number(cobro.montoProveedor),
      moneda: cobro.moneda,
      pedidoAppId: cobro.pedidoAppId,
      wooOrderId: cobro.wooOrderId,
      conjuntoNombre: cobro.pedidoApp?.conjunto?.nombre ?? null,
      pagadoDetectadoEn: cobro.pagadoDetectadoEn,
      pendienteSincronizarWoo: cobro.pendienteSincronizarWoo,
      requiereAccion: ESTADOS_REQUIEREN_ACCION.includes(cobro.estado),
      creadoEn: cobro.creadoEn,
      actualizadoEn: cobro.actualizadoEn,
    };
  }

  async listar(actor: CommerceActor, query: unknown) {
    const f = ListarPagosDTO.parse(query);
    const filtros: Prisma.PagoCobroWhereInput[] = [this.alcance(actor)];
    if (f.canal) filtros.push({ canal: f.canal });
    if (f.estado) filtros.push({ estado: f.estado });
    if (f.requierenAccion) filtros.push({ estado: { in: ESTADOS_REQUIEREN_ACCION } });
    if (f.desde || f.hasta) filtros.push({ creadoEn: { gte: f.desde, lte: f.hasta } });
    if (f.q) {
      const num = /^\d+$/.test(f.q) ? Number(f.q) : null;
      filtros.push({
        OR: [
          { referenceCode: { contains: f.q, mode: "insensitive" } },
          { wooOrderId: f.q },
          ...(num != null ? [{ pedidoAppId: num }] : []),
        ],
      });
    }
    const where: Prisma.PagoCobroWhereInput = { AND: filtros };

    const [total, filas] = await Promise.all([
      this.prisma.pagoCobro.count({ where }),
      this.prisma.pagoCobro.findMany({
        where,
        orderBy: { creadoEn: "desc" },
        skip: (f.pagina - 1) * f.porPagina,
        take: f.porPagina,
        include: { pedidoApp: { select: { id: true, conjunto: { select: { nombre: true } } } } },
      }),
    ]);
    return { total, pagina: f.pagina, porPagina: f.porPagina, items: filas.map((c) => this.serializar(c)) };
  }

  async obtener(actor: CommerceActor, cobroId: number) {
    const cobro = await this.prisma.pagoCobro.findFirst({
      where: { AND: [{ id: cobroId }, this.alcance(actor)] },
      include: {
        pedidoApp: { select: { id: true, conjunto: { select: { nombre: true } } } },
        eventos: { orderBy: { creadoEn: "asc" } },
      },
    });
    if (!cobro) throw commerceHttpError(404, "Cobro no encontrado");
    return {
      ...this.serializar(cobro),
      eventos: cobro.eventos.map((e) => ({
        id: e.id,
        tipo: e.tipo,
        estadoAnterior: e.estadoAnterior,
        estadoNuevo: e.estadoNuevo,
        payload: e.payload,
        actorId: e.actorId,
        creadoEn: e.creadoEn,
      })),
    };
  }

  /**
   * Cierra un cobro que necesitaba decision humana. No mueve dinero ni
   * reactiva pedidos: solo deja constancia de lo que se hizo por fuera
   * (devolver el dinero, o resolverlo por otra via) para que salga de la
   * lista de pendientes. Queda en la bitacora del cobro con quien lo hizo.
   */
  async resolver(actor: CommerceActor, cobroId: number, payload: unknown) {
    const dto = ResolverPagoDTO.parse(payload);
    const cobro = await this.prisma.pagoCobro.findFirst({ where: { AND: [{ id: cobroId }, this.alcance(actor)] } });
    if (!cobro) throw commerceHttpError(404, "Cobro no encontrado");
    if (!ESTADOS_REQUIEREN_ACCION.includes(cobro.estado)) {
      throw commerceHttpError(409, "Este cobro no esta pendiente de una decision");
    }

    const estadoNuevo = dto.accion === "DEVUELTO" ? EstadoCobro.DEVUELTO : EstadoCobro.RESUELTO;
    await this.prisma.$transaction(async (tx) => {
      const claim = await tx.pagoCobro.updateMany({
        where: { id: cobro.id, estado: cobro.estado },
        data: { estado: estadoNuevo },
      });
      if (claim.count === 0) throw commerceHttpError(409, "El cobro cambio mientras lo resolvias. Actualiza e intenta de nuevo");
      await tx.pagoEvento.create({
        data: {
          cobroId: cobro.id,
          tipo: "ACCION_MANUAL",
          estadoAnterior: cobro.estado,
          estadoNuevo,
          payload: { accion: dto.accion, motivo: dto.motivo, nombre: actor.nombre },
          actorId: actor.id,
        },
      });
    });
    return this.obtener(actor, cobro.id);
  }

  /** Recaudo confirmado (cobros PAGADO) por dia o por canal en un rango de fechas. */
  async reporteRecaudo(actor: CommerceActor, query: unknown) {
    const dto = ReporteRecaudoDTO.parse(query);
    const cobros = await this.prisma.pagoCobro.findMany({
      where: {
        AND: [
          this.alcance(actor),
          { estado: EstadoCobro.PAGADO },
          { pagadoDetectadoEn: { gte: dto.desde, lte: dto.hasta } },
        ],
      },
      select: { canal: true, montoEsperado: true, pagadoDetectadoEn: true },
    });

    const grupos = new Map<string, { total: number; cantidad: number }>();
    for (const c of cobros) {
      const clave =
        dto.agrupar === "canal" ? c.canal : (c.pagadoDetectadoEn as Date).toISOString().slice(0, 10);
      const g = grupos.get(clave) ?? { total: 0, cantidad: 0 };
      g.total += Number(c.montoEsperado);
      g.cantidad += 1;
      grupos.set(clave, g);
    }
    return {
      agrupar: dto.agrupar,
      totalRecaudado: cobros.reduce((s, c) => s + Number(c.montoEsperado), 0),
      cantidad: cobros.length,
      grupos: [...grupos.entries()]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([clave, g]) => ({ clave, ...g })),
    };
  }

  /** Cuantos cobros esperan una decision (para el indicador del panel). */
  async contarRequierenAccion(actor: CommerceActor) {
    return this.prisma.pagoCobro.count({
      where: { AND: [this.alcance(actor), { estado: { in: ESTADOS_REQUIEREN_ACCION } }] },
    });
  }
}
