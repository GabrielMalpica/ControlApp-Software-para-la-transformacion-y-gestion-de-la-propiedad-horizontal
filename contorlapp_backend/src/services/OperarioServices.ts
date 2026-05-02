// src/services/OperarioService.ts
import {
  PrismaClient,
  EstadoTarea,
  EstadoUsoHerramienta,
  TipoMovimientoInsumo,
  Prisma,
} from "@prisma/client";
import { z } from "zod";
import { TareaService } from "./TareaServices";
import { InventarioService } from "./InventarioServices";
import { uploadEvidenciaToDrive } from "../utils/drive_evidencias";
import fs from "fs";
import { NotificacionService } from "./NotificacionService";
import { elementoParentChainInclude } from "../utils/elementoHierarchy";

const TareaIdDTO = z.object({ tareaId: z.number().int().positive() });

const MarcarCompletadaDTO = z.object({
  tareaId: z.number().int().positive(),
  evidencias: z.array(z.string()).default([]),
  insumosUsados: z
    .array(
      z.object({
        insumoId: z.number().int().positive(),
        cantidad: z.coerce.number().positive(),
      })
    )
    .default([]),
});

const FechaDTO = z.object({ fecha: z.coerce.date() });

const CerrarMultipartDTO = z.object({
  accion: z.enum(["COMPLETADA", "NO_COMPLETADA"]).optional(),
  observaciones: z.string().optional(),
  fechaFinalizarTarea: z.string().optional(),
  insumosUsados: z.string().optional(),
});

export class OperarioService {
  constructor(private prisma: PrismaClient, private operarioId: number) {}

  /** Obtiene el límite semanal (horas) desde la Empresa del operario */
  private async getLimiteHorasSemana(): Promise<number> {
    const op = await this.prisma.operario.findUnique({
      where: { id: this.operarioId.toString() },
      select: { empresa: { select: { limiteHorasSemana: true } } },
    });
    return op?.empresa?.limiteHorasSemana ?? 46;
  }

