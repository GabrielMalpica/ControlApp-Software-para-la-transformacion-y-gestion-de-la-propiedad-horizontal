import { Prisma, Rol, type PrismaClient } from "@prisma/client";
import { cached, cacheDelete } from "./RedisService";

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
  Rol.residente,
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
    key: "cronograma.correctivas_programar",
    module: "cronograma",
    moduleLabel: "Cronogramas",
    label: "Programar correctivas en cronograma",
    description:
      "Permite crear y programar tareas correctivas directamente desde la vista semanal del cronograma.",
  },
  {
    key: "cronograma.excluidas_ver",
    module: "cronograma",
    moduleLabel: "Cronogramas",
    label: "Ver excluidas en cronograma",
    description:
      "Permite consultar las preventivas excluidas en standby desde la agenda semanal del cronograma.",
  },
  {
    key: "solicitudes.ver",
    module: "solicitudes",
    moduleLabel: "Solicitudes",
    label: "Ver solicitudes",
    description: "Permite consultar solicitudes de tareas, insumos y maquinaria.",
  },
  {
    key: "solicitudes.crear",
    module: "solicitudes",
    moduleLabel: "Solicitudes",
    label: "Crear solicitudes",
    description: "Permite solicitar tareas, insumos, maquinaria y herramientas.",
  },
  {
    key: "solicitudes.gestionar",
    module: "solicitudes",
    moduleLabel: "Solicitudes",
    label: "Gestionar solicitudes",
    description: "Permite aprobar, rechazar, editar o eliminar solicitudes.",
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
    key: "maquinaria.asignar",
    module: "maquinaria",
    moduleLabel: "Maquinaria",
    label: "Asignar maquinaria al cronograma",
    description:
      "Permite asignar y liberar máquinas concretas sobre las necesidades del cronograma.",
  },
  {
    key: "herramientas.ver",
    module: "herramientas",
    moduleLabel: "Herramientas",
    label: "Ver agenda de herramientas",
    description: "Permite consultar la agenda y disponibilidad de herramientas.",
  },
  {
    key: "empresa.gestionar",
    module: "empresa",
    moduleLabel: "Empresa",
    label: "Gestionar empresa",
    description: "Permite modificar la configuracion general de la empresa.",
  },
  {
    key: "usuarios.gestionar",
    module: "usuarios",
    moduleLabel: "Usuarios",
    label: "Gestionar usuarios",
    description: "Permite crear, editar, asignar roles y retirar usuarios de la empresa.",
  },
  {
    key: "conjuntos.ver",
    module: "conjuntos",
    moduleLabel: "Conjuntos",
    label: "Ver conjuntos",
    description: "Permite consultar el listado y el detalle de los conjuntos de la empresa.",
  },
  {
    key: "conjuntos.gestionar",
    module: "conjuntos",
    moduleLabel: "Conjuntos",
    label: "Gestionar conjuntos",
    description: "Permite crear, editar y eliminar conjuntos de la empresa.",
  },
  {
    key: "inventario.gestionar",
    module: "inventario",
    moduleLabel: "Inventario",
    label: "Gestionar inventario",
    description: "Permite modificar catalogos y existencias de inventario.",
  },
  {
    key: "herramientas.gestionar",
    module: "herramientas",
    moduleLabel: "Herramientas",
    label: "Gestionar herramientas",
    description: "Permite crear herramientas y ajustar sus existencias.",
  },
  {
    key: "mapa_areas.ver",
    module: "mapa_areas",
    moduleLabel: "Mapa de areas",
    label: "Ver mapa de areas",
    description: "Permite consultar el mapa e informacion visual del conjunto.",
  },
  {
    key: "mapa_areas.gestionar",
    module: "mapa_areas",
    moduleLabel: "Mapa de areas",
    label: "Gestionar mapa de areas",
    description: "Permite cargar el plano y modificar ubicaciones o areas.",
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
  {
    key: "residentes.ver",
    module: "residentes",
    moduleLabel: "Residentes",
    label: "Ver residentes",
    description: "Permite consultar y listar residentes por conjunto.",
  },
  {
    key: "residentes.crear",
    module: "residentes",
    moduleLabel: "Residentes",
    label: "Crear residentes manualmente",
    description: "Permite registrar residentes individuales y generar su acceso inicial.",
  },
  {
    key: "residentes.editar",
    module: "residentes",
    moduleLabel: "Residentes",
    label: "Editar residentes",
    description: "Permite actualizar datos y estado de residentes existentes.",
  },
  {
    key: "residentes.eliminar",
    module: "residentes",
    moduleLabel: "Residentes",
    label: "Eliminar residentes",
    description: "Permite eliminar residentes y sus credenciales asociadas.",
  },
  {
    key: "residentes.cargar_masivo",
    module: "residentes",
    moduleLabel: "Residentes",
    label: "Cargar residentes masivamente",
    description: "Permite importar residentes desde archivos Excel o CSV y generar reportes de fallos.",
  },
  {
    key: "plan_esperanza.acceso",
    module: "plan_esperanza",
    moduleLabel: "Plan Esperanza",
    label: "Acceder a Plan Esperanza",
    description: "Permite ver, iniciar y completar diagnosticos del Plan Esperanza.",
  },
  {
    key: "plan_esperanza.configurar",
    module: "plan_esperanza",
    moduleLabel: "Plan Esperanza",
    label: "Configurar periodicidad",
    description: "Permite cambiar el intervalo de meses del Plan Esperanza.",
  },
];

