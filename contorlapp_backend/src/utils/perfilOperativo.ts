// Helpers puros de perfiles operativos (sin Prisma).

export const ROLES_EN_ORDEN = [
  "TODERO",
  "SALVAVIDAS",
  "ASEO",
  "PISCINERO",
  "JARDINERO",
] as const;

export type RolFuncion = (typeof ROLES_EN_ORDEN)[number];

const ETIQUETA_ROL: Record<RolFuncion, string> = {
  TODERO: "Todero",
  SALVAVIDAS: "Salvavidas",
  ASEO: "Aseo",
  PISCINERO: "Piscinero",
  JARDINERO: "Jardinero",
};

/** Roles únicos en el orden del enum (misma regla que usa la migración). */
export function rolesNormalizados<T extends string>(roles: readonly T[]): T[] {
  const unicos = Array.from(new Set(roles));
  return unicos.sort(
    (a, b) =>
      ROLES_EN_ORDEN.indexOf(a as unknown as RolFuncion) -
      ROLES_EN_ORDEN.indexOf(b as unknown as RolFuncion),
  );
}

/** "Todero-Salvavidas" para una combinación; "Todero" para un solo rol. */
export function nombrePerfilDesdeRoles(roles: readonly string[]): string {
  return rolesNormalizados(roles)
    .map((r) => ETIQUETA_ROL[r as RolFuncion] ?? r)
    .join("-");
}

export function mismosRoles(a: readonly string[], b: readonly string[]): boolean {
  const x = rolesNormalizados(a);
  const y = rolesNormalizados(b);
  return x.length === y.length && x.every((r, i) => r === y[i]);
}

/** Minúsculas y sin acentos, para comparar nombres y palabras clave. */
export function normalizarTexto(valor: string): string {
  return valor
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .trim();
}
