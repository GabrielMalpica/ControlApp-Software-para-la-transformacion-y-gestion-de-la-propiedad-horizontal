// Sesiones seguras (auditoria de seguridad S1, S2, S3, S4, S12): JWT con
// emisor/audiencia/algoritmo fijos, estado de sesion contrastado con la BD,
// contrasena temporal obligatoria del lado del servidor, cookie de renovacion
// rotativa con deteccion de reuso y restablecimiento con jerarquia de roles.
import bcrypt from "bcrypt";
import express from "express";
import jwt from "jsonwebtoken";
import request from "supertest";

const estadoSesionMock = jest.fn();

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));
jest.mock("../../src/services/SesionService", () => ({
  ...jest.requireActual("../../src/services/SesionService"),
  estadoSesionUsuario: (...args: unknown[]) => estadoSesionMock(...args),
}));

import { authRequiredUnlessPublic } from "../../src/middlewares/auth.middleware";
import authRouter from "../../src/routes/auth";
import { AuthService } from "../../src/services/authService";
import {
  hashToken,
  motivoSesionInvalida,
  rotarSesionRefresh,
} from "../../src/services/SesionService";
import {
  JWT_AUDIENCIA,
  JWT_EMISOR,
  firmarTokenSesion,
  verificarTokenSesion,
} from "../../src/utils/jwtSesion";

const SECRETO = "secreto-de-pruebas";

beforeAll(() => {
  process.env.JWT_SECRET = SECRETO;
});

beforeEach(() => {
  estadoSesionMock.mockReset();
});

function tokenDe(datos: Partial<{ rol: string; versionSesion: number }> = {}) {
  return firmarTokenSesion(
    {
      usuarioId: "u-1",
      rol: datos.rol ?? "gerente",
      correo: "u1@test.com",
      empresaId: "E-1",
      versionSesion: datos.versionSesion ?? 0,
    },
    600,
  ).token;
}

function estado(parcial: Partial<{
  activo: boolean;
  rol: string;
  versionSesion: number;
  requiereCambioContrasena: boolean;
}> = {}) {
  return {
    activo: true,
    rol: "gerente",
    versionSesion: 0,
    requiereCambioContrasena: false,
    ...parcial,
  };
}

function appProtegida() {
  const app = express();
  app.use(express.json());
  app.use(authRequiredUnlessPublic);
  app.get("/recurso", (_req, res) => {
    res.json({ ok: true });
  });
  app.get("/auth/me", (_req, res) => {
    res.json({ ok: true });
  });
  return app;
}

describe("JWT de sesion", () => {
  test("lleva emisor, audiencia y version de sesion", () => {
    const payload = jwt.decode(tokenDe({ versionSesion: 3 })) as jwt.JwtPayload;
    expect(payload.iss).toBe(JWT_EMISOR);
    expect(payload.aud).toBe(JWT_AUDIENCIA);
    expect(payload.sv).toBe(3);
    expect(payload.jti).toEqual(expect.any(String));
  });

  test("rechaza tokens sin audiencia (formato anterior)", () => {
    const viejo = jwt.sign({ sub: "u-1", rol: "gerente", correo: "x@test.com" }, SECRETO);
    expect(() => verificarTokenSesion(viejo)).toThrow();
  });

  test("rechaza tokens emitidos para otra audiencia (p. ej. el futuro MCP)", () => {
    const otro = jwt.sign({ sub: "u-1", rol: "gerente" }, SECRETO, {
      issuer: JWT_EMISOR,
      audience: "https://mcp.example.com/mcp",
    });
    expect(() => verificarTokenSesion(otro)).toThrow();
  });

  test("rechaza alg none y firmas con otro secreto", () => {
    const sinFirma = jwt.sign({ sub: "u-1", rol: "gerente" }, "", {
      algorithm: "none",
      issuer: JWT_EMISOR,
      audience: JWT_AUDIENCIA,
    });
    const ajeno = jwt.sign({ sub: "u-1", rol: "gerente" }, "otro-secreto", {
      issuer: JWT_EMISOR,
      audience: JWT_AUDIENCIA,
    });
    expect(() => verificarTokenSesion(sinFirma)).toThrow();
    expect(() => verificarTokenSesion(ajeno)).toThrow();
  });
});

