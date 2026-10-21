// El administrador (cliente dueño de sus conjuntos) solo ve sus conjuntos en
// reportes y asistencia; el equipo interno ve toda la empresa.
jest.mock("../../src/db/prisma", () => ({ prisma: {} }));
jest.mock("../../src/middlewares/tenant.middleware", () => ({
  empresaIdAutenticada: jest.fn(async () => "EMP-1"),
}));
jest.mock("../../src/services/RedisService", () => ({
  ...jest.requireActual("../../src/services/RedisService"),
  cached: (_clave: string, _ttl: number, loader: () => Promise<unknown>) => loader(),
}));
jest.mock("../../src/services/InformeMensualService", () => ({
  crearEjecutorInforme: jest.fn(() => jest.fn()),
}));
jest.mock("../../src/services/InformeMensualJobs", () => ({
  informeMensualJobs: {
    iniciar: jest.fn(() => ({
      id: "job-1",
      estado: "EN_COLA",
      progreso: 0,
      mensaje: null,
      error: null,
      nombreArchivo: "",
    })),
    posicionEnCola: jest.fn(() => 0),
  },
}));

import { prisma } from "../../src/db/prisma";
import {
  alcanceConjuntos,
  exigirConjuntoEnAlcance,
} from "../../src/aplicacion/alcanceConjuntos";
import { ReporteController } from "../../src/controller/ReporteController";
import { AsistenciaController } from "../../src/controller/AsistenciaController";
import { crearEjecutorInforme } from "../../src/services/InformeMensualService";
import { informeMensualJobs } from "../../src/services/InformeMensualJobs";

const CONJUNTOS = [
  { nit: "C-ADMIN-1", empresaId: "EMP-1", administradorId: "adm-1" },
  { nit: "C-ADMIN-2", empresaId: "EMP-1", administradorId: "adm-1" },
  { nit: "C-OTRO", empresaId: "EMP-1", administradorId: "adm-2" },
];
const PROPIOS = ["C-ADMIN-1", "C-ADMIN-2"];
const TODOS = CONJUNTOS.map((c) => c.nit);

const db = prisma as any;

function prepararPrisma() {
  for (const key of Object.keys(db)) delete db[key];
  Object.assign(db, {
    conjunto: {
      findMany: jest.fn(async ({ where }: any) =>
        CONJUNTOS.filter(
          (c) =>
            c.empresaId === where.empresaId &&
            (where.administradorId === undefined || c.administradorId === where.administradorId),
        ).map((c) => ({ nit: c.nit })),
      ),
      findFirst: jest.fn(async ({ where }: any) => {
        const c = CONJUNTOS.find((x) => x.nit === where.nit && x.empresaId === where.empresaId);
        return c ? { nit: c.nit } : null;
      }),
    },
    residente: {
      findFirst: jest.fn(async () => ({ conjuntoId: "C-OTRO" })),
    },
    tarea: { groupBy: jest.fn().mockResolvedValue([]) },
    compromisoConjunto: { findMany: jest.fn().mockResolvedValue([]) },
    visitaSupervisor: { findMany: jest.fn().mockResolvedValue([]) },
    conceptoAsistencia: { count: jest.fn().mockResolvedValue(1), createMany: jest.fn() },
    operario: { findMany: jest.fn().mockResolvedValue([]) },
    registroAsistencia: { findMany: jest.fn().mockResolvedValue([]) },
    festivo: { findMany: jest.fn().mockResolvedValue([]) },
    $queryRaw: jest.fn().mockResolvedValue([]),
  });
}

function usuario(rol: string, sub: string) {
  return { sub, rol, empresaId: "EMP-1" };
}

async function llamar(handler: any, req: { user: any; query?: any; body?: any }) {
  const res: any = {
    statusCode: 200,
    body: undefined as unknown,
    status: jest.fn(function (this: any, code: number) {
      res.statusCode = code;
      return res;
    }),
    json: jest.fn((body: unknown) => {
      res.body = body;
      return res;
    }),
    setHeader: jest.fn(),
    send: jest.fn(),
  };
  const next = jest.fn();
  await handler({ query: {}, body: {}, params: {}, ...req }, res, next);
  const error = next.mock.calls[0]?.[0];
  return { res, error };
}

const RANGO = { desde: "2026-09-01", hasta: "2026-09-30" };
const PERIODO = { anio: "2026", mes: "9" };

