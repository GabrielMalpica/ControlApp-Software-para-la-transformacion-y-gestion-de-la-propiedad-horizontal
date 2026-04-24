"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildMaquinariaNoDisponibleError = buildMaquinariaNoDisponibleError;
function buildMaquinariaNoDisponibleError(params) {
    const { maquinariaId, conflictos, maquinaNombre } = params;
    const titulo = maquinaNombre
        ? `La máquina "${maquinaNombre}" no está disponible`
        : `La maquinaria #${maquinariaId} no está disponible`;
    // ejemplos legibles (máx 4)
    const ejemplos = conflictos.slice(0, 4).map((c) => {
        const desc = c.ocupadoPor.descripcion ?? "Tarea sin descripción";
        return {
            tareaSolicitada: {
                tareaId: c.tareaId,
                descripcion: c.tareaDescripcion ?? "Tarea sin descripción",
            },
            entrega: c.rangoSolicitado.entrega,
            recogida: c.rangoSolicitado.recogida,
            ocupadaPor: {
                conjuntoId: c.ocupadoPor.conjuntoId,
                tareaId: c.ocupadoPor.tareaId,
                descripcion: desc,
                desde: c.ocupadoPor.ini,
                hasta: c.ocupadoPor.fin,
            },
        };
    });
    const primerConflicto = conflictos[0];
    const tareaSolicitadaLabel = primerConflicto
        ? `La tarea "${(primerConflicto.tareaDescripcion ?? "Tarea sin descripción").trim()}" (#${primerConflicto.tareaId})`
        : "Una tarea del cronograma";
    const tareaOcupanteLabel = primerConflicto
        ? `la tarea "${(primerConflicto.ocupadoPor.descripcion ?? "Tarea sin descripción").trim()}" (#${primerConflicto.ocupadoPor.tareaId})`
        : "otra tarea";
    const message = `${titulo}. ${tareaSolicitadaLabel} tiene agenda cruzada con ${tareaOcupanteLabel}. ` +
        `Se detectaron ${conflictos.length} conflicto(s) de reserva/uso. Revisa esa tarea antes de publicar.`;
    const userHint = "Tip: revisa la tarea reportada, abre la agenda de maquinaria y ajusta fechas, bloque o máquina asignada.";
    return {
        ok: false,
        reason: "MAQUINARIA_NO_DISPONIBLE",
        message,
        userHint,
        resumen: {
            maquinariaId,
            conflictosCount: conflictos.length,
            ejemplos,
        },
        // 👇 esto lo dejas para debug/soporte (frontend puede ocultarlo)
        conflictos,
    };
}
