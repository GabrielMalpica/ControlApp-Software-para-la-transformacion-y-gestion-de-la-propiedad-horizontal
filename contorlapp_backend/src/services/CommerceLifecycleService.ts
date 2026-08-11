import {
  EstadoPedidoInterno,
  Prisma,
  Rol,
  TipoMovimientoInsumo,
  TipoPedidoApp,
  type PrismaClient,
} from "@prisma/client";
import { CambiarEstadoPedidoDTO, MapearPedidoItemDTO } from "../model/Commerce";
import {
  CommerceAccessService,
  commerceHttpError,
  type CommerceActor,
} from "./CommerceAccessService";
import { CommercePointsService } from "./CommercePointsService";

type TransactionClient = Prisma.TransactionClient;

const TRANSICIONES: Record<EstadoPedidoInterno, EstadoPedidoInterno[]> = {
  BORRADOR: [EstadoPedidoInterno.PENDIENTE_PAGO, EstadoPedidoInterno.CANCELADO],
  PENDIENTE_PAGO: [EstadoPedidoInterno.PAGADO, EstadoPedidoInterno.CANCELADO],
  PAGADO: [EstadoPedidoInterno.PENDIENTE_ENVIO, EstadoPedidoInterno.CANCELADO],
  PENDIENTE_ENVIO: [EstadoPedidoInterno.ENVIADO, EstadoPedidoInterno.CANCELADO],
  ENVIADO: [EstadoPedidoInterno.RECIBIDO],
  RECIBIDO: [EstadoPedidoInterno.ENTREGADO],
  ENTREGADO: [],
  CANCELADO: [],
};

/**
 * TODO(pasarela-Mono): consultar el estado de pago en WooCommerce/Mono.la antes
 * de permitir PENDIENTE_PAGO -> PAGADO desde un flujo confiable del servidor.
 */
export async function verificarPagoEnWooCommerce(_pedidoId: number): Promise<boolean> {
  return false;
}

/**
 * TODO(pasarela-Mono): validar criptograficamente la firma y la antiguedad del
 * webhook antes de aceptar cualquier cambio de estado de pago.
 */
export async function validarWebhookWooCommerce(
  _payload: unknown,
  _signature: string,
): Promise<boolean> {
  return false;
}

type PedidoCompleto = Prisma.PedidoAppGetPayload<{
  include: {
    conjunto: { select: { nombre: true; empresaId: true } };
    items: { include: { insumo: { select: { id: true; nombre: true; unidad: true } } } };
    historialEstados: {
      include: { cambiadoPor: { select: { nombre: true } } };
    };
    consumosInventario: {
      include: {
        insumo: { select: { id: true; nombre: true; unidad: true } };
        inventario: {
          select: {
            insumos: { select: { insumoId: true; cantidad: true } };
          };
        };
      };
    };
  };
}>;

type PedidoRecepcion = Prisma.PedidoAppGetPayload<{
  include: {
    conjunto: { select: { nombre: true; empresaId: true } };
    items: { include: { insumo: true } };
  };
}>;

type ItemMapping = {
  item: PedidoRecepcion["items"][number];
  insumo: { id: number; nombre: string; unidad: string } | null;
  origen: "MANUAL" | "WOO_PRODUCT_ID" | "SKU" | "SIN_MAPEO";
};

export class CommerceLifecycleService {
  private readonly access: CommerceAccessService;
  private readonly points: CommercePointsService;

  constructor(private prisma: PrismaClient) {
    this.access = new CommerceAccessService(prisma);
    this.points = new CommercePointsService(prisma);
  }

  private getAllowedTransitions(actor: CommerceActor, pedido: PedidoCompleto) {
    const possible = TRANSICIONES[pedido.estado];
    if (actor.rol !== Rol.residente) return possible;

    const residentAllowed: Partial<Record<EstadoPedidoInterno, EstadoPedidoInterno[]>> = {
      BORRADOR: [EstadoPedidoInterno.CANCELADO],
      PENDIENTE_PAGO: [EstadoPedidoInterno.CANCELADO],
      ENVIADO: [EstadoPedidoInterno.RECIBIDO],
      RECIBIDO: [EstadoPedidoInterno.ENTREGADO],
    };
    return possible.filter((estado) => residentAllowed[pedido.estado]?.includes(estado));
  }

