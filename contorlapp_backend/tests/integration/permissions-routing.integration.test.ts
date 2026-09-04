import express from "express";
import request from "supertest";

const listarCompromisosMock = jest.fn((_req: any, res: any) =>
  res.json([{ id: 1, titulo: "Compromiso visible" }]),
);
const roleGateExecutionMock = jest.fn();

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
  requirePermission: () => (_req: any, _res: any, next: any) => next(),
}));

jest.mock("../../src/middlewares/role.middleware", () => ({
  requireRoles: () => (_req: any, res: any, _next: any) => {
    roleGateExecutionMock();
    res.status(403).json({ message: "Bloqueado por rol fijo" });
  },
}));

jest.mock("../../src/middlewares/tenant.middleware", () => ({
  requireConjuntoScope: () => (_req: any, _res: any, next: any) => next(),
  requireResourceScope: () => (_req: any, _res: any, next: any) => next(),
}));

import GerenteRoutes from "../../src/routes/Gerente";

describe("Enrutado dinamico de permisos", () => {
  beforeEach(() => {
    listarCompromisosMock.mockClear();
    roleGateExecutionMock.mockClear();
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
});
