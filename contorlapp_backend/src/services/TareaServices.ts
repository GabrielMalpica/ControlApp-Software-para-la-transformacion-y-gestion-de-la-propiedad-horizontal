// src/services/TareaService.ts
import {
  PrismaClient,
  Prisma,
  EstadoTarea,
  TipoFuncion,
  TipoTarea,
  TipoMovimientoInsumo,
} from "@prisma/client";
import { z } from "zod";
import fs from "fs";
import {
  CrearTareaDTO,
  CorregirCierreDTO,
  EditarTareaDTO,
  FiltroTareaDTO,
  tareaPublicSelect,
  toTareaPublica,
} from "../model/Tarea";
import { isFestivoDate } from "../utils/schedulerUtils";
import {
  validarIntervaloProgramacion,
  validarOperariosDisponiblesEnFecha,
  validarLimiteSemanalOperarios,
} from "../utils/operarioAvailability";
import {
  buildEvidenciaFileName,
  eliminarEvidenciaDeDrive,
  extraerDriveId,
  uploadEvidenciaToDrive,
} from "../utils/drive_evidencias";
import { AuditoriaService } from "./AuditoriaService";
import { AccionAuditoria, EntidadAuditoria, ModuloAuditoria } from "../model/Auditoria";

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
  if (!conjuntoId) return;
  const result = await validarIntervaloProgramacion({
    prisma,
    conjuntoId,
    fechaInicio,
    fechaFin,
    operariosIds,
  });
  if (!result.ok) throw new Error(result.mensaje);
}

const CompletarConInsumosDTO = z.object({
  insumosUsados: z.array(ConsumoItemDTO).default([]),
});

const SupervisorIdDTO = z.object({ supervisorId: z.number().int().positive() });

const RechazarDTO = z.object({
  supervisorId: z.number().int().positive(),
  observacion: z.string().min(3).max(500),
});

function recursoFueraDeEmpresa(): Error & { status: number } {
  const error = new Error("Recurso no encontrado") as Error & {
    status: number;
  };
  error.status = 404;
  return error;
}

