import fs from "fs";
import type { PrismaClient } from "@prisma/client";
import { NotificacionService } from "./NotificacionService";
import { buildEvidenciaFileName, uploadEvidenciaToDrive } from "../utils/drive_evidencias";
import { subirEvidenciasConMarca } from "../utils/marca_agua_evidencia";

export const ESTADOS_PQRS = [
  "RECIBIDO",
  "EN_REVISION",
  "EN_PROCESO",
  "EN_ESPERA",
  "CERRADO",
] as const;

export type EstadoPqrs = (typeof ESTADOS_PQRS)[number];

const ETIQUETAS_ESTADO: Record<EstadoPqrs, string> = {
  RECIBIDO: "Recibido",
  EN_REVISION: "En revisión",
  EN_PROCESO: "En proceso",
  EN_ESPERA: "En espera",
  CERRADO: "Cerrado",
};

function makeHttpError(status: number, message: string) {
  const err = new Error(message) as Error & { status: number };
  err.status = status;
  return err;
}

type ActorRow = { nombre: string; rol: string } | null;

type ActualizacionRow = {
  id: number;
  estado: string;
  observacion: string | null;
  evidencias: string[];
  actorId: string | null;
  creadaEn: Date;
  actor?: ActorRow;
};

type CompromisoRow = {
  id: number;
  conjuntoId: string;
  titulo: string;
  completado: boolean;
  estado: string;
  creadaEn: Date;
  cerradaEn: Date | null;
  actualizadaEn: Date;
  creadoPorId: string | null;
  creadoPor?: ActorRow;
  conjunto?: { nit: string; nombre: string } | null;
  actualizaciones?: ActualizacionRow[];
};

const selectCompromiso = {
  id: true,
  conjuntoId: true,
  titulo: true,
  completado: true,
  estado: true,
  creadaEn: true,
  cerradaEn: true,
  actualizadaEn: true,
  creadoPorId: true,
  creadoPor: { select: { nombre: true, rol: true } },
  actualizaciones: {
    orderBy: { creadaEn: "asc" as const },
    select: {
      id: true,
      estado: true,
      observacion: true,
      evidencias: true,
      actorId: true,
      creadaEn: true,
      actor: { select: { nombre: true, rol: true } },
    },
  },
};

export class CompromisoConjuntoService {
  constructor(private readonly prisma: PrismaClient) {}

  private buildAns(compromiso: Pick<CompromisoRow, "completado" | "creadaEn">) {
    if (compromiso.completado) {
      return { ansEstado: "cerrado", ansColor: "neutral", ansLabel: "Cerrado" };
    }

    const msAbierto = Date.now() - compromiso.creadaEn.getTime();
    const diasAbierto = Math.max(0, Math.floor(msAbierto / (1000 * 60 * 60 * 24)));
    if (diasAbierto <= 7) return { ansEstado: "verde", ansColor: "green", ansLabel: "ANS en tiempo" };
    if (diasAbierto <= 21) return { ansEstado: "naranja", ansColor: "orange", ansLabel: "ANS en seguimiento" };
    return { ansEstado: "rojo", ansColor: "red", ansLabel: "ANS critico" };
  }

  private formatRol(rol?: string | null) {
    const normalized = String(rol ?? "").trim().toLowerCase();
    if (normalized == "jefe_operaciones") return "Jefe de operaciones";
    if (normalized == "administrador") return "Administrador";
    if (normalized == "supervisor") return "Supervisor";
    if (normalized == "operario") return "Operario";
    if (normalized == "gerente") return "Gerente";
    return normalized ? normalized[0].toUpperCase() + normalized.slice(1) : null;
  }

  private serializeActualizacion(item: ActualizacionRow) {
    const estado = ESTADOS_PQRS.includes(item.estado as EstadoPqrs)
      ? (item.estado as EstadoPqrs)
      : "RECIBIDO";
    return {
      id: item.id,
      estado,
      estadoLabel: ETIQUETAS_ESTADO[estado],
      observacion: item.observacion,
      evidencias: item.evidencias,
      actorId: item.actorId,
      actorNombre: item.actor?.nombre ?? null,
      actorRol: this.formatRol(item.actor?.rol),
      creadaEn: item.creadaEn,
    };
  }

