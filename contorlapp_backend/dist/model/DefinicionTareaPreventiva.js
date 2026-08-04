"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.definicionPreventivaPublicSelect = exports.GenerarCronogramaMensualDTO = exports.ReemplazarConExcluidaDTO = exports.AgendarExcluidaDTO = exports.SugerirHuecosExcluidaDTO = exports.ListarExcluidasBorradorDTO = exports.PeriodoBorradorDTO = exports.GenerarCronogramaDTO = exports.FiltroDefinicionPreventivaDTO = exports.EliminarPreventivasLoteDTO = exports.EditarDefinicionPreventivaDTO = exports.CrearDefinicionPreventivaDTO = void 0;
exports.toDefinicionTareaPreventivaPublica = toDefinicionTareaPreventivaPublica;
exports.calcularMinutosEstimados = calcularMinutosEstimados;
// src/model/DefinicionTareaPreventiva.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
const UsuarioIdDTO = zod_1.z
    .union([zod_1.z.string().trim().min(1), zod_1.z.number().int().positive()])
    .transform((value) => String(value));
/* ===================== DTOs ===================== */
const InsumoPlanItemDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    consumoPorUnidad: zod_1.z.coerce.number().min(0),
});
/**
 * La definicion preventiva declara la NECESIDAD de maquinaria (que tipo y cuantas),
 * no una maquina concreta. La maquina real se asigna despues desde el cronograma
 * de maquinaria. `maquinariaId` se sigue aceptando de entrada como sugerencia,
 * para no romper clientes antiguos.
 */
/**
 * `nullish` en los ids no es cosmético: el controller parsea el DTO y el servicio
 * lo vuelve a parsear, así que el esquema tiene que aceptar su propia salida
 * (donde `maquinariaSugeridaId` ya es `null`).
 */
const MaquinariaPlanItemDTO = zod_1.z
    .object({
    tipo: zod_1.z.nativeEnum(client_1.TipoMaquinaria),
    cantidad: zod_1.z.coerce.number().int().min(1).default(1),
    maquinariaSugeridaId: zod_1.z.number().int().positive().nullish(),
    maquinariaId: zod_1.z.number().int().positive().nullish(),
})
    .transform(({ tipo, cantidad, maquinariaSugeridaId, maquinariaId }) => ({
    tipo,
    cantidad,
    maquinariaSugeridaId: maquinariaSugeridaId ?? maquinariaId ?? null,
}));
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
    fechasProgramadasJson: zod_1.z.array(zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/)).optional(),
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
    responsableSugeridoId: UsuarioIdDTO.optional(),
    operariosIds: zod_1.z.array(UsuarioIdDTO).optional(),
    supervisorId: UsuarioIdDTO.optional(),
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
    fechasProgramadasJson: zod_1.z
        .array(zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/))
        .optional()
        .nullable(),
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
    responsableSugeridoId: UsuarioIdDTO.optional().nullable(),
    operariosIds: zod_1.z.array(UsuarioIdDTO).optional().nullable(),
    supervisorId: UsuarioIdDTO.optional().nullable(),
    activo: zod_1.z.boolean().optional(),
});
/** Borrado en lote de definiciones preventivas */
exports.EliminarPreventivasLoteDTO = zod_1.z.object({
    ids: zod_1.z.array(zod_1.z.number().int().positive()).min(1).max(200),
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
const ConfirmacionReemplazoDTO = zod_1.z.object({
    defId: zod_1.z.number().int().positive(),
    fecha: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    prioridadSolicitante: zod_1.z.number().int().min(1).max(3),
    prioridadObjetivo: zod_1.z.number().int().min(2).max(3),
    aceptar: zod_1.z.boolean(),
    candidataId: zod_1.z.number().int().positive().optional(),
});
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
    confirmacionesReemplazo: zod_1.z.array(ConfirmacionReemplazoDTO).optional(),
    /**
     * RESET  = se descarta el borrador previo y se planifica todo de cero (default, contrato antiguo).
     * CONSERVAR = se respeta el borrador ya cuadrado y solo se planifican las
     *             definiciones que aun no tienen tarea en el periodo.
     */
    modo: zod_1.z.enum(["RESET", "CONSERVAR"]).optional().default("RESET"),
});
exports.PeriodoBorradorDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    anio: zod_1.z.coerce.number().int().min(2000).max(2100),
    mes: zod_1.z.coerce.number().int().min(1).max(12),
});
exports.ListarExcluidasBorradorDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    anio: zod_1.z.coerce.number().int().min(2000).max(2100),
    mes: zod_1.z.coerce.number().int().min(1).max(12),
    fecha: zod_1.z.coerce.date().optional(),
});
exports.SugerirHuecosExcluidaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    excluidaId: zod_1.z.coerce.number().int().positive(),
    fechaPreferida: zod_1.z.coerce.date().optional(),
    maxOpciones: zod_1.z.coerce.number().int().min(1).max(20).optional(),
});
exports.AgendarExcluidaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    excluidaId: zod_1.z.coerce.number().int().positive(),
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
    bloques: zod_1.z
        .array(zod_1.z.object({
        fechaInicio: zod_1.z.coerce.date(),
        fechaFin: zod_1.z.coerce.date(),
    }))
        .min(1)
        .optional(),
}).refine((d) => ((d.fechaInicio == null && d.fechaFin == null) ||
    (d.fechaInicio != null && d.fechaFin != null && d.fechaFin >= d.fechaInicio)) &&
    (d.bloques == null || d.bloques.every((b) => b.fechaFin >= b.fechaInicio)) &&
    !(d.bloques != null &&
        d.bloques.length > 0 &&
        (d.fechaInicio != null || d.fechaFin != null)), {
    message: "Envia fechaInicio/fechaFin o bloques validos, pero no ambos a la vez.",
});
exports.ReemplazarConExcluidaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    tareaId: zod_1.z.coerce.number().int().positive(),
    excluidaId: zod_1.z.coerce.number().int().positive(),
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
    fechasProgramadasJson: true,
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
