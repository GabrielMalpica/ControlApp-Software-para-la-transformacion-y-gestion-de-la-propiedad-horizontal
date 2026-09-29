import { Prisma } from "@prisma/client";

/**
 * Prisma "de mentira" para PagoCobro/PagoEvento: solo lo que PagoService usa
 * (create, findFirst, findUnique[OrThrow], findMany, update, updateMany,
 * $transaction con rollback real si el callback lanza). No reemplaza una
 * prueba de integracion contra Postgres -en particular no reproduce el
 * candado de pg_advisory_xact_lock-, pero permite probar la logica de
 * PagoService (backoff, duplicados, huerfanos, rollback) sin una base real.
 */

type Row = Record<string, any>;

function esOperador(valor: unknown): valor is Record<string, unknown> {
  return (
    valor != null &&
    typeof valor === "object" &&
    !(valor instanceof Date) &&
    !(valor instanceof Prisma.Decimal)
  );
}

function mismoValor(a: unknown, b: unknown): boolean {
  if (a instanceof Prisma.Decimal || b instanceof Prisma.Decimal) {
    if (a == null || b == null) return a == null && b == null;
    return new Prisma.Decimal(a as Prisma.Decimal.Value).equals(new Prisma.Decimal(b as Prisma.Decimal.Value));
  }
  if (a instanceof Date || b instanceof Date) {
    if (a == null || b == null) return a == null && b == null;
    return new Date(a as Date).getTime() === new Date(b as Date).getTime();
  }
  return a === b;
}

function cumpleCondicion(valorFila: unknown, condicion: unknown): boolean {
  if (condicion === undefined) return true;
  if (!esOperador(condicion)) return mismoValor(valorFila, condicion);
  const cond = condicion as Record<string, unknown>;
  if ("not" in cond) return !mismoValor(valorFila, cond.not);
  if ("in" in cond) return (cond.in as unknown[]).some((v) => mismoValor(valorFila, v));
  if ("notIn" in cond) return !(cond.notIn as unknown[]).some((v) => mismoValor(valorFila, v));
  if ("lte" in cond) return valorFila != null && (valorFila as any) <= (cond.lte as any);
  if ("lt" in cond) return valorFila != null && (valorFila as any) < (cond.lt as any);
  if ("gt" in cond) return valorFila != null && (valorFila as any) > (cond.gt as any);
  if ("gte" in cond) return valorFila != null && (valorFila as any) >= (cond.gte as any);
  return mismoValor(valorFila, condicion);
}

function cumpleWhere(fila: Row, where: Record<string, unknown> = {}): boolean {
  return Object.entries(where).every(([clave, condicion]) => {
    if (condicion === undefined) return true;
    if (clave === "OR") {
      return (condicion as Record<string, unknown>[]).some((sub) => cumpleWhere(fila, sub));
    }
    return cumpleCondicion(fila[clave], condicion);
  });
}

function aplicarData(fila: Row, data: Record<string, unknown>): Row {
  const nueva = { ...fila };
  for (const [clave, valor] of Object.entries(data)) {
    if (valor && typeof valor === "object" && "increment" in (valor as Record<string, unknown>)) {
      nueva[clave] = (nueva[clave] ?? 0) + (valor as { increment: number }).increment;
    } else {
      nueva[clave] = valor;
    }
  }
  if (!("actualizadoEn" in data)) nueva.actualizadoEn = new Date();
  return nueva;
}

function ordenar(filas: Row[], orderBy?: Record<string, "asc" | "desc">) {
  if (!orderBy) return filas;
  const [[clave, direccion]] = Object.entries(orderBy);
  const signo = direccion === "desc" ? -1 : 1;
  return [...filas].sort((a, b) => {
    const va = a[clave];
    const vb = b[clave];
    if (va == null && vb == null) return 0;
    if (va == null) return -1 * signo;
    if (vb == null) return 1 * signo;
    if (va > vb) return signo;
    if (va < vb) return -signo;
    return 0;
  });
}