  private serializeCompromiso(item: CompromisoRow) {
    const estado = ESTADOS_PQRS.includes(item.estado as EstadoPqrs)
      ? (item.estado as EstadoPqrs)
      : item.completado ? "CERRADO" : "RECIBIDO";
    const ans = this.buildAns(item);
    const actualizaciones = (item.actualizaciones ?? []).map((x) => this.serializeActualizacion(x));
    return {
      id: item.id,
      conjuntoId: item.conjuntoId,
      titulo: item.titulo,
      estado,
      estadoLabel: ETIQUETAS_ESTADO[estado],
      completado: estado === "CERRADO",
      creadaEn: item.creadaEn,
      cerradaEn: item.cerradaEn,
      actualizadaEn: item.actualizadaEn,
      creadoPorId: item.creadoPorId,
      creadoPorNombre: item.creadoPor?.nombre ?? null,
      creadoPorRol: this.formatRol(item.creadoPor?.rol),
      actualizaciones,
      ultimaActualizacion: actualizaciones.length > 0 ? actualizaciones[actualizaciones.length - 1] : null,
      diasAbierto: Math.max(0, Math.floor((Date.now() - item.creadaEn.getTime()) / (1000 * 60 * 60 * 24))),
      ansEstado: ans.ansEstado,
      ansColor: ans.ansColor,
      ansLabel: ans.ansLabel,
      conjuntoNombre: item.conjunto?.nombre ?? item.conjuntoId,
      conjuntoNit: item.conjunto?.nit ?? item.conjuntoId,
    };
  }

  async listarPorConjunto(conjuntoId: string) {
    const items = await this.prisma.compromisoConjunto.findMany({
      where: { conjuntoId },
      orderBy: [{ completado: "asc" }, { creadaEn: "desc" }],
      select: { ...selectCompromiso, conjunto: { select: { nit: true, nombre: true } } },
    });
    return items.map((item) => this.serializeCompromiso(item as CompromisoRow));
  }

  async listarGlobal(empresaId: string) {
    const empresa = empresaId.trim();
    if (!empresa) throw makeHttpError(401, "No se pudo identificar la empresa autenticada");
    const items = await this.prisma.compromisoConjunto.findMany({
      where: { conjunto: { empresaId: empresa } },
      orderBy: [{ completado: "asc" }, { conjunto: { nombre: "asc" } }, { creadaEn: "desc" }],
      select: { ...selectCompromiso, conjunto: { select: { nit: true, nombre: true } } },
    });
    return items.map((item) => this.serializeCompromiso(item as CompromisoRow));
  }

  async crear(input: { conjuntoId: string; titulo: string; creadoPorId?: string | null }) {
    const titulo = input.titulo.trim();
    if (!titulo) throw makeHttpError(400, "El compromiso no puede estar vacio");
    const created = await this.prisma.compromisoConjunto.create({
      data: {
        conjuntoId: input.conjuntoId,
        titulo,
        creadoPorId: input.creadoPorId ?? null,
        estado: "RECIBIDO",
        actualizaciones: {
          create: { estado: "RECIBIDO", actorId: input.creadoPorId ?? null },
        },
      },
      select: { ...selectCompromiso, conjunto: { select: { nit: true, nombre: true } } },
    });
    return this.serializeCompromiso(created as CompromisoRow);
  }

  async actualizar(id: number, data: { titulo?: string }) {
    const current = await this.prisma.compromisoConjunto.findUnique({ where: { id } });
    if (!current) throw makeHttpError(404, "Compromiso no encontrado");
    const payload: { titulo?: string } = {};
    if (typeof data.titulo === "string") {
      const titulo = data.titulo.trim();
      if (!titulo) throw makeHttpError(400, "El compromiso no puede estar vacio");
      payload.titulo = titulo;
    }
    const updated = await this.prisma.compromisoConjunto.update({
      where: { id },
      data: payload,
      select: { ...selectCompromiso, conjunto: { select: { nit: true, nombre: true } } },
    });
    return this.serializeCompromiso(updated as CompromisoRow);
  }

