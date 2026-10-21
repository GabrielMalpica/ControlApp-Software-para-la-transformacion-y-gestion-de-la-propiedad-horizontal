// Panel "Integraciones IA": solo gerentes, revocar, reducir permisos y
// aprobar operaciones de alto riesgo de su propia conexion.
import express from "express";
import request from "supertest";

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));
jest.mock("../../src/middlewares/auth.middleware", () => ({
  authRequired: (req: any, _res: any, next: any) => {
    req.user = { sub: req.headers["x-usuario"], rol: req.headers["x-rol"], empresaId: "E-1" };
    next();
  },
}));

import integracionesRouter from "../../src/routes/IntegracionesIa";
import { IntegracionesIaService, type ActorPanel } from "../../src/services/IntegracionesIaService";
import { crearFakeMcpPrisma } from "../helpers/fakeMcpPrisma";

const gerente: ActorPanel = { id: "g-1", nombre: "Gabriela", empresaId: "E-1" };
const otroGerente: ActorPanel = { id: "g-2", nombre: "Gonzalo", empresaId: "E-1" };

async function semilla() {
  const prisma = crearFakeMcpPrisma();
  const propia = await prisma.mcpConexion.create({
    data: {
      id: "11111111-1111-4111-8111-111111111111",
      usuarioId: "g-1",
      empresaId: "E-1",
      clienteId: "https://claude.ai/x",
      clienteNombre: "Claude",
      scopes: ["conjuntos:read", "personal:read", "personal:write"],
      estado: "ACTIVA",
    },
  });
  const ajena = await prisma.mcpConexion.create({
    data: {
      id: "22222222-2222-4222-8222-222222222222",
      usuarioId: "x-9",
      empresaId: "E-2",
      clienteId: "https://chatgpt.com/oauth/client.json",
      clienteNombre: "ChatGPT",
      scopes: ["conjuntos:read"],
      estado: "ACTIVA",
    },
  });
  await prisma.mcpRefreshToken.create({ data: { conexionId: propia.id, tokenHash: "h", revocadoEn: null } });
  await prisma.mcpConfirmacion.create({
    data: {
      id: "33333333-3333-4333-8333-333333333333",
      conexionId: propia.id,
      usuarioId: "g-1",
      empresaId: "E-1",
      estado: "PENDIENTE_APROBACION",
      resumen: "Publicar cronograma",
      expiraEn: new Date(Date.now() + 60_000),
    },
  });
  return { prisma, propia, ajena, service: new IntegracionesIaService(prisma) };
}

describe("panel de integraciones IA", () => {
  test("revocar corta refresh tokens y confirmaciones pendientes, y se audita", async () => {
    const { prisma, propia, service } = await semilla();
    await service.revocar(otroGerente, propia.id);
    expect(prisma.mcpConexion.filas[0]).toMatchObject({ estado: "REVOCADA", revocadaPorId: "g-2" });
    expect(prisma.mcpRefreshToken.filas[0].revocadoEn).toBeInstanceOf(Date);
    expect(prisma.mcpConfirmacion.filas[0].estado).toBe("RECHAZADA");
    expect(prisma.auditoriaEvento.filas[0]).toMatchObject({ accion: "MCP_REVOCAR", modulo: "SEGURIDAD" });
  });

  test("una conexion de otra empresa no existe para este gerente", async () => {
    const { ajena, service } = await semilla();
    await expect(service.revocar(gerente, ajena.id)).rejects.toMatchObject({ status: 404 });
  });

  test("solo se pueden quitar permisos, y solo quien autorizo", async () => {
    const { propia, service } = await semilla();
    await expect(service.reducirPermisos(otroGerente, propia.id, ["conjuntos:read"])).rejects.toMatchObject({ status: 403 });
    await expect(service.reducirPermisos(gerente, propia.id, ["conjuntos:read", "cronograma:publicar"])).rejects.toMatchObject({
      status: 400,
    });
    const out = await service.reducirPermisos(gerente, propia.id, ["conjuntos:read"]);
    expect(out.permisos).toEqual(["conjuntos:read"]);
  });

  test("aprobar habilita la confirmacion 15 minutos; otro gerente no puede decidir", async () => {
    const { prisma, service } = await semilla();
    const id = "33333333-3333-4333-8333-333333333333";
    await expect(service.decidir(otroGerente, id, "aprobar")).rejects.toMatchObject({ status: 404 });
    await service.decidir(gerente, id, "aprobar");
    expect(prisma.mcpConfirmacion.filas[0].estado).toBe("APROBADA");
    expect(prisma.mcpConfirmacion.filas[0].expiraEn.getTime()).toBeGreaterThan(Date.now() + 14 * 60_000);
    await expect(service.decidir(gerente, id, "rechazar")).rejects.toMatchObject({ status: 409 });
  });

  test.each(["administrador", "jefe_operaciones", "supervisor", "operario", "residente"])(
    "el rol %s no entra al panel",
    async (rol) => {
      const app = express();
      app.use(express.json());
      app.use("/integraciones-ia", integracionesRouter);
      const res = await request(app).get("/integraciones-ia/conexiones").set("x-usuario", "u-1").set("x-rol", rol);
      expect(res.status).toBe(403);
    },
  );
});
