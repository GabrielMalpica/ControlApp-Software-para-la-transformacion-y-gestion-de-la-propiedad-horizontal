import express from "express";
import request from "supertest";

const listarCompromisosMock = jest.fn((_req: any, res: any) =>
  res.json([{ id: 1, titulo: "Compromiso visible" }]),
);
const roleGateExecutionMock = jest.fn();
let mockGrantedPermission = "compromisos.ver";

jest.mock("../../src/controller/GerenteController", () => ({
  GerenteController: jest.fn().mockImplementation(
    () =>
      new Proxy(
        {},
        {
          get: () => (_req: any, res: any) => res.status(204).end(),
        },
      ),
  ),
}));

jest.mock("../../src/controller/CompromisoConjuntoController", () => ({
  CompromisoConjuntoController: jest.fn().mockImplementation(() => ({
    listarPorConjunto: listarCompromisosMock,
    listarGlobal: (_req: any, res: any) => res.json([]),
    crear: (_req: any, res: any) => res.status(201).json({}),
    actualizar: (_req: any, res: any) => res.json({}),
    eliminar: (_req: any, res: any) => res.json({ ok: true }),
  })),
}));

jest.mock("../../src/controller/EmpresaController", () => ({
  EmpresaController: jest.fn().mockImplementation(
    () =>
      new Proxy(
        {},
        {
          get: () => (_req: any, res: any) => res.status(204).end(),
        },
      ),
  ),
}));

jest.mock("../../src/controller/HerramientaStockController", () => ({
  HerramientaStockController: jest.fn().mockImplementation(
    () =>
      new Proxy(
        {},
        {
          get: () => (_req: any, res: any) => res.status(204).end(),
        },
      ),
  ),
}));

jest.mock("../../src/middlewares/auth.middleware", () => ({
  authRequired: (req: any, _res: any, next: any) => {
    req.user = {
      sub: "jefe-1",
      rol: "jefe_operaciones",
      empresaId: "EMP-1",
    };
    next();
  },
}));

jest.mock("../../src/middlewares/permission.middleware", () => ({
  requirePermission:
    (...permissions: string[]) =>
    (_req: any, res: any, next: any) => {
      if (permissions.includes(mockGrantedPermission)) {
        next();
        return;
      }
      res.status(403).json({ message: "Bloqueado por permiso" });
    },
}));

jest.mock("../../src/middlewares/role.middleware", () => ({
  requireRoles: () => (_req: any, res: any, _next: any) => {
    roleGateExecutionMock();
    res.status(403).json({ message: "Bloqueado por rol fijo" });
  },
}));

jest.mock("../../src/middlewares/tenant.middleware", () => ({
  requireConjuntoScope: () => (_req: any, _res: any, next: any) => next(),
  requireEmpresaScope: () => (_req: any, _res: any, next: any) => next(),
  requireResourceScope: () => (_req: any, _res: any, next: any) => next(),
}));

import EmpresaRoutes from "../../src/routes/Empresa";
import GerenteRoutes from "../../src/routes/Gerente";
import HerramientaStockRoutes from "../../src/routes/HerramientaStock";

describe("Enrutado dinamico de permisos", () => {
  beforeEach(() => {
    listarCompromisosMock.mockClear();
    roleGateExecutionMock.mockClear();
    mockGrantedPermission = "compromisos.ver";
  });

  test("un jefe con permiso llega a compromisos aunque la URL historica sea /gerente", async () => {
    const app = express();
    app.use(express.json());
    app.use("/gerente", GerenteRoutes);

    const response = await request(app).get(
      "/gerente/conjuntos/CONJ-1/compromisos",
    );

    expect(response.status).toBe(200);
    expect(response.body).toEqual([
      { id: 1, titulo: "Compromiso visible" },
    ]);
    expect(listarCompromisosMock).toHaveBeenCalledTimes(1);
    expect(roleGateExecutionMock).not.toHaveBeenCalled();
  });

  test("el permiso de programar correctivas habilita los datos auxiliares del formulario", async () => {
    mockGrantedPermission = "cronograma.correctivas_programar";
    const app = express();
    app.use(express.json());
    app.use("/gerente", GerenteRoutes);
    app.use("/empresa", EmpresaRoutes);
    app.use("/herramientas", HerramientaStockRoutes);

    const responses = await Promise.all([
      request(app).get("/gerente/conjuntos/CONJ-1"),
      request(app).get("/gerente/supervisores"),
      request(app).get("/empresa/EMP-1/maquinaria/disponible"),
      request(app).get("/herramientas/conjunto/CONJ-1/disponibles"),
    ]);

    expect(responses.map((response) => response.status)).toEqual([
      204,
      204,
      204,
      204,
    ]);
    expect(roleGateExecutionMock).not.toHaveBeenCalled();
  });
});