describe("estado de sesion contra la BD", () => {
  test("motivoSesionInvalida detecta usuario borrado, inactivo, cambio de rol y sesiones cerradas", () => {
    expect(motivoSesionInvalida({ rol: "gerente", sv: 0 }, null)).toMatch(/no existe/);
    expect(motivoSesionInvalida({ rol: "gerente", sv: 0 }, estado({ activo: false }))).toMatch(/inactivo/);
    expect(motivoSesionInvalida({ rol: "gerente", sv: 0 }, estado({ rol: "supervisor" }))).toMatch(/rol/);
    expect(motivoSesionInvalida({ rol: "gerente", sv: 0 }, estado({ versionSesion: 1 }))).toMatch(/sesión se cerró/);
    expect(motivoSesionInvalida({ rol: "gerente", sv: 2 }, estado({ versionSesion: 2 }))).toBeNull();
  });

  test("un token valido de un usuario desactivado ya no entra", async () => {
    estadoSesionMock.mockResolvedValue(estado({ activo: false }));
    const res = await request(appProtegida())
      .get("/recurso")
      .set("Authorization", `Bearer ${tokenDe()}`);
    expect(res.status).toBe(401);
    expect(res.body.code).toBe("SESION_INVALIDA");
  });

  test("un gerente degradado pierde el acceso aunque su token no haya vencido", async () => {
    estadoSesionMock.mockResolvedValue(estado({ rol: "operario" }));
    const res = await request(appProtegida())
      .get("/recurso")
      .set("Authorization", `Bearer ${tokenDe({ rol: "gerente" })}`);
    expect(res.status).toBe(401);
  });

  test("subir la version de sesion invalida los tokens emitidos antes", async () => {
    estadoSesionMock.mockResolvedValue(estado({ versionSesion: 1 }));
    const res = await request(appProtegida())
      .get("/recurso")
      .set("Authorization", `Bearer ${tokenDe({ versionSesion: 0 })}`);
    expect(res.status).toBe(401);
  });

  test("con la sesion vigente la peticion pasa", async () => {
    estadoSesionMock.mockResolvedValue(estado());
    const res = await request(appProtegida())
      .get("/recurso")
      .set("Authorization", `Bearer ${tokenDe()}`);
    expect(res.status).toBe(200);
  });

  test("token del formato anterior responde 401", async () => {
    const viejo = jwt.sign({ sub: "u-1", rol: "gerente", correo: "x@test.com" }, SECRETO);
    const res = await request(appProtegida()).get("/recurso").set("Authorization", `Bearer ${viejo}`);
    expect(res.status).toBe(401);
    expect(estadoSesionMock).not.toHaveBeenCalled();
  });
});

describe("contrasena temporal obligatoria en el servidor", () => {
  test("solo deja leer la sesion y cambiar la contrasena", async () => {
    estadoSesionMock.mockResolvedValue(estado({ requiereCambioContrasena: true }));
    const app = appProtegida();
    const token = tokenDe();

    const bloqueada = await request(app).get("/recurso").set("Authorization", `Bearer ${token}`);
    expect(bloqueada.status).toBe(403);
    expect(bloqueada.body.code).toBe("CAMBIO_CONTRASENA_REQUERIDO");

    const me = await request(app).get("/auth/me").set("Authorization", `Bearer ${token}`);
    expect(me.status).toBe(200);
  });
});

/* ------------------------------- AuthService ------------------------------- */