beforeEach(() => {
  prepararPrisma();
});

describe("alcanceConjuntos", () => {
  test("administrador: solo los conjuntos que administra dentro de su empresa", async () => {
    const alcance = await alcanceConjuntos(db, {
      usuarioId: "adm-1",
      rol: "administrador",
      empresaId: "EMP-1",
    });
    expect(alcance).toEqual(PROPIOS);
    expect(db.conjunto.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { administradorId: "adm-1", empresaId: "EMP-1" } }),
    );
  });

  test.each(["gerente", "jefe_operaciones", "supervisor", "operario"])(
    "%s: sin restricción dentro de la empresa",
    async (rol) => {
      const alcance = await alcanceConjuntos(db, { usuarioId: "u-1", rol, empresaId: "EMP-1" });
      expect(alcance).toBeNull();
      expect(db.conjunto.findMany).not.toHaveBeenCalled();
    },
  );

  test("residente: solo su conjunto; rol desconocido: ninguno", async () => {
    await expect(
      alcanceConjuntos(db, { usuarioId: "res-1", rol: "residente", empresaId: "EMP-1" }),
    ).resolves.toEqual(["C-OTRO"]);
    await expect(
      alcanceConjuntos(db, { usuarioId: "x", rol: "invitado", empresaId: "EMP-1" }),
    ).resolves.toEqual([]);
  });

  test("un conjunto fuera del alcance responde 404; sin conjunto o sin restricción pasa", () => {
    expect(() => exigirConjuntoEnAlcance(PROPIOS, "C-OTRO")).toThrow(
      expect.objectContaining({ status: 404, message: "Recurso no encontrado" }),
    );
    expect(() => exigirConjuntoEnAlcance(PROPIOS, "C-ADMIN-2")).not.toThrow();
    expect(() => exigirConjuntoEnAlcance(PROPIOS, undefined)).not.toThrow();
    expect(() => exigirConjuntoEnAlcance(null, "C-OTRO")).not.toThrow();
  });
});

describe("Reportes por alcance", () => {
  const c = new ReporteController();

  test("administrador sin conjunto: los KPIs cuentan solo sus conjuntos", async () => {
    const { error } = await llamar(c.kpis, {
      user: usuario("administrador", "adm-1"),
      query: RANGO,
    });
    expect(error).toBeUndefined();
    const where = db.tarea.groupBy.mock.calls[0][0].where;
    expect(where.conjuntoId).toEqual({ in: PROPIOS });
  });

  test("administrador con un conjunto ajeno: 404 sin consultar tareas", async () => {
    const { error } = await llamar(c.kpis, {
      user: usuario("administrador", "adm-1"),
      query: { ...RANGO, conjuntoId: "C-OTRO" },
    });
    expect(error).toMatchObject({ status: 404, message: "Recurso no encontrado" });
    expect(db.tarea.groupBy).not.toHaveBeenCalled();
  });

  test("administrador con un conjunto propio: filtra por ese conjunto", async () => {
    await llamar(c.kpis, {
      user: usuario("administrador", "adm-1"),
      query: { ...RANGO, conjuntoId: "C-ADMIN-2" },
    });
    expect(db.tarea.groupBy.mock.calls[0][0].where.conjuntoId).toBe("C-ADMIN-2");
  });

  test("administrador sin conjunto: compromisos (consulta directa) también se limitan", async () => {
    await llamar(c.compromisosDashboard, {
      user: usuario("administrador", "adm-1"),
      query: RANGO,
    });
    const where = db.compromisoConjunto.findMany.mock.calls[0][0].where;
    expect(where.conjuntoId).toEqual({ in: PROPIOS });
    expect(where.conjunto).toEqual({ empresaId: "EMP-1" });
  });

  test("gerente sin conjunto: toda la empresa; con cualquier conjunto de la empresa: permitido", async () => {
    await llamar(c.kpis, { user: usuario("gerente", "ger-1"), query: RANGO });
    expect(db.tarea.groupBy.mock.calls[0][0].where.conjuntoId).toEqual({ in: TODOS });

    const { error } = await llamar(c.kpis, {
      user: usuario("gerente", "ger-1"),
      query: { ...RANGO, conjuntoId: "C-OTRO" },
    });
    expect(error).toBeUndefined();
    expect(db.tarea.groupBy.mock.calls[1][0].where.conjuntoId).toBe("C-OTRO");

    await llamar(c.compromisosDashboard, { user: usuario("gerente", "ger-1"), query: RANGO });
    expect(db.compromisoConjunto.findMany.mock.calls[0][0].where).not.toHaveProperty("conjuntoId");
  });

  test("informe PDF del administrador sin conjunto: se arma solo con sus conjuntos", async () => {
    const { res, error } = await llamar(c.iniciarInformeMensualPdf, {
      user: usuario("administrador", "adm-1"),
      body: RANGO,
    });
    expect(error).toBeUndefined();
    expect(res.statusCode).toBe(202);
    expect(crearEjecutorInforme).toHaveBeenCalledWith(
      expect.objectContaining({ empresaId: "EMP-1", alcance: PROPIOS, conjuntoId: undefined }),
    );
    // La clave de deduplicación distingue el alcance.
    const { clave } = (informeMensualJobs.iniciar as jest.Mock).mock.calls[0][0];
    expect(clave).toContain(PROPIOS.join(","));
  });

  test("informe PDF del administrador con un conjunto ajeno: 404", async () => {
    const { error } = await llamar(c.iniciarInformeMensualPdf, {
      user: usuario("administrador", "adm-1"),
      body: { ...RANGO, conjuntoId: "C-OTRO" },
    });
    expect(error).toMatchObject({ status: 404 });
    expect(informeMensualJobs.iniciar).not.toHaveBeenCalled();
  });

  test("informe PDF del gerente sin conjunto: toda la empresa", async () => {
    await llamar(c.iniciarInformeMensualPdf, { user: usuario("gerente", "ger-1"), body: RANGO });
    expect(crearEjecutorInforme).toHaveBeenCalledWith(expect.objectContaining({ alcance: null }));
  });
});

