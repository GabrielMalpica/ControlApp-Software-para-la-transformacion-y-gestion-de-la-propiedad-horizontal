// src/utils/maquinariaNecesidades.ts
import { TipoMaquinaria } from "@prisma/client";

/**
 * Una definicion preventiva declara QUE TIPO de maquina necesita, no una maquina
 * concreta. La maquina real se asigna despues desde la agenda de recursos.
 *
 * El tipo se expresa con `tipoCatalogoId` (TipoMaquinariaCatalogo de la
 * empresa). Los planes antiguos solo traen `tipo` (enum legado), que al
 * publicar se resuelve al catalogo por `tipoLegacy`.
 */
export type NecesidadMaquinaria = {
  tipoCatalogoId: number | null;
  tipo: TipoMaquinaria | null;
  cantidad: number;
  obligatorio: boolean;
  /** Preselección en la agenda de recursos. No compromete la máquina. */
  maquinariaSugeridaId: number | null;
};

const TIPOS_VALIDOS = new Set<string>(Object.values(TipoMaquinaria));

function aEntero(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
}

function normalizarTipo(value: unknown): TipoMaquinaria | null {
  const texto = String(value ?? "").trim().toUpperCase();
  return TIPOS_VALIDOS.has(texto) ? (texto as TipoMaquinaria) : null;
}

function aBooleano(value: unknown, porDefecto: boolean): boolean {
  if (typeof value === "boolean") return value;
  if (value === "false" || value === 0) return false;
  if (value === "true" || value === 1) return true;
  return porDefecto;
}

/**
 * Lee `maquinariaPlanJson` de una definicion o de una tarea.
 *
 * Tolerante con el historico: acepta `{tipoCatalogoId, cantidad, obligatorio}`,
 * `{tipo, cantidad, maquinariaSugeridaId}` y el antiguo `{maquinariaId}`. Los
 * items sin tipo resoluble se descartan, porque sin tipo no hay necesidad que
 * asignar. Sin `obligatorio`, la necesidad es obligatoria.
 */
export function parseNecesidadesMaquinaria(json: unknown): NecesidadMaquinaria[] {
  if (!Array.isArray(json)) return [];

  const salida: NecesidadMaquinaria[] = [];

  for (const item of json) {
    if (!item || typeof item !== "object") continue;

    const raw = item as Record<string, unknown>;
    const tipoCatalogoId = aEntero(raw.tipoCatalogoId);
    const tipo = normalizarTipo(raw.tipo);
    if (tipoCatalogoId == null && !tipo) continue;

    salida.push({
      tipoCatalogoId,
      tipo,
      cantidad: aEntero(raw.cantidad) ?? 1,
      obligatorio: aBooleano(raw.obligatorio, true),
      maquinariaSugeridaId:
        aEntero(raw.maquinariaSugeridaId) ?? aEntero(raw.maquinariaId),
    });
  }

  return salida;
}

/**
 * Ids de maquinas realmente comprometidas en el plan (formato antiguo).
 * Con el modelo por necesidad esto queda vacio y, por tanto, ni la publicacion
 * ni el movimiento de tareas en el borrador vuelven a chocar por maquinaria.
 */
export function parseMaquinariaIdsComprometidos(json: unknown): number[] {
  if (!Array.isArray(json)) return [];

  return json
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const raw = item as Record<string, unknown>;
      // Si el item ya declara un tipo, `maquinariaId` es solo una sugerencia.
      if (normalizarTipo(raw.tipo) || aEntero(raw.tipoCatalogoId)) return null;
      return aEntero(raw.maquinariaId);
    })
    .filter((id): id is number => id != null);
}

/**
 * Clave estable de un tipo dentro de un plan: el catalogo si se conoce y, si no,
 * el enum legado. Sirve para sumar cantidades repetidas del mismo tipo.
 */
export function claveTipoNecesidad(necesidad: NecesidadMaquinaria): string {
  return necesidad.tipoCatalogoId != null
    ? `cat:${necesidad.tipoCatalogoId}`
    : `enum:${necesidad.tipo}`;
}

/** Suma las cantidades por tipo de un plan de maquinaria. */
export function agruparNecesidadesPorTipo(
  necesidades: NecesidadMaquinaria[],
): Map<string, number> {
  const salida = new Map<string, number>();
  for (const necesidad of necesidades) {
    const clave = claveTipoNecesidad(necesidad);
    salida.set(clave, (salida.get(clave) ?? 0) + necesidad.cantidad);
  }
  return salida;
}
