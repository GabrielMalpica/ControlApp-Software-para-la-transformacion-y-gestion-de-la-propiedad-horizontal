// src/services/TareaService.ts
import { PrismaClient, EstadoTarea, TipoTarea } from "../generated/prisma";
import { z } from "zod";
import {
  CrearTareaDTO,
  EditarTareaDTO,
  FiltroTareaDTO,
  tareaPublicSelect,
  toTareaPublica,
} from "../model/Tarea_tmp";

const EvidenciaDTO = z.object({ imagen: z.string().min(1) });

const ConsumoItemDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

const CompletarConInsumosDTO = z.object({
  insumosUsados: z.array(ConsumoItemDTO).default([]),
});

const SupervisorIdDTO = z.object({ supervisorId: z.number().int().positive() });

const RechazarDTO = z.object({
  supervisorId: z.number().int().positive(),
  observacion: z.string().min(3).max(500),
});

export class TareaService {
  constructor(
    private prisma: PrismaClient,
    private tareaId: number,
  ) {}

  /* =====================================================
   *       CRUD GENERAL (CORRECTIVAS POR DEFECTO)
   * ===================================================== */

  // ✅ Crear tarea (correctiva por defecto)

  async iniciarTarea(): Promise<void> {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: this.tareaId },
      select: { estado: true },
    });

    if (!tarea) throw new Error("Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.ASIGNADA) {
      throw new Error("Solo se puede iniciar una tarea que esté ASIGNADA.");
    }

    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.EN_PROCESO,
        fechaIniciarTarea: new Date(),
      },
    });
  }

  async marcarComoCompletadaConInsumos(
    payload: unknown,
    inventarioService: {
      consumirInsumoPorId: (payload: unknown) => Promise<void>;
    },
  ): Promise<void> {
    const { insumosUsados } = CompletarConInsumosDTO.parse(payload);

    await this.prisma.$transaction(async () => {
      // 1) Consumir insumos (si falla, aborta la transacción)
      for (const { insumoId, cantidad } of insumosUsados) {
        await inventarioService.consumirInsumoPorId({ insumoId, cantidad });
      }

      // 2) Cambiar estado -> PENDIENTE_APROBACION y guardar snapshot de insumosUsados
      await this.prisma.tarea.update({
        where: { id: this.tareaId },
        data: {
          insumosUsados, // Json
          estado: EstadoTarea.PENDIENTE_APROBACION,
          fechaFinalizarTarea: new Date(),
        },
      });
    });
  }

  async marcarNoCompletada(): Promise<void> {
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: { estado: EstadoTarea.NO_COMPLETADA },
    });
  }

  static async crearTareaCorrectiva(prisma: PrismaClient, payload: unknown) {
    const dto = CrearTareaDTO.parse(payload);

    // Operarios (M:N)
    const operariosConnect =
      dto.operariosIds && dto.operariosIds.length
        ? dto.operariosIds.map((id) => ({ id: id }))
        : dto.operarioId
          ? [{ id: dto.operarioId }]
          : [];

    const data: any = {
      descripcion: dto.descripcion,
      fechaInicio: dto.fechaInicio,
      fechaFin: dto.fechaFin,
      duracionMinutos: dto.duracionMinutos,

      tipo: dto.tipo ?? TipoTarea.CORRECTIVA,
      estado: dto.estado ?? EstadoTarea.ASIGNADA,
      frecuencia: dto.frecuencia ?? null,

      evidencias: dto.evidencias ?? [],
      insumosUsados: dto.insumosUsados ?? undefined,
      observaciones: dto.observaciones ?? null,
      observacionesRechazo: dto.observacionesRechazo ?? null,

      ubicacion: { connect: { id: dto.ubicacionId } },
      elemento: { connect: { id: dto.elementoId } },
    };

    // Conjunto (por NIT)
    if (dto.conjuntoId) {
      data.conjunto = { connect: { nit: dto.conjuntoId } };
    }

    // Supervisor (id numérico → string)
    if (dto.supervisorId != null) {
      data.supervisor = { connect: { id: dto.supervisorId } };
    }

    // Operarios
    if (operariosConnect.length) {
      data.operarios = { connect: operariosConnect };
    }

    const creada = await prisma.tarea.create({
      data,
      select: tareaPublicSelect,
    });

    return toTareaPublica(creada);
  }

  // ✏️ Editar tarea
  static async editarTarea(prisma: PrismaClient, id: number, payload: unknown) {
    const dto = EditarTareaDTO.parse(payload);

    const data: any = {
      descripcion: dto.descripcion ?? undefined,
      fechaInicio: dto.fechaInicio ?? undefined,
      fechaFin: dto.fechaFin ?? undefined,
      duracionHoras: dto.duracionHoras ?? undefined,

      tipo: dto.tipo ?? undefined,
      estado: dto.estado ?? undefined,
      frecuencia: dto.frecuencia ?? undefined,

      evidencias: dto.evidencias ?? undefined,
      insumosUsados: dto.insumosUsados ?? undefined,
      observaciones:
        dto.observaciones !== undefined ? dto.observaciones : undefined,
      observacionesRechazo:
        dto.observacionesRechazo !== undefined
          ? dto.observacionesRechazo
          : undefined,
    };

    if (dto.ubicacionId != null) {
      data.ubicacion = { connect: { id: dto.ubicacionId } };
    }
    if (dto.elementoId != null) {
      data.elemento = { connect: { id: dto.elementoId } };
    }

    if (dto.conjuntoId !== undefined) {
      data.conjunto = dto.conjuntoId
        ? { connect: { nit: dto.conjuntoId } }
        : { disconnect: true };
    }

    if (dto.supervisorId !== undefined) {
      data.supervisor =
        dto.supervisorId != null
          ? { connect: { id: dto.supervisorId } }
          : { disconnect: true };
    }

    // Reemplazar operarios si viene el array
    if (dto.operariosIds) {
      data.operarios = {
        set: dto.operariosIds.map((id) => ({ id: id })),
      };
    }

    const actualizada = await prisma.tarea.update({
      where: { id },
      data,
      select: tareaPublicSelect,
    });

    return toTareaPublica(actualizada);
  }

  // 🔍 Obtener una tarea
  static async obtenerTarea(prisma: PrismaClient, id: number) {
    const tarea = await prisma.tarea.findUnique({
      where: { id },
      select: tareaPublicSelect,
    });
    if (!tarea) throw new Error("Tarea no encontrada.");
    return toTareaPublica(tarea);
  }

  // 📋 Listar tareas con filtros
  static async listarTareas(prisma: PrismaClient, payloadFiltro?: unknown) {
    const filtro = payloadFiltro ? FiltroTareaDTO.parse(payloadFiltro) : {};

    const where: any = {};

    if (filtro.conjuntoId) where.conjuntoId = filtro.conjuntoId;
    if (filtro.ubicacionId) where.ubicacionId = filtro.ubicacionId;
    if (filtro.elementoId) where.elementoId = filtro.elementoId;

    if (filtro.operarioId) {
      where.operarios = {
        some: { id: filtro.operarioId },
      };
    }

    if (filtro.supervisorId) {
      where.supervisorId = filtro.supervisorId;
    }

    if (filtro.tipo) where.tipo = filtro.tipo;
    if (filtro.frecuencia) where.frecuencia = filtro.frecuencia;
    if (filtro.estado) where.estado = filtro.estado;
    if (filtro.borrador !== undefined) where.borrador = filtro.borrador;

    if (filtro.periodoAnio) where.periodoAnio = filtro.periodoAnio;
    if (filtro.periodoMes) where.periodoMes = filtro.periodoMes;
    if (filtro.grupoPlanId) where.grupoPlanId = filtro.grupoPlanId;

    if (filtro.fechaInicio || filtro.fechaFin) {
      where.fechaInicio = {};
      if (filtro.fechaInicio) where.fechaInicio.gte = filtro.fechaInicio;
      if (filtro.fechaFin) where.fechaInicio.lte = filtro.fechaFin;
    }

    const tareas = await prisma.tarea.findMany({
      where,
      select: tareaPublicSelect,
      orderBy: [{ fechaInicio: "desc" }, { id: "desc" }],
    });

    return tareas.map(toTareaPublica);
  }

  // 🗑️ Eliminar tarea (con regla de negocio)
  static async eliminarTarea(prisma: PrismaClient, id: number) {
    const tarea = await prisma.tarea.findUnique({
      where: { id },
      select: {
        id: true,
        estado: true,
        borrador: true,
      },
    });

    if (!tarea) throw new Error("Tarea no encontrada.");

    // 🔒 Reglas de negocio (ajústalas a tu gusto)
    if (
      tarea.estado === EstadoTarea.COMPLETADA ||
      tarea.estado === EstadoTarea.APROBADA ||
      tarea.estado === EstadoTarea.PENDIENTE_APROBACION
    ) {
      throw new Error(
        "No se puede eliminar una tarea que ya fue ejecutada o está en aprobación.",
      );
    }

    // ✅ Recomendación: si NO es borrador, mejor CANCELAR en vez de borrar
    // (si quieres permitir borrado igual, comenta este bloque)
    if (!tarea.borrador) {
      throw new Error(
        "No se permite eliminar tareas publicadas. Cáncelala (estado CANCELADA) o elimine solo borradores.",
      );
    }

    await prisma.$transaction(async (tx) => {
      // 1) Liberar maquinaria asignada al conjunto por esta tarea (si existiera)
      // (tu relación tiene onDelete: SetNull, pero igual lo hacemos explícito)
      await tx.maquinariaConjunto.updateMany({
        where: { tareaId: id },
        data: { tareaId: null },
      });

      const [um, uh, ci, mc] = await Promise.all([
        prisma.usoMaquinaria.count({ where: { tarea } }),
        prisma.usoHerramienta.count({ where: { tarea } }),
        prisma.consumoInsumo.count({ where: { tarea } }),
        prisma.maquinariaConjunto.count({ where: { tarea } }),
      ]);

      console.log("refs tarea", { um, uh, ci, mc });

      // 2) Borrar usos de maquinaria/herramienta ligados a la tarea (FK dura)
      await tx.usoMaquinaria.deleteMany({
        where: { tareaId: id },
      });

      await tx.usoHerramienta.deleteMany({
        where: { tareaId: id },
      });

      // 3) Borrar consumos ligados a la tarea (si aplica en tu schema real)
      await tx.consumoInsumo.deleteMany({
        where: { tareaId: id },
      });

      // 4) (Opcional) Desconectar relación M:N de operarios (normalmente Prisma lo limpia,
      // pero lo dejo por si tu DB tiene restricciones raras)
      await tx.tarea.update({
        where: { id },
        data: { operarios: { set: [] } },
      });

      // 5) Ahora sí, borrar la tarea
      await tx.tarea.delete({ where: { id } });
    });

    return { ok: true, message: "Tarea eliminada correctamente." };
  }

  /* =====================================================
   *  A PARTIR DE AQUÍ, DEJA TUS MÉTODOS EXISTENTES IGUAL:
   *  agregarEvidencia, iniciarTarea, marcarComoCompletadaConInsumos,
   *  marcarNoCompletada, aprobarTarea, rechazarTarea, resumen, etc.
   * ===================================================== */
}
