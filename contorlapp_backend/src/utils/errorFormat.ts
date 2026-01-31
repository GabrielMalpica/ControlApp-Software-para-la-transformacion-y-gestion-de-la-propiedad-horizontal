type ConflictoMaquinaria = {
  tareaId: number;
  maquinariaId: number;
  rangoSolicitado: { entrega: string; recogida: string; ini: string; fin: string };
  ocupadoPor: {
    usoId: number;
    tareaId: number;
    conjuntoId: string;
    descripcion: string | null;
    ini: string;
    fin: string;
  };
};

export function buildMaquinariaNoDisponibleError(params: {
  maquinariaId: number;
  conflictos: ConflictoMaquinaria[];
  // opcional para personalizar:
  maquinaNombre?: string;
}) {
  const { maquinariaId, conflictos, maquinaNombre } = params;

  const titulo = maquinaNombre
    ? `La máquina "${maquinaNombre}" no está disponible`
    : `La maquinaria #${maquinariaId} no está disponible`;

  // ejemplos legibles (máx 4)
  const ejemplos = conflictos.slice(0, 4).map((c) => {
    const desc = c.ocupadoPor.descripcion ?? "Tarea sin descripción";
    return {
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

  const message =
    `${titulo}. ` +
    `Está reservada en ${conflictos.length} fecha(s) del cronograma. ` +
    `Selecciona otra máquina o ajusta el plan (días/fechas).`;

  const userHint =
    "Tip: abre la agenda de maquinaria o cambia la máquina por una del conjunto si está disponible.";

  return {
    ok: false as const,
    reason: "MAQUINARIA_NO_DISPONIBLE" as const,
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
