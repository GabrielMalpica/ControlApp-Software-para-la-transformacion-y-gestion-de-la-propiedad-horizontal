// src/model/Auditoria.ts
import { z } from "zod";

/**
 * Modulos y acciones se manejan como texto libre (no como enums de Prisma) para que
 * auditar un modulo nuevo no obligue a una migracion de base de datos.
 */
export const ModuloAuditoria = {
  TAREA: "TAREA",
  CRONOGRAMA: "CRONOGRAMA",
  PREVENTIVA: "PREVENTIVA",
  EXCLUIDA: "EXCLUIDA",
} as const;

export type ModuloAuditoria = (typeof ModuloAuditoria)[keyof typeof ModuloAuditoria];

export const EntidadAuditoria = {
  TAREA: "Tarea",
  DEFINICION_PREVENTIVA: "DefinicionTareaPreventiva",
  EXCLUIDA_BORRADOR: "PreventivaExcluidaBorrador",
  CRONOGRAMA_PERIODO: "CronogramaPeriodo",
} as const;

export type EntidadAuditoria = (typeof EntidadAuditoria)[keyof typeof EntidadAuditoria];

export const AccionAuditoria = {
  CREAR: "CREAR",
  EDITAR: "EDITAR",
  ELIMINAR: "ELIMINAR",
  REEMPLAZAR: "REEMPLAZAR",
  REPROGRAMAR: "REPROGRAMAR",
  DIVIDIR: "DIVIDIR",
  REORDENAR: "REORDENAR",
  GENERAR_BORRADOR: "GENERAR_BORRADOR",
  PUBLICAR: "PUBLICAR",
  ELIMINAR_CRONOGRAMA: "ELIMINAR_CRONOGRAMA",
  REASIGNAR_OPERARIO: "REASIGNAR_OPERARIO",
  AGENDAR_EXCLUIDA: "AGENDAR_EXCLUIDA",
  DESCARTAR_EXCLUIDA: "DESCARTAR_EXCLUIDA",
  PROGRAMAR_CORRECTIVA: "PROGRAMAR_CORRECTIVA",
  ASIGNAR_MAQUINARIA: "ASIGNAR_MAQUINARIA",
  LIBERAR_MAQUINARIA: "LIBERAR_MAQUINARIA",
} as const;

export type AccionAuditoria = (typeof AccionAuditoria)[keyof typeof AccionAuditoria];

export const OrigenAuditoria = {
  USUARIO: "USUARIO",
  SCHEDULER: "SCHEDULER",
  CRON: "CRON",
} as const;

export type OrigenAuditoria = (typeof OrigenAuditoria)[keyof typeof OrigenAuditoria];

/** Quien ejecuta la accion. Todos los campos son opcionales: los jobs automaticos no tienen actor. */
export type ActorAuditoria = {
  id?: string | null;
  rol?: string | null;
  nombre?: string | null;
};

export type RegistroAuditoria = {
  modulo: string;
  entidad: string;
  entidadId: string | number;
  accion: string;

  conjuntoId?: string | null;
  empresaId?: number | null;

  actor?: ActorAuditoria | null;
  origen?: string;

  descripcion?: string | null;
  datosAntes?: unknown;
  datosDespues?: unknown;
  metadataJson?: unknown;

  periodoAnio?: number | null;
  periodoMes?: number | null;
};

/** Evento serializado para el cliente (el id es BigInt en Prisma y no viaja en JSON). */
export type AuditoriaEventoPublico = {
  id: string;
  modulo: string;
  entidad: string;
  entidadId: string;
  accion: string;
  conjuntoId: string | null;
  actorId: string | null;
  actorRol: string | null;
  actorNombre: string | null;
  origen: string;
  descripcion: string | null;
  metadataJson: unknown;
  periodoAnio: number | null;
  periodoMes: number | null;
  creadoEn: Date;
};

export type TrazabilidadEntidad = {
  entidadId: string;
  creadoPor: ActorAuditoria | null;
  creadoEn: Date | null;
  ultimaModificacion:
    | {
        actor: ActorAuditoria | null;
        accion: string;
        descripcion: string | null;
        fecha: Date;
      }
    | null;
  totalEventos: number;
};

export const FiltroAuditoriaDTO = z.object({
  modulo: z.string().min(1).optional(),
  entidad: z.string().min(1).optional(),
  entidadId: z.coerce.string().min(1).optional(),
  accion: z.string().min(1).optional(),
  actorId: z.string().min(1).optional(),
  anio: z.coerce.number().int().min(2000).max(2100).optional(),
  mes: z.coerce.number().int().min(1).max(12).optional(),
  limit: z.coerce.number().int().min(1).max(500).optional(),
});

export const TrazabilidadAuditoriaDTO = z.object({
  modulo: z.string().min(1).optional(),
  entidad: z.string().min(1),
  entidadIds: z.array(z.coerce.string().min(1)).min(1).max(1000),
});

export const InformeAuditoriaDTO = z.object({
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
  modulo: z.string().min(1).optional(),
});