describe("Asistencia por alcance", () => {
  const c = new AsistenciaController();

  test("administrador sin conjunto: el grid trae solo operarios de sus conjuntos", async () => {
    const { error } = await llamar(c.getGrid, {
      user: usuario("administrador", "adm-1"),
      query: PERIODO,
    });
    expect(error).toBeUndefined();
    const args = db.operario.findMany.mock.calls[0][0];
    expect(args.where.empresaId).toBe("EMP-1");
    expect(args.where.AND).toContainEqual({
      OR: [
        { conjuntos: { some: { nit: { in: PROPIOS }, activo: true } } },
        {
          registrosAsistencia: {
            some: { conjuntoId: { in: PROPIOS }, fecha: expect.any(Object) },
          },
        },
      ],
    });
    // Tampoco ve los nombres de conjuntos de otros clientes.
    expect(args.select.conjuntos.where).toEqual({ activo: true, nit: { in: PROPIOS } });
  });

  test("administrador con un conjunto ajeno: 404 en grid, resumen, visitas y exportar", async () => {
    for (const handler of [c.getGrid, c.getResumen, c.getVisitasSupervisores, c.exportarExcel]) {
      const { error } = await llamar(handler, {
        user: usuario("administrador", "adm-1"),
        query: { ...PERIODO, conjuntoId: "C-OTRO" },
      });
      expect(error).toMatchObject({ status: 404, message: "Recurso no encontrado" });
    }
    expect(db.operario.findMany).not.toHaveBeenCalled();
    expect(db.visitaSupervisor.findMany).not.toHaveBeenCalled();
  });

  test("administrador sin conjunto: visitas de supervisores solo en sus conjuntos", async () => {
    await llamar(c.getVisitasSupervisores, {
      user: usuario("administrador", "adm-1"),
      query: PERIODO,
    });
    const where = db.visitaSupervisor.findMany.mock.calls[0][0].where;
    expect(where.conjuntoId).toEqual({ in: PROPIOS });
    expect(where.supervisor).toEqual({ empresaId: "EMP-1" });
  });

  test("gerente sin conjunto: grid y visitas de toda la empresa, como antes", async () => {
    await llamar(c.getGrid, { user: usuario("gerente", "ger-1"), query: PERIODO });
    const args = db.operario.findMany.mock.calls[0][0];
    expect(args.where.AND).toHaveLength(2);
    expect(args.select.conjuntos.where).toEqual({ activo: true });

    await llamar(c.getVisitasSupervisores, { user: usuario("gerente", "ger-1"), query: PERIODO });
    expect(db.visitaSupervisor.findMany.mock.calls[0][0].where).not.toHaveProperty("conjuntoId");
  });
});
