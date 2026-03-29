// src/services/TareaService.ts
import { PrismaClient, EstadoTarea, TipoTarea } from "@prisma/client";
import { z } from "zod";
import {
  CrearTareaDTO,
  EditarTareaDTO,
  FiltroTareaDTO,
  tareaPublicSelect,
  toTareaPublica,
} from "../model/Tarea";
import { isFestivoDate } from "../utils/schedulerUtils";
import {
  validarOperariosDisponiblesEnFecha,
  validarOperariosDisponiblesEnRango,
  validarLimiteSemanalOperarios,
} from "../utils/operarioAvailability";

const EvidenciaDTO = z.object({ imagen: z.string().min(1) });

const ConsumoItemDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

async function validarOperariosEnHorarioTarea(params: {
  prisma: PrismaClient;
  conjuntoId?: string | null;
  fechaInicio: Date;
  fechaFin: Date;
  operariosIds: string[];
}) {
  const { prisma, conjuntoId, fechaInicio, fechaFin, operariosIds } = params;
  if (!conjuntoId || !operariosIds.length) return;

  const toMin = (value: unknown) => {
    const text = String(value ?? "").trim();
    const match = text.match(/(\d{1,2}):(\d{2})/);
    if (!match) return null;
    return Number(match[1]) * 60 + Number(match[2]);
  };

  const dia = fechaInicio.getDay();
  const horarios = await prisma.conjuntoHorario.findMany({ where: { conjuntoId } });
  const horario = horarios.find((h) => {
    const map: Record<string, number> = {
      LUNES: 1,
      MARTES: 2,
      MIERCOLES: 3,
      JUEVES: 4,
      VIERNES: 5,
      SABADO: 6,
      DOMINGO: 0,
    };
    return map[String(h.dia)] === dia;
  });
  if (!horario) return;

  const jornadas = await prisma.operario.findMany({
    where: { id: { in: operariosIds } },
    select: {
      id: true,
      usuario: { select: { jornadaLaboral: true, patronJornada: true } },
    },
  });
  const jornadasByOperario = new Map(
    jornadas.map((j) => [
      j.id,
      {
        jornadaLaboral: j.usuario?.jornadaLaboral ?? null,
        patronJornada: j.usuario?.patronJornada ?? null,
      },
    ]),
  );

  const startMin = toMin(horario.horaApertura);
  const endMin = toMin(horario.horaCierre);
  if (startMin == null || endMin == null) return;
  const result = await validarOperariosDisponiblesEnRango({
    prisma,
    fechaInicio,
    fechaFin,
    operariosIds,
    jornadasByOperario,
    horarioDia: {
      startMin,
      endMin,
      descansoStartMin: horario.descansoInicio
        ? toMin(horario.descansoInicio) ?? undefined
        : undefined,
      descansoEndMin: horario.descansoFin
        ? toMin(horario.descansoFin) ?? undefined
        : undefined,
    },
  });

  if (!result.ok) {
    throw new Error(
      `Los operarios ${result.noDisponibles.join(", ")} no tienen horario disponible para ese rango.`,
    );
  }
}

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

    const esFestivo = await isFestivoDate({
      prisma,
      fecha: dto.fechaInicio,
      pais: "CO",
    });
    if (esFestivo) {
      throw new Error(
        "No se permite programar tareas en festivos.",
      );
    }

    const operarios = dto.operariosIds?.length
      ? dto.operariosIds.map(String)
      : dto.operarioId
        ? [String(dto.operarioId)]
        : [];
    if (operarios.length) {
      const disponibilidad = await validarOperariosDisponiblesEnFecha({
        prisma,
        fecha: dto.fechaInicio,
        operariosIds: operarios,
      });
      if (!disponibilidad.ok) {
        throw new Error(
          `Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`,
        );
      }
      await validarOperariosEnHorarioTarea({
        prisma,
        conjuntoId: dto.conjuntoId ?? null,
        fechaInicio: dto.fechaInicio,
        fechaFin: dto.fechaFin ?? new Date(dto.fechaInicio.getTime() + (dto.duracionMinutos ?? Math.round((dto.duracionHoras ?? 1) * 60)) * 60000),
        operariosIds: operarios,
      });
      if (dto.conjuntoId) {
        const duracionMinutos =
          dto.duracionMinutos ??
          (dto.fechaFin
            ? Math.max(1, Math.round((dto.fechaFin.getTime() - dto.fechaInicio.getTime()) / 60000))
            : Math.max(1, Math.round((dto.duracionHoras ?? 1) * 60)));
        const limite = await validarLimiteSemanalOperarios({
          prisma,
          conjuntoId: dto.conjuntoId,
          operariosIds: operarios,
          fechaInicio: dto.fechaInicio,
          duracionMinutos,
        });
        if (!limite.ok) {
          throw new Error(
            `Los operarios ${limite.excedidos.join(", ")} superan su limite semanal con esta tarea.`,
          );
        }
      }
    }

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

    const actual = await prisma.tarea.findUnique({
      where: { id },
      select: {
        conjuntoId: true,
        fechaInicio: true,
        fechaFin: true,
        operarios: { select: { id: true } },
      },
    });

    const fechaInicioFinal = dto.fechaInicio ?? actual?.fechaInicio;
    const fechaFinFinal = dto.fechaFin ?? actual?.fechaFin;
    const conjuntoIdFinal = dto.conjuntoId !== undefined ? dto.conjuntoId : actual?.conjuntoId;
    const operariosFinal = dto.operariosIds?.map(String) ?? actual?.operarios.map((o) => o.id) ?? [];

    if (fechaInicioFinal && fechaFinFinal && operariosFinal.length) {
      const disponibilidad = await validarOperariosDisponiblesEnFecha({
        prisma,
        fecha: fechaInicioFinal,
        operariosIds: operariosFinal,
      });
      if (!disponibilidad.ok) {
        throw new Error(
          `Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`,
        );
      }
      await validarOperariosEnHorarioTarea({
        prisma,
        conjuntoId: conjuntoIdFinal ?? null,
        fechaInicio: fechaInicioFinal,
        fechaFin: fechaFinFinal,
        operariosIds: operariosFinal,
      });
      if (conjuntoIdFinal) {
        const duracionMinutos = Math.max(
          1,
          Math.round((fechaFinFinal.getTime() - fechaInicioFinal.getTime()) / 60000),
        );
        const limite = await validarLimiteSemanalOperarios({
          prisma,
          conjuntoId: conjuntoIdFinal,
          operariosIds: operariosFinal,
          fechaInicio: fechaInicioFinal,
          duracionMinutos,
          excluirTareaId: id,
        });
        if (!limite.ok) {
          throw new Error(
            `Los operarios ${limite.excedidos.join(", ")} superan su limite semanal con esta tarea.`,
          );
        }
      }
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
