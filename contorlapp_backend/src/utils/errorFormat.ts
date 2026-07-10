export type ConflictoMaquinaria = {
  maquinariaId: number;
  maquinaNombre?: string | null;
  tareaSolicitada: {
    tareaId: number;
    descripcion: string;
    conjuntoId: string | null;
    conjuntoNombre?: string | null;
    estado?: string | null;
    usoInicio: string;
    usoFin: string;
    reservaInicio: string;
    reservaFin: string;
    entrega: string;
    recogida: string;
  };
  ocupadoPor: {
    usoId: number;
    tareaId: number;
    conjuntoId: string | null;
    conjuntoNombre?: string | null;
    estado?: string | null;
    descripcion: string | null;
    fuente: string;
    usoInicio: string;
    usoFin: string;
    reservaInicio: string;
    reservaFin: string;
  };
  tipoSolape: "USO_REAL" | "RESERVA_LOGISTICA" | "BORRADOR_INTERNO";
  motivo: string;
  sugerencia?: {
    libreDesde: string | null;
    inicioUsoSugerido: string | null;
    finUsoSugerido: string | null;
    nota?: string | null;
  } | null;
};

export function buildMaquinariaNoDisponibleError(params: {
  maquinariaId: number;
  conflictos: ConflictoMaquinaria[];
  maquinaNombre?: string;
}) {
  const { maquinariaId, conflictos, maquinaNombre } = params;

  const titulo = maquinaNombre
    ? `La máquina "${maquinaNombre}" no está disponible`
    : `La maquinaria #${maquinariaId} no está disponible`;

  // ejemplos legibles (máx 4)
  const ejemplos = conflictos.slice(0, 4).map((c) => {
    const desc = c.ocupadoPor.descripcion ?? "Tarea sin descripcion";
    return {
      tareaSolicitada: {
        tareaId: c.tareaSolicitada.tareaId,
        descripcion: c.tareaSolicitada.descripcion,
      },
      entrega: c.tareaSolicitada.entrega,
      recogida: c.tareaSolicitada.recogida,
      tipoSolape: c.tipoSolape,
      ocupadaPor: {
        conjuntoId: c.ocupadoPor.conjuntoId,
        conjuntoNombre: c.ocupadoPor.conjuntoNombre ?? null,
        tareaId: c.ocupadoPor.tareaId,
        descripcion: desc,
        estado: c.ocupadoPor.estado ?? null,
        desde: c.ocupadoPor.reservaInicio,
        hasta: c.ocupadoPor.reservaFin,
      },
      motivo: c.motivo,
      sugerencia: c.sugerencia ?? null,
    };
  });

  const primerConflicto = conflictos[0];
  const tareaSolicitadaLabel = primerConflicto
    ? `La tarea "${primerConflicto.tareaSolicitada.descripcion.trim()}" (#${primerConflicto.tareaSolicitada.tareaId})`
    : "Una tarea del cronograma";

  const tareaOcupanteLabel = primerConflicto
    ? `la tarea "${(primerConflicto.ocupadoPor.descripcion ?? "Tarea sin descripcion").trim()}" (#${primerConflicto.ocupadoPor.tareaId})`
    : "otra tarea";

  const message =
    `${titulo}. ${tareaSolicitadaLabel} tiene agenda cruzada con ${tareaOcupanteLabel}. ` +
    `Se detectaron ${conflictos.length} conflicto(s) de reserva/uso. Revisa el detalle para ajustar la maquina o reprogramar la tarea.`;

  const userHint =
    "Tip: revisa la tarea reportada, abre la agenda de maquinaria y compara uso real vs ventana de reserva antes de mover o publicar.";

  return {
    status: 409,
    ok: false as const,
    title: titulo,
    reason: "MAQUINARIA_NO_DISPONIBLE" as const,
    message,
    userHint,
    resumen: {
      maquinariaId,
      maquinaNombre: maquinaNombre ?? null,
      conflictosCount: conflictos.length,
      ejemplos,
    },
    conflictos,
  };
}
