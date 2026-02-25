// src/services/SupervisorService.ts
import {
  PrismaClient,
  Prisma,
  EstadoTarea,
  EstadoUsoHerramienta,
  TipoMovimientoInsumo,
} from "@prisma/client";
import { z } from "zod";
import { InventarioService } from "./InventarioServices";
import { uploadEvidenciaToDrive } from "../utils/drive_evidencias";
import fs from "fs";
import { NotificacionService } from "./NotificacionService";

/**
 * Supervisor Fase 1:
 * - Lista tareas por conjunto/operario/estado/rango fechas
 * - Cierra tarea (cuando el operario no usa app): guarda evidencias y deja PENDIENTE_APROBACION
 * - Veredicto: aprobar / rechazar / no_completada
 *
 * IDs: supervisorId = string (cédula)
 */

type InsumoUsado = {
  insumoId: number;
  cantidad: number;
};

type InsumoPlan = {
  insumoId: number;
  nombre?: string;
  unidad?: string;
  cantidad?: number;
};

function parseInsumosPlanJson(raw: any): InsumoPlan[] {
  if (!raw) return [];
  try {
    // Prisma Json puede venir como object/array ya parseado
    const v = raw;
    if (Array.isArray(v)) return v as InsumoPlan[];
    if (typeof v === "string") {
      const parsed = JSON.parse(v);
      return Array.isArray(parsed) ? (parsed as InsumoPlan[]) : [];
    }
    // si viene como {items:[...]} o similar, intenta detectar
    if (typeof v === "object") {
      if (Array.isArray((v as any).items))
        return (v as any).items as InsumoPlan[];
    }
    return [];
  } catch {
    return [];
  }
}

const ListarDTO = z.object({
  conjuntoId: z.string().optional(),
  operarioId: z.string().optional(),
  estado: z.nativeEnum(EstadoTarea).optional(),
  desde: z.coerce.date().optional(),
  hasta: z.coerce.date().optional(),
  borrador: z.coerce.boolean().optional(),
});

const CerrarMultipartDTO = z.object({
  observaciones: z.string().optional(),
  fechaFinalizarTarea: z.string().optional(), // viene string ISO
  insumosUsados: z.string().optional(), // JSON string
});

export const CerrarDTO = z.object({
  evidencias: z.array(z.string()).optional().default([]),
  fechaFinalizarTarea: z.coerce.date().optional(),
  observaciones: z.string().max(500).optional(),

  // 1) ✅ insumos usados
  insumosUsados: z
    .array(
      z.object({
        insumoId: z.number().int().positive(),
        cantidad: z.coerce.number().positive(),
      }),
    )
    .optional()
    .default([]),

  // 2) ✅ maquinaria usada
  maquinariasUsadas: z
    .array(
      z.object({
        maquinariaId: z.number().int().positive(),
        observacion: z.string().max(300).optional(),
      }),
    )
    .optional()
    .default([]),

  // 3) ✅ herramientas usadas
  herramientasUsadas: z
    .array(
      z.object({
        herramientaId: z.number().int().positive(),
        cantidad: z.coerce.number().positive().optional().default(1),
        observacion: z.string().max(300).optional(),
      }),
    )
    .optional()
    .default([]),
});

const VeredictoDTO = z.object({
  accion: z.enum(["APROBAR", "RECHAZAR", "NO_COMPLETADA"]),
  observacionesRechazo: z.string().min(3).max(500).optional(),
  fechaVerificacion: z.coerce.date().optional(),
});

export class SupervisorService {
  constructor(
    private prisma: PrismaClient,
    private supervisorId: string,
  ) {}

