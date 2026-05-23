import { Prisma, Rol, type PrismaClient } from "@prisma/client";

type PermissionDefinition = {
  key: string;
  module: string;
  moduleLabel: string;
  label: string;
  description: string;
};

type PermissionMatrixInput = Partial<Record<Rol, Partial<Record<string, boolean>>>>;

const ROLE_ORDER: Rol[] = [
  Rol.gerente,
  Rol.administrador,
  Rol.jefe_operaciones,
  Rol.supervisor,
  Rol.operario,
];

const MANAGED_ROLE_ORDER: Rol[] = ROLE_ORDER.filter((rol) => rol !== Rol.gerente);

const PERMISSION_CATALOG: PermissionDefinition[] = [
  {
    key: "tareas.crear",
    module: "tareas",
    moduleLabel: "Tareas",
    label: "Crear tareas correctivas",
    description: "Permite crear nuevas tareas correctivas.",
  },
  {
    key: "tareas.ver",
    module: "tareas",
    moduleLabel: "Tareas",
    label: "Ver tareas",
    description: "Permite entrar a las pantallas y listados de tareas.",
  },
  {
    key: "tareas.cerrar",
    module: "tareas",
    moduleLabel: "Tareas",
    label: "Cerrar tareas",
    description: "Permite cerrar tareas desde cronograma o listados.",
  },
  {
    key: "tareas.veredicto",
    module: "tareas",
    moduleLabel: "Tareas",
    label: "Dar veredicto final",
    description: "Permite aprobar o rechazar tareas pendientes de veredicto.",
  },
  {
    key: "cronograma.ver",
    module: "cronograma",
    moduleLabel: "Cronogramas",
    label: "Ver cronogramas",
    description: "Permite abrir y consultar el cronograma del conjunto.",
  },
  {
    key: "cronograma.imprimir",
    module: "cronograma",
    moduleLabel: "Cronogramas",
    label: "Imprimir cronograma",
    description: "Permite usar la vista imprimible del cronograma.",
  },
  {
    key: "cronograma.publicar",
    module: "cronograma",
    moduleLabel: "Cronogramas",
    label: "Publicar cronograma",
    description: "Permite publicar el cronograma preventivo generado.",
  },
  {
    key: "cronograma.eliminar_publicado",
    module: "cronograma",
    moduleLabel: "Cronogramas",
    label: "Eliminar cronograma publicado",
    description: "Permite borrar las tareas publicadas del cronograma.",
  },
  {
    key: "solicitudes.ver",
    module: "solicitudes",
    moduleLabel: "Solicitudes",
    label: "Ver solicitudes",
    description: "Permite consultar solicitudes de tareas, insumos y maquinaria.",
  },
  {
    key: "inventario.ver",
    module: "inventario",
    moduleLabel: "Inventario",
    label: "Ver inventario",
    description: "Permite consultar el inventario del conjunto.",
  },
  {
    key: "maquinaria.ver",
    module: "maquinaria",
    moduleLabel: "Maquinaria",
    label: "Ver agenda de maquinaria",
    description: "Permite consultar la agenda y disponibilidad de maquinaria.",
  },
  {
    key: "herramientas.ver",
    module: "herramientas",
    moduleLabel: "Herramientas",
    label: "Ver agenda de herramientas",
    description: "Permite consultar la agenda y disponibilidad de herramientas.",
  },
  {
    key: "mapa_areas.ver",
    module: "mapa_areas",
    moduleLabel: "Mapa de areas",
    label: "Ver mapa de areas",
    description: "Permite consultar el mapa e informacion visual del conjunto.",
  },
  {
    key: "compromisos.ver",
    module: "compromisos",
    moduleLabel: "Compromisos y PQRS",
    label: "Ver compromisos",
    description: "Permite consultar compromisos o PQRS del conjunto.",
  },
  {
    key: "compromisos.gestionar",
    module: "compromisos",
    moduleLabel: "Compromisos y PQRS",
    label: "Gestionar compromisos",
    description: "Permite crear, editar o eliminar compromisos o PQRS.",
  },
  {
    key: "compromisos.globales_ver",
    module: "compromisos",
    moduleLabel: "Compromisos y PQRS",
    label: "Ver compromisos globales",
    description: "Permite consultar la vista global por conjunto.",
  },
  {
    key: "reportes.ver",
    module: "reportes",
    moduleLabel: "Reportes",
    label: "Ver reportes",
    description: "Permite abrir dashboards y analitica del sistema.",
  },
  {
    key: "cumpleanos.ver",
    module: "cumpleanos",
    moduleLabel: "Cumpleanos",
    label: "Ver cumpleanos",
    description: "Permite ver el banner y la pantalla de cumpleanos.",
  },
];

