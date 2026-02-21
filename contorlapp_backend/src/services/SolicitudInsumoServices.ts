// src/services/SolicitudInsumoService.ts
import { PrismaClient } from "@prisma/client";
import {
  CrearSolicitudInsumoDTO,
  AprobarSolicitudInsumoDTO,
  FiltroSolicitudInsumoDTO,
} from "../model/SolicitudInsumo";
import { NotificacionService } from "./NotificacionService";

export class SolicitudInsumoService {
  constructor(private prisma: PrismaClient) {}

  async crear(payload: unknown, actorId?: string | null) {
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
    const creada = await this.prisma.solicitudInsumo.create({
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
      include: {
        insumosSolicitados: {
          include: { insumo: { select: { nombre: true, unidad: true } } }, // ✅ aquí
        },
      },
    });

    try {
      const notificaciones = new NotificacionService(this.prisma);
      await notificaciones.notificarSolicitudInsumosCreada({
        solicitudId: creada.id,
        conjuntoId: dto.conjuntoId,
        totalItems: dto.items.length,
        actorId: actorId ?? null,
      });
    } catch (e) {
      console.error(
        "No se pudo notificar creacion de solicitud de insumos:",
        e,
      );
    }

    return creada;
  }

  async aprobar(id: number, payload: unknown) {
    const dto = AprobarSolicitudInsumoDTO.parse(payload);

    return this.prisma.$transaction(async (tx) => {
      const sol = await this.prisma.solicitudInsumo.findUnique({
        where: { id },
        include: {
          insumosSolicitados: {
            include: { insumo: true },
          },
        },
      });

      if (!sol) throw new Error("Solicitud no encontrada");
      if (sol.aprobado) return sol;

      // inventario del conjunto
      const inventario = await tx.inventario.upsert({
        where: { conjuntoId: sol.conjuntoId },
        update: {},
        create: { conjuntoId: sol.conjuntoId },
        select: { id: true },
      });

      // cargar stock
      for (const it of sol.insumosSolicitados) {
        // si tienes unique compuesto inventarioId+insumoId, usa upsert por esa llave.
        // si no lo tienes, usa findFirst + update/create.
        const existente = await tx.inventarioInsumo.findFirst({
          where: { inventarioId: inventario.id, insumoId: it.insumoId },
          select: { id: true },
        });

        if (existente) {
          await tx.inventarioInsumo.update({
            where: { id: existente.id },
            data: { cantidad: { increment: it.cantidad as any } },
          });
        } else {
          await tx.inventarioInsumo.create({
            data: {
              inventarioId: inventario.id,
              insumoId: it.insumoId,
              cantidad: it.cantidad as any,
            },
          });
        }

        // opcional: registrar movimiento ENTRADA
        await tx.consumoInsumo.create({
          data: {
            inventarioId: inventario.id,
            insumoId: it.insumoId,
            cantidad: it.cantidad as any,
            fecha: new Date(),
            // tipo: "ENTRADA",
            // observacion: `Ingreso por aprobación solicitud #${id}`
          } as any,
        });
      }

      // aprobar solicitud
      return this.prisma.solicitudInsumo.update({
        where: { id },
        data: {
          aprobado: true,
          fechaAprobacion: dto.fechaAprobacion ?? new Date(),
          empresaId: dto.empresaId ?? undefined,
        },
        include: {
          insumosSolicitados: {
            include: { insumo: { select: { nombre: true, unidad: true } } }, // ✅ aquí
          },
        },
      });
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
      include: {
        insumosSolicitados: {
          include: { insumo: { select: { nombre: true, unidad: true } } }, // ✅ aquí
        },
      },
      orderBy: { id: "desc" },
    });
  }

  async obtener(id: number) {
    return this.prisma.solicitudInsumo.findUnique({
      where: { id },
      include: {
        insumosSolicitados: {
          include: { insumo: { select: { nombre: true, unidad: true } } }, // ✅ aquí
        },
      },
    });
  }

  async eliminar(id: number) {
    await this.prisma.solicitudInsumo.delete({ where: { id } });
  }
}