type FilaUsuario = {
  id: string;
  nombre: string;
  correo: string;
  contrasena: string;
  rol: string;
  activo: boolean;
  requiereCambioContrasena: boolean;
  versionSesion: number;
};

function dbFalsa(usuarios: FilaUsuario[]) {
  const porId = new Map(usuarios.map((u) => [u.id, u]));
  const db: any = {
    usuario: {
      findFirst: jest.fn(async ({ where }: any) =>
        usuarios.find((u) => u.correo.toLowerCase() === String(where.correo.equals).toLowerCase()) ?? null,
      ),
      findUnique: jest.fn(async ({ where }: any) => porId.get(where.id) ?? null),
      update: jest.fn(async ({ where, data }: any) => {
        const fila = porId.get(where.id)!;
        if (data.versionSesion?.increment) fila.versionSesion += data.versionSesion.increment;
        if (typeof data.requiereCambioContrasena === "boolean") {
          fila.requiereCambioContrasena = data.requiereCambioContrasena;
        }
        if (data.contrasena) fila.contrasena = data.contrasena;
        return { versionSesion: fila.versionSesion };
      }),
    },
    gerente: { findUnique: jest.fn(async () => ({ empresaId: "E-1" })) },
    jefeOperaciones: { findUnique: jest.fn(async () => ({ empresaId: "E-1" })) },
    operario: { findUnique: jest.fn(async () => ({ empresaId: "E-1" })) },
    supervisor: { findUnique: jest.fn(async () => ({ empresaId: "E-1" })) },
    permisoRol: { findMany: jest.fn(async () => []) },
    conjunto: { findFirst: jest.fn(async () => null) },
    sesionRefresh: {
      deleteMany: jest.fn(async () => ({ count: 0 })),
      create: jest.fn(async ({ data }: any) => data),
      updateMany: jest.fn(async () => ({ count: 1 })),
    },
    auditoriaEvento: { create: jest.fn(async () => ({})) },
  };
  db.$transaction = jest.fn(async (fn: any) => fn(db));
  return db;
}

async function usuario(parcial: Partial<FilaUsuario> & { id: string; rol: string }): Promise<FilaUsuario> {
  return {
    nombre: `Usuario ${parcial.id}`,
    correo: `${parcial.id}@test.com`,
    contrasena: await bcrypt.hash("clave-correcta", 4),
    activo: true,
    requiereCambioContrasena: false,
    versionSesion: 0,
    ...parcial,
  };
}

describe("login", () => {
  test("un usuario inactivo no inicia sesion aunque la contrasena sea correcta", async () => {
    const db = dbFalsa([await usuario({ id: "g-inactivo", rol: "gerente", activo: false })]);
    await expect(
      new AuthService(db).login("g-inactivo@test.com", "clave-correcta"),
    ).rejects.toMatchObject({ status: 403 });
  });

  test("la contrasena incorrecta sigue respondiendo credenciales invalidas", async () => {
    const db = dbFalsa([await usuario({ id: "g-mal", rol: "gerente", activo: false })]);
    await expect(new AuthService(db).login("g-mal@test.com", "otra")).rejects.toMatchObject({
      status: 401,
    });
  });

  test("la app movil recibe un token de 8 h con la version de sesion", async () => {
    const db = dbFalsa([await usuario({ id: "g-app", rol: "gerente", versionSesion: 4 })]);
    const sesion = await new AuthService(db).login("g-app@test.com", "clave-correcta");
    const payload = verificarTokenSesion(sesion.token);
    expect(payload.sv).toBe(4);
    expect((payload.exp ?? 0) - (payload.iat ?? 0)).toBe(8 * 60 * 60);
    expect(sesion.refresh).toBeUndefined();
    expect(db.sesionRefresh.create).not.toHaveBeenCalled();
  });

  test("la web recibe un token corto y una sesion de renovacion hasheada", async () => {
    const db = dbFalsa([await usuario({ id: "g-web", rol: "gerente" })]);
    const sesion = await new AuthService(db).login("g-web@test.com", "clave-correcta", {
      sesionWeb: true,
    });
    const payload = verificarTokenSesion(sesion.token);
    expect((payload.exp ?? 0) - (payload.iat ?? 0)).toBe(15 * 60);
    expect(sesion.refresh?.token).toEqual(expect.any(String));
    const guardado = db.sesionRefresh.create.mock.calls[0][0].data;
    expect(guardado.tokenHash).toBe(hashToken(sesion.refresh!.token));
    expect(JSON.stringify(guardado)).not.toContain(sesion.refresh!.token);
  });
});

