// src/utils/herramientaNecesidades.ts

/**
 * A diferencia de maquinaria (que declara un TIPO), una definicion preventiva
 * declara ya una herramienta concreta del catalogo de la empresa: herramientaId +
 * cuantas hacen falta. La unidad real (de que stock sale) se decide despues, desde
 * el cronograma de herramientas.
 */
export type NecesidadHerramienta = {
  herramientaId: number;
  cantidad: number;
};

function aNumeroPositivo(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function aEnteroPositivo(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
}

/**
 * Lee `herramientasPlanJson` de una definicion o de una tarea. Items sin
 * `herramientaId` resoluble se descartan. Sin `cantidad`, se asume 1.
 */
export function parseNecesidadesHerramienta(json: unknown): NecesidadHerramienta[] {
  if (!Array.isArray(json)) return [];

  const salida: NecesidadHerramienta[] = [];

  for (const item of json) {
    if (!item || typeof item !== "object") continue;

    const raw = item as Record<string, unknown>;
    const herramientaId = aEnteroPositivo(raw.herramientaId);
    if (!herramientaId) continue;

    salida.push({
      herramientaId,
      cantidad: aNumeroPositivo(raw.cantidad) ?? 1,
    });
  }

  return salida;
}

/** Suma las cantidades por herramienta de un plan. */
export function agruparNecesidadesPorHerramienta(
  necesidades: NecesidadHerramienta[],
): Map<number, number> {
  const salida = new Map<number, number>();
  for (const necesidad of necesidades) {
    salida.set(
      necesidad.herramientaId,
      (salida.get(necesidad.herramientaId) ?? 0) + necesidad.cantidad,
    );
  }
  return salida;
}
