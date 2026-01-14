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

    const [conjunto, maquinaria, operario] = await Promise.all([
      this.prisma.conjunto.findUnique({
        where: { nit: dto.conjuntoId },
        select: { nit: true },
      }),
      this.prisma.maquinaria.findUnique({
        where: { id: dto.maquinariaId },
        select: { id: true },
      }),
      this.prisma.operario.findUnique({
        where: { id: dto.operarioId },
        select: { id: true },
      }), // ✅ string
    ]);

    if (!conjunto) throw new Error("Conjunto no existe");
    if (!maquinaria) throw new Error("Maquinaria no existe");
    if (!operario) throw new Error("Operario no existe");

    return this.prisma.solicitudMaquinaria.create({
      data: {
        conjuntoId: dto.conjuntoId,
        maquinariaId: dto.maquinariaId,
        operarioId: dto.operarioId, // ✅ string
        empresaId: dto.empresaId ?? null,
        fechaUso: dto.fechaUso,
        fechaDevolucionEstimada: dto.fechaDevolucionEstimada,
      },
    });
  }

  async editar(id: number, payload: unknown) {
    const dto = EditarSolicitudMaquinariaDTO.parse(payload);

    return this.prisma.solicitudMaquinaria.update({
      where: { id },
      data: {
        maquinariaId: dto.maquinariaId ?? undefined,
        operarioId: dto.operarioId ?? undefined, // ✅ string | undefined
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
      if ((sol as any).estado === "APROBADA") return sol;

      const activa = await tx.maquinariaConjunto.findFirst({
        where: { maquinariaId: sol.maquinariaId, estado: "ACTIVA" },
        select: { id: true },
      });
      if (activa)
        throw new Error("La maquinaria no está disponible para préstamo");

      const asignacion = await tx.maquinariaConjunto.create({
        data: {
          conjunto: { connect: { nit: sol.conjuntoId } },
          maquinaria: { connect: { id: sol.maquinariaId } },

          tipoTenencia: "PRESTADA",
          estado: "ACTIVA",
          fechaInicio: dto.fechaAprobacion ?? new Date(),
          fechaDevolucionEstimada: sol.fechaDevolucionEstimada,

          // ✅ ahora sí puedes usar relación responsable
          ...(sol.operarioId
            ? { responsable: { connect: { id: sol.operarioId } } }
            : {}),

          // ✅ y también conectar la solicitud (si tu relación existe así)
          solicitudMaquinaria: { connect: { id: sol.id } },
        },
      });

      const updated = await tx.solicitudMaquinaria.update({
        where: { id },
        data: {
          estado: "APROBADA",
          fechaAprobacion: dto.fechaAprobacion ?? new Date(),
        } as any,
      });

      return { solicitud: updated, asignacion };
    });
  }

  async listar(payload: unknown) {
    const f = FiltroSolicitudMaquinariaDTO.parse(payload);

    const rango: { gte?: Date; lte?: Date } = {};
    if (f.fechaDesde) rango.gte = f.fechaDesde;
    if (f.fechaHasta) rango.lte = f.fechaHasta;

    return this.prisma.solicitudMaquinaria.findMany({
      where: {
        conjuntoId: f.conjuntoId ?? undefined,
        empresaId: f.empresaId ?? undefined,
        maquinariaId: f.maquinariaId ?? undefined,
        operarioId: f.operarioId ?? undefined, // ✅ string
        // aprobado: f.aprobado ?? undefined,   // ❌ solo si existe en schema
        fechaSolicitud: Object.keys(rango).length > 0 ? rango : undefined,
      } as any,
      orderBy: { id: "desc" },
    });
  }

  async obtener(id: number) {
    return this.prisma.solicitudMaquinaria.findUnique({ where: { id } });
  }

  async eliminar(id: number) {
    await this.prisma.solicitudMaquinaria.delete({ where: { id } });
  }
}
