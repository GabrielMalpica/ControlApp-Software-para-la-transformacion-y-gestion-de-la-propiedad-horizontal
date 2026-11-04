// Sesion larga de la app Android: token de renovacion en el cuerpo (no en
// cookie), ventanas propias del canal "app", rutas /auth/refresh-app y
// recuperacion cuando la respuesta de una renovacion se pierde por mala senal.
import express from "express";
import request from "supertest";

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));

import authRouter from "../../src/routes/auth";
import { authRequiredUnlessPublic } from "../../src/middlewares/auth.middleware";
import { AuthService } from "../../src/services/authService";
import {
  crearSesionRefresh,
  hashToken,
  inactividadMs,
  rotarSesionRefresh,
  vidaMaximaMs,
} from "../../src/services/SesionService";

beforeAll(() => {
  process.env.JWT_SECRET = "secreto-de-pruebas";
});

afterEach(() => {
  jest.restoreAllMocks();
  delete process.env.SESION_APP_INACTIVIDAD_DIAS;
  delete process.env.SESION_APP_MAX_DIAS;
});

function filaRefresh(parcial: Record<string, unknown> = {}) {
  const ahora = Date.now();
  return {
    id: "r-1",
    familiaId: "fam-1",
    usuarioId: "u-1",
    tokenHash: hashToken("token-actual"),
    versionSesion: 0,
    creadoEn: new Date(ahora - 60_000),
    expiraEn: new Date(ahora + 3_600_000),
    familiaExpiraEn: new Date(ahora + 86_400_000),
    usadoEn: null as Date | null,
    revocadoEn: null as Date | null,
    canal: "app",
    usuario: { activo: true, versionSesion: 0 },
    ...parcial,
  };
}

function dbRefresh(fila: ReturnType<typeof filaRefresh> | null, sucesor: { id: string } | null = null) {
  const db: any = {
    sesionRefresh: {
      findUnique: jest.fn(async () => fila),
      findFirst: jest.fn(async () => sucesor),
      updateMany: jest.fn(async () => ({ count: 1 })),
      deleteMany: jest.fn(async () => ({ count: 0 })),
      create: jest.fn(async ({ data }: any) => data),
    },
  };
  db.$transaction = jest.fn(async (fn: any) => fn(db));
  return db;
}

describe("ventanas del canal app", () => {
  test("por defecto: 30 dias sin uso y 90 dias en total; la web sigue igual", () => {
    expect(inactividadMs("app")).toBe(30 * 86_400_000);
    expect(vidaMaximaMs("app")).toBe(90 * 86_400_000);
    expect(inactividadMs("web")).toBe(24 * 3_600_000);
    expect(vidaMaximaMs("web")).toBe(7 * 86_400_000);
  });

  test("se configuran por variables y quedan acotadas", () => {
    process.env.SESION_APP_INACTIVIDAD_DIAS = "500";
    process.env.SESION_APP_MAX_DIAS = "0";
    expect(inactividadMs("app")).toBe(90 * 86_400_000);
    expect(vidaMaximaMs("app")).toBe(1 * 86_400_000);
  });

  test("crear una sesion de la app guarda el canal y la vence en 30 dias", async () => {
    const db = dbRefresh(null);
    const antes = Date.now();
    const out = await crearSesionRefresh(db, { usuarioId: "u-1", versionSesion: 0, canal: "app" });
    const data = db.sesionRefresh.create.mock.calls[0][0].data;
    expect(data.canal).toBe("app");
    expect(out.expiraEn.getTime()).toBeGreaterThanOrEqual(antes + 30 * 86_400_000 - 1_000);
  });
});

