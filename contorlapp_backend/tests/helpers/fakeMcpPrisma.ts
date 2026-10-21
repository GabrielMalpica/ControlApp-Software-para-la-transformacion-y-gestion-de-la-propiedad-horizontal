// Prisma en memoria con lo justo para el flujo OAuth + MCP de las pruebas.
// Soporta filtros por igualdad, `null`, `{ in: [...] }`, `{ lt }` y
// `{ contains }`, que es lo que usan los modulos del MCP.
import { randomUUID } from "crypto";

type Fila = Record<string, any>;

function coincide(fila: Fila, where: Fila | undefined): boolean {
  if (!where) return true;
  return Object.entries(where).every(([clave, condicion]) => {
    if (clave === "OR") return (condicion as Fila[]).some((w) => coincide(fila, w));
    if (clave === "AND") return (condicion as Fila[]).every((w) => coincide(fila, w));
    const valor = fila[clave];
    if (condicion === null) return valor === null || valor === undefined;
    if (condicion instanceof Date) return valor instanceof Date && valor.getTime() === condicion.getTime();
    if (typeof condicion === "object") {
      if ("in" in condicion) return (condicion.in as unknown[]).includes(valor);
      if ("lt" in condicion) return valor < condicion.lt;
      if ("contains" in condicion) {
        return String(valor ?? "").toLowerCase().includes(String(condicion.contains).toLowerCase());
      }
      if ("equals" in condicion) {
        return String(valor ?? "").toLowerCase() === String(condicion.equals).toLowerCase();
      }
      return coincide(valor ?? {}, condicion);
    }
    return valor === condicion;
  });
}

function tabla(clave: string, filas: Fila[] = []) {
  return {
    filas,
    async create({ data }: { data: Fila }) {
      const fila = { id: data.id ?? randomUUID(), creadoEn: new Date(), creadaEn: new Date(), ...data };
      filas.push(fila);
      return fila;
    },
    async findUnique({ where }: { where: Fila }) {
      return filas.find((f) => coincide(f, where)) ?? null;
    },
    async findFirst({ where }: { where?: Fila } = {}) {
      return filas.find((f) => coincide(f, where)) ?? null;
    },
    async findMany({ where }: { where?: Fila } = {}) {
      return filas.filter((f) => coincide(f, where));
    },
    async count({ where }: { where?: Fila } = {}) {
      return filas.filter((f) => coincide(f, where)).length;
    },
    async update({ where, data }: { where: Fila; data: Fila }) {
      const fila = filas.find((f) => coincide(f, where));
      if (!fila) throw new Error(`${clave}: no encontrado`);
      Object.assign(fila, data, { actualizadaEn: new Date() });
      return fila;
    },
    async updateMany({ where, data }: { where?: Fila; data: Fila }) {
      const afectadas = filas.filter((f) => coincide(f, where));
      for (const fila of afectadas) Object.assign(fila, data);
      return { count: afectadas.length };
    },
    async delete({ where }: { where: Fila }) {
      const i = filas.findIndex((f) => coincide(f, where));
      if (i < 0) throw new Error(`${clave}: no encontrado`);
      return filas.splice(i, 1)[0];
    },
    async deleteMany({ where }: { where?: Fila } = {}) {
      let n = 0;
      for (let i = filas.length - 1; i >= 0; i--) {
        if (coincide(filas[i], where)) {
          filas.splice(i, 1);
          n++;
        }
      }
      return { count: n };
    },
  };
}

export type SemillaMcp = {
  usuarios?: Array<{ id: string; nombre: string; correo?: string; rol: string; activo?: boolean }>;
  gerentes?: Array<{ id: string; empresaId: string | null; mcpHabilitado: boolean }>;
  conjuntos?: Array<{ nit: string; nombre: string; empresaId: string; activo?: boolean; administradorId?: string | null }>;
};

export function crearFakeMcpPrisma(semilla: SemillaMcp = {}) {
  const usuarios = tabla("usuario", (semilla.usuarios ?? []).map((u) => ({ activo: true, ...u })));
  const gerentes = tabla("gerente", (semilla.gerentes ?? []).map((g) => ({ ...g })));
  const conjuntos = tabla(
    "conjunto",
    (semilla.conjuntos ?? []).map((c) => ({
      activo: true,
      direccion: "Calle 1",
      tipoServicio: [],
      administradorId: null,
      ...c,
      _count: { operarios: 0 },
    })),
  );
  const conexiones = tabla("mcpConexion");
  const refresh = tabla("mcpRefreshToken");
  const notificaciones: Fila[] = [];

  const prisma: any = {
    usuario: {
      ...usuarios,
      async findUnique({ where }: { where: Fila }) {
        const u = usuarios.filas.find((f) => coincide(f, where));
        if (!u) return null;
        return { ...u, gerente: gerentes.filas.find((g) => g.id === u.id) ?? null };
      },
    },
    gerente: gerentes,
    conjunto: conjuntos,
    configuracionSistema: tabla("configuracionSistema"),
    permisoRol: tabla("permisoRol"),
    mcpSolicitudAutorizacion: tabla("mcpSolicitudAutorizacion"),
    mcpConexion: {
      ...conexiones,
      async upsert({ where, create, update }: { where: any; create: Fila; update: Fila }) {
        const clave = where.usuarioId_clienteId;
        const existente = conexiones.filas.find(
          (c) => c.usuarioId === clave.usuarioId && c.clienteId === clave.clienteId,
        );
        if (existente) {
          Object.assign(existente, update);
          return existente;
        }
        return conexiones.create({ data: { estado: "ACTIVA", ultimoUsoEn: null, ...create } });
      },
    },
    mcpCodigoAutorizacion: tabla("mcpCodigoAutorizacion"),
    mcpRefreshToken: {
      ...refresh,
      async findUnique({ where, include, select }: { where: Fila; include?: Fila; select?: Fila }) {
        const fila = refresh.filas.find((f) => coincide(f, where));
        if (!fila) return null;
        const conexion =
          include?.conexion || select?.conexion
            ? conexiones.filas.find((c) => c.id === fila.conexionId)
            : undefined;
        return { ...fila, ...(conexion ? { conexion } : {}) };
      },
    },
    mcpClienteRegistrado: tabla("mcpClienteRegistrado"),
    mcpInvocacion: tabla("mcpInvocacion"),
    mcpConfirmacion: tabla("mcpConfirmacion"),
    auditoriaEvento: tabla("auditoriaEvento"),
    compromisoConjunto: tabla("compromisoConjunto"),
    async $executeRaw() {
      notificaciones.push({ en: new Date() });
      return 1;
    },
    async $queryRaw() {
      return [{ "?column?": 1 }];
    },
    async $transaction(fn: any) {
      return typeof fn === "function" ? fn(prisma) : Promise.all(fn);
    },
    _notificaciones: notificaciones,
  };
  return prisma;
}
