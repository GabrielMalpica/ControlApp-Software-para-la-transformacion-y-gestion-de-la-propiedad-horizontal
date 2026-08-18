export type ElementoConPadres = {
  id: number;
  nombre: string;
  padre?: ElementoConPadres | null;
};

export type ConfiguracionZonaEfectiva = {
  elementoId: number;
  nombre: string;
  orden: number;
  colorHex: string;
  configurado: boolean;
};

export type ConfiguracionZonaGuardada = {
  elementoZonaId: number;
  orden: number;
  colorHex: string;
};

export function normalizarNombreZona(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function politicaZonaPredeterminada(nombre: string): {
  orden: number;
  colorHex: string;
} {
  const normalizado = normalizarNombreZona(nombre);
  if (normalizado.includes("humed") || normalizado.includes("agua")) {
    return { orden: 10, colorHex: "#2196F3" };
  }
  if (
    normalizado.includes("verde") ||
    normalizado.includes("jardin") ||
    normalizado.includes("cesped")
  ) {
    return { orden: 20, colorHex: "#43A047" };
  }
  if (
    normalizado.includes("transit") ||
    normalizado.includes("circul") ||
    normalizado.includes("estacionamiento")
  ) {
    return { orden: 30, colorHex: "#FB8C00" };
  }
  return { orden: 100, colorHex: "#2E7D32" };
}

export function obtenerZonaRaiz(
  elemento: ElementoConPadres | null | undefined,
): ElementoConPadres | null {
  if (!elemento) return null;
  let actual = elemento;
  while (actual.padre) actual = actual.padre;
  return actual;
}

export function resolverConfiguracionZona(
  elemento: ElementoConPadres | null | undefined,
  configuraciones: ReadonlyMap<number, ConfiguracionZonaGuardada>,
): ConfiguracionZonaEfectiva | null {
  const zona = obtenerZonaRaiz(elemento);
  if (!zona) return null;
  const guardada = configuraciones.get(zona.id);
  const predeterminada = politicaZonaPredeterminada(zona.nombre);
  return {
    elementoId: zona.id,
    nombre: zona.nombre,
    orden: guardada?.orden ?? predeterminada.orden,
    colorHex: guardada?.colorHex.toUpperCase() ?? predeterminada.colorHex,
    configurado: guardada != null,
  };
}