function proyectar(fila: Row, select?: Record<string, boolean>) {
  if (!select) return { ...fila };
  const out: Row = {};
  for (const clave of Object.keys(select)) out[clave] = fila[clave];
  return out;
}

export function crearFakePagosPrisma() {
  let cobros: Row[] = [];
  let eventos: Row[] = [];
  let nextCobroId = 1;
  let nextEventoId = 1;

  function snapshot() {
    return { cobros: cobros.map((f) => ({ ...f })), eventos: eventos.map((f) => ({ ...f })) };
  }
  function restaurar(foto: { cobros: Row[]; eventos: Row[] }) {
    cobros = foto.cobros;
    eventos = foto.eventos;
  }

  function crearApi(): any {
    return {
      pagoCobro: {
        create: async ({ data }: { data: Row }) => {
          const ahora = new Date();
          const fila: Row = {
            id: nextCobroId++,
            proveedor: "factus",
            estado: "CREADO",
            moneda: "COP",
            montoProveedor: null,
            estadoProveedor: null,
            qrBase64: null,
            expiraLocalEn: null,
            proximaVerificacion: null,
            intentosVerificacion: 0,
            lockedUntil: null,
            pagadoDetectadoEn: null,
            pendienteSincronizarWoo: false,
            pedidoAppId: null,
            wooOrderId: null,
            usuarioId: null,
            creadoEn: ahora,
            actualizadoEn: ahora,
            ...data,
          };
          cobros.push(fila);
          return { ...fila };
        },
        findFirst: async ({ where, orderBy }: { where?: Row; orderBy?: Row }) => {
          const encontrados = ordenar(
            cobros.filter((f) => cumpleWhere(f, where)),
            orderBy,
          );
          return encontrados[0] ? { ...encontrados[0] } : null;
        },
        findMany: async ({ where, orderBy, take, select }: { where?: Row; orderBy?: Row; take?: number; select?: Row }) => {
          let filas = ordenar(
            cobros.filter((f) => cumpleWhere(f, where)),
            orderBy,
          );
          if (typeof take === "number") filas = filas.slice(0, take);
          return filas.map((f) => proyectar(f, select));
        },
        findUnique: async ({ where }: { where: { id: number } }) => {
          const fila = cobros.find((f) => f.id === where.id);
          return fila ? { ...fila } : null;
        },
        findUniqueOrThrow: async ({ where }: { where: { id: number } }) => {
          const fila = cobros.find((f) => f.id === where.id);
          if (!fila) throw new Error(`PagoCobro ${where.id} no existe`);
          return { ...fila };
        },
        update: async ({ where, data }: { where: { id: number }; data: Row }) => {
          const idx = cobros.findIndex((f) => f.id === where.id);
          if (idx === -1) throw new Error(`PagoCobro ${where.id} no existe`);
          cobros[idx] = aplicarData(cobros[idx], data);
          return { ...cobros[idx] };
        },
        updateMany: async ({ where, data }: { where?: Row; data: Row }) => {
          let count = 0;
          cobros = cobros.map((f) => {
            if (!cumpleWhere(f, where)) return f;
            count++;
            return aplicarData(f, data);
          });
          return { count };
        },
      },
      pagoEvento: {
        create: async ({ data }: { data: Row }) => {
          const fila = { id: nextEventoId++, creadoEn: new Date(), ...data };
          eventos.push(fila);
          return { ...fila };
        },
      },
      $executeRaw: async () => 0,
      $transaction: async (callback: (tx: any) => Promise<unknown>) => {
        const foto = snapshot();
        try {
          return await callback(crearApi());
        } catch (error) {
          restaurar(foto);
          throw error;
        }
      },
      _debug: {
        cobros: () => cobros.map((f) => ({ ...f })),
        eventos: () => eventos.map((f) => ({ ...f })),
      },
    };
  }

  return crearApi();
}
