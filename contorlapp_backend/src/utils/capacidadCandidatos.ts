// Selección de recursos alternativos por capacidades (categorías permitidas).
// Sin Prisma. La única fuente de verdad es PerfilOperativoCategoria: nunca se
// infiere una capacidad por el nombre del cargo ni por los roles.

export type PlazaRecurso = {
  id: number;
  orden: number;
  operarioId: string | null;
  plazaActiva: boolean;
  perfilActivo: boolean;
  /** Ids de CategoriaTarea que el perfil de la plaza puede ejecutar. */
  categoriasPermitidas: ReadonlySet<number>;
};

/** Motivos de exclusión por falta de cupo o de operario (los únicos que admiten rescate). */
export const MOTIVOS_RESCATABLES_POR_CAPACIDAD: ReadonlySet<string> = new Set([
  "SIN_HUECO",
  "SIN_CANDIDATAS",
  "SIN_CAPACIDAD_P1",
  // Plaza vacante: otro perfil compatible puede cubrir la tarea.
  "NECESIDAD_SIN_OPERARIO",
  // Desplazada por una de mayor prioridad: otro recurso puede absorberla.
  "REEMPLAZO_PRIORIDAD",
]);

export function motivoRescatablePorCapacidad(motivoTipo: string): boolean {
  return MOTIVOS_RESCATABLES_POR_CAPACIDAD.has(motivoTipo);
}

/**
 * Plazas distintas de las del dueño que pueden ejecutar la categoría: activas,
 * ocupadas, con perfil activo y con la categoría entre sus capacidades.
 */
export function plazasCandidatas(params: {
  categoriaId: number;
  plazasDuenasIds: readonly number[];
  plazas: readonly PlazaRecurso[];
}): PlazaRecurso[] {
  const duenas = new Set(params.plazasDuenasIds);
  return params.plazas
    .filter(
      (plaza) =>
        !duenas.has(plaza.id) &&
        plaza.plazaActiva &&
        plaza.perfilActivo &&
        plaza.operarioId != null &&
        plaza.categoriasPermitidas.has(params.categoriaId),
    )
    .sort((a, b) => a.orden - b.orden || a.id - b.id);
}

/**
 * Orden de prueba de las candidatas para un día concreto: la menos cargada
 * primero; luego orden de la plaza e id (determinista).
 */
export function ordenarCandidatasPorCarga(
  candidatas: readonly PlazaRecurso[],
  minutosAsignados: (plazaId: number) => number,
): PlazaRecurso[] {
  return [...candidatas].sort(
    (a, b) =>
      minutosAsignados(a.id) - minutosAsignados(b.id) ||
      a.orden - b.orden ||
      a.id - b.id,
  );
}

export type ExcluidaParaRescate = {
  id: number;
  defId: number | null;
  prioridad: number;
  categoriaOrden: number | null;
  ordenEnCategoria: number | null;
  fechaObjetivoMs: number;
};

/**
 * Orden de atención del rescate: prioridad de selección, luego orden de la
 * categoría y orden interno, y por último fecha, definición e id.
 */
export function ordenarExcluidasParaRescate<T extends ExcluidaParaRescate>(
  excluidas: readonly T[],
): T[] {
  const alFinal = Number.MAX_SAFE_INTEGER;
  return [...excluidas].sort(
    (a, b) =>
      a.prioridad - b.prioridad ||
      (a.categoriaOrden ?? alFinal) - (b.categoriaOrden ?? alFinal) ||
      (a.ordenEnCategoria ?? alFinal) - (b.ordenEnCategoria ?? alFinal) ||
      a.fechaObjetivoMs - b.fechaObjetivoMs ||
      (a.defId ?? alFinal) - (b.defId ?? alFinal) ||
      a.id - b.id,
  );
}
