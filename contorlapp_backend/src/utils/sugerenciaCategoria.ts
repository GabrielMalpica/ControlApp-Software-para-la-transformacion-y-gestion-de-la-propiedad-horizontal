// Sugerencia de categoría por palabras clave (sin Prisma). Solo PROPONE: el
// usuario confirma antes de guardar.
import { normalizarTexto } from "./perfilOperativo";

export type CategoriaParaSugerir = {
  id: number;
  nombre: string;
  ordenProgramacion: number;
  palabrasClave: readonly string[];
};

export type SugerenciaCategoria = {
  categoriaId: number;
  categoriaNombre: string;
  coincidencias: string[];
};

/** Una coincidencia en la descripción pesa más que una en el contexto (elemento/ubicación). */
const PESO_DESCRIPCION = 2;
const PESO_CONTEXTO = 1;

function escapar(texto: string): string {
  return texto.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * La palabra clave debe EMPEZAR en límite de palabra, pero puede ser una raíz
 * ("barr" coincide con "barrer" y "barrido"; "poda" no coincide con "apoda").
 */
function contiene(textoNormalizado: string, claveNormalizada: string): boolean {
  if (!claveNormalizada) return false;
  return new RegExp(`(^|[^a-z0-9])${escapar(claveNormalizada)}`).test(textoNormalizado);
}

function coincidenciasEn(texto: string, categoria: CategoriaParaSugerir): string[] {
  const normalizado = normalizarTexto(texto);
  return Array.from(
    new Set(
      categoria.palabrasClave
        .map((p) => ({ original: p, clave: normalizarTexto(p) }))
        .filter((p) => contiene(normalizado, p.clave))
        .map((p) => p.original),
    ),
  );
}

/**
 * Gana la categoría con mayor puntaje (descripción pesa el doble que el
 * contexto); ante empate, la de menor orden de programación y luego la de
 * menor id (determinista). null si nada coincide.
 */
export function sugerirCategoriaPorTexto(
  texto: string,
  categorias: readonly CategoriaParaSugerir[],
  contexto = "",
): SugerenciaCategoria | null {
  let mejor: { cat: CategoriaParaSugerir; puntaje: number; coincidencias: string[] } | null = null;
  for (const cat of categorias) {
    const enDescripcion = coincidenciasEn(texto, cat);
    const enContexto = contexto
      ? coincidenciasEn(contexto, cat).filter((c) => !enDescripcion.includes(c))
      : [];
    const puntaje =
      enDescripcion.length * PESO_DESCRIPCION + enContexto.length * PESO_CONTEXTO;
    if (puntaje === 0) continue;
    if (
      !mejor ||
      puntaje > mejor.puntaje ||
      (puntaje === mejor.puntaje &&
        (cat.ordenProgramacion < mejor.cat.ordenProgramacion ||
          (cat.ordenProgramacion === mejor.cat.ordenProgramacion && cat.id < mejor.cat.id)))
    ) {
      mejor = { cat, puntaje, coincidencias: [...enDescripcion, ...enContexto] };
    }
  }
  return mejor
    ? {
        categoriaId: mejor.cat.id,
        categoriaNombre: mejor.cat.nombre,
        coincidencias: mejor.coincidencias,
      }
    : null;
}
