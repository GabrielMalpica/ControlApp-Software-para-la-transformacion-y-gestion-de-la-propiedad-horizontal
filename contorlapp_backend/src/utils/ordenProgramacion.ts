// Orden de programación dentro del día (prioridad 2). Es independiente de la
// prioridad de selección (P1/P2/P3), que solo decide qué tareas entran al mes.
// Sin Prisma: se prueba de forma aislada y la comparten el generador y los tests.

export type DatosOrdenProgramacion = {
  /** Orden de la categoría (1 = primero). null/undefined = sin categoría activa. */
  categoriaOrden: number | null | undefined;
  categoriaId: number | null | undefined;
  /** Orden interno dentro de la categoría (1 = primero). null = al final de su categoría. */
  ordenEnCategoria: number | null | undefined;
  /** Prioridad de selección: solo desempata, nunca reordena categorías. */
  prioridad: number;
  definicionId: number | null | undefined;
  /** Horario previo (ms): conserva el orden relativo existente en empates totales. */
  fechaInicioMs: number;
  id: number;
};

const AL_FINAL = Number.MAX_SAFE_INTEGER;

function valor(n: number | null | undefined): number {
  return n == null || !Number.isFinite(n) ? AL_FINAL : n;
}

/**
 * Orden: categoría → orden interno → prioridad de selección → definición →
 * horario previo → id. Una tarea sin categoría va después de todas las que sí
 * la tienen y su orden interno se ignora (no tiene categoría a la que
 * pertenecer). Es un orden total, así que el resultado no depende del orden
 * de entrada (determinista entre generaciones).
 */
export function compararOrdenProgramacion(
  a: DatosOrdenProgramacion,
  b: DatosOrdenProgramacion,
): number {
  const aTieneCategoria = a.categoriaOrden != null;
  const bTieneCategoria = b.categoriaOrden != null;
  return (
    valor(a.categoriaOrden) - valor(b.categoriaOrden) ||
    valor(a.categoriaId) - valor(b.categoriaId) ||
    valor(aTieneCategoria ? a.ordenEnCategoria : null) -
      valor(bTieneCategoria ? b.ordenEnCategoria : null) ||
    a.prioridad - b.prioridad ||
    valor(a.definicionId) - valor(b.definicionId) ||
    a.fechaInicioMs - b.fechaInicioMs ||
    a.id - b.id
  );
}

export function ordenarPorProgramacion<T>(
  items: readonly T[],
  datos: (item: T) => DatosOrdenProgramacion,
): T[] {
  return [...items].sort((a, b) =>
    compararOrdenProgramacion(datos(a), datos(b)),
  );
}
