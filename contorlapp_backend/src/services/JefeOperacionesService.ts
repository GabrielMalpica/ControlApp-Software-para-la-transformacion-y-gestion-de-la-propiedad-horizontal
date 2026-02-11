// src/services/JefeOperacionesService.ts
import { PrismaClient, EstadoTarea } from "../generated/prisma";
import { z } from "zod";
import { uploadEvidenciaToDrive } from "../utils/drive_evidencias";
import fs from "fs";

const ConjuntoIdSchema = z.string().trim().min(1).optional();

const VeredictoDTO = z.object({
  accion: z.enum(["APROBAR", "RECHAZAR", "NO_COMPLETADA"]),
  observacionesRechazo: z.string().min(3).max(500).optional(),
  fechaVerificacion: z.coerce.date().optional(),
});

const VeredictoMultipartDTO = z.object({
  accion: z.enum(["APROBAR", "RECHAZAR", "NO_COMPLETADA"]),
  observacionesRechazo: z.string().optional(),
  fechaVerificacion: z.string().optional(),
  evidenciasExtra: z.string().optional(),
});

export class JefeOperacionesService {
  private empresaIdNum: number | null;

  constructor(
    private prisma: PrismaClient,
    empresaId: unknown,
  ) {
    const n = Number(empresaId);
    this.empresaIdNum = Number.isFinite(n) && n > 0 ? n : null;
  }

  async listarPendientes(conjuntoId?: string) {
    const nit = ConjuntoIdSchema.parse(conjuntoId);

    return this.prisma.tarea.findMany({
      where: {
        estado: EstadoTarea.PENDIENTE_APROBACION,
        ...(nit ? { conjuntoId: nit } : {}),
      },
      orderBy: [{ fechaFinalizarTarea: "desc" }, { id: "desc" }],
      include: {
        conjunto: true,
        ubicacion: true,
        elemento: true,
        operarios: { include: { usuario: true } },
        supervisor: { include: { usuario: true } },
      },
    });
  }

  async veredicto(tareaId: number, payload: unknown) {
    const dto = VeredictoDTO.parse(payload ?? {});
    return this._aplicarVeredictoCore({
      tareaId,
      accion: dto.accion,
      fechaVerificacion: dto.fechaVerificacion ?? new Date(),
      observacionesRechazo: dto.observacionesRechazo,
      evidenciasNuevas: [],
    });
  }

  async veredictoConEvidencias(
    tareaId: number,
    payload: unknown,
    files: Express.Multer.File[],
  ) {
    const dto = VeredictoMultipartDTO.parse(payload ?? {});
    const fechaVer = dto.fechaVerificacion
      ? new Date(dto.fechaVerificacion)
      : new Date();

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: {
        id: true,
        estado: true,
        evidencias: true,
        conjuntoId: true,
        conjunto: { select: { nit: true, nombre: true } },
      },
    });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error(
        "Solo puedes dar veredicto a tareas PENDIENTE_APROBACION.",
      );
    }

    let evidenciasExtra: string[] = [];
    if (dto.evidenciasExtra?.trim()) {
      try {
        const parsed = JSON.parse(dto.evidenciasExtra);
        evidenciasExtra = z.array(z.string().min(3)).parse(parsed);
      } catch {
        throw new Error(
          'evidenciasExtra debe ser JSON válido: ["url1","url2"]',
        );
      }
    }

    const urlsDrive: string[] = [];
    try {
      for (const f of files ?? []) {
        const url = await uploadEvidenciaToDrive({
          filePath: f.path,
          fileName: `Aprobacion_Tarea_${tareaId}_${fechaVer.toISOString().replace(/[:.]/g, "-")}_${f.originalname}`,
          mimeType: f.mimetype,
          conjuntoNit:
            tarea.conjunto?.nit ?? tarea.conjuntoId ?? "SIN_CONJUNTO",
          conjuntoNombre: tarea.conjunto?.nombre ?? undefined,
          fecha: fechaVer,
        });
        urlsDrive.push(url);
      }
    } finally {
      for (const f of files ?? []) {
        try {
          if (fs.existsSync(f.path)) fs.unlinkSync(f.path);
        } catch {}
      }
    }

    const actuales = tarea.evidencias ?? [];
    const merged = [...actuales, ...evidenciasExtra, ...urlsDrive]
      .map((x) => x.trim())
      .filter((x) => x.length > 0);

    const evidenciasFinal = Array.from(new Set(merged));

    return this._aplicarVeredictoCore({
      tareaId,
      accion: dto.accion,
      fechaVerificacion: fechaVer,
      observacionesRechazo: dto.observacionesRechazo,
      evidenciasNuevas: evidenciasFinal,
    });
  }

  private async _aplicarVeredictoCore(params: {
    tareaId: number;
    accion: "APROBAR" | "RECHAZAR" | "NO_COMPLETADA";
    fechaVerificacion: Date;
    observacionesRechazo?: string;
    evidenciasNuevas: string[];
  }) {
    const {
      tareaId,
      accion,
      fechaVerificacion,
      observacionesRechazo,
      evidenciasNuevas,
    } = params;

    const dataEvidencias =
      evidenciasNuevas.length > 0 ? { evidencias: evidenciasNuevas } : {};

    if (accion === "APROBAR") {
      await this.prisma.tarea.update({
        where: { id: tareaId },
        data: {
          ...dataEvidencias,
          estado: EstadoTarea.APROBADA,
          fechaVerificacion,
          empresaAprobadaId: this.empresaIdNum, // ✅ number|null
          empresaRechazadaId: null,
          observacionesRechazo: null,
        },
      });
      return { ok: true, estado: EstadoTarea.APROBADA };
    }

    if (accion === "NO_COMPLETADA") {
      await this.prisma.tarea.update({
        where: { id: tareaId },
        data: {
          ...dataEvidencias,
          estado: EstadoTarea.NO_COMPLETADA,
          fechaVerificacion,
          empresaAprobadaId: null,
          empresaRechazadaId: null,
          observacionesRechazo: null,
        },
      });
      return { ok: true, estado: EstadoTarea.NO_COMPLETADA };
    }

    if (!observacionesRechazo?.trim()) {
      throw new Error("Para rechazar debes enviar observacionesRechazo.");
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        ...dataEvidencias,
        estado: EstadoTarea.RECHAZADA,
        fechaVerificacion,
        observacionesRechazo: observacionesRechazo.trim(),
        empresaRechazadaId: this.empresaIdNum, // ✅ number|null
        empresaAprobadaId: null,
      },
    });

    return { ok: true, estado: EstadoTarea.RECHAZADA };
  }
}