const ALL_PERMISSION_KEYS = new Set(PERMISSION_CATALOG.map((item) => item.key));

const DEFAULT_PERMISSIONS_BY_ROLE: Record<Rol, Set<string>> = {
  [Rol.gerente]: new Set(PERMISSION_CATALOG.map((item) => item.key)),
  [Rol.administrador]: new Set([
    "cronograma.ver",
    "inventario.ver",
    "mapa_areas.ver",
    "compromisos.ver",
    "compromisos.gestionar",
    "reportes.ver",
    "cumpleanos.ver",
  ]),
  [Rol.jefe_operaciones]: new Set([
    "tareas.ver",
    "tareas.cerrar",
    "tareas.veredicto",
    "cronograma.ver",
    "cronograma.imprimir",
    "solicitudes.ver",
    "inventario.ver",
    "maquinaria.ver",
    "herramientas.ver",
    "mapa_areas.ver",
    "compromisos.ver",
    "compromisos.gestionar",
    "compromisos.globales_ver",
    "cumpleanos.ver",
  ]),
  [Rol.supervisor]: new Set([
    "tareas.crear",
    "tareas.ver",
    "tareas.cerrar",
    "cronograma.ver",
    "cronograma.imprimir",
    "solicitudes.ver",
    "inventario.ver",
    "maquinaria.ver",
    "herramientas.ver",
    "mapa_areas.ver",
    "compromisos.ver",
    "compromisos.gestionar",
    "compromisos.globales_ver",
    "reportes.ver",
  ]),
  [Rol.operario]: new Set([
    "tareas.ver",
    "tareas.cerrar",
    "solicitudes.ver",
    "mapa_areas.ver",
    "cumpleanos.ver",
  ]),
};

function normalizeRole(value: string | Rol | null | undefined): Rol | null {
  const role = String(value ?? "").trim().toLowerCase();
  return ROLE_ORDER.find((item) => item === role) ?? null;
}

function ensureEmpresaId(value: string | null | undefined): string {
  const empresaId = String(value ?? "").trim();
  if (!empresaId) {
    throw new Error("No se pudo resolver la empresa para consultar permisos.");
  }

  return empresaId;
}

function hasText(value: string | null | undefined): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

export class PermissionService {
  constructor(private prisma: PrismaClient) {}

  private async resolveFallbackEmpresaId(): Promise<string> {
    const empresa = await this.prisma.empresa.findFirst({
      select: { nit: true },
      orderBy: { id: "asc" },
    });

    return ensureEmpresaId(empresa?.nit);
  }

  static roleOrder(): Rol[] {
    return [...ROLE_ORDER];
  }

  static managedRoles(): Rol[] {
    return [...MANAGED_ROLE_ORDER];
  }

  static catalog(): PermissionDefinition[] {
    return PERMISSION_CATALOG.map((item) => ({ ...item }));
  }

  static isValidPermission(permission: string): boolean {
    return ALL_PERMISSION_KEYS.has(permission);
  }

  static defaultPermissionsForRole(role: Rol): Set<string> {
    return new Set(DEFAULT_PERMISSIONS_BY_ROLE[role] ?? []);
  }

  async resolveEmpresaIdForUser(userId: string, role: string | Rol): Promise<string> {
    const normalizedRole = normalizeRole(role);
    if (!normalizedRole) {
      throw new Error("El rol del usuario no es valido para resolver permisos.");
    }

    switch (normalizedRole) {
      case Rol.gerente: {
        const gerente = await this.prisma.gerente.findUnique({
          where: { id: userId },
          select: { empresaId: true },
        });
        return hasText(gerente?.empresaId)
          ? gerente!.empresaId!.trim()
          : this.resolveFallbackEmpresaId();
      }
      case Rol.jefe_operaciones: {
        const jefe = await this.prisma.jefeOperaciones.findUnique({
          where: { id: userId },
          select: { empresaId: true },
        });
        return hasText(jefe?.empresaId)
          ? jefe!.empresaId!.trim()
          : this.resolveFallbackEmpresaId();
      }
      case Rol.supervisor: {
        const supervisor = await this.prisma.supervisor.findUnique({
          where: { id: userId },
          select: { empresaId: true },
        });
        return hasText(supervisor?.empresaId)
          ? supervisor!.empresaId!.trim()
          : this.resolveFallbackEmpresaId();
      }
      case Rol.operario: {
        const operario = await this.prisma.operario.findUnique({
          where: { id: userId },
          select: { empresaId: true },
        });
        return hasText(operario?.empresaId)
          ? operario!.empresaId!.trim()
          : this.resolveFallbackEmpresaId();
      }
      case Rol.administrador: {
        const conjunto = await this.prisma.conjunto.findFirst({
          where: { administradorId: userId },
          select: { empresaId: true },
          orderBy: { nit: "asc" },
        });
        return hasText(conjunto?.empresaId)
          ? conjunto!.empresaId!.trim()
          : this.resolveFallbackEmpresaId();
      }
    }
  }