  private async loadPedido(pedidoId: number) {
    const pedido = await this.prisma.pedidoApp.findUnique({
      where: { id: pedidoId },
      include: {
        conjunto: { select: { nombre: true, empresaId: true } },
        items: {
          include: { insumo: { select: { id: true, nombre: true, unidad: true } } },
        },
        historialEstados: {
          include: { cambiadoPor: { select: { nombre: true } } },
          orderBy: { creadoEn: "asc" },
        },
        consumosInventario: {
          include: {
            insumo: { select: { id: true, nombre: true, unidad: true } },
            inventario: {
              select: { insumos: { select: { insumoId: true, cantidad: true } } },
            },
          },
          orderBy: { fecha: "asc" },
        },
      },
    });
    if (!pedido) throw commerceHttpError(404, "Pedido no encontrado");
    return pedido;
  }

  private serializePedido(actor: CommerceActor, pedido: PedidoCompleto) {
    return {
      id: pedido.id,
      tipo: pedido.tipo,
      estado: pedido.estado,
      estadoWoo: pedido.estadoWoo,
      wooOrderId: pedido.wooOrderId,
      usuarioId: pedido.usuarioId,
      conjuntoId: pedido.conjuntoId,
      conjuntoNombre: pedido.conjunto?.nombre ?? null,
      total: Number(pedido.total),
      moneda: pedido.moneda,
      pagarAhora: Number(pedido.pagarAhora),
      fechaServicio: pedido.fechaServicio,
      turnoServicio: pedido.turnoServicio,
      opcionPagoServicio: pedido.opcionPagoServicio,
      addonsServicio: pedido.addonsServicio,
      whatsappPhone: String(
        process.env.WOO_WHATSAPP_PHONE ?? process.env.WHATSAPP_PHONE ?? "",
      ).replace(/\D/g, ""),
      creadoEn: pedido.creadoEn,
      actualizadoEn: pedido.actualizadoEn,
      entradaInventarioAplicada: pedido.entradaInventarioAplicada,
      entradaInventarioAplicadaEn: pedido.entradaInventarioAplicadaEn,
      puntosAplicados: pedido.puntosAplicados,
      puntosAplicadosEn: pedido.puntosAplicadosEn,
      descuentoPuntos: Number(pedido.descuentoPuntos),
      transicionesPermitidas: this.getAllowedTransitions(actor, pedido),
      items: pedido.items.map((item) => ({
        id: item.id,
        wooProductId: item.wooProductId,
        nombreProducto: item.nombreProducto,
        sku: item.sku,
        cantidad: Number(item.cantidad),
        precioUnitario: Number(item.precioUnitario),
        subtotal: Number(item.subtotal),
        pagarAhora: Number(item.pagarAhora),
        fechaServicio: item.fechaServicio,
        turnoServicio: item.turnoServicio,
        opcionPagoServicio: item.opcionPagoServicio,
        addonsServicio: item.addonsServicio,
        insumo: item.insumo,
      })),
      historial: pedido.historialEstados.map((item) => ({
        id: item.id,
        estadoAnterior: item.estadoAnterior,
        estadoNuevo: item.estadoNuevo,
        cambiadoPor: item.cambiadoPor.nombre,
        cambiadoPorRol: item.cambiadoPorRol,
        motivo: item.motivo,
        creadoEn: item.creadoEn,
      })),
      entradasInventario: pedido.consumosInventario.map((consumo) => {
        const stock = consumo.inventario.insumos.find(
          (item) => item.insumoId === consumo.insumoId,
        );
        return {
          insumoId: consumo.insumoId,
          insumoNombre: consumo.insumo.nombre,
          unidad: consumo.insumo.unidad,
          cantidad: Number(consumo.cantidad),
          stockActual: Number(stock?.cantidad ?? 0),
          fecha: consumo.fecha,
        };
      }),
    };
  }