describe("restablecer la contrasena de otro usuario", () => {
  test("un jefe con usuarios.gestionar no puede restablecer la de un gerente", async () => {
    const db = dbFalsa([
      await usuario({ id: "jefe-1", rol: "jefe_operaciones" }),
      await usuario({ id: "gerente-1", rol: "gerente" }),
    ]);
    await expect(
      new AuthService(db).cambiarContrasenaUsuarioPorGerente("jefe-1", "gerente-1", "nueva-segura-1"),
    ).rejects.toMatchObject({ status: 403 });
    expect(db.usuario.update).not.toHaveBeenCalled();
  });

  test("un jefe no puede restablecer la de otro jefe", async () => {
    const db = dbFalsa([
      await usuario({ id: "jefe-a", rol: "jefe_operaciones" }),
      await usuario({ id: "jefe-b", rol: "jefe_operaciones" }),
    ]);
    await expect(
      new AuthService(db).cambiarContrasenaUsuarioPorGerente("jefe-a", "jefe-b", "nueva-segura-1"),
    ).rejects.toMatchObject({ status: 403 });
  });

  test("al restablecer queda temporal, se cierran sus sesiones y se audita", async () => {
    const operario = await usuario({ id: "op-1", rol: "operario", versionSesion: 2 });
    const db = dbFalsa([await usuario({ id: "gerente-2", rol: "gerente" }), operario]);

    const out = await new AuthService(db).cambiarContrasenaUsuarioPorGerente(
      "gerente-2",
      "op-1",
      "nueva-segura-1",
      "E-1",
    );

    expect(out.ok).toBe(true);
    expect(operario.requiereCambioContrasena).toBe(true);
    expect(operario.versionSesion).toBe(3);
    expect(db.sesionRefresh.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { usuarioId: "op-1", revocadoEn: null } }),
    );
    const auditoria = db.auditoriaEvento.create.mock.calls[0][0].data;
    expect(auditoria).toMatchObject({
      modulo: "SEGURIDAD",
      entidadId: "op-1",
      accion: "RESTABLECER_CONTRASENA",
      actorId: "gerente-2",
    });
    expect(JSON.stringify(auditoria)).not.toContain("nueva-segura-1");
  });
});

describe("cambiar la propia contrasena", () => {
  test("cierra las demas sesiones y entrega una nueva a este dispositivo", async () => {
    const yo = await usuario({ id: "sup-1", rol: "supervisor", versionSesion: 5 });
    const db = dbFalsa([yo]);
    const sesion = await new AuthService(db).cambiarContrasena(
      "sup-1",
      "clave-correcta",
      "otra-clave-larga",
    );
    expect(yo.versionSesion).toBe(6);
    expect(verificarTokenSesion(sesion.token).sv).toBe(6);
  });
});

/* -------------------------- rotacion de la cookie -------------------------- */

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
    usuario: { activo: true, versionSesion: 0 },
    ...parcial,
  };
}

function dbRefresh(fila: ReturnType<typeof filaRefresh> | null) {
  const db: any = {
    sesionRefresh: {
      findUnique: jest.fn(async () => fila),
      updateMany: jest.fn(async () => ({ count: 1 })),
      create: jest.fn(async ({ data }: any) => data),
    },
  };
  db.$transaction = jest.fn(async (fn: any) => fn(db));
  return db;
}

