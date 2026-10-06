import type { PrismaClient } from "@prisma/client";

type TareaConCategoria = {
  categoriaId?: number | null;
  definicionId?: number | null;
};

export type CategoriaCronograma = {
  categoriaId: number | null;
  categoriaNombre: string | null;
  categoriaColorHex: string | null;
};

function normalizarColor(valor: string | null | undefined): string | null {
  const limpio = (valor ?? "").trim().replace(/^#/, "");
  return /^[0-9A-Fa-f]{6}$/.test(limpio) ? `#${limpio.toUpperCase()}` : null;
}

/**
 * Agrega a cada tarea la categoría con la que se debe pintar en el
 * cronograma (borrador y publicado).
 *
 * La categoría sale de la propia tarea y, si no la tiene, de su preventiva
 * (definición): varios caminos que crean tareas (dividir, reprogramar desde
 * excluidas, bloque manual, reordenar) no copian `categoriaId`, y así el
 * color no depende de que todos lo hagan. Son dos consultas en lote.
 */
export async function adjuntarCategoriaCronograma<T extends TareaConCategoria>(
  prisma: PrismaClient,
  tareas: T[],
): Promise<Array<T & CategoriaCronograma>> {
  if (!tareas.length) return [];

  const definicionesSinCategoria = Array.from(
    new Set(
      tareas
        .filter((t) => t.categoriaId == null && t.definicionId != null)
        .map((t) => t.definicionId as number),
    ),
  );
  const categoriaPorDefinicion = new Map<number, number>();
  if (definicionesSinCategoria.length) {
    const defs = await prisma.definicionTareaPreventiva.findMany({
      where: { id: { in: definicionesSinCategoria }, categoriaId: { not: null } },
      select: { id: true, categoriaId: true },
    });
    for (const def of defs) {
      if (def.categoriaId != null) categoriaPorDefinicion.set(def.id, def.categoriaId);
    }
  }

  const categoriaIdDe = (t: T): number | null =>
    t.categoriaId ??
    (t.definicionId != null ? (categoriaPorDefinicion.get(t.definicionId) ?? null) : null);

  const ids = Array.from(
    new Set(tareas.map(categoriaIdDe).filter((id): id is number => id != null)),
  );
  const categorias = ids.length
    ? await prisma.categoriaTarea.findMany({
        where: { id: { in: ids } },
        select: { id: true, nombre: true, colorHex: true },
      })
    : [];
  const porId = new Map(categorias.map((c) => [c.id, c]));

  return tareas.map((t) => {
    const categoriaId = categoriaIdDe(t);
    const categoria = categoriaId != null ? porId.get(categoriaId) : undefined;
    return {
      ...t,
      categoriaId,
      categoriaNombre: categoria?.nombre ?? null,
      categoriaColorHex: normalizarColor(categoria?.colorHex),
    };
  });
}