  async getPedido(userId: string, pedidoId: number) {
    const [actor, pedido] = await Promise.all([
      this.access.getActor(userId),
      this.loadPedido(pedidoId),
    ]);
    await this.access.assertPedidoAccess(actor, pedido);
    return this.serializePedido(actor, pedido);
  }

  private async resolveMappings(
    client: TransactionClient | PrismaClient,
    pedido: PedidoRecepcion,
  ): Promise<ItemMapping[]> {
    const empresaId = pedido.conjunto?.empresaId;
    if (!empresaId) {
      return pedido.items.map((item) => ({ item, insumo: null, origen: "SIN_MAPEO" }));
    }

    const mappings: ItemMapping[] = [];
    for (const item of pedido.items) {
      if (item.insumo && item.insumo.empresaId === empresaId) {
        mappings.push({ item, insumo: item.insumo, origen: "MANUAL" });
        continue;
      }
      if (item.wooProductId) {
        const byProduct = await client.insumo.findFirst({
          where: { empresaId, wooProductId: item.wooProductId },
          select: { id: true, nombre: true, unidad: true },
        });
        if (byProduct) {
          mappings.push({ item, insumo: byProduct, origen: "WOO_PRODUCT_ID" });
          continue;
        }
      }
      if (item.sku?.trim()) {
        const bySku = await client.insumo.findFirst({
          where: {
            empresaId,
            wooSku: { equals: item.sku.trim(), mode: "insensitive" },
          },
          select: { id: true, nombre: true, unidad: true },
        });
        if (bySku) {
          mappings.push({ item, insumo: bySku, origen: "SKU" });
          continue;
        }
      }
      mappings.push({ item, insumo: null, origen: "SIN_MAPEO" });
    }
    return mappings;
  }

  private async loadPedidoRecepcion(client: TransactionClient | PrismaClient, pedidoId: number) {
    return client.pedidoApp.findUnique({
      where: { id: pedidoId },
      include: { conjunto: { select: { nombre: true, empresaId: true } }, items: { include: { insumo: true } } },
    });
  }

  async previewRecepcion(userId: string, pedidoId: number) {
    const actor = await this.access.getActor(userId);
    if (!this.access.esRolOperativo(actor)) {
      throw commerceHttpError(403, "Solo administracion u operaciones pueden recibir inventario");
    }
    const pedido = await this.loadPedidoRecepcion(this.prisma, pedidoId);
    if (!pedido || pedido.tipo !== TipoPedidoApp.CONJUNTO || !pedido.conjuntoId) {
      throw commerceHttpError(404, "Pedido operativo no encontrado");
    }
    await this.access.assertConjuntoAccess(actor, pedido.conjuntoId);

    const mappings = await this.resolveMappings(this.prisma, pedido);
    const insumosDisponibles = pedido.conjunto?.empresaId
      ? await this.prisma.insumo.findMany({
          where: { empresaId: pedido.conjunto.empresaId },
          select: { id: true, nombre: true, unidad: true, wooSku: true, wooProductId: true },
          orderBy: { nombre: "asc" },
        })
      : [];
    return {
      pedidoId,
      puedeAplicar:
        !pedido.entradaInventarioAplicada &&
        pedido.estado === EstadoPedidoInterno.ENVIADO &&
        mappings.every((mapping) => mapping.insumo !== null),
      yaAplicada: pedido.entradaInventarioAplicada,
      mensaje: pedido.entradaInventarioAplicada
        ? "La entrada de este pedido ya fue aplicada"
        : mappings.some((mapping) => !mapping.insumo)
          ? "Mapea todos los productos antes de confirmar la recepcion"
          : "La confirmacion sumara estas cantidades al inventario de forma definitiva",
      items: mappings.map((mapping) => ({
        itemId: mapping.item.id,
        producto: mapping.item.nombreProducto,
        sku: mapping.item.sku,
        cantidad: Number(mapping.item.cantidad),
        insumo: mapping.insumo,
        origenMapeo: mapping.origen,
      })),
      insumosDisponibles,
    };
  }

