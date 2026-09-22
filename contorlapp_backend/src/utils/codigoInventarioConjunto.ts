const ROMANOS = new Set([
  "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
]);

/**
 * Deriva el prefijo de código interno (MAQ-/HER-) a partir del nombre del
 * conjunto: iniciales de cada palabra (ej. "Bosques de Morelia" -> "BDM").
 * Si el nombre termina en un número o numeral romano (ej. "Bosques de
 * Morelia 2" / "... II"), ese número se conserva pegado a las iniciales
 * ("BDM2"). No se inventa un número si el nombre no trae uno.
 */
export function prefijoConjunto(nombre: string): string {
  const palabras = nombre
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (!palabras.length) return "CNJ";

  let numero = "";
  const ultima = palabras[palabras.length - 1].toUpperCase();
  if (/^\d+$/.test(ultima) || ROMANOS.has(ultima)) {
    numero = ultima;
    palabras.pop();
  }

  const iniciales = palabras
    .map((palabra) => palabra.replace(/[^a-zA-Z0-9]/g, "").charAt(0))
    .filter(Boolean)
    .join("")
    .toUpperCase()
    .slice(0, 8);

  return `${iniciales || "CNJ"}${numero}`;
}
