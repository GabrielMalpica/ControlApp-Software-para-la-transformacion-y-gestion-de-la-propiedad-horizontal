export function calcularDuracionMeses(inicio?: Date | null, fin?: Date | null): number | null {
  if (!inicio || !fin) return null;
  const y = fin.getFullYear() - inicio.getFullYear();
  const m = fin.getMonth() - inicio.getMonth();
  const d = fin.getDate() - inicio.getDate();
  const total = y * 12 + m + (d >= 0 ? 0 : -1);
  return Math.max(total, 0);
}