const ALL_PERMISSION_KEYS = new Set(PERMISSION_CATALOG.map((item) => item.key));

// Un permiso de accion incluye el acceso de lectura minimo necesario para
// poder ejecutar esa accion. La matriz conserva los interruptores separados:
// desactivar "ver" sigue ocultando el modulo si tampoco hay una accion activa.
const PERMISSIONS_THAT_GRANT_ACCESS: Readonly<Record<string, readonly string[]>> = {
  "tareas.ver": ["tareas.crear", "tareas.cerrar", "tareas.veredicto"],
  "cronograma.ver": [
    "cronograma.imprimir",
    "cronograma.publicar",
    "cronograma.eliminar_publicado",
    "cronograma.correctivas_programar",
    "cronograma.excluidas_ver",
  ],
  "solicitudes.ver": ["solicitudes.crear", "solicitudes.gestionar"],
  "inventario.ver": ["inventario.gestionar"],
  "maquinaria.ver": ["maquinaria.asignar"],
  "herramientas.ver": ["herramientas.gestionar"],
  "conjuntos.ver": ["conjuntos.gestionar"],
  "mapa_areas.ver": ["mapa_areas.gestionar"],
  "compromisos.ver": ["compromisos.gestionar"],
  "residentes.ver": [
    "residentes.crear",
    "residentes.editar",
    "residentes.eliminar",
    "residentes.cargar_masivo",
  ],
  "plan_esperanza.acceso": ["plan_esperanza.configurar"],
};

