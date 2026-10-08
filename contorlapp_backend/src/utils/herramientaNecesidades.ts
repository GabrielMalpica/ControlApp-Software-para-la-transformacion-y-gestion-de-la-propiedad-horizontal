// src/utils/herramientaNecesidades.ts

/**
 * A diferencia de maquinaria (que declara un TIPO del catalogo de maquinaria),
 * una definicion preventiva declara una herramienta del catalogo de la empresa:
 * herramientaId + cuantas unidades hacen falta. Las unidades fisicas
 * (HerramientaItem, con su codigo) se reservan despues desde la agenda de
 * recursos, igual que la maquinaria.
 */
export type NecesidadHerramienta = {
  herramientaId: number;
  /** Unidades fisicas requeridas (entero >= 1). */
  cantidad: number;
  obligatorio: boolean;
};

function aEnteroPositivo(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
}

/** Cantidades historicas decimales (stock por cantidad) se redondean hacia arriba. */
function aUnidades(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.max(1, Math.ceil(n)) : null;
}

/**
 * Lee `herramientasPlanJson` de una definicion o de una tarea. Items sin
 * `herramientaId` resoluble se descartan. Sin `cantidad`, se asume 1; sin
 * `obligatorio`, la necesidad es obligatoria.
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
      cantidad: aUnidades(raw.cantidad) ?? 1,
      obligatorio: raw.obligatorio === false || raw.obligatorio === "false" ? false : true,
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