  async agregarSeguimiento(input: {
    id: number;
    estado: EstadoPqrs;
    observacion?: string;
    actorId: string;
    files: Express.Multer.File[];
    evidenciasCaptura?: unknown;
  }) {
    const current = await this.prisma.compromisoConjunto.findUnique({
      where: { id: input.id },
      include: {
        conjunto: { select: { nit: true, nombre: true, direccion: true, latitud: true, longitud: true } },
      },
    });
    if (!current) throw makeHttpError(404, "PQRS no encontrada");
    if (current.completado || current.estado === "CERRADO") {
      throw makeHttpError(409, "La PQRS está cerrada y no admite más actualizaciones");
    }

    const observacion = input.observacion?.trim() || null;
    if (observacion && observacion.length > 2000) {
      throw makeHttpError(400, "La observación no puede superar 2000 caracteres");
    }

    const actor = await this.prisma.usuario.findUnique({
      where: { id: input.actorId },
      select: { nombre: true, rol: true },
    });
    const fecha = new Date();
    let evidencias: string[] = [];
    try {
      evidencias = await subirEvidenciasConMarca(
        { files: input.files, capturas: input.evidenciasCaptura, conjunto: current.conjunto },
        (file, indice) => uploadEvidenciaToDrive({
          filePath: file.path,
          fileName: buildEvidenciaFileName({
            subidoPor: actor?.nombre ?? input.actorId,
            rol: actor?.rol ?? "USUARIO",
            fecha,
            originalName: file.originalname,
            indice,
          }),
          mimeType: file.mimetype,
          conjuntoNit: current.conjunto.nit,
          conjuntoNombre: current.conjunto.nombre,
          fecha,
          subcarpeta: "PQRS",
        }),
      );
    } finally {
      for (const file of input.files) {
        try { if (fs.existsSync(file.path)) fs.unlinkSync(file.path); } catch { /* best effort */ }
      }
    }

    const cierre = input.estado === "CERRADO";
    const updated = await this.prisma.$transaction(async (tx) => {
      const changed = await tx.compromisoConjunto.updateMany({
        where: { id: input.id, completado: false, estado: { not: "CERRADO" } },
        data: {
          estado: input.estado,
          completado: cierre,
          ...(cierre ? { cerradaEn: fecha } : {}),
        },
      });
      if (changed.count !== 1) throw makeHttpError(409, "La PQRS se cerró antes de guardar el avance");
      await tx.compromisoActualizacion.create({
        data: {
          compromisoId: input.id,
          estado: input.estado,
          observacion,
          evidencias,
          actorId: input.actorId,
          creadaEn: fecha,
        },
      });
      return tx.compromisoConjunto.findUniqueOrThrow({
        where: { id: input.id },
        select: { ...selectCompromiso, conjunto: { select: { nit: true, nombre: true } } },
      });
    });

    try {
      await new NotificacionService(this.prisma).notificarActualizacionPqrs({
        compromisoId: input.id,
        conjuntoId: current.conjuntoId,
        titulo: current.titulo,
        estado: input.estado,
        actorId: input.actorId,
      });
    } catch (error) {
      console.error("No se pudo notificar el avance de PQRS:", error);
    }
    return this.serializeCompromiso(updated as CompromisoRow);
  }

  async eliminar(id: number) {
    const current = await this.prisma.compromisoConjunto.findUnique({ where: { id } });
    if (!current) throw makeHttpError(404, "Compromiso no encontrado");
    if (current.completado || current.estado === "CERRADO") {
      throw makeHttpError(409, "Las PQRS cerradas se conservan en completados");
    }
    await this.prisma.compromisoConjunto.delete({ where: { id } });
    return { ok: true };
  }
}
