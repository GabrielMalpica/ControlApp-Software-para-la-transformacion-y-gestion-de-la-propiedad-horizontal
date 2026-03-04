"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.definicionPreventivaPublicSelect = exports.GenerarCronogramaMensualDTO = exports.GenerarCronogramaDTO = exports.FiltroDefinicionPreventivaDTO = exports.EditarDefinicionPreventivaDTO = exports.CrearDefinicionPreventivaDTO = void 0;
exports.toDefinicionTareaPreventivaPublica = toDefinicionTareaPreventivaPublica;
exports.calcularMinutosEstimados = calcularMinutosEstimados;
// src/model/DefinicionTareaPreventiva.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
/* ===================== DTOs ===================== */
const InsumoPlanItemDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    consumoPorUnidad: zod_1.z.coerce.number().min(0),
});
const MaquinariaPlanItemDTO = zod_1.z.object({
    maquinariaId: zod_1.z.number().int().positive().optional(),
    tipo: zod_1.z.string().min(1).optional(),
    cantidad: zod_1.z.coerce.number().min(0).optional(),
});
const HerramientaPlanItemDTO = zod_1.z.object({
    herramientaId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.coerce.number().min(0).optional(),
});
/** Crear definición (molde) de tarea preventiva */
exports.CrearDefinicionPreventivaDTO = zod_1.z
    .object({
    conjuntoId: zod_1.z.string().min(3),
    ubicacionId: zod_1.z.number().int().positive(),
    elementoId: zod_1.z.number().int().positive(),
    descripcion: zod_1.z.string().min(3),
    frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia),
    prioridad: zod_1.z.number().int().min(1).max(3).default(2),
    // programación específica
    diaSemanaProgramado: zod_1.z.nativeEnum(client_1.DiaSemana).optional().nullable(),
    diaMesProgramado: zod_1.z.number().int().min(1).max(31).optional().nullable(),
    // A) rendimiento/área
    unidadCalculo: zod_1.z.nativeEnum(client_1.UnidadCalculo).optional().nullable(),
    areaNumerica: zod_1.z.coerce.number().min(0).optional(),
    rendimientoBase: zod_1.z.coerce.number().min(0).optional(),
    // 👇 sin enums nuevos: literal union
    rendimientoTiempoBase: zod_1.z.enum(["POR_MINUTO", "POR_HORA"]).optional(),
    // B) duración fija
    duracionMinutosFija: zod_1.z.number().int().min(1).optional(),
    diasParaCompletar: zod_1.z.number().int().min(1).max(31).optional().nullable(),
    // compat temporal
    duracionHorasFija: zod_1.z.coerce.number().positive().optional(),
    insumoPrincipalId: zod_1.z.number().int().positive().optional(),
    consumoPrincipalPorUnidad: zod_1.z.coerce.number().min(0).optional(),
    insumosPlanJson: zod_1.z.array(InsumoPlanItemDTO).optional(),
    maquinariaPlanJson: zod_1.z.array(MaquinariaPlanItemDTO).optional(),
    herramientasPlanJson: zod_1.z.array(HerramientaPlanItemDTO).optional(),
    responsableSugeridoId: zod_1.z.number().int().positive().optional(),
    operariosIds: zod_1.z.array(zod_1.z.number().int().positive()).optional(),
    supervisorId: zod_1.z.number().int().positive().optional(),
    activo: zod_1.z.boolean().default(true),
})
    .refine((d) => {
    const tieneRendimiento = !!d.unidadCalculo &&
        d.areaNumerica !== undefined &&
        d.rendimientoBase !== undefined;
    const tieneDuracionMin = d.duracionMinutosFija !== undefined;
    const tieneDuracionHoras = d.duracionHorasFija !== undefined;
    return tieneRendimiento || tieneDuracionMin || tieneDuracionHoras;
}, {
    message: "Debe indicar (unidadCalculo + areaNumerica + rendimientoBase) o duracionMinutosFija (o duracionHorasFija compat).",
});
/** Editar definición preventiva (todo opcional) */
exports.EditarDefinicionPreventivaDTO = zod_1.z.object({
    ubicacionId: zod_1.z.number().int().positive().optional(),
    elementoId: zod_1.z.number().int().positive().optional(),
    descripcion: zod_1.z.string().min(3).optional(),
    frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia).optional(),
    prioridad: zod_1.z.number().int().min(1).max(3).optional(),
    diaSemanaProgramado: zod_1.z.nativeEnum(client_1.DiaSemana).optional().nullable(),
    diaMesProgramado: zod_1.z.number().int().min(1).max(31).optional().nullable(),
    unidadCalculo: zod_1.z.nativeEnum(client_1.UnidadCalculo).optional().nullable(),
    areaNumerica: zod_1.z.coerce.number().min(0).optional().nullable(),
    rendimientoBase: zod_1.z.coerce.number().min(0).optional().nullable(),
    rendimientoTiempoBase: zod_1.z
        .enum(["POR_MINUTO", "POR_HORA"])
        .optional()
        .nullable(),
    duracionMinutosFija: zod_1.z.number().int().min(1).optional().nullable(),
    diasParaCompletar: zod_1.z.number().int().min(1).max(31).optional().nullable(),
    duracionHorasFija: zod_1.z.coerce.number().positive().optional().nullable(),
    insumoPrincipalId: zod_1.z.number().int().positive().optional().nullable(),
    consumoPrincipalPorUnidad: zod_1.z.coerce.number().min(0).optional().nullable(),
    insumosPlanJson: zod_1.z.array(InsumoPlanItemDTO).optional().nullable(),
    maquinariaPlanJson: zod_1.z.array(MaquinariaPlanItemDTO).optional().nullable(),
    herramientasPlanJson: zod_1.z.array(HerramientaPlanItemDTO).optional().nullable(),
    responsableSugeridoId: zod_1.z.number().int().positive().optional().nullable(),
    operariosIds: zod_1.z.array(zod_1.z.number().int().positive()).optional().nullable(),
    supervisorId: zod_1.z.number().int().positive().optional().nullable(),
    activo: zod_1.z.boolean().optional(),
});
/** Filtro para listar/consultar definiciones */
exports.FiltroDefinicionPreventivaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    ubicacionId: zod_1.z.number().int().positive().optional(),
    elementoId: zod_1.z.number().int().positive().optional(),
    frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia).optional(),
    activo: zod_1.z.boolean().optional(),
});
/** DTO para generar el cronograma/borrador mensual */
exports.GenerarCronogramaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    anio: zod_1.z.coerce.number().int().min(2000).max(2100),
    mes: zod_1.z.coerce.number().int().min(1).max(12),
    tamanoBloqueHoras: zod_1.z.coerce.number().positive().max(12).optional(),
    tamanoBloqueMinutos: zod_1.z.coerce
        .number()
        .int()
        .min(1)
        .max(12 * 60)
        .optional(),
});
// Alias opcional por compatibilidad
exports.GenerarCronogramaMensualDTO = exports.GenerarCronogramaDTO;
/* ===================== SELECT PARA PRISMA ===================== */
exports.definicionPreventivaPublicSelect = {
    id: true,
    conjuntoId: true,
    ubicacionId: true,
    elementoId: true,
    descripcion: true,
    frecuencia: true,
    prioridad: true,
    diaSemanaProgramado: true,
    diaMesProgramado: true,
    unidadCalculo: true,
    areaNumerica: true,
    rendimientoBase: true,
    rendimientoTiempoBase: true,
    duracionMinutosFija: true,
    diasParaCompletar: true,
    insumoPrincipalId: true,
    consumoPrincipalPorUnidad: true,
    insumosPlanJson: true,
    maquinariaPlanJson: true,
    herramientasPlanJson: true,
    activo: true,
    creadoEn: true,
    actualizadoEn: true,
};
/** Helper para castear el resultado Prisma al tipo público */
function toDefinicionTareaPreventivaPublica(row) {
    return row;
}
/* ===================== Utilidad ===================== */
/**
 * Calcula minutos estimados dado área y rendimiento.
 */
function calcularMinutosEstimados(params) {
    const { cantidad, rendimiento, duracionMinutosFija, rendimientoTiempoBase = "POR_HORA", } = params;
    if (duracionMinutosFija != null)
        return Math.max(1, Math.round(duracionMinutosFija));
    if (cantidad != null && rendimiento != null && rendimiento > 0) {
        if (rendimientoTiempoBase === "POR_MINUTO") {
            return Math.max(1, Math.round(cantidad / rendimiento));
        }
        // POR_HORA
        const horas = cantidad / rendimiento;
        return Math.max(1, Math.round(horas * 60));
    }
    return null;
}