const DEFAULT_PERMISSIONS_BY_ROLE: Record<Rol, Set<string>> = {
  [Rol.gerente]: new Set(PERMISSION_CATALOG.map((item) => item.key)),
  [Rol.administrador]: new Set([
    "residentes.ver",
    "solicitudes.crear",
    "cronograma.ver",
    "inventario.ver",
    "mapa_areas.ver",
    "compromisos.ver",
    "compromisos.gestionar",
    "reportes.ver",
    "cumpleanos.ver",
    "residentes.crear",
    "residentes.editar",
    "residentes.eliminar",
    "residentes.cargar_masivo",
  ]),
  [Rol.jefe_operaciones]: new Set([
    "conjuntos.ver",
    "tareas.ver",
    "tareas.cerrar",
    "tareas.veredicto",
    "cronograma.ver",
    "cronograma.imprimir",
    "solicitudes.ver",
    "solicitudes.crear",
    "solicitudes.gestionar",
    "inventario.ver",
    "inventario.gestionar",
    "maquinaria.ver",
    "maquinaria.asignar",
    "herramientas.ver",
    "herramientas.gestionar",
    "mapa_areas.ver",
    "mapa_areas.gestionar",
    "compromisos.ver",
    "compromisos.gestionar",
    "compromisos.globales_ver",
    "cumpleanos.ver",
  ]),
  [Rol.supervisor]: new Set([
    "conjuntos.ver",
    "tareas.crear",
    "tareas.ver",
    "tareas.cerrar",
    "cronograma.ver",
    "cronograma.imprimir",
    "cronograma.correctivas_programar",
    "solicitudes.ver",
    "solicitudes.crear",
    "inventario.ver",
    "maquinaria.ver",
    "herramientas.ver",
    "mapa_areas.ver",
    "compromisos.ver",
    "compromisos.gestionar",
    "compromisos.globales_ver",
    "reportes.ver",
    "plan_esperanza.acceso",
  ]),
  [Rol.operario]: new Set([
    "tareas.ver",
    "tareas.cerrar",
    "solicitudes.ver",
    "solicitudes.crear",
    "mapa_areas.ver",
    "cumpleanos.ver",
  ]),
  [Rol.residente]: new Set([
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

export class PermissionService {
  constructor(private prisma: PrismaClient) {}

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

  static hasAnyPermission(
    effectivePermissions: ReadonlySet<string>,
    requiredPermissions: readonly string[],
  ): boolean {
    return requiredPermissions.some((required) => {
      if (effectivePermissions.has(required)) return true;
      return (PERMISSIONS_THAT_GRANT_ACCESS[required] ?? []).some((grant) =>
        effectivePermissions.has(grant),
      );
    });
  }

  static defaultPermissionsForRole(role: Rol): Set<string> {
    return new Set(DEFAULT_PERMISSIONS_BY_ROLE[role] ?? []);
  }

  async resolveEmpresaIdForUser(userId: string, role: string | Rol): Promise<string> {
    const normalizedRole = normalizeRole(role);
    if (!normalizedRole) {
      throw new Error("El rol del usuario no es valido para resolver permisos.");
    }

    // La empresa de un usuario practicamente nunca cambia entre requests; se
    // resolvia con una consulta a BD en cada request (varias veces por
    // request: auth, tenant scope, permisos). Se cachea 60s.
    return cached(
      `empresa:usuario:v1:${userId}:${normalizedRole}`,
      60,
      () => this._resolveEmpresaIdForUser(userId, normalizedRole),
    );
  }

  private async _resolveEmpresaIdForUser(userId: string, normalizedRole: Rol): Promise<string> {
    switch (normalizedRole) {
      case Rol.gerente: {
        const gerente = await this.prisma.gerente.findUnique({
          where: { id: userId },
          select: { empresaId: true },
        });
        return ensureEmpresaId(gerente?.empresaId);
      }
      case Rol.jefe_operaciones: {
        const jefe = await this.prisma.jefeOperaciones.findUnique({
          where: { id: userId },
          select: { empresaId: true },
        });
        return ensureEmpresaId(jefe?.empresaId);
      }
      case Rol.supervisor: {
        const supervisor = await this.prisma.supervisor.findUnique({
          where: { id: userId },
          select: { empresaId: true },
        });
        return ensureEmpresaId(supervisor?.empresaId);
      }
      case Rol.operario: {
        const operario = await this.prisma.operario.findUnique({
          where: { id: userId },
          select: { empresaId: true },
        });
        return ensureEmpresaId(operario?.empresaId);
      }
      case Rol.administrador: {
        const conjunto = await this.prisma.conjunto.findFirst({
          where: { administradorId: userId },
          select: { empresaId: true },
          orderBy: { nit: "asc" },
        });
        return ensureEmpresaId(conjunto?.empresaId);
      }
      case Rol.residente: {
        const residente = await this.prisma.residente.findUnique({
          where: { id: userId },
          select: { conjunto: { select: { empresaId: true } } },
        });
        return ensureEmpresaId(residente?.conjunto?.empresaId);
      }
    }
  }

  async getEffectivePermissionsForRole(empresaId: string, role: string | Rol): Promise<Set<string>> {
    const normalizedRole = normalizeRole(role);
    if (!normalizedRole) return new Set();

    if (normalizedRole === Rol.gerente) {
      return PermissionService.defaultPermissionsForRole(normalizedRole);
    }

    // permisoRol cambia rarisimo (solo via replacePermissionMatrix) pero se
    // consultaba en cada request autenticado; se cachea 60s y se invalida
    // explicitamente al guardar cambios.
    const effectiveArray = await cached(
      `permisos:rol:v1:${empresaId}:${normalizedRole}`,
      60,
      async () => [...(await this._getEffectivePermissionsForRole(empresaId, normalizedRole))],
    );

    return new Set(effectiveArray);
  }

  private async _getEffectivePermissionsForRole(
    empresaId: string,
    normalizedRole: Rol,
  ): Promise<Set<string>> {
    const effective = PermissionService.defaultPermissionsForRole(normalizedRole);

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

    await cacheDelete(
      ...uniqueRoles.map((role) => `permisos:rol:v1:${empresaId}:${role}`),
    );

    return this.getPermissionMatrix(empresaId);
  }
}
