// src/utils/maquinariaNecesidades.ts
import { TipoMaquinaria } from "@prisma/client";

/**
 * Una definicion preventiva declara QUE TIPO de maquina necesita, no una maquina
 * concreta. La maquina real se asigna despues, para toda la empresa, desde el
 * cronograma de maquinaria.
 */
export type NecesidadMaquinaria = {
  tipo: TipoMaquinaria;
  cantidad: number;
  /** Preselección en el cronograma de maquinaria. No compromete la máquina. */
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

/**
 * Lee `maquinariaPlanJson` de una definicion o de una tarea.
 *
 * Tolerante con el historico: acepta el formato nuevo `{tipo, cantidad,
 * maquinariaSugeridaId}` y el antiguo `{maquinariaId}`. Los items sin tipo
 * resoluble se descartan, porque sin tipo no hay necesidad que asignar.
 */
export function parseNecesidadesMaquinaria(json: unknown): NecesidadMaquinaria[] {
  if (!Array.isArray(json)) return [];

  const salida: NecesidadMaquinaria[] = [];

  for (const item of json) {
    if (!item || typeof item !== "object") continue;

    const raw = item as Record<string, unknown>;
    const tipo = normalizarTipo(raw.tipo);
    if (!tipo) continue;

    salida.push({
      tipo,
      cantidad: aEntero(raw.cantidad) ?? 1,
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
      if (normalizarTipo(raw.tipo)) return null;
      return aEntero(raw.maquinariaId);
    })
    .filter((id): id is number => id != null);
}

/** Suma las cantidades por tipo de un plan de maquinaria. */
export function agruparNecesidadesPorTipo(
  necesidades: NecesidadMaquinaria[],
): Map<TipoMaquinaria, number> {
  const salida = new Map<TipoMaquinaria, number>();
  for (const necesidad of necesidades) {
    salida.set(
      necesidad.tipo,
      (salida.get(necesidad.tipo) ?? 0) + necesidad.cantidad,
    );
  }
  return salida;
}