  async mapearItem(userId: string, pedidoId: number, itemId: number, payload: unknown) {
    const { insumoId } = MapearPedidoItemDTO.parse(payload);
    const actor = await this.access.getActor(userId);
    if (!this.access.esRolOperativo(actor)) {
      throw commerceHttpError(403, "Tu rol no puede mapear productos a insumos");
    }
    const initial = await this.loadPedidoRecepcion(this.prisma, pedidoId);
    if (!initial || initial.tipo !== TipoPedidoApp.CONJUNTO || !initial.conjuntoId) {
      throw commerceHttpError(404, "Pedido operativo no encontrado");
    }
    await this.access.assertConjuntoAccess(actor, initial.conjuntoId);

    await this.prisma.$transaction(async (tx) => {
      const pedido = await this.loadPedidoRecepcion(tx, pedidoId);
      if (!pedido || pedido.tipo !== TipoPedidoApp.CONJUNTO || !pedido.conjuntoId) {
        throw commerceHttpError(404, "Pedido operativo no encontrado");
      }
      if (pedido.entradaInventarioAplicada) {
        throw commerceHttpError(409, "El inventario de este pedido ya fue aplicado");
      }
      const item = pedido.items.find((value) => value.id === itemId);
      if (!item) throw commerceHttpError(404, "El item no pertenece al pedido");
      const empresaId = pedido.conjunto?.empresaId;
      if (!empresaId) {
        throw commerceHttpError(409, "El conjunto no tiene una empresa para resolver insumos");
      }
      const insumo = await tx.insumo.findFirst({ where: { id: insumoId, empresaId } });
      if (!insumo) throw commerceHttpError(404, "El insumo no pertenece a la empresa del conjunto");

      const identifiers: Prisma.InsumoWhereInput[] = [
        ...(item.wooProductId ? [{ wooProductId: item.wooProductId }] : []),
        ...(item.sku?.trim() ? [{ wooSku: item.sku.trim() }] : []),
      ];
      const conflict = identifiers.length
        ? await tx.insumo.findFirst({
            where: {
              empresaId,
              id: { not: insumoId },
              OR: identifiers,
            },
            select: { nombre: true },
          })
        : null;
      if (conflict) {
        throw commerceHttpError(
          409,
          `El producto ya esta asociado al insumo ${conflict.nombre}. Corrige ese mapeo primero`,
        );
      }

      await tx.insumo.update({
        where: { id: insumoId },
        data: {
          ...(item.wooProductId && !insumo.wooProductId
            ? { wooProductId: item.wooProductId }
            : {}),
          ...(item.sku?.trim() && !insumo.wooSku ? { wooSku: item.sku.trim() } : {}),
        },
      });
      await tx.pedidoAppItem.update({ where: { id: itemId }, data: { insumoId } });
    });

    return this.previewRecepcion(userId, pedidoId);
  }

