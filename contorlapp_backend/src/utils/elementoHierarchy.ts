export const elementoTreeInclude = {
  hijos: {
    include: {
      hijos: {
        include: {
          hijos: true,
        },
      },
    },
  },
} as const;

export const elementoParentChainInclude = {
  padre: {
    include: {
      padre: {
        include: {
          padre: true,
        },
      },
    },
  },
} as const;

/**
 * Selector minimo para mostrar un operario asignado a una tarea (nombre +
 * cargo). Evita traer la fila Usuario completa (incluye el hash de
 * contrasena y datos personales como EPS, tipo de sangre, direccion).
 */
export const operarioResumenSelect = {
  id: true,
  funciones: true,
  usuario: { select: { nombre: true } },
} as const;

/** Equivalente a operarioResumenSelect para Supervisor (sin `funciones`). */
export const supervisorResumenSelect = {
  id: true,
  usuario: { select: { nombre: true } },
} as const;

/**
 * Todos los campos de Usuario que el frontend (Usuario.fromJson) puede leer,
 * EXCEPTO `contrasena` (el hash bcrypt nunca debe salir de la API). Usar en
 * lugar de `include: { usuario: true }` en pantallas que muestran el perfil
 * completo (no solo el nombre) de administradores/operarios.
 */
export const usuarioSinContrasenaSelect = {
  id: true,
  nombre: true,
  correo: true,
  rol: true,
  activo: true,
  requiereCambioContrasena: true,
  telefono: true,
  fechaNacimiento: true,
  direccion: true,
  estadoCivil: true,
  numeroHijos: true,
  padresVivos: true,
  tipoSangre: true,
  eps: true,
  fondoPensiones: true,
  tallaCamisa: true,
  tallaPantalon: true,
  tallaCalzado: true,
  tipoContrato: true,
  jornadaLaboral: true,
  patronJornada: true,
} as const;

type ElementoNode = {
  id: number;
  nombre: string;
  padreId?: number | null;
  hijos?: ElementoNode[];
  padre?: ElementoNode | null;
};

export function normalizarArbolElementos<T extends ElementoNode>(
  elementos: T[],
): T[] {
  return [...elementos].sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
}

export function aplanarElementosHoja<T extends ElementoNode>(
  elementos: T[],
  parentPath: string[] = [],
): Array<T & { ruta: string }> {
  const out: Array<T & { ruta: string }> = [];

  for (const item of elementos) {
    const path = [...parentPath, item.nombre];
    const hijos = item.hijos ?? [];
    if (!hijos.length) {
      out.push({ ...item, ruta: path.join(" > ") });
      continue;
    }
    out.push(...aplanarElementosHoja(hijos as T[], path));
  }

  return out;
}

export function construirRutaElemento(
  elemento:
    | (ElementoNode & {
        padre?: (ElementoNode & { padre?: ElementoNode | null }) | null;
      })
    | null
    | undefined,
): string | null {
  if (!elemento) return null;
  const names: string[] = [];
  let current: any = elemento;
  while (current) {
    names.unshift(String(current.nombre));
    current = current.padre ?? null;
  }
  return names.join(" > ");
}