async function validarRelacionesDeTarea(params: {
  prisma: PrismaClient;
  empresaId: string;
  conjuntoId: string;
  ubicacionId: number;
  elementoId: number;
  supervisorId?: string | null;
  operariosIds: string[];
}): Promise<void> {
  const {
    prisma,
    empresaId,
    conjuntoId,
    ubicacionId,
    elementoId,
    supervisorId,
  } = params;
  const operariosIds = [...new Set(params.operariosIds)];

  const [conjunto, supervisor, operariosValidos] = await Promise.all([
    prisma.conjunto.findFirst({
      where: {
        nit: conjuntoId,
        empresaId,
        ubicaciones: {
          some: {
            id: ubicacionId,
            elementos: { some: { id: elementoId } },
          },
        },
      },
      select: { nit: true },
    }),
    supervisorId
      ? prisma.supervisor.findFirst({
          where: { id: supervisorId, empresaId },
          select: { id: true },
        })
      : Promise.resolve({ id: "sin-supervisor" }),
    operariosIds.length
      ? prisma.operario.count({
          where: {
            id: { in: operariosIds },
            empresaId,
            conjuntos: { some: { nit: conjuntoId } },
          },
        })
      : Promise.resolve(0),
  ]);

  if (!conjunto || !supervisor || operariosValidos !== operariosIds.length) {
    throw recursoFueraDeEmpresa();
  }
}

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

      // 2) Cambiar estado -> APROBADA (cierre directo, sin paso de aprobación) y guardar snapshot de insumosUsados
      const ahora = new Date();
      await this.prisma.tarea.update({
        where: { id: this.tareaId },
        data: {
          insumosUsados, // Json
          estado: EstadoTarea.APROBADA,
          fechaFinalizarTarea: ahora,
          fechaVerificacion: ahora,
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

  static async crearTareaCorrectiva(
    prisma: PrismaClient,
    payload: unknown,
    empresaId: string,
  ) {
    const dto = CrearTareaDTO.parse(payload);
    if (!dto.conjuntoId) throw recursoFueraDeEmpresa();

    const operarios = dto.operariosIds?.length
      ? dto.operariosIds.map(String)
      : dto.operarioId
        ? [String(dto.operarioId)]
        : [];

    await validarRelacionesDeTarea({
      prisma,
      empresaId,
      conjuntoId: dto.conjuntoId,
      ubicacionId: dto.ubicacionId,
      elementoId: dto.elementoId,
      supervisorId: dto.supervisorId,
      operariosIds: operarios,
    });

    const esFestivo = await isFestivoDate({
      prisma,
      fecha: dto.fechaInicio,
      pais: "CO",
    });
    if (esFestivo) {
      // Los operarios con rol SALVAVIDAS (solo o combinado) sí pueden
      // trabajar festivos, dentro del horario de su cargo -se valida más
      // abajo igual que cualquier otro día- (misma regla que en el
      // generador: DefinicionTareaPreventivaService.defPuedeTrabajarFestivo).
      const puedenTrabajarFestivo =
        operarios.length > 0 &&
        (
          await prisma.operario.findMany({
            where: { id: { in: operarios } },
            select: { funciones: true },
          })
        ).every((o) => o.funciones.includes(TipoFuncion.SALVAVIDAS));
      if (!puedenTrabajarFestivo) {
        throw new Error(
          "No se permite programar tareas en festivos.",
        );
      }
    }

    await validarOperariosEnHorarioTarea({
      prisma,
      conjuntoId: dto.conjuntoId ?? null,
      fechaInicio: dto.fechaInicio,
      fechaFin:
        dto.fechaFin ??
        new Date(
          dto.fechaInicio.getTime() +
            (dto.duracionMinutos ?? Math.round((dto.duracionHoras ?? 1) * 60)) *
              60000,
        ),
      operariosIds: operarios,
    });

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
  static async editarTarea(
    prisma: PrismaClient,
    id: number,
    payload: unknown,
    empresaId: string,
  ) {
    const dto = EditarTareaDTO.parse(payload);

    if (dto.conjuntoId === null) throw recursoFueraDeEmpresa();

    const actual = await prisma.tarea.findFirst({
      where: { id, conjunto: { empresaId } },
      select: {
        conjuntoId: true,
        ubicacionId: true,
        elementoId: true,
        supervisorId: true,
        fechaInicio: true,
        fechaFin: true,
        operarios: { select: { id: true } },
      },
    });
    if (!actual?.conjuntoId) throw recursoFueraDeEmpresa();

    const conjuntoIdFinal = dto.conjuntoId ?? actual.conjuntoId;
    const operariosFinal =
      dto.operariosIds?.map(String) ?? actual.operarios.map((o) => o.id);

    await validarRelacionesDeTarea({
      prisma,
      empresaId,
      conjuntoId: conjuntoIdFinal,
      ubicacionId: dto.ubicacionId ?? actual.ubicacionId,
      elementoId: dto.elementoId ?? actual.elementoId,
      supervisorId:
        dto.supervisorId !== undefined
          ? dto.supervisorId
          : actual.supervisorId,
      operariosIds: operariosFinal,
    });

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

    const fechaInicioFinal = dto.fechaInicio ?? actual?.fechaInicio;
    const fechaFinFinal = dto.fechaFin ?? actual?.fechaFin;

    if (fechaInicioFinal && fechaFinFinal) {
      await validarOperariosEnHorarioTarea({
        prisma,
        conjuntoId: conjuntoIdFinal ?? null,
        fechaInicio: fechaInicioFinal,
        fechaFin: fechaFinFinal,
        operariosIds: operariosFinal,
      });
    }

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
  static async obtenerTarea(
    prisma: PrismaClient,
    id: number,
    empresaId: string,
  ) {
    const tarea = await prisma.tarea.findFirst({
      where: { id, conjunto: { empresaId } },
      select: tareaPublicSelect,
    });
    if (!tarea) throw new Error("Tarea no encontrada.");
    return toTareaPublica(tarea);
  }

  // 📋 Listar tareas con filtros
  static async listarTareas(
    prisma: PrismaClient,
    payloadFiltro: unknown | undefined,
    empresaId: string,
  ) {
    const filtro = payloadFiltro ? FiltroTareaDTO.parse(payloadFiltro) : {};

    const where: any = { conjunto: { empresaId } };

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
  static async eliminarTarea(
    prisma: PrismaClient,
    id: number,
    empresaId: string,
  ) {
    const tarea = await prisma.tarea.findFirst({
      where: { id, conjunto: { empresaId } },
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
      tarea.estado === EstadoTarea.PENDIENTE_APROBACION ||
      tarea.estado === EstadoTarea.APROBADA
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

  /**
   * Corrige el cierre de una tarea ya cerrada (APROBADA / NO_COMPLETADA /
   * RECHAZADA): permite quitar/agregar evidencias y reemplazar por completo
   * los insumos usados, revirtiendo el consumo anterior y aplicando el
   * nuevo. No toca el veredicto ni quién cerró la tarea originalmente
   * (finalizadaPorId/finalizadaPorRol) — solo deja constancia de la
   * corrección en AuditoriaEvento.
   */
  static async corregirCierre(
    prisma: PrismaClient,
    tareaId: number,
    payload: unknown,
    files: Express.Multer.File[],
    empresaId: string,
    actor: { id: string; rol: string; nombre?: string | null },
  ) {
    const dto = CorregirCierreDTO.parse(payload ?? {});

    const tarea = await prisma.tarea.findFirst({
      where: { id: tareaId, conjunto: { empresaId } },
      select: {
        id: true,
        estado: true,
        evidencias: true,
        insumosUsados: true,
        conjuntoId: true,
        fechaFinalizarTarea: true,
        fechaFin: true,
        conjunto: { select: { nit: true, nombre: true } },
      },
    });

    if (!tarea) throw new Error("Tarea no encontrada.");

    const estadosCorregibles = new Set<EstadoTarea>([
      EstadoTarea.APROBADA,
      EstadoTarea.NO_COMPLETADA,
      EstadoTarea.RECHAZADA,
    ]);
    if (!estadosCorregibles.has(tarea.estado)) {
      throw new Error(
        `No se puede corregir el cierre de una tarea en estado ${tarea.estado}.`,
      );
    }

    const actuales = tarea.evidencias ?? [];
    const eliminarSet = new Set(dto.evidenciasEliminar);
    const restantes = actuales.filter((url) => !eliminarSet.has(url));

    // Subir evidencias nuevas a Drive: mismo patrón que el cierre directo.
    const urlsNuevas: string[] = [];
    try {
      let indice = 0;
      for (const f of files ?? []) {
        indice++;
        const url = await uploadEvidenciaToDrive({
          filePath: f.path,
          fileName: buildEvidenciaFileName({
            subidoPor: actor.nombre ?? actor.id,
            rol: actor.rol,
            fecha: new Date(),
            originalName: f.originalname,
            indice,
          }),
          mimeType: f.mimetype,
          conjuntoNit: tarea.conjunto?.nit ?? tarea.conjuntoId ?? "SIN_CONJUNTO",
          conjuntoNombre: tarea.conjunto?.nombre ?? undefined,
          fecha: new Date(),
        });
        urlsNuevas.push(url);
      }
    } finally {
      for (const f of files ?? []) {
        try {
          if (fs.existsSync(f.path)) fs.unlinkSync(f.path);
        } catch {}
      }
    }

    const evidenciasFinal = Array.from(
      new Set(
        [...restantes, ...urlsNuevas]
          .map((x) => x.trim())
          .filter((x) => x.length > 0),
      ),
    );

    const insumosAntes = (tarea.insumosUsados as unknown) ?? null;
    const insumosNuevos = dto.insumosUsados; // undefined => no se toca el consumo

    const tareaActualizada = await prisma.$transaction(async (tx) => {
      if (insumosNuevos !== undefined) {
        if (!tarea.conjuntoId) {
          throw new Error(
            "La tarea no tiene conjunto asignado, no puedo ajustar el inventario.",
          );
        }

        const inventario = await tx.inventario.findUnique({
          where: { conjuntoId: tarea.conjuntoId },
          select: { id: true },
        });
        if (!inventario) {
          throw new Error("No existe inventario para este conjunto.");
        }

        // Se conserva la fecha del cierre original: los informes filtran el
        // consumo por rango de fechas y una corrección no debe "mover" la
        // tarea al informe del mes en que se corrige.
        const fechaConsumo = tarea.fechaFinalizarTarea ?? tarea.fechaFin;

        // 1) Revertir el consumo que dejó el cierre original (agrupado por
        // insumo, por si hubiera varias filas para el mismo insumo).
        const consumosPrevios = await tx.consumoInsumo.findMany({
          where: { tareaId, tipo: TipoMovimientoInsumo.SALIDA },
          select: { id: true, insumoId: true, cantidad: true },
        });

        const reversionPorInsumo = new Map<number, Prisma.Decimal>();
        for (const c of consumosPrevios) {
          const previo = reversionPorInsumo.get(c.insumoId) ?? new Prisma.Decimal(0);
          reversionPorInsumo.set(c.insumoId, previo.plus(c.cantidad));
        }

        for (const [insumoId, cantidad] of reversionPorInsumo) {
          await tx.inventarioInsumo.updateMany({
            where: { inventarioId: inventario.id, insumoId },
            data: { cantidad: { increment: cantidad } },
          });
        }

        if (consumosPrevios.length > 0) {
          await tx.consumoInsumo.deleteMany({
            where: { id: { in: consumosPrevios.map((c) => c.id) } },
          });
        }

        // 2) Aplicar la lista corregida (mismo patrón de descuento del cierre).
        for (const item of insumosNuevos) {
          const invItem = await tx.inventarioInsumo.findUnique({
            where: {
              inventarioId_insumoId: {
                inventarioId: inventario.id,
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
              inventario: { connect: { id: inventario.id } },
              insumo: { connect: { id: item.insumoId } },
              tipo: TipoMovimientoInsumo.SALIDA,
              tarea: { connect: { id: tareaId } },
              cantidad: usar,
              fecha: fechaConsumo,
              observacion: `Corrección de cierre de tarea #${tareaId} por ${actor.rol} ${actor.id}: ${dto.motivo}`,
              registradoPorId: actor.id,
            },
          });
        }
      }

      const actualizada = await tx.tarea.update({
        where: { id: tareaId },
        data: {
          evidencias: evidenciasFinal,
          insumosUsados:
            insumosNuevos !== undefined ? (insumosNuevos as any) : undefined,
          observaciones: dto.observaciones ?? undefined,
        },
        select: tareaPublicSelect,
      });

      await new AuditoriaService(tx).registrarEstricto({
        modulo: ModuloAuditoria.TAREA,
        entidad: EntidadAuditoria.TAREA,
        entidadId: tareaId,
        accion: AccionAuditoria.CORREGIR_CIERRE,
        conjuntoId: tarea.conjuntoId,
        empresaId,
        actor,
        descripcion: dto.motivo,
        datosAntes: { evidencias: actuales, insumosUsados: insumosAntes },
        datosDespues: {
          evidencias: evidenciasFinal,
          insumosUsados: insumosNuevos ?? insumosAntes,
        },
      });

      return actualizada;
    });

    // Las evidencias quitadas tambien se borran de Drive. Va despues de la
    // transaccion: si Drive falla, la tarea ya quedo bien y solo se avisa en
    // el log (el archivo huerfano no afecta al informe).
    const quitadas = actuales.filter(
      (url) => eliminarSet.has(url) && !evidenciasFinal.includes(url.trim()),
    );
    await TareaService.borrarEvidenciasDeDrive(prisma, tareaId, quitadas);

    return toTareaPublica(tareaActualizada);
  }

  /**
   * Borra de Drive las evidencias que se quitaron de una tarea. Solo toca
   * archivos que estaban en esa tarea (nunca ids arbitrarios del cliente) y
   * conserva los que otra tarea siga usando.
   */
  private static async borrarEvidenciasDeDrive(
    prisma: PrismaClient,
    tareaId: number,
    urls: string[],
  ) {
    for (const url of urls) {
      const fileId = extraerDriveId(url);
      if (!fileId) continue;
      try {
        const otrasTareas = await prisma.tarea.count({
          where: { id: { not: tareaId }, evidencias: { has: url } },
        });
        if (otrasTareas > 0) continue;
        await eliminarEvidenciaDeDrive(fileId);
      } catch (err) {
        console.error(
          `[corregir-cierre] no se pudo borrar de Drive la evidencia ${fileId} (tarea ${tareaId}):`,
          err instanceof Error ? err.message : err,
        );
      }
    }
  }

  /* =====================================================
   *  A PARTIR DE AQUÍ, DEJA TUS MÉTODOS EXISTENTES IGUAL:
   *  agregarEvidencia, iniciarTarea, marcarComoCompletadaConInsumos,
   *  marcarNoCompletada, aprobarTarea, rechazarTarea, resumen, etc.
   * ===================================================== */
}