  private async applyInventory(tx: TransactionClient, pedido: PedidoRecepcion) {
    if (pedido.entradaInventarioAplicada) return;
    if (!pedido.conjuntoId) throw commerceHttpError(409, "El pedido no tiene conjunto asociado");

    const mappings = await this.resolveMappings(tx, pedido);
    const missing = mappings.filter((mapping) => !mapping.insumo);
    if (missing.length) {
      throw commerceHttpError(
        409,
        `Falta mapear ${missing.map((mapping) => mapping.item.nombreProducto).join(", ")}`,
      );
    }

    const grouped = new Map<number, { cantidad: Prisma.Decimal; nombre: string }>();
    for (const mapping of mappings) {
      const insumo = mapping.insumo!;
      const current = grouped.get(insumo.id);
      grouped.set(insumo.id, {
        nombre: insumo.nombre,
        cantidad: new Prisma.Decimal(current?.cantidad ?? 0).plus(mapping.item.cantidad),
      });
    }

    const claim = await tx.pedidoApp.updateMany({
      where: { id: pedido.id, entradaInventarioAplicada: false },
      data: { entradaInventarioAplicada: true, entradaInventarioAplicadaEn: new Date() },
    });
    if (claim.count === 0) return;

    const inventario = await tx.inventario.upsert({
      where: { conjuntoId: pedido.conjuntoId },
      create: { conjuntoId: pedido.conjuntoId },
      update: {},
    });
    for (const [insumoId, item] of grouped) {
      await tx.inventarioInsumo.upsert({
        where: { inventarioId_insumoId: { inventarioId: inventario.id, insumoId } },
        create: { inventarioId: inventario.id, insumoId, cantidad: item.cantidad },
        update: { cantidad: { increment: item.cantidad } },
      });
      await tx.consumoInsumo.upsert({
        where: {
          pedidoAppId_insumoId_tipo: {
            pedidoAppId: pedido.id,
            insumoId,
            tipo: TipoMovimientoInsumo.ENTRADA,
          },
        },
        create: {
          inventarioId: inventario.id,
          insumoId,
          pedidoAppId: pedido.id,
          tipo: TipoMovimientoInsumo.ENTRADA,
          cantidad: item.cantidad,
          fecha: new Date(),
          observacion: `Entrada por recepcion del pedido operativo #${pedido.id}`,
        },
        update: {},
      });
    }
  }

  async transicionar(userId: string, pedidoId: number, payload: unknown) {
    const dto = CambiarEstadoPedidoDTO.parse(payload);
    const actor = await this.access.getActor(userId);
    const initial = await this.loadPedido(pedidoId);
    await this.access.assertPedidoAccess(actor, initial);

    if (initial.estado === dto.estadoDestino) {
      return this.serializePedido(actor, initial);
    }
    const allowed = this.getAllowedTransitions(actor, initial);
    if (!allowed.includes(dto.estadoDestino)) {
      throw commerceHttpError(
        409,
        `No puedes pasar el pedido de ${initial.estado} a ${dto.estadoDestino}`,
      );
    }

    await this.prisma.$transaction(async (tx) => {
      const pedido = await this.loadPedidoRecepcion(tx, pedidoId);
      if (!pedido) throw commerceHttpError(404, "Pedido no encontrado");
      if (pedido.estado !== initial.estado) {
        throw commerceHttpError(409, "El pedido cambio de estado. Actualiza el detalle e intenta de nuevo");
      }

      if (
        dto.estadoDestino === EstadoPedidoInterno.RECIBIDO &&
        pedido.tipo === TipoPedidoApp.CONJUNTO
      ) {
        await this.applyInventory(tx, pedido);
      }

      const updated = await tx.pedidoApp.updateMany({
        where: { id: pedidoId, estado: initial.estado },
        data: { estado: dto.estadoDestino },
      });
      if (updated.count === 0) {
        throw commerceHttpError(409, "El pedido cambio de estado. Actualiza e intenta de nuevo");
      }
      await tx.pedidoAppEstadoHistorico.create({
        data: {
          pedidoId,
          estadoAnterior: initial.estado,
          estadoNuevo: dto.estadoDestino,
          cambiadoPorId: actor.id,
          cambiadoPorRol: actor.rol,
          motivo: dto.motivo || null,
        },
      });

      if (dto.estadoDestino === EstadoPedidoInterno.ENTREGADO) {
        await this.points.applyAccumulation(tx, {
          id: pedido.id,
          usuarioId: pedido.usuarioId,
          conjuntoId: pedido.conjuntoId,
          tipo: pedido.tipo,
          estado: dto.estadoDestino,
          total: pedido.total,
          puntosAplicados: pedido.puntosAplicados,
          entregaVerificada: initial.estado === EstadoPedidoInterno.RECIBIDO,
        });
      }
    });

    return this.getPedido(userId, pedidoId);
  }
}
