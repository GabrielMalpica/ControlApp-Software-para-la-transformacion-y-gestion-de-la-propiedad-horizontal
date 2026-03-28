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
