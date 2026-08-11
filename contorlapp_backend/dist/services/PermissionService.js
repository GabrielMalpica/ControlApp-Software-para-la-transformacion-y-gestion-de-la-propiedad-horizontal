"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PermissionService = void 0;
const client_1 = require("@prisma/client");
const ROLE_ORDER = [
    client_1.Rol.gerente,
    client_1.Rol.administrador,
    client_1.Rol.jefe_operaciones,
    client_1.Rol.supervisor,
    client_1.Rol.operario,
    client_1.Rol.residente,
];
const MANAGED_ROLE_ORDER = ROLE_ORDER.filter((rol) => rol !== client_1.Rol.gerente);
const PERMISSION_CATALOG = [
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
        description: "Permite crear y programar tareas correctivas directamente desde la vista semanal del cronograma.",
    },
    {
        key: "cronograma.excluidas_ver",
        module: "cronograma",
        moduleLabel: "Cronogramas",
        label: "Ver excluidas en cronograma",
        description: "Permite consultar las preventivas excluidas en standby desde la agenda semanal del cronograma.",
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
        key: "maquinaria.asignar",
        module: "maquinaria",
        moduleLabel: "Maquinaria",
        label: "Asignar maquinaria al cronograma",
        description: "Permite asignar y liberar máquinas concretas sobre las necesidades del cronograma.",
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
const DEFAULT_PERMISSIONS_BY_ROLE = {
    [client_1.Rol.gerente]: new Set(PERMISSION_CATALOG.map((item) => item.key)),
    [client_1.Rol.administrador]: new Set([
        "residentes.ver",
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
    [client_1.Rol.jefe_operaciones]: new Set([
        "tareas.ver",
        "tareas.cerrar",
        "tareas.veredicto",
        "cronograma.ver",
        "cronograma.imprimir",
        "solicitudes.ver",
        "inventario.ver",
        "inventario.gestionar",
        "maquinaria.ver",
        "maquinaria.asignar",
        "herramientas.ver",
        "herramientas.gestionar",
        "mapa_areas.ver",
        "compromisos.ver",
        "compromisos.gestionar",
        "compromisos.globales_ver",
        "cumpleanos.ver",
    ]),
    [client_1.Rol.supervisor]: new Set([
        "tareas.crear",
        "tareas.ver",
        "tareas.cerrar",
        "cronograma.ver",
        "cronograma.imprimir",
        "cronograma.correctivas_programar",
        "solicitudes.ver",
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
    [client_1.Rol.operario]: new Set([
        "tareas.ver",
        "tareas.cerrar",
        "solicitudes.ver",
        "mapa_areas.ver",
        "cumpleanos.ver",
    ]),
    [client_1.Rol.residente]: new Set([]),
};
function normalizeRole(value) {
    const role = String(value ?? "").trim().toLowerCase();
    return ROLE_ORDER.find((item) => item === role) ?? null;
}
function ensureEmpresaId(value) {
    const empresaId = String(value ?? "").trim();
    if (!empresaId) {
        throw new Error("No se pudo resolver la empresa para consultar permisos.");
    }
    return empresaId;
}
class PermissionService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    static roleOrder() {
        return [...ROLE_ORDER];
    }
    static managedRoles() {
        return [...MANAGED_ROLE_ORDER];
    }
    static catalog() {
        return PERMISSION_CATALOG.map((item) => ({ ...item }));
    }
    static isValidPermission(permission) {
        return ALL_PERMISSION_KEYS.has(permission);
    }
    static defaultPermissionsForRole(role) {
        return new Set(DEFAULT_PERMISSIONS_BY_ROLE[role] ?? []);
    }
    async resolveEmpresaIdForUser(userId, role) {
        const normalizedRole = normalizeRole(role);
        if (!normalizedRole) {
            throw new Error("El rol del usuario no es valido para resolver permisos.");
        }
        switch (normalizedRole) {
            case client_1.Rol.gerente: {
                const gerente = await this.prisma.gerente.findUnique({
                    where: { id: userId },
                    select: { empresaId: true },
                });
                return ensureEmpresaId(gerente?.empresaId);
            }
            case client_1.Rol.jefe_operaciones: {
                const jefe = await this.prisma.jefeOperaciones.findUnique({
                    where: { id: userId },
                    select: { empresaId: true },
                });
                return ensureEmpresaId(jefe?.empresaId);
            }
            case client_1.Rol.supervisor: {
                const supervisor = await this.prisma.supervisor.findUnique({
                    where: { id: userId },
                    select: { empresaId: true },
                });
                return ensureEmpresaId(supervisor?.empresaId);
            }
            case client_1.Rol.operario: {
                const operario = await this.prisma.operario.findUnique({
                    where: { id: userId },
                    select: { empresaId: true },
                });
                return ensureEmpresaId(operario?.empresaId);
            }
            case client_1.Rol.administrador: {
                const conjunto = await this.prisma.conjunto.findFirst({
                    where: { administradorId: userId },
                    select: { empresaId: true },
                    orderBy: { nit: "asc" },
                });
                return ensureEmpresaId(conjunto?.empresaId);
            }
            case client_1.Rol.residente: {
                const residente = await this.prisma.residente.findUnique({
                    where: { id: userId },
                    select: { conjunto: { select: { empresaId: true } } },
                });
                return ensureEmpresaId(residente?.conjunto?.empresaId);
            }
        }
    }
    async getEffectivePermissionsForRole(empresaId, role) {
        const normalizedRole = normalizeRole(role);
        if (!normalizedRole)
            return new Set();
        const effective = PermissionService.defaultPermissionsForRole(normalizedRole);
        if (normalizedRole === client_1.Rol.gerente) {
            return effective;
        }
        let overrides = [];
        try {
            overrides = await this.prisma.permisoRol.findMany({
                where: { empresaId, rol: normalizedRole },
                select: { permiso: true, permitido: true },
            });
        }
        catch (error) {
            if (error instanceof client_1.Prisma.PrismaClientKnownRequestError &&
                error.code === "P2021") {
                return effective;
            }
            throw error;
        }
        for (const override of overrides) {
            if (!PermissionService.isValidPermission(override.permiso))
                continue;
            if (override.permitido) {
                effective.add(override.permiso);
            }
            else {
                effective.delete(override.permiso);
            }
        }
        return effective;
    }
    async getEffectivePermissionsForUser(params) {
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
    async getPermissionMatrix(empresaId) {
        const matrix = {};
        for (const role of ROLE_ORDER) {
            const effective = await this.getEffectivePermissionsForRole(empresaId, role);
            matrix[role] = {};
            for (const item of PERMISSION_CATALOG) {
                matrix[role][item.key] = effective.has(item.key);
            }
        }
        const modules = new Map();
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
    async replacePermissionMatrix(empresaId, input) {
        const payloadRoles = Object.keys(input)
            .map((role) => normalizeRole(role))
            .filter((role) => role != null && role !== client_1.Rol.gerente);
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
            }
            catch (error) {
                if (error instanceof client_1.Prisma.PrismaClientKnownRequestError &&
                    error.code === "P2021") {
                    throw new Error("La tabla de permisos aun no existe en la base de datos. Ejecuta las migraciones del backend antes de usar esta pantalla.");
                }
                throw error;
            }
            const rows = [];
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
                }
                catch (error) {
                    if (error instanceof client_1.Prisma.PrismaClientKnownRequestError &&
                        error.code === "P2021") {
                        throw new Error("La tabla de permisos aun no existe en la base de datos. Ejecuta las migraciones del backend antes de guardar cambios.");
                    }
                    throw error;
                }
            }
        });
        return this.getPermissionMatrix(empresaId);
    }
}
exports.PermissionService = PermissionService;
