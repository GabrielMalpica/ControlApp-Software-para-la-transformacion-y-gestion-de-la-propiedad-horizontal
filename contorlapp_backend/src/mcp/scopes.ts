// src/mcp/scopes.ts
//
// Permisos que un gerente concede a un cliente de IA. Formato `modulo:nivel`.
// Lo que no tiene scope (usuarios y roles, permisos, empresa, pagos,
// residentes, documentos de la web, evidencias) no existe por MCP.
// Ver docs/mcp/MCP_INTEGRATION_GUIDELINES.md antes de anadir uno.

export type DefinicionScope = {
  scope: string;
  titulo: string;
  descripcion: string;
  nivel: "lectura" | "escritura" | "alto_riesgo";
  /** Scopes que este concede implicitamente (p. ej. escribir implica leer). */
  incluye?: string[];
};

export const CATALOGO_SCOPES: DefinicionScope[] = [
  { scope: "conjuntos:read", titulo: "Ver conjuntos", descripcion: "Conjuntos, horarios y ubicaciones.", nivel: "lectura" },
  { scope: "conjuntos:write", titulo: "Crear conjuntos", descripcion: "Crear conjuntos con su estructura (nunca eliminarlos).", nivel: "escritura", incluye: ["conjuntos:read"] },
  { scope: "personal:read", titulo: "Ver personal", descripcion: "Operarios y supervisores: nombre, conjunto, plaza y funciones (sin cédulas ni datos de salud).", nivel: "lectura" },
  { scope: "personal:pii", titulo: "Ver datos de contacto", descripcion: "Teléfono y correo del personal.", nivel: "lectura", incluye: ["personal:read"] },
  { scope: "personal:write", titulo: "Gestionar personal", descripcion: "Crear operarios, asignar o liberar plazas y trasladar operarios (siempre con confirmación).", nivel: "escritura", incluye: ["personal:read"] },
  { scope: "tareas:read", titulo: "Ver tareas", descripcion: "Tareas del cronograma publicado y su estado.", nivel: "lectura" },
  { scope: "cronograma:read", titulo: "Ver cronogramas", descripcion: "Estado del borrador y del cronograma publicado.", nivel: "lectura" },
  { scope: "cronograma:publicar", titulo: "Publicar cronogramas", descripcion: "Publicar el cronograma de un mes. Requiere tu aprobación dentro de ControlApp.", nivel: "alto_riesgo", incluye: ["cronograma:read"] },
  { scope: "asistencia:read", titulo: "Ver asistencia", descripcion: "Asistencia diaria y mensual, faltas y novedades.", nivel: "lectura" },
  { scope: "asistencia:write", titulo: "Registrar novedades", descripcion: "Registrar novedades de asistencia (falta, permiso, incapacidad...).", nivel: "escritura", incluye: ["asistencia:read"] },
  { scope: "inventario:read", titulo: "Ver inventario", descripcion: "Existencias de insumos e insumos por agotarse.", nivel: "lectura" },
  { scope: "inventario:write", titulo: "Mover inventario", descripcion: "Registrar entradas y consumos de insumos.", nivel: "escritura", incluye: ["inventario:read"] },
  { scope: "recursos:read", titulo: "Ver maquinaria", descripcion: "Maquinaria y su estado.", nivel: "lectura" },
  { scope: "solicitudes:read", titulo: "Ver solicitudes", descripcion: "Solicitudes de insumos pendientes.", nivel: "lectura" },
  { scope: "compromisos:read", titulo: "Ver compromisos", descripcion: "Compromisos y PQRS por conjunto.", nivel: "lectura" },
  { scope: "compromisos:write", titulo: "Crear compromisos", descripcion: "Crear compromisos de un conjunto.", nivel: "escritura", incluye: ["compromisos:read"] },
  { scope: "reportes:read", titulo: "Ver indicadores", descripcion: "Indicadores de tareas por periodo.", nivel: "lectura" },
];

const POR_SCOPE = new Map(CATALOGO_SCOPES.map((item) => [item.scope, item]));

export const TODOS_LOS_SCOPES = CATALOGO_SCOPES.map((item) => item.scope);

/** Datos personales: nunca se piden por defecto, el gerente los marca a proposito. */
const SCOPES_SENSIBLES = new Set(["personal:pii"]);

/** Lo minimo para empezar (RFC 9728 `scopes_supported`): lecturas no sensibles. */
export const SCOPES_LECTURA = CATALOGO_SCOPES.filter(
  (item) => item.nivel === "lectura" && !SCOPES_SENSIBLES.has(item.scope),
).map((item) => item.scope);

export function esScopeValido(scope: string): boolean {
  return POR_SCOPE.has(scope);
}

export function definicionScope(scope: string): DefinicionScope | undefined {
  return POR_SCOPE.get(scope);
}

/** Expande los scopes concedidos con los que implican (jerarquia). */
export function expandirScopes(concedidos: Iterable<string>): Set<string> {
  const resultado = new Set<string>();
  const pendientes = [...concedidos];
  while (pendientes.length) {
    const scope = pendientes.pop()!;
    if (resultado.has(scope) || !POR_SCOPE.has(scope)) continue;
    resultado.add(scope);
    pendientes.push(...(POR_SCOPE.get(scope)?.incluye ?? []));
  }
  return resultado;
}

export function tieneScope(concedidos: Iterable<string>, requerido: string): boolean {
  return expandirScopes(concedidos).has(requerido);
}

/** Normaliza el parametro `scope` de OAuth: separado por espacios, solo validos, sin repetir. */
export function parsearScopes(valor: unknown): string[] {
  return [
    ...new Set(
      String(valor ?? "")
        .split(/\s+/)
        .map((s) => s.trim())
        .filter((s) => s && esScopeValido(s)),
    ),
  ];
}