  /** Lista tareas para el supervisor (por conjunto/operario/estado y rango) */
  async listarTareas(payload: unknown) {
    const dto = ListarDTO.parse(payload ?? {});
    const where: Prisma.TareaWhereInput = {};

    if (dto.conjuntoId) where.conjuntoId = dto.conjuntoId;
    if (dto.estado) where.estado = dto.estado as any;
    if (dto.borrador !== undefined) where.borrador = dto.borrador;

    if (dto.operarioId) where.operarios = { some: { id: dto.operarioId } };

    if (dto.desde || dto.hasta) {
      where.fechaInicio = {};
      if (dto.desde) where.fechaInicio.gte = dto.desde;
      if (dto.hasta) where.fechaInicio.lte = dto.hasta;
    }

    const rows = await this.prisma.tarea.findMany({
      where,
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
      include: {
        ubicacion: true,
        elemento: true,
        conjunto: true,
        operarios: { include: { usuario: true } },
        supervisor: { include: { usuario: true } },

        insumoPrincipal: { select: { id: true, nombre: true, unidad: true } },

        usoHerramientas: {
          include: { herramienta: { select: { id: true, nombre: true } } },
        },
        usoMaquinarias: {
          include: { maquinaria: { select: { id: true, nombre: true } } },
        },
      },
    });

    const byGP = new Map<
      string,
      { herramientas: any[]; maquinarias: any[]; insumos: any[] }
    >();

    for (const t of rows) {
      const gp = (t as any).grupoPlanId as string | null;
      if (!gp) continue;

      const herramientas = t.usoHerramientas.map((u) => ({
        herramientaId: u.herramientaId,
        nombre: u.herramienta?.nombre ?? "",
        cantidad: Number(u.cantidad),
        estado: u.estado,
      }));

      const maquinarias = t.usoMaquinarias.map((u) => ({
        maquinariaId: u.maquinariaId,
        nombre: u.maquinaria?.nombre ?? "",
      }));

      const insumos = parseInsumosPlanJson((t as any).insumosPlanJson);

      const cur = byGP.get(gp) ?? {
        herramientas: [],
        maquinarias: [],
        insumos: [],
      };
      if (herramientas.length) cur.herramientas = herramientas;
      if (maquinarias.length) cur.maquinarias = maquinarias;
      if (insumos.length) cur.insumos = insumos;

      byGP.set(gp, cur);
    }

    return rows.map((t) => {
      const gp = (t as any).grupoPlanId as string | null;

      let herramientasAsignadas = t.usoHerramientas.map((u) => ({
        herramientaId: u.herramientaId,
        nombre: u.herramienta?.nombre ?? "",
        cantidad: Number(u.cantidad),
        estado: u.estado,
      }));

      let maquinariasAsignadas = t.usoMaquinarias.map((u) => ({
        maquinariaId: u.maquinariaId,
        nombre: u.maquinaria?.nombre ?? "",
      }));

      let insumosProgramados = parseInsumosPlanJson((t as any).insumosPlanJson);

      if (gp) {
        const ref = byGP.get(gp);
        if (ref) {
          if (!herramientasAsignadas.length)
            herramientasAsignadas = ref.herramientas;
          if (!maquinariasAsignadas.length)
            maquinariasAsignadas = ref.maquinarias;
          if (!insumosProgramados.length) insumosProgramados = ref.insumos;
        }
      }

      return {
        id: t.id,
        descripcion: t.descripcion,
        fechaInicio: t.fechaInicio,
        fechaFin: t.fechaFin,
        duracionMinutos: t.duracionMinutos,
        prioridad: t.prioridad,
        estado: t.estado,
        evidencias: t.evidencias ?? [],
        observaciones: t.observaciones,
        observacionesRechazo: t.observacionesRechazo,
        borrador: t.borrador,

        conjuntoId: t.conjuntoId ?? null,
        conjuntoNombre: t.conjunto?.nombre ?? null,

        supervisorId: t.supervisorId ?? null,
        supervisorNombre: t.supervisor?.usuario?.nombre ?? null,

        ubicacionId: t.ubicacionId,
        ubicacionNombre: t.ubicacion?.nombre ?? null,

        elementoId: t.elementoId,
        elementoNombre: t.elemento?.nombre ?? null,

        operariosIds: t.operarios.map((o) => o.id),
        operariosNombres: t.operarios.map((o) => o.usuario?.nombre ?? ""),

        herramientasAsignadas,
        maquinariasAsignadas,

        // ✅ insumos
        insumoPrincipalNombre: t.insumoPrincipal?.nombre ?? null,
        insumoPrincipalUnidad: t.insumoPrincipal?.unidad ?? null,
        consumoPrincipalPorUnidad: t.consumoPrincipalPorUnidad ?? null,
        consumoTotalEstimado: t.consumoTotalEstimado ?? null,
        insumosProgramados,
      };
    });
  }