  async getEffectivePermissionsForRole(empresaId: string, role: string | Rol): Promise<Set<string>> {
    const normalizedRole = normalizeRole(role);
    if (!normalizedRole) return new Set();

    const effective = PermissionService.defaultPermissionsForRole(normalizedRole);

    if (normalizedRole === Rol.gerente) {
      return effective;
    }

    let overrides: Array<{ permiso: string; permitido: boolean }> = [];

    try {
      overrides = await this.prisma.permisoRol.findMany({
        where: { empresaId, rol: normalizedRole },
        select: { permiso: true, permitido: true },
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2021"
      ) {
        return effective;
      }

      throw error;
    }

    for (const override of overrides) {
      if (!PermissionService.isValidPermission(override.permiso)) continue;
      if (override.permitido) {
        effective.add(override.permiso);
      } else {
        effective.delete(override.permiso);
      }
    }

    return effective;
  }

  async getEffectivePermissionsForUser(params: {
    userId: string;
    role: string | Rol;
    empresaId?: string | null;
  }): Promise<{ empresaId: string; permissions: string[] }> {
    const normalizedRole = normalizeRole(params.role);
    if (!normalizedRole) {
      return { empresaId: "", permissions: [] };
    }

    const empresaId = params.empresaId?.trim() || (await this.resolveEmpresaIdForUser(params.userId, normalizedRole));
    const permissions = await this.getEffectivePermissionsForRole(empresaId, normalizedRole);

    return {
      empresaId,
      permissions: [...permissions].sort(),
    };
  }

  async getPermissionMatrix(empresaId: string) {
    const matrix: Record<string, Record<string, boolean>> = {};

    for (const role of ROLE_ORDER) {
      const effective = await this.getEffectivePermissionsForRole(empresaId, role);
      matrix[role] = {};
      for (const item of PERMISSION_CATALOG) {
        matrix[role][item.key] = effective.has(item.key);
      }
    }

    const modules = new Map<string, { key: string; label: string; permissions: PermissionDefinition[] }>();
    for (const item of PERMISSION_CATALOG) {
      if (!modules.has(item.module)) {
        modules.set(item.module, {
          key: item.module,
          label: item.moduleLabel,
          permissions: [],
        });
      }
      modules.get(item.module)?.permissions.push({ ...item });
    }

    return {
      roles: ROLE_ORDER,
      managedRoles: MANAGED_ROLE_ORDER,
      modules: [...modules.values()],
      matrix,
    };
  }

  async replacePermissionMatrix(empresaId: string, input: PermissionMatrixInput) {
    const payloadRoles = Object.keys(input)
      .map((role) => normalizeRole(role))
      .filter((role): role is Rol => role != null && role !== Rol.gerente);

    if (payloadRoles.length === 0) {
      throw new Error("No se recibieron roles validos para actualizar permisos.");
    }

    const uniqueRoles = [...new Set(payloadRoles)];

    await this.prisma.$transaction(async (tx) => {
      try {
        await tx.permisoRol.deleteMany({
          where: {
            empresaId,
            rol: { in: uniqueRoles },
          },
        });
      } catch (error) {
        if (
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === "P2021"
        ) {
          throw new Error(
            "La tabla de permisos aun no existe en la base de datos. Ejecuta las migraciones del backend antes de usar esta pantalla.",
          );
        }

        throw error;
      }

      const rows: Array<{ empresaId: string; rol: Rol; permiso: string; permitido: boolean }> = [];

      for (const role of uniqueRoles) {
        const defaults = PermissionService.defaultPermissionsForRole(role);
        const roleMatrix = input[role] ?? {};

        for (const item of PERMISSION_CATALOG) {
          const rawValue = roleMatrix[item.key];
          const value = rawValue == null ? defaults.has(item.key) : rawValue === true;
          const defaultValue = defaults.has(item.key);

          if (value !== defaultValue) {
            rows.push({
              empresaId,
              rol: role,
              permiso: item.key,
              permitido: value,
            });
          }
        }
      }

      if (rows.length > 0) {
        try {
          await tx.permisoRol.createMany({ data: rows });
        } catch (error) {
          if (
            error instanceof Prisma.PrismaClientKnownRequestError &&
            error.code === "P2021"
          ) {
            throw new Error(
              "La tabla de permisos aun no existe en la base de datos. Ejecuta las migraciones del backend antes de guardar cambios.",
            );
          }

          throw error;
        }
      }
    });

    return this.getPermissionMatrix(empresaId);
  }
}
