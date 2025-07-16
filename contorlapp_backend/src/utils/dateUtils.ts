export function formatearFecha(fecha: Date | string): string {
  const date = typeof fecha === 'string' ? new Date(fecha) : fecha;
  const dia = String(date.getDate()).padStart(2, '0');
  const mes = String(date.getMonth() + 1).padStart(2, '0'); // Los meses van de 0 a 11
  const anio = date.getFullYear();
  return `${dia}/${mes}/${anio}`;
}