  // dentro de SupervisorService
  async cronogramaImprimible(payload: {
    conjuntoId: string;
    operarioId: string;
    desde: Date;
    hasta: Date;
  }) {
    // Reutiliza tu listarTareas
    const tareas = await this.listarTareas({
      conjuntoId: payload.conjuntoId,
      operarioId: payload.operarioId,
      desde: payload.desde,
      hasta: payload.hasta,
      // normalmente imprimimos ASIGNADA/EN_PROCESO (tú decides)
    });

    // Datos operario / conjunto (opcional pero recomendado)
    const operario = await this.prisma.operario.findUnique({
      where: { id: payload.operarioId },
      include: { usuario: true },
    });

    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: payload.conjuntoId },
      select: { nit: true, nombre: true },
    });

    // Agrupar por día (ISO yyyy-mm-dd)
    const diasMap = new Map<string, any[]>();
    for (const t of tareas as any[]) {
      const key = this.isoDate(this.dayOnly(new Date(t.fechaInicio)));
      const arr = diasMap.get(key) ?? [];
      arr.push({
        id: t.id,
        hora:
          `${String(new Date(t.fechaInicio).getHours()).padStart(2, "0")}:${String(new Date(t.fechaInicio).getMinutes()).padStart(2, "0")}` +
          " - " +
          `${String(new Date(t.fechaFin).getHours()).padStart(2, "0")}:${String(new Date(t.fechaFin).getMinutes()).padStart(2, "0")}`,
        descripcion: t.descripcion ?? "",
        ubicacion: t.ubicacionNombre ?? "",
        elemento: t.elementoNombre ?? "",
        prioridad: t.prioridad ?? null,
        herramientas: (t.herramientasAsignadas ?? []).map(
          (h: any) => `${h.nombre} x${h.cantidad}`,
        ),
        maquinarias: (t.maquinariasAsignadas ?? []).map(
          (m: any) => `${m.nombre}`,
        ),
      });
      diasMap.set(key, arr);
    }

    // Ordenar días y tareas por hora
    const dias = Array.from(diasMap.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([fecha, tareasDia]) => ({
        fecha,
        tareas: tareasDia.sort((a, b) => a.hora.localeCompare(b.hora)),
      }));

    return {
      ok: true,
      conjuntoId: payload.conjuntoId,
      conjuntoNombre: conjunto?.nombre ?? null,
      operarioId: payload.operarioId,
      operarioNombre: operario?.usuario?.nombre ?? null,
      desde: payload.desde,
      hasta: payload.hasta,
      dias,
    };
  }

  /**
   * Cerrar tarea por supervisor (operario SIN app):
   * - Solo si está ASIGNADA / EN_PROCESO / COMPLETADA
   * - Guarda evidencias
   * - estado -> PENDIENTE_APROBACION
   * - fechaFinalizarTarea -> now (o la enviada)
   * - descuenta insumos + registra usos de maquinaria/herramientas y libera lo prestado
   */
  async cerrarTarea(tareaId: number, payload: unknown) {
    const dto = CerrarDTO.parse(payload ?? {});

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: {
        id: true,
        estado: true,
        evidencias: true,
        conjuntoId: true,
        operarios: { select: { id: true } },
      },
    });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");

    const permitidos = new Set<EstadoTarea>([
      EstadoTarea.ASIGNADA,
      EstadoTarea.EN_PROCESO,
      EstadoTarea.COMPLETADA,
    ]);

    if (!permitidos.has(tarea.estado)) {
      throw new Error(`No puedes cerrar una tarea en estado ${tarea.estado}.`);
    }

    if (!tarea.conjuntoId) {
      throw new Error(
        "❌ La tarea no tiene conjunto asignado (no puedo afectar inventario/stock).",
      );
    }

    const inv = await this.prisma.inventario.findUnique({
      where: { conjuntoId: tarea.conjuntoId },
      select: { id: true },
    });

    if (!inv) {
      throw new Error(
        `❌ El conjunto ${tarea.conjuntoId} no tiene inventario creado.`,
      );
    }

    const ahora = dto.fechaFinalizarTarea ?? new Date();

    const actuales = tarea.evidencias ?? [];
    const mergeEvidencias = [...actuales, ...(dto.evidencias ?? [])];

    const insumosUsados = dto.insumosUsados ?? [];
    const maquinariasUsadas = dto.maquinariasUsadas ?? [];
    const herramientasUsadas = dto.herramientasUsadas ?? [];

    // opcional: trazabilidad
    const operarioId = tarea.operarios?.[0]?.id ?? null;

    await this.prisma.$transaction(async (tx) => {
      // 1) ✅ DESCONTAR INSUMOS
      const inventarioSvc = new InventarioService(tx as any, inv.id);

      for (const it of insumosUsados) {
        await inventarioSvc.consumirInsumoPorId({
          insumoId: it.insumoId,
          cantidad: it.cantidad,
        });
      }

      // 2) ✅ MAQUINARIA: asegurar uso abierto + cerrar + liberar maquinariaConjunto
      for (const m of maquinariasUsadas) {
        // 2.0 Asegurar uso abierto
        const existeUsoAbierto = await tx.usoMaquinaria.findFirst({
          where: {
            tareaId,
            maquinariaId: m.maquinariaId,
            fechaFin: null,
          },
          select: { id: true },
        });

        if (!existeUsoAbierto) {
          await tx.usoMaquinaria.create({
            data: {
              tarea: { connect: { id: tareaId } },
              maquinaria: { connect: { id: m.maquinariaId } },
              ...(operarioId
                ? { operario: { connect: { id: operarioId } } }
                : {}),
              fechaInicio: ahora,
              observacion: m.observacion ?? null,
            },
          });
        }

        // 2.1 Cerrar usos abiertos
        await tx.usoMaquinaria.updateMany({
          where: {
            tareaId,
            maquinariaId: m.maquinariaId,
            fechaFin: null,
          },
          data: {
            fechaFin: ahora,
            // si viene observación, la guardamos; si no, no pisamos con null
            ...(m.observacion ? { observacion: m.observacion } : {}),
            ...(operarioId ? { operarioId } : {}),
          },
        });

        // 2.2 Liberar maquinaria del conjunto (si estaba amarrada a esta tarea)
        await tx.maquinariaConjunto.updateMany({
          where: {
            conjuntoId: tarea.conjuntoId!,
            maquinariaId: m.maquinariaId,
            tareaId: tareaId,
          },
          data: {
            tareaId: null,
            operarioId: null,
            fechaDevolucionEstimada: null,
          },
        });
      }

      // 3) ✅ HERRAMIENTAS: asegurar uso abierto + cerrar + marcar DEVUELTA
      for (const h of herramientasUsadas) {
        const existeUsoAbierto = await tx.usoHerramienta.findFirst({
          where: {
            tareaId,
            herramientaId: h.herramientaId,
            fechaFin: null,
          },
          select: { id: true },
        });

        if (!existeUsoAbierto) {
          await tx.usoHerramienta.create({
            data: {
              tarea: { connect: { id: tareaId } },
              herramienta: { connect: { id: h.herramientaId } },
              cantidad: h.cantidad ?? 1,
              estado: EstadoUsoHerramienta.EN_USO,
              ...(operarioId
                ? { operario: { connect: { id: operarioId } } }
                : {}),
              fechaInicio: ahora,
              observacion: h.observacion ?? null,
            },
          });
        }

        await tx.usoHerramienta.updateMany({
          where: {
            tareaId,
            herramientaId: h.herramientaId,
            fechaFin: null,
          },
          data: {
            fechaFin: ahora,
            estado: EstadoUsoHerramienta.DEVUELTA,
            ...(h.observacion ? { observacion: h.observacion } : {}),
            ...(operarioId ? { operarioId } : {}),
          },
        });
      }

      // 4) ✅ ACTUALIZAR TAREA: evidencias + observaciones + estado pendiente aprobación
      await tx.tarea.update({
        where: { id: tareaId },
        data: {
          evidencias: mergeEvidencias,
          observaciones: dto.observaciones ?? undefined,
          estado: EstadoTarea.PENDIENTE_APROBACION,
          fechaFinalizarTarea: ahora,
          supervisorId: this.supervisorId,
        },
      });
    });
  }

  async cerrarTareaConEvidencias(
    tareaId: number,
    payload: unknown,
    files: Express.Multer.File[],
  ) {
    const dto = CerrarMultipartDTO.parse(payload ?? {});
    const fechaCierre = dto.fechaFinalizarTarea
      ? new Date(dto.fechaFinalizarTarea)
      : new Date();

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: {
        id: true,
        descripcion: true,
        estado: true,
        evidencias: true,
        conjuntoId: true,
        supervisorId: true,
        conjunto: { select: { nit: true, nombre: true } },
      },
    });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");

    const permitidos = new Set<EstadoTarea>([
      EstadoTarea.ASIGNADA,
      EstadoTarea.EN_PROCESO,
      EstadoTarea.COMPLETADA,
    ]);

    if (!permitidos.has(tarea.estado)) {
      throw new Error(`No puedes cerrar una tarea en estado ${tarea.estado}.`);
    }

    if (!tarea.conjuntoId) {
      throw new Error(
        "La tarea no tiene conjunto asignado, no puedo descontar inventario.",
      );
    }

    // 1) Parse insumosUsados (JSON string)
    let insumosUsados: InsumoUsado[] = [];
    if (dto.insumosUsados && dto.insumosUsados.trim().length) {
      try {
        const parsed = JSON.parse(dto.insumosUsados);
        insumosUsados = z
          .array(
            z.object({
              insumoId: z.number().int().positive(),
              cantidad: z.number().positive(),
            }),
          )
          .parse(parsed);
      } catch {
        throw new Error(
          "insumosUsados debe ser un JSON válido: [{insumoId, cantidad}]",
        );
      }
    }

    // 2) Subir evidencias a Drive
    const urls: string[] = [];
    try {
      for (const f of files ?? []) {
        const url = await uploadEvidenciaToDrive({
          filePath: f.path,
          fileName: `Tarea_${tareaId}_${fechaCierre
            .toISOString()
            .replace(/[:.]/g, "-")}_${f.originalname}`,
          mimeType: f.mimetype,
          conjuntoNit: tarea.conjunto?.nit ?? tarea.conjuntoId,
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

    // 3) Transacción: descontar inventario + registrar consumo + liberar usos + cerrar tarea
    await this.prisma.$transaction(async (tx) => {
      const inventario = await tx.inventario.findUnique({
        where: { conjuntoId: tarea.conjuntoId! },
        select: { id: true },
      });

      if (!inventario) {
        throw new Error("No existe inventario para este conjunto.");
      }

      // ✅ descontar parcial: resta SOLO lo usado
      for (const item of insumosUsados) {
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

        const actual = invItem.cantidad; // Prisma.Decimal
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
            fecha: fechaCierre,
            observacion: `Consumo en cierre de tarea #${tareaId} por supervisor ${this.supervisorId}`,
            // operarioId NO se manda (undefined) para no chocar con tu modelo
          },
        });
      }

      // ✅ liberar maquinaria en uso (UsoMaquinaria)
      await tx.usoMaquinaria.updateMany({
        where: { tareaId, fechaFin: null },
        data: {
          fechaFin: fechaCierre,
          observacion: "Devuelta al cerrar tarea",
        },
      });

      // ✅ liberar herramientas en uso (UsoHerramienta)
      await tx.usoHerramienta.updateMany({
        where: { tareaId, fechaFin: null },
        data: {
          fechaFin: fechaCierre,
          estado: EstadoUsoHerramienta.DEVUELTA,
          observacion: "Devuelta al cerrar tarea",
        },
      });

      // ✅ MUY IMPORTANTE: si tu ocupación depende de MaquinariaConjunto.tareaId
      await tx.maquinariaConjunto.updateMany({
        where: { tareaId },
        data: { tareaId: null },
      });

      // ✅ cerrar tarea
      await tx.tarea.update({
        where: { id: tareaId },
        data: {
          evidencias: evidenciasMerge,
          observaciones: dto.observaciones ?? undefined,
          insumosUsados: insumosUsados as any,
          estado: EstadoTarea.PENDIENTE_APROBACION,
          fechaFinalizarTarea: fechaCierre,
          supervisorId: this.supervisorId,
          finalizadaPorId: this.supervisorId,
          finalizadaPorRol: "SUPERVISOR",
        },
      });
    });

    try {
      const notificaciones = new NotificacionService(this.prisma);
      await notificaciones.notificarCierreTarea({
        tareaId,
        descripcionTarea: tarea.descripcion,
        conjuntoId: tarea.conjuntoId,
        actorId: this.supervisorId,
        actorRol: "SUPERVISOR",
        supervisorId: tarea.supervisorId,
      });
    } catch (e) {
      console.error("No se pudo notificar cierre de tarea (supervisor):", e);
    }
  }

  /**
   * Veredicto del supervisor:
   * - APROBAR => APROBADA
   * - RECHAZAR => RECHAZADA + observacionesRechazo
   * - NO_COMPLETADA => NO_COMPLETADA
   *
   * Solo aplica si está PENDIENTE_APROBACION.
   */
  async veredicto(tareaId: number, payload: unknown) {
    const dto = VeredictoDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { estado: true },
    });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error(
        "Solo puedes dar veredicto a tareas en PENDIENTE_APROBACION.",
      );
    }

    const fechaVer = dto.fechaVerificacion ?? new Date();

    if (dto.accion === "APROBAR") {
      await this.prisma.tarea.update({
        where: { id: tareaId },
        data: {
          estado: EstadoTarea.APROBADA,
          fechaVerificacion: fechaVer,
          supervisorId: this.supervisorId,
        },
      });
      return;
    }

    if (dto.accion === "NO_COMPLETADA") {
      await this.prisma.tarea.update({
        where: { id: tareaId },
        data: {
          estado: EstadoTarea.NO_COMPLETADA,
          fechaVerificacion: fechaVer,
          supervisorId: this.supervisorId,
        },
      });
      return;
    }

    // RECHAZAR
    if (
      !dto.observacionesRechazo ||
      dto.observacionesRechazo.trim().length < 3
    ) {
      throw new Error("Para rechazar debes enviar observacionesRechazo.");
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        estado: EstadoTarea.RECHAZADA,
        observacionesRechazo: dto.observacionesRechazo,
        fechaVerificacion: fechaVer,
        supervisorId: this.supervisorId,
      },
    });
  }

  private dayOnly(d: Date) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  }

  private isoDate(d: Date) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  }
}
