// src/services/SolicitudMaquinariaService.ts
import { PrismaClient } from "../generated/prisma";
import {
  CrearSolicitudMaquinariaDTO,
  EditarSolicitudMaquinariaDTO,
  AprobarSolicitudMaquinariaDTO,
  FiltroSolicitudMaquinariaDTO,
} from "../model/SolicitudMaquinaria";

export class SolicitudMaquinariaService {
  constructor(private prisma: PrismaClient) {}

  async crear(payload: unknown) {
    const dto = CrearSolicitudMaquinariaDTO.parse(payload);

    // Validaciones básicas
    const [conjunto, maquinaria, operario] = await Promise.all([
      this.prisma.conjunto.findUnique({ where: { nit: dto.conjuntoId } }),
      this.prisma.maquinaria.findUnique({ where: { id: dto.maquinariaId } }),
      this.prisma.operario.findUnique({ where: { id: dto.operarioId.toString() } }),
    ]);
    if (!conjunto) throw new Error("Conjunto no existe");
    if (!maquinaria) throw new Error("Maquinaria no existe");
    if (!operario) throw new Error("Operario no existe");

    return this.prisma.solicitudMaquinaria.create({
      data: {
        conjuntoId: dto.conjuntoId,
        maquinariaId: dto.maquinariaId,
        operarioId: dto.operarioId.toString(),
        empresaId: dto.empresaId ?? null,
        fechaUso: dto.fechaUso,
        fechaDevolucionEstimada: dto.fechaDevolucionEstimada,
        aprobado: false,
        // fechaSolicitud la pone Prisma por default(now())
      },
    });
  }

  async editar(id: number, payload: unknown) {
    const dto = EditarSolicitudMaquinariaDTO.parse(payload);
    return this.prisma.solicitudMaquinaria.update({
      where: { id },
      data: {
        maquinariaId: dto.maquinariaId ?? undefined,
        operarioId: dto.operarioId!.toString() ?? undefined,
        empresaId: dto.empresaId === undefined ? undefined : dto.empresaId,
        fechaUso: dto.fechaUso ?? undefined,
        fechaDevolucionEstimada: dto.fechaDevolucionEstimada ?? undefined,
      },
    });
  }

  async aprobar(id: number, payload: unknown) {
    const dto = AprobarSolicitudMaquinariaDTO.parse(payload);

    return this.prisma.$transaction(async (tx) => {
      const sol = await tx.solicitudMaquinaria.findUnique({ where: { id } });
      if (!sol) throw new Error("Solicitud no encontrada");
      if (sol.aprobado) return sol;

      // Verificar disponibilidad real de la maquinaria antes de prestarla
      const maq = await tx.maquinaria.findUnique({
        where: { id: sol.maquinariaId },
        select: { disponible: true, conjuntoId: true },
      });
      if (!maq) throw new Error("Maquinaria no existe");
      if (!maq.disponible) {
        throw new Error("La maquinaria no está disponible para préstamo");
      }

      // Asignar maquinaria al conjunto/operario y bloquearla
      await tx.maquinaria.update({
        where: { id: sol.maquinariaId },
        data: {
          disponible: false,
          conjuntoId: sol.conjuntoId,
          operarioId: sol.operarioId,
          fechaPrestamo: dto.fechaAprobacion ?? new Date(),
          fechaDevolucionEstimada: sol.fechaDevolucionEstimada,
        },
      });

      // Marcar solicitud como aprobada
      return tx.solicitudMaquinaria.update({
        where: { id },
        data: {
          aprobado: true,
          fechaAprobacion: dto.fechaAprobacion ?? new Date(),
        },
      });
    });
  }

  async listar(payload: unknown) {
    const f = FiltroSolicitudMaquinariaDTO.parse(payload);

    // Construir rango sobre fechaSolicitud (tu campo existente)
    const rango: { gte?: Date; lte?: Date } = {};
    if (f.fechaDesde) rango.gte = f.fechaDesde;
    if (f.fechaHasta) rango.lte = f.fechaHasta;

    return this.prisma.solicitudMaquinaria.findMany({
      where: {
        conjuntoId: f.conjuntoId ?? undefined,
        empresaId: f.empresaId ?? undefined,
        maquinariaId: f.maquinariaId ?? undefined,
        operarioId: f.operarioId!.toString() ?? undefined,
        aprobado: f.aprobado ?? undefined,
        fechaSolicitud:
          Object.keys(rango).length > 0 ? rango : undefined, // sólo si viene gte/lte
      },
      orderBy: { id: "desc" },
    });
  }

  async obtener(id: number) {
    return this.prisma.solicitudMaquinaria.findUnique({
      where: { id },
    });
  }

  async eliminar(id: number) {
    await this.prisma.solicitudMaquinaria.delete({ where: { id } });
  }
}