  /** Asigna una tarea al operario respetando el límite semanal empresarial */
  async asignarTarea(payload: unknown): Promise<void> {
    const { tareaId } = TareaIdDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: {
        fechaInicio: true,
        duracionMinutos: true,
        id: true,
        borrador: true,
      },
    });
    if (!tarea) throw new Error("Tarea no encontrada");
    if (tarea.borrador) {
      throw new Error("No se puede asignar una tarea en borrador.");
    }

    const limite = await this.getLimiteHorasSemana();
    const horasSemana = await this.horasAsignadasEnSemana(tarea.fechaInicio);
    if (horasSemana + tarea.duracionMinutos > limite) {
      const operario = await this.prisma.operario.findUnique({
        where: { id: this.operarioId.toString() },
        include: { usuario: true },
      });
      const nombre = operario?.usuario?.nombre ?? "Operario";
      throw new Error(
        `❌ Supera el límite de ${limite} horas semanales para ${nombre}`
      );
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { operarios: { connect: { id: this.operarioId.toString() } } },
    });
  }

  /** Inicia una tarea (cambia estado a EN_PROCESO) */
  async iniciarTarea(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { id: true, borrador: true },
    });
    if (!tarea || tarea.borrador) {
      throw new Error("La tarea no existe o está en borrador.");
    }
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.iniciarTarea();
  }

  /**
   * Marca tarea como completada y consume insumos.
   * - Usa InventarioService para registrar el consumo (con operarioId/tareaId si tu versión lo soporta).
   * - Cambia estado a PENDIENTE_APROBACION (lo hace TareaService).
   * - Actualiza evidencias.
   */
  async marcarComoCompletada(
    payload: unknown,
    inventarioService: InventarioService
  ) {
    const { tareaId, evidencias, insumosUsados } =
      MarcarCompletadaDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { id: true, conjuntoId: true, borrador: true },
    });
    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.borrador) {
      throw new Error("No se puede completar una tarea en borrador.");
    }
    if (tarea.conjuntoId === null) {
      throw new Error("❌ La tarea no tiene un conjunto asignado.");
    }

    // Si tu InventarioService.consumirInsumoPorId acepta metadata (operarioId/tareaId),
    // puedes pasarla así para evitar duplicados y tener mejor trazabilidad.
    // Ej: await inventarioService.consumirInsumoPorId({ insumoId, cantidad, operarioId: this.operarioId, tareaId })
    await new TareaService(this.prisma, tareaId).marcarComoCompletadaConInsumos(
      { insumosUsados },
      {
        // Adapter que cumple con (payload: unknown) => Promise<void>
        consumirInsumoPorId: async (payload: unknown) => {
          // valida/extrae campos con Zod (opcional pero recomendado)
          const p = z
            .object({
              insumoId: z.number().int().positive(),
              cantidad: z.number().int().positive(),
            })
            .parse(payload);

          // llama a tu InventarioService con el shape que ya acepta
          // si en tu InventarioService agregaste metadata (operarioId/tareaId),
          // complétala aquí.
          await (inventarioService as any).consumirInsumoPorId({
            insumoId: p.insumoId,
            cantidad: p.cantidad,
            // operarioId: this.operarioId,
            // tareaId,
          });
        },
      }
    );

    // Guardar/mergear evidencias (no lo hace TareaService)
    const actuales =
      (
        await this.prisma.tarea.findUnique({
          where: { id: tareaId },
          select: { evidencias: true },
        })
      )?.evidencias ?? [];

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { evidencias: [...actuales, ...evidencias] },
    });
  }

  /** Marca una tarea como NO_COMPLETADA */
  async marcarComoNoCompletada(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { id: true, borrador: true },
    });
    if (!tarea || tarea.borrador) {
      throw new Error("La tarea no existe o está en borrador.");
    }
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.marcarNoCompletada();
  }

  /** Tareas del día para este operario */
  async tareasDelDia(payload: unknown) {
    const { fecha } = FechaDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
        borrador: false,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha },
      },
    });
  }

  async listarTareas() {
    return this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
        borrador: false,
      },
      orderBy: { fechaInicio: "asc" },
      include: {
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
        conjunto: true,
      },
    });
  }

  async cerrarTareaConEvidencias(
    tareaId: number,
    payload: unknown,
    files: Express.Multer.File[],
  ) {
    const dto = CerrarMultipartDTO.parse(payload ?? {});
    const accion = dto.accion ?? "COMPLETADA";
    const fechaCierre = dto.fechaFinalizarTarea
      ? new Date(dto.fechaFinalizarTarea)
      : new Date();

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: {
        id: true,
        descripcion: true,
        estado: true,
        borrador: true,
        evidencias: true,
        conjuntoId: true,
        supervisorId: true,
        operarios: { select: { id: true } },
        conjunto: { select: { nit: true, nombre: true } },
      },
    });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.borrador) {
      throw new Error("No se puede cerrar una tarea en borrador.");
    }

    const operarioAsignado = tarea.operarios.some(
      (o) => o.id === this.operarioId.toString(),
    );
    if (!operarioAsignado) {
      throw new Error("❌ Esta tarea no está asignada al operario autenticado.");
    }

    const permitidos = new Set<EstadoTarea>([
      EstadoTarea.ASIGNADA,
      EstadoTarea.EN_PROCESO,
      EstadoTarea.COMPLETADA,
    ]);

    if (!permitidos.has(tarea.estado)) {
      throw new Error(`No puedes cerrar una tarea en estado ${tarea.estado}.`);
    }

    if (accion === "COMPLETADA" && !tarea.conjuntoId) {
      throw new Error(
        "La tarea no tiene conjunto asignado, no puedo descontar inventario.",
      );
    }

    let insumosUsados: Array<{ insumoId: number; cantidad: number }> = [];
    if (accion === "COMPLETADA" && dto.insumosUsados && dto.insumosUsados.trim().length) {
      try {
        insumosUsados = z
          .array(
            z.object({
              insumoId: z.number().int().positive(),
              cantidad: z.number().positive(),
            }),
          )
          .parse(JSON.parse(dto.insumosUsados));
      } catch {
        throw new Error(
          "insumosUsados debe ser un JSON válido: [{insumoId, cantidad}]",
        );
      }
    }

    const urls: string[] = [];
    try {
      for (const f of files ?? []) {
        const url = await uploadEvidenciaToDrive({
          filePath: f.path,
          fileName: `Tarea_${tareaId}_${fechaCierre
            .toISOString()
            .replace(/[:.]/g, "-")}_${f.originalname}`,
          mimeType: f.mimetype,
          conjuntoNit: tarea.conjunto?.nit ?? tarea.conjuntoId ?? "SIN_CONJUNTO",
          conjuntoNombre: tarea.conjunto?.nombre ?? undefined,
          fecha: fechaCierre,
        });
        urls.push(url);
      }
    } finally {
      for (const f of files ?? []) {
        try {
          if (fs.existsSync(f.path)) fs.unlinkSync(f.path);
        } catch {}
      }
    }

    const evidenciasMerge = [...(tarea.evidencias ?? []), ...urls];

    await this.prisma.$transaction(async (tx) => {
      const inventario = accion === "COMPLETADA"
        ? await tx.inventario.findUnique({
            where: { conjuntoId: tarea.conjuntoId! },
            select: { id: true },
          })
        : null;

      if (accion === "COMPLETADA" && !inventario) {
        throw new Error("No existe inventario para este conjunto.");
      }

      for (const item of insumosUsados) {
        const invItem = await tx.inventarioInsumo.findUnique({
          where: {
            inventarioId_insumoId: {
                inventarioId: inventario!.id,
              insumoId: item.insumoId,
            },
          },
          select: { id: true, cantidad: true },
        });

        if (!invItem) {
          throw new Error(
            `El insumo ${item.insumoId} no existe en inventario del conjunto.`,
          );
        }

        const actual = invItem.cantidad;
        const usar = new Prisma.Decimal(item.cantidad);

        if (usar.lte(0)) continue;
        if (actual.lt(usar)) {
          throw new Error(
            `Stock insuficiente para insumo ${item.insumoId}. Stock=${actual.toString()} / Usar=${usar.toString()}`,
          );
        }

        await tx.inventarioInsumo.update({
          where: { id: invItem.id },
          data: { cantidad: actual.minus(usar) },
        });

        await tx.consumoInsumo.create({
          data: {
            inventario: { connect: { id: inventario!.id } },
            insumo: { connect: { id: item.insumoId } },
            tipo: TipoMovimientoInsumo.SALIDA,
            tarea: { connect: { id: tareaId } },
            operario: { connect: { id: this.operarioId.toString() } },
            cantidad: usar,
            fecha: fechaCierre,
            observacion: `Consumo en cierre de tarea #${tareaId} por operario ${this.operarioId}`,
          },
        });
      }

      await tx.usoMaquinaria.updateMany({
        where: { tareaId, fechaFin: null },
        data: {
          fechaFin: fechaCierre,
          operarioId: this.operarioId.toString(),
          observacion: "Devuelta al cerrar tarea por operario",
        },
      });

      await tx.usoHerramienta.updateMany({
        where: { tareaId, fechaFin: null },
        data: {
          fechaFin: fechaCierre,
          operarioId: this.operarioId.toString(),
          estado: EstadoUsoHerramienta.DEVUELTA,
          observacion: "Devuelta al cerrar tarea por operario",
        },
      });

      await tx.maquinariaConjunto.updateMany({
        where: { tareaId },
        data: { tareaId: null, operarioId: null, fechaDevolucionEstimada: null },
      });

      if (accion === "NO_COMPLETADA" && (!dto.observaciones || dto.observaciones.trim().length < 3)) {
        throw new Error("Debes indicar el motivo u observación de por qué no se realizó la tarea.");
      }

      await tx.tarea.update({
        where: { id: tareaId },
        data: {
          evidencias: evidenciasMerge,
          observaciones: dto.observaciones ?? undefined,
          insumosUsados: accion === "COMPLETADA" ? (insumosUsados as any) : undefined,
          estado:
            accion === "NO_COMPLETADA"
              ? EstadoTarea.NO_COMPLETADA
              : EstadoTarea.PENDIENTE_APROBACION,
          fechaFinalizarTarea: fechaCierre,
          finalizadaPorId: this.operarioId.toString(),
          finalizadaPorRol: "OPERARIO",
        },
      });
    });

    try {
      const notificaciones = new NotificacionService(this.prisma);
      if (tarea.conjuntoId) {
        await notificaciones.notificarCierreTarea({
          tareaId,
          descripcionTarea: tarea.descripcion,
          conjuntoId: tarea.conjuntoId,
          actorId: this.operarioId.toString(),
          actorRol: "OPERARIO",
          supervisorId: tarea.supervisorId,
        });
      }
    } catch (e) {
      console.error("No se pudo notificar cierre de tarea (operario):", e);
    }
  }

  /** Suma de horas en la semana (lunes a domingo) de la fecha dada */
  async horasAsignadasEnSemana(fecha: Date): Promise<number> {
    const inicio = this.inicioSemana(fecha);
    const fin = new Date(inicio);
    fin.setDate(inicio.getDate() + 6);
    fin.setHours(23, 59, 59, 999);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
        borrador: false,
        fechaFin: { gte: inicio },
        fechaInicio: { lte: fin },
      },
      select: { duracionMinutos: true },
    });

    return tareas.reduce((sum, t) => sum + t.duracionMinutos, 0);
  }

  async horasRestantesEnSemana(payload: unknown): Promise<number> {
    const { fecha } = FechaDTO.parse(payload);
    const limite = await this.getLimiteHorasSemana();
    const horas = await this.horasAsignadasEnSemana(fecha);
    return Math.max(0, limite - horas);
  }

  async resumenDeHoras(payload: unknown): Promise<string> {
    const { fecha } = FechaDTO.parse(payload);
    const limite = await this.getLimiteHorasSemana();
    const horas = await this.horasAsignadasEnSemana(fecha);
    const operario = await this.prisma.operario.findUnique({
      where: { id: this.operarioId.toString() },
      include: { usuario: true },
    });
    const nombre = operario?.usuario?.nombre ?? "Operario";
    return `🔔 A ${nombre} le quedan ${Math.max(
      0,
      limite - horas
    )}h disponibles esta semana (límite ${limite}h).`;
    // si quieres, puedes retornar también { horasAsignadas: horas, limite, restantes: limite - horas }
  }

  /** Lunes de la semana ISO de la fecha dada */
  private inicioSemana(fecha: Date): Date {
    const d = new Date(fecha);
    const day = d.getDay(); // 0=Dom ... 6=Sab
    const diff = d.getDate() - day + (day === 0 ? -6 : 1); // Lunes
    return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
  }
}