describe("rotacion del token de la app", () => {
  test("rota y conserva el canal", async () => {
    const db = dbRefresh(filaRefresh());
    const out = await rotarSesionRefresh(db, "token-actual", null, "app");
    expect(out.token).not.toBe("token-actual");
    expect(db.sesionRefresh.create.mock.calls[0][0].data.canal).toBe("app");
  });

  test("un token de la web no sirve en la ruta de la app (ni al reves)", async () => {
    await expect(
      rotarSesionRefresh(dbRefresh(filaRefresh({ canal: "web" })), "token-actual", null, "app"),
    ).rejects.toMatchObject({ status: 401 });
    await expect(
      rotarSesionRefresh(dbRefresh(filaRefresh({ canal: "app" })), "token-actual", null, "web"),
    ).rejects.toMatchObject({ status: 401 });
  });

  test("respuesta perdida: si el sucesor nunca se uso, se reemplaza en vez de cerrar la sesion", async () => {
    const db = dbRefresh(filaRefresh({ usadoEn: new Date(Date.now() - 2 * 60_000) }), { id: "r-2" });
    const out = await rotarSesionRefresh(db, "token-actual", null, "app");
    expect(out.usuarioId).toBe("u-1");
    expect(db.sesionRefresh.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "r-2", usadoEn: null, revocadoEn: null },
        data: expect.objectContaining({ motivoRevocacion: "RESPUESTA_PERDIDA" }),
      }),
    );
    expect(db.sesionRefresh.create.mock.calls[0][0].data).toMatchObject({
      familiaId: "fam-1",
      tokenHash: hashToken(out.token),
      canal: "app",
    });
  });

  test("si el sucesor ya se uso, es un reuso: se revoca la familia", async () => {
    const db = dbRefresh(filaRefresh({ usadoEn: new Date(Date.now() - 2 * 60_000) }), null);
    await expect(rotarSesionRefresh(db, "token-actual", null, "app")).rejects.toMatchObject({
      status: 401,
    });
    expect(db.sesionRefresh.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { familiaId: "fam-1", revocadoEn: null },
        data: expect.objectContaining({ motivoRevocacion: "REUSO_DETECTADO" }),
      }),
    );
  });

  test("pasados 10 minutos ya no hay recuperacion", async () => {
    const db = dbRefresh(filaRefresh({ usadoEn: new Date(Date.now() - 11 * 60_000) }), { id: "r-2" });
    await expect(rotarSesionRefresh(db, "token-actual", null, "app")).rejects.toMatchObject({
      status: 401,
    });
    expect(db.sesionRefresh.findFirst).not.toHaveBeenCalled();
  });

  test("en la web no aplica la recuperacion", async () => {
    const db = dbRefresh(
      filaRefresh({ canal: "web", usadoEn: new Date(Date.now() - 2 * 60_000) }),
      { id: "r-2" },
    );
    await expect(rotarSesionRefresh(db, "token-actual", null, "web")).rejects.toMatchObject({
      status: 401,
    });
    expect(db.sesionRefresh.findFirst).not.toHaveBeenCalled();
  });
});

/* --------------------------------- rutas ---------------------------------- */

function appAuth() {
  const app = express();
  app.use(express.json());
  app.use(authRequiredUnlessPublic);
  app.use("/auth", authRouter);
  app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    res
      .status(typeof err?.status === "number" ? err.status : 500)
      .json({ message: err?.message, code: err?.code });
  });
  return app;
}

function sesionFalsa(canal: "web" | "app" | undefined) {
  return {
    token: "jwt-de-acceso",
    tokenExpiraEn: new Date("2026-11-05T00:00:00.000Z"),
    user: { id: "u-1", nombre: "Operario", rol: "operario" } as any,
    refresh: canal ? { token: "refresh-largo-de-la-app-123456", expiraEn: new Date("2026-12-05T00:00:00.000Z") } : undefined,
    canal,
  };
}

describe("rutas de la sesion de la app", () => {
  test("login con sesionApp devuelve el token de renovacion en el cuerpo y sin cookie", async () => {
    const login = jest
      .spyOn(AuthService.prototype, "login")
      .mockResolvedValue(sesionFalsa("app") as any);
    const res = await request(appAuth())
      .post("/auth/login")
      .send({ correo: "op@test.com", contrasena: "x", sesionApp: true });
    expect(res.status).toBe(200);
    expect(login.mock.calls[0][2]).toMatchObject({ sesionApp: true, sesionWeb: false });
    expect(res.body.refreshToken).toBe("refresh-largo-de-la-app-123456");
    expect(res.body.refreshExpiraEn).toBe("2026-12-05T00:00:00.000Z");
    expect(res.body.sesionWeb).toBe(false);
    expect(res.headers["set-cookie"]).toBeUndefined();
  });

  test("login web sigue sin exponer el token de renovacion en el cuerpo", async () => {
    jest.spyOn(AuthService.prototype, "login").mockResolvedValue(sesionFalsa("web") as any);
    const res = await request(appAuth())
      .post("/auth/login")
      .send({ correo: "g@test.com", contrasena: "x", sesionWeb: true });
    expect(res.body.refreshToken).toBeUndefined();
    expect(res.body.sesionWeb).toBe(true);
    expect(String(res.headers["set-cookie"] ?? "")).toContain("ca_sesion=");
  });

  test("refresh-app es publica, no pide Origin y devuelve el token nuevo", async () => {
    const refrescar = jest
      .spyOn(AuthService.prototype, "refrescarSesionApp")
      .mockResolvedValue(sesionFalsa("app") as any);
    const res = await request(appAuth())
      .post("/auth/refresh-app")
      .send({ refreshToken: "refresh-largo-de-la-app-anterior" });
    expect(res.status).toBe(200);
    expect(refrescar.mock.calls[0][0]).toBe("refresh-largo-de-la-app-anterior");
    expect(res.body.token).toBe("jwt-de-acceso");
    expect(res.body.refreshToken).toBe("refresh-largo-de-la-app-123456");
  });

  test("refresh-app sin token pide iniciar sesion", async () => {
    const res = await request(appAuth()).post("/auth/refresh-app").send({});
    expect(res.status).toBe(401);
    expect(res.body.code).toBe("SESION_INVALIDA");
  });
});
