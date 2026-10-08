/**
 * Íconos que se pueden asignar a una categoría de tarea. La clave es el
 * contrato con la app: Flutter la traduce a un `IconData` constante (ver
 * controlapp_frontend/lib/utils/cronograma/categoria_iconos.dart). Agregar
 * una clave aquí exige agregarla también allá.
 */
export const ICONOS_CATEGORIA = [
  "limpieza",
  "desinfeccion",
  "jardin",
  "cesped",
  "arboles",
  "piscina",
  "salvamento",
  "agua",
  "residuos",
  "reciclaje",
  "mantenimiento",
  "reparacion",
  "electrico",
  "plomeria",
  "pintura",
  "fumigacion",
  "vigilancia",
  "supervision",
  "parqueadero",
  "otra",
] as const;

export type IconoCategoria = (typeof ICONOS_CATEGORIA)[number];

const VALIDOS = new Set<string>(ICONOS_CATEGORIA);

export function esIconoCategoria(valor: unknown): valor is IconoCategoria {
  return typeof valor === "string" && VALIDOS.has(valor);
}

/** Null/vacío = sin ícono (la app sugiere uno por el nombre). */
export function limpiarIconoCategoria(valor: string | null | undefined): IconoCategoria | null {
  if (valor == null) return null;
  const limpio = valor.trim();
  if (!limpio) return null;
  if (!esIconoCategoria(limpio)) {
    const err = new Error("El ícono de la categoría no es válido.") as Error & { status: number };
    err.status = 400;
    throw err;
  }
  return limpio;
}
