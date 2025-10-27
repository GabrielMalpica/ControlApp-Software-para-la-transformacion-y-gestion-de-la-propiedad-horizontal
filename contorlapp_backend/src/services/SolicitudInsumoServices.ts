// src/services/SolicitudInsumoService.ts
import { PrismaClient } from "../generated/prisma";
import {
  CrearSolicitudInsumoDTO,
  AprobarSolicitudInsumoDTO,
  FiltroSolicitudInsumoDTO,
} from "../model/SolicitudInsumo";

export class SolicitudInsumoService {
  constructor(private prisma: PrismaClient) {}

  async crear(payload: unknown) {
    const dto = CrearSolicitudInsumoDTO.parse(payload);

    // Validaciones básicas
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: dto.conjuntoId },
      select: { nit: true },
    });
    if (!conjunto) throw new Error("Conjunto no existe");

    // Validar que todos los insumos existan
    const insumoIds = dto.items.map((i) => i.insumoId);
    const insumos = await this.prisma.insumo.findMany({
      where: { id: { in: insumoIds } },
      select: { id: true },
    });
    if (insumos.length !== insumoIds.length) {
      throw new Error("Uno o más insumos no existen");
    }

    // Crear con nested create en la relación insumosSolicitados
    return this.prisma.solicitudInsumo.create({
      data: {
        conjuntoId: dto.conjuntoId,
        empresaId: dto.empresaId ?? null,
        aprobado: false,
        insumosSolicitados: {
          create: dto.items.map((it) => ({
            insumoId: it.insumoId,
            cantidad: it.cantidad,
          })),
        },
      },
      include: { insumosSolicitados: true },
    });
  }

  async aprobar(id: number, payload: unknown) {
    const dto = AprobarSolicitudInsumoDTO.parse(payload);

    const sol = await this.prisma.solicitudInsumo.findUnique({
      where: { id },
      include: { insumosSolicitados: true },
    });
    if (!sol) throw new Error("Solicitud no encontrada");
    if (sol.aprobado) return sol;

    // (opcional) al aprobar podrías provisionar inventario del conjunto:
    // const inventario = await this.prisma.inventario.findUnique({ where: { conjuntoId: sol.conjuntoId }});
    // if (inventario) {
    //   for (const it of sol.insumosSolicitados) {
    //     await this.prisma.inventarioInsumo.upsert({
    //       where: { inventarioId_insumoId: { inventarioId: inventario.id, insumoId: it.insumoId } },
    //       update: { cantidad: { increment: it.cantidad } },
    //       create: { inventarioId: inventario.id, insumoId: it.insumoId, cantidad: it.cantidad },
    //     });
    //   }
    // }

    return this.prisma.solicitudInsumo.update({
      where: { id },
      data: {
        aprobado: true,
        fechaAprobacion: dto.fechaAprobacion ?? new Date(),
        empresaId: dto.empresaId ?? undefined,
      },
      include: { insumosSolicitados: true },
    });
  }

  async listar(payload: unknown) {
    const f = FiltroSolicitudInsumoDTO.parse(payload);

    // Construir rango sobre fechaSolicitud
    const rango: { gte?: Date; lte?: Date } = {};
    if (f.fechaDesde) rango.gte = f.fechaDesde;
    if (f.fechaHasta) rango.lte = f.fechaHasta;

    return this.prisma.solicitudInsumo.findMany({
      where: {
        conjuntoId: f.conjuntoId ?? undefined,
        empresaId: f.empresaId ?? undefined,
        aprobado: f.aprobado ?? undefined,
        fechaSolicitud: Object.keys(rango).length ? rango : undefined,
      },
      include: { insumosSolicitados: true },
      orderBy: { id: "desc" },
    });
  }

  async obtener(id: number) {
    return this.prisma.solicitudInsumo.findUnique({
      where: { id },
      include: { insumosSolicitados: true },
    });
  }

  async eliminar(id: number) {
    await this.prisma.solicitudInsumo.delete({ where: { id } });
  }
}
