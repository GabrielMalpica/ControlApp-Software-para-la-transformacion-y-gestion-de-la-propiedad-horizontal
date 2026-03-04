"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.tareaPublicSelect = exports.RegistrarInsumosUsadosDTO = exports.AgregarEvidenciasDTO = exports.RechazarTareaEmpresaDTO = exports.AprobarTareaEmpresaDTO = exports.VerificarTareaDTO = exports.FinalizarTareaDTO = exports.IniciarTareaDTO = exports.FiltroTareaDTO = exports.EditarTareaDTO = exports.CrearTareaDTO = exports.MaquinariaPlanItemDTO = exports.InsumoPlanItemDTO = exports.InsumoUsadoItemDTO = void 0;
exports.toTareaPublica = toTareaPublica;
// src/models/tarea.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
exports.InsumoUsadoItemDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.coerce.number().positive(),
});
/** Planificación (JSON) */
exports.InsumoPlanItemDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    consumoPorUnidad: zod_1.z.coerce.number().min(0),
});
exports.MaquinariaPlanItemDTO = zod_1.z.object({
    maquinariaId: zod_1.z.number().int().positive().optional(),
    tipo: zod_1.z.string().min(1).optional(),
    cantidad: zod_1.z.coerce.number().min(0).optional(),
});
/** Crear tarea (correctiva o preventiva ya instanciada) */
exports.CrearTareaDTO = zod_1.z
    .object({
    descripcion: zod_1.z.string().min(3),
    fechaInicio: zod_1.z.coerce.date(),
    // ✅ opcional (puede venir o no)
    fechaFin: zod_1.z.coerce.date().optional(),
    // ✅ opcional (puede venir o no)
    duracionMinutos: zod_1.z.coerce.number().int().min(1).optional(),
    duracionHoras: zod_1.z.coerce.number().positive().optional(),
    prioridad: zod_1.z.coerce.number().int().min(1).max(3).optional(),
    tipo: zod_1.z.nativeEnum(client_1.TipoTarea).optional(),
    estado: zod_1.z.nativeEnum(client_1.EstadoTarea).optional(),
    frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia).optional(),
    evidencias: zod_1.z.array(zod_1.z.string()).optional().default([]),
    insumosUsados: zod_1.z.any().optional(),
    observaciones: zod_1.z.string().optional(),
    observacionesRechazo: zod_1.z.string().optional(),
    ubicacionId: zod_1.z.coerce.number().int().positive(),
    elementoId: zod_1.z.coerce.number().int().positive(),
    conjuntoId: zod_1.z.string().min(1).nullable().optional(),
    supervisorId: zod_1.z.string().min(1).nullable().optional(),
    operariosIds: zod_1.z.array(zod_1.z.string().min(1)).optional(),
    operarioId: zod_1.z.string().min(1).optional(),
    // ✅ NUEVO: asignación de maquinaria/herramientas en creación
    maquinariaIds: zod_1.z
        .array(zod_1.z.coerce.number().int().positive())
        .optional()
        .default([]),
    herramientas: zod_1.z
        .array(zod_1.z.object({
        herramientaId: zod_1.z.coerce.number().int().positive(),
        cantidad: zod_1.z.coerce.number().positive().default(1),
    }))
        .optional()
        .default([]),
})
    .superRefine((d, ctx) => {
    // ✅ debe existir al menos uno: fechaFin o duración
    const hasDur = (d.duracionMinutos != null && d.duracionMinutos >= 1) ||
        (d.duracionHoras != null && d.duracionHoras > 0);
    if (!d.fechaFin && !hasDur) {
        ctx.addIssue({
            code: zod_1.z.ZodIssueCode.custom,
            message: "Debes enviar fechaFin o duracionMinutos o duracionHoras.",
            path: ["fechaFin"],
        });
        return;
    }
    // ✅ si vienen ambos (fechaFin y duración), validamos coherencia mínima
    if (d.fechaFin && hasDur) {
        const durMin = d.duracionMinutos ?? Math.round((d.duracionHoras ?? 0) * 60);
        const diffMin = Math.round((d.fechaFin.getTime() - d.fechaInicio.getTime()) / 60000);
        // tolerancia 1 min
        if (Math.abs(diffMin - durMin) > 1) {
            ctx.addIssue({
                code: zod_1.z.ZodIssueCode.custom,
                message: "fechaFin no coincide con la duración enviada (duracionMinutos/duracionHoras).",
                path: ["fechaFin"],
            });
        }
    }
    // ✅ fechaFin no puede ser antes de inicio
    if (d.fechaFin && d.fechaFin.getTime() <= d.fechaInicio.getTime()) {
        ctx.addIssue({
            code: zod_1.z.ZodIssueCode.custom,
            message: "fechaFin debe ser posterior a fechaInicio.",
            path: ["fechaFin"],
        });
    }
});
/** Editar tarea (parcial) */
exports.EditarTareaDTO = zod_1.z.object({
    descripcion: zod_1.z.string().min(3).optional(),
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
    duracionMinutos: zod_1.z.number().int().min(1).optional(),
    duracionHoras: zod_1.z.coerce.number().positive().optional(),
    prioridad: zod_1.z.number().int().min(1).max(3).optional(),
    tipo: zod_1.z.nativeEnum(client_1.TipoTarea).optional(),
    estado: zod_1.z.nativeEnum(client_1.EstadoTarea).optional(),
    frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia).optional(),
    evidencias: zod_1.z.array(zod_1.z.string()).optional(),
    insumosUsados: zod_1.z.any().optional(),
    observaciones: zod_1.z.string().nullable().optional(),
    observacionesRechazo: zod_1.z.string().nullable().optional(),
    ubicacionId: zod_1.z.number().int().positive().optional(),
    elementoId: zod_1.z.number().int().positive().optional(),
    conjuntoId: zod_1.z.string().min(1).nullable().optional(),
    supervisorId: zod_1.z.string().min(1).nullable().optional(),
    operariosIds: zod_1.z.array(zod_1.z.string().min(1)).optional(),
    operarioId: zod_1.z.string().min(1).optional(),
});
/** Filtros para listar/consultar tareas */
exports.FiltroTareaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    supervisorId: zod_1.z.string().optional(),
    operarioId: zod_1.z.string().optional(),
    ubicacionId: zod_1.z.number().int().optional(),
    elementoId: zod_1.z.number().int().optional(),
    tipo: zod_1.z.nativeEnum(client_1.TipoTarea).optional(),
    frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia).optional(),
    estado: zod_1.z.nativeEnum(client_1.EstadoTarea).optional(),
    borrador: zod_1.z.boolean().optional(),
    periodoAnio: zod_1.z.number().int().optional(),
    periodoMes: zod_1.z.number().int().min(1).max(12).optional(),
    grupoPlanId: zod_1.z.string().uuid().optional(),
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
});
/** Iniciar tarea (track operario y timestamp real) */
exports.IniciarTareaDTO = zod_1.z.object({
    fechaIniciarTarea: zod_1.z.coerce.date().default(() => new Date()),
});
/** Finalizar tarea (track operario y timestamp real) */
exports.FinalizarTareaDTO = zod_1.z.object({
    fechaFinalizarTarea: zod_1.z.coerce.date().default(() => new Date()),
});
/** Verificar tarea por supervisor/empresa */
exports.VerificarTareaDTO = zod_1.z.object({
    supervisorId: zod_1.z.number().int().optional(), // si aplica verificación por supervisor
    fechaVerificacion: zod_1.z.coerce.date().default(() => new Date()),
});
/** Aprobar tarea por empresa (usa relación empresaAprobada) */
exports.AprobarTareaEmpresaDTO = zod_1.z.object({
    empresaAprobadaId: zod_1.z.number().int().positive(),
});
/** Rechazar tarea por empresa (usa relación empresaRechazada) */
exports.RechazarTareaEmpresaDTO = zod_1.z.object({
    empresaRechazadaId: zod_1.z.number().int().positive(),
    observacionesRechazo: zod_1.z.string().min(3).optional(),
});
/** Agregar evidencias (anexos) */
exports.AgregarEvidenciasDTO = zod_1.z.object({
    evidencias: zod_1.z.array(zod_1.z.string()).min(1),
});
/** Registrar insumos usados (JSON real) */
exports.RegistrarInsumosUsadosDTO = zod_1.z.object({
    insumosUsados: zod_1.z.array(exports.InsumoUsadoItemDTO).min(1),
});
/* ===================== SELECT BASE PARA PRISMA ===================== */
exports.tareaPublicSelect = {
    id: true,
    descripcion: true,
    fechaInicio: true,
    fechaFin: true,
    duracionMinutos: true,
    prioridad: true,
    estado: true,
    evidencias: true,
    insumosUsados: true,
    observaciones: true,
    observacionesRechazo: true,
    tipo: true,
    frecuencia: true,
    conjuntoId: true,
    supervisorId: true,
    ubicacionId: true,
    elementoId: true,
};
function toTareaPublica(row) {
    return row;
}