describe("rotacion del token de renovacion", () => {
  test("cambia el token por otro de la misma familia y marca el anterior como usado", async () => {
    const db = dbRefresh(filaRefresh());
    const out = await rotarSesionRefresh(db, "token-actual");
    expect(out.usuarioId).toBe("u-1");
    expect(out.token).not.toBe("token-actual");
    expect(db.sesionRefresh.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: "r-1", usadoEn: null, revocadoEn: null } }),
    );
    expect(db.sesionRefresh.create.mock.calls[0][0].data).toMatchObject({
      familiaId: "fam-1",
      tokenHash: hashToken(out.token),
    });
  });

  test("reusar un token viejo revoca toda la familia (robo de cookie)", async () => {
    const db = dbRefresh(filaRefresh({ usadoEn: new Date(Date.now() - 10 * 60_000) }));
    await expect(rotarSesionRefresh(db, "token-actual")).rejects.toMatchObject({ status: 401 });
    expect(db.sesionRefresh.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { familiaId: "fam-1", revocadoEn: null },
        data: expect.objectContaining({ motivoRevocacion: "REUSO_DETECTADO" }),
      }),
    );
  });

  test("dos pestanas renovando a la vez no cierran la sesion", async () => {
    const db = dbRefresh(filaRefresh({ usadoEn: new Date(Date.now() - 2_000) }));
    await expect(rotarSesionRefresh(db, "token-actual")).rejects.toMatchObject({ status: 409 });
    expect(db.sesionRefresh.updateMany).not.toHaveBeenCalled();
  });

  test("tras cerrar todas las sesiones la cookie deja de servir", async () => {
    const db = dbRefresh(filaRefresh({ usuario: { activo: true, versionSesion: 1 } }));
    await expect(rotarSesionRefresh(db, "token-actual")).rejects.toMatchObject({ status: 401 });
  });

  test("token desconocido, revocado o vencido responde 401", async () => {
    await expect(rotarSesionRefresh(dbRefresh(null), "x")).rejects.toMatchObject({ status: 401 });
    await expect(
      rotarSesionRefresh(dbRefresh(filaRefresh({ revocadoEn: new Date() })), "token-actual"),
    ).rejects.toMatchObject({ status: 401 });
    await expect(
      rotarSesionRefresh(dbRefresh(filaRefresh({ expiraEn: new Date(Date.now() - 1) })), "token-actual"),
    ).rejects.toMatchObject({ status: 401 });
  });
});

/* --------------------------------- rutas ---------------------------------- */

function appAuth() {
  const app = express();
  app.use(express.json());
  app.use(authRequiredUnlessPublic);
  app.use("/auth", authRouter);
  app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    res.status(typeof err?.status === "number" ? err.status : 500).json({ message: err?.message });
  });
  return app;
}

describe("rutas de autenticacion", () => {
  test("la recuperacion con correo y cedula quedo desactivada", async () => {
    const res = await request(appAuth())
      .post("/auth/recuperar-contrasena")
      .send({ correo: "alguien@test.com", id: "12345678", nuevaContrasena: "tomada-1234" });
    expect(res.status).toBe(410);
    expect(res.body.code).toBe("RECUPERACION_DESACTIVADA");
  });

  test("la renovacion exige el origen del frontend (CSRF)", async () => {
    const sinOrigen = await request(appAuth()).post("/auth/refresh");
    expect(sinOrigen.status).toBe(403);

    const ajeno = await request(appAuth()).post("/auth/refresh").set("Origin", "https://evil.example");
    expect(ajeno.status).toBe(403);
  });

  test("sin cookie la renovacion pide iniciar sesion", async () => {
    const res = await request(appAuth()).post("/auth/refresh").set("Origin", "http://localhost:5300");
    expect(res.status).toBe(401);
  });
});
