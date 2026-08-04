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

/* ------------------------------------------------------------------ */
/* Validacion: mensajes de usuario, nunca el volcado interno de Zod    */
/* ------------------------------------------------------------------ */

/**
 * Traduce un issue de Zod a un mensaje que puede leer el usuario final.
 *
 * Los mensajes por defecto de Zod ("Invalid input: expected number, received
 * null") describen la excepcion tecnica y no deben salir al cliente. Los
 * mensajes propios (los que escribimos en `.refine()` / `{ message }`) si se
 * conservan, porque ya estan redactados para el usuario.
 */
export function mensajeValidacionAmigable(issue: {
  code?: string;
  message?: string;
  minimum?: unknown;
  maximum?: unknown;
}): string {
  // `custom` y `invalid_union` con mensaje propio vienen redactados por nosotros.
  if (issue.code === "custom" && issue.message) return issue.message;

  switch (issue.code) {
    case "invalid_type":
      return "Falta este dato o tiene un formato que no corresponde.";
    case "too_small":
      return issue.minimum != null
        ? `El valor es demasiado corto o pequeño (mínimo ${issue.minimum}).`
        : "El valor es demasiado corto o pequeño.";
    case "too_big":
      return issue.maximum != null
        ? `El valor es demasiado largo o grande (máximo ${issue.maximum}).`
        : "El valor es demasiado largo o grande.";
    case "invalid_value":
    case "invalid_enum_value":
      return "El valor seleccionado no es una opción válida.";
    case "invalid_format":
    case "invalid_string":
      return "El formato de este dato no es válido.";
    case "not_multiple_of":
      return "El valor no es un múltiplo permitido.";
    case "unrecognized_keys":
      return "Se enviaron datos que no corresponden a este formulario.";
    default:
      return "Revisa este dato.";
  }
}
