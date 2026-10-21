// Flujo completo del MCP con un Prisma en memoria: descubrimiento (RFC 9728 /
// RFC 8414), autorizacion con PKCE S256, login solo de gerentes habilitados,
// consentimiento por scopes, emision y rotacion de tokens, llamadas MCP
// (2025 y 2026-07-28), reto de scope, revocacion y kill switch.
import { createHash, generateKeyPairSync, randomBytes } from "crypto";
import request from "supertest";

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));

import { crearAppMcp } from "../../src/mcp/app";
import { leerConfigMcp, type ConfigMcp } from "../../src/mcp/config";
import { invalidarFlagsMcp } from "../../src/mcp/estado";
import { limpiarCacheClientes } from "../../src/mcp/oauth/clientes";
import { reiniciarVentanasLocales } from "../../src/middlewares/rate-limit.middleware";
import { firmarTokenSesion } from "../../src/utils/jwtSesion";
import { crearFakeMcpPrisma } from "../helpers/fakeMcpPrisma";

const CLAUDE_ID = "https://claude.ai/oauth/mcp-oauth-client-metadata";
const CLAUDE_REDIRECT = "https://claude.ai/api/mcp/auth_callback";

function configPrueba(): ConfigMcp {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return leerConfigMcp({
    NODE_ENV: "test",
    MCP_ENABLED: "true",
    MCP_ISSUER: "http://localhost:3100",
    MCP_JWT_PRIVATE_KEY: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
    MCP_REF_KEY: randomBytes(32).toString("base64"),
  } as NodeJS.ProcessEnv);
}

const fetchCimd = jest.fn(async (url: string) => {
  if (url !== CLAUDE_ID) return new Response("no", { status: 404 });
  return new Response(
    JSON.stringify({
      client_id: CLAUDE_ID,
      client_name: "Claude",
      redirect_uris: [CLAUDE_REDIRECT],
      token_endpoint_auth_method: "none",
    }),
    { status: 200 },
  );
}) as unknown as typeof fetch;

const credenciales: Record<string, { id: string; nombre: string; rol: string }> = {
  "gerente@test.com": { id: "g-1", nombre: "Gabriela Gerente", rol: "gerente" },
  "nohabilitado@test.com": { id: "g-2", nombre: "Gerente Sin Acceso", rol: "gerente" },
  "admin@test.com": { id: "a-1", nombre: "Ana Administradora", rol: "administrador" },
  "jefe@test.com": { id: "j-1", nombre: "Jorge Jefe", rol: "jefe_operaciones" },
};

function montar() {
  const prisma = crearFakeMcpPrisma({
    usuarios: [
      { id: "g-1", nombre: "Gabriela Gerente", rol: "gerente" },
      { id: "g-2", nombre: "Gerente Sin Acceso", rol: "gerente" },
      { id: "a-1", nombre: "Ana Administradora", rol: "administrador" },
      { id: "j-1", nombre: "Jorge Jefe", rol: "jefe_operaciones" },
    ],
    gerentes: [
      { id: "g-1", empresaId: "E-1", mcpHabilitado: true },
      { id: "g-2", empresaId: "E-1", mcpHabilitado: false },
    ],
    conjuntos: [
      { nit: "900-1", nombre: "Serramonte", empresaId: "E-1" },
      { nit: "900-2", nombre: "Altavista", empresaId: "E-1" },
      { nit: "800-9", nombre: "De otra empresa", empresaId: "E-2" },
    ],
  });
  const config = configPrueba();
  const app = crearAppMcp({
    config,
    prisma,
    fetchImpl: fetchCimd,
    verificarCredenciales: async (correo, contrasena) => {
      const usuario = credenciales[correo];
      if (!usuario || contrasena !== "clave-correcta") throw Object.assign(new Error("x"), { status: 401 });
      return usuario;
    },
  });
  return { app, prisma, config };
}

let ipSecuencia = 1;
const nuevaIp = () => `10.0.${Math.floor(ipSecuencia / 250)}.${(ipSecuencia++ % 250) + 1}`;

function pkce() {
  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  return { verifier, challenge };
}

function campoOculto(html: string, nombre: string): string {
  const m = html.match(new RegExp(`name="${nombre}" value="([^"]+)"`));
  if (!m) throw new Error(`No se encontro ${nombre}`);
  return m[1];
}

async function autorizar(
  app: any,
  opciones: { correo?: string; scopes?: string[]; state?: string } = {},
): Promise<{ code: string; verifier: string; location: URL }> {
  const ip = nuevaIp();
  const { verifier, challenge } = pkce();
  const aut = await request(app)
    .get("/oauth/authorize")
    .set("X-Forwarded-For", ip)
    .query({
      response_type: "code",
      client_id: CLAUDE_ID,
      redirect_uri: CLAUDE_REDIRECT,
      code_challenge: challenge,
      code_challenge_method: "S256",
      state: opciones.state ?? "estado-1",
      scope: "conjuntos:read personal:read",
      resource: "http://localhost:3100/mcp",
    });
  expect(aut.status).toBe(200);
  const login = await request(app)
    .post("/oauth/login")
    .set("X-Forwarded-For", ip)
    .type("form")
    .send({
      solicitud: campoOculto(aut.text, "solicitud"),
      csrf: campoOculto(aut.text, "csrf"),
      correo: opciones.correo ?? "gerente@test.com",
      contrasena: "clave-correcta",
    });
  expect(login.status).toBe(200);
  // CSP: form-action debe permitir la redireccion al cliente.
  expect(login.headers["content-security-policy"]).toContain("form-action 'self' https://claude.ai");
  const scopes = opciones.scopes ?? ["conjuntos:read", "personal:read"];
  const consentimiento = await request(app)
    .post("/oauth/consentir")
    .set("X-Forwarded-For", ip)
    .type("form")
    .send(
      [
        `solicitud=${encodeURIComponent(campoOculto(login.text, "solicitud"))}`,
        `csrf=${encodeURIComponent(campoOculto(login.text, "csrf"))}`,
        "decision=aprobar",
        ...scopes.map((s) => `scope=${encodeURIComponent(s)}`),
      ].join("&"),
    );
  expect(consentimiento.status).toBe(302);
  const location = new URL(consentimiento.headers.location);
  return { code: location.searchParams.get("code") ?? "", verifier, location };
}

async function canjear(app: any, code: string, verifier: string) {
  return request(app)
    .post("/oauth/token")
    .set("X-Forwarded-For", nuevaIp())
    .type("form")
    .send({
      grant_type: "authorization_code",
      code,
      redirect_uri: CLAUDE_REDIRECT,
      client_id: CLAUDE_ID,
      code_verifier: verifier,
      resource: "http://localhost:3100/mcp",
    });
}

async function conectar(app: any, scopes?: string[]) {
  const { code, verifier } = await autorizar(app, { scopes });
  const token = await canjear(app, code, verifier);
  expect(token.status).toBe(200);
  return token.body as { access_token: string; refresh_token: string; scope: string };
}

/** Llamada MCP de 2025 (sin sesion) y lectura de la respuesta (JSON o SSE). */
async function rpc(app: any, accessToken: string, method: string, params: unknown = {}) {
  const res = await request(app)
    .post("/mcp")
    .set("Authorization", `Bearer ${accessToken}`)
    .set("Accept", "application/json, text/event-stream")
    .set("Content-Type", "application/json")
    .set("MCP-Protocol-Version", "2025-11-25")
    .send({ jsonrpc: "2.0", id: 1, method, params });
  let cuerpo: any = res.body;
  if (typeof res.text === "string" && res.text.includes("data:")) {
    const linea = res.text.split("\n").find((l) => l.startsWith("data:"));
    cuerpo = JSON.parse(linea!.slice(5));
  }
  return { status: res.status, headers: res.headers, cuerpo };
}

beforeEach(async () => {
  reiniciarVentanasLocales();
  limpiarCacheClientes();
  await invalidarFlagsMcp();
});

describe("descubrimiento", () => {
  test("metadatos del recurso protegido (RFC 9728)", async () => {
    const { app } = montar();
    const res = await request(app).get("/.well-known/oauth-protected-resource/mcp");
    expect(res.body).toMatchObject({
      resource: "http://localhost:3100/mcp",
      authorization_servers: ["http://localhost:3100"],
    });
    expect(res.body.scopes_supported).toContain("conjuntos:read");
    expect(res.body.scopes_supported).not.toContain("personal:write");
  });

  test("metadatos del servidor (RFC 8414): PKCE S256, CIMD, iss y sin DCR", async () => {
    const { app } = montar();
    const res = await request(app).get("/.well-known/oauth-authorization-server");
    expect(res.body.code_challenge_methods_supported).toEqual(["S256"]);
    expect(res.body.token_endpoint_auth_methods_supported).toEqual(["none"]);
    expect(res.body.client_id_metadata_document_supported).toBe(true);
    expect(res.body.authorization_response_iss_parameter_supported).toBe(true);
    expect(res.body.registration_endpoint).toBeUndefined();
  });

  test("sin token, /mcp responde 401 con el puntero a los metadatos", async () => {
    const { app } = montar();
    const res = await request(app).post("/mcp").send({ jsonrpc: "2.0", id: 1, method: "tools/list" });
    expect(res.status).toBe(401);
    expect(res.headers["www-authenticate"]).toContain(
      'resource_metadata="http://localhost:3100/.well-known/oauth-protected-resource/mcp"',
    );
  });
});

describe("autorizacion", () => {
  test("un cliente fuera de la lista blanca no recibe redireccion", async () => {
    const { app } = montar();
    const res = await request(app).get("/oauth/authorize").query({
      response_type: "code",
      client_id: "https://evil.example/client.json",
      redirect_uri: "https://evil.example/cb",
      code_challenge: pkce().challenge,
      code_challenge_method: "S256",
    });
    expect(res.status).toBe(400);
    expect(res.headers.location).toBeUndefined();
  });

  test("un redirect que el cliente no declara se rechaza sin redirigir", async () => {
    const { app } = montar();
    const res = await request(app).get("/oauth/authorize").query({
      response_type: "code",
      client_id: CLAUDE_ID,
      redirect_uri: "https://claude.ai/otro",
      code_challenge: pkce().challenge,
      code_challenge_method: "S256",
    });
    expect(res.status).toBe(400);
    expect(res.headers.location).toBeUndefined();
  });

  test("sin PKCE S256 vuelve al cliente con invalid_request, state e iss", async () => {
    const { app } = montar();
    const res = await request(app).get("/oauth/authorize").query({
      response_type: "code",
      client_id: CLAUDE_ID,
      redirect_uri: CLAUDE_REDIRECT,
      code_challenge: "x",
      code_challenge_method: "plain",
      state: "abc",
    });
    expect(res.status).toBe(302);
    const url = new URL(res.headers.location);
    expect(url.searchParams.get("error")).toBe("invalid_request");
    expect(url.searchParams.get("state")).toBe("abc");
    expect(url.searchParams.get("iss")).toBe("http://localhost:3100");
  });

  test("otro resource (RFC 8707) se rechaza con invalid_target", async () => {
    const { app } = montar();
    const res = await request(app).get("/oauth/authorize").query({
      response_type: "code",
      client_id: CLAUDE_ID,
      redirect_uri: CLAUDE_REDIRECT,
      code_challenge: pkce().challenge,
      code_challenge_method: "S256",
      resource: "https://otra-api.example/mcp",
    });
    expect(new URL(res.headers.location).searchParams.get("error")).toBe("invalid_target");
  });

  test.each([
    ["admin@test.com", "Solo los gerentes"],
    ["jefe@test.com", "Solo los gerentes"],
    ["nohabilitado@test.com", "no tiene habilitada"],
  ])("%s no puede conectar una IA", async (correo, mensaje) => {
    const { app, prisma } = montar();
    const ip = nuevaIp();
    const aut = await request(app)
      .get("/oauth/authorize")
      .set("X-Forwarded-For", ip)
      .query({
        response_type: "code",
        client_id: CLAUDE_ID,
        redirect_uri: CLAUDE_REDIRECT,
        code_challenge: pkce().challenge,
        code_challenge_method: "S256",
      });
    const login = await request(app)
      .post("/oauth/login")
      .set("X-Forwarded-For", ip)
      .type("form")
      .send({
        solicitud: campoOculto(aut.text, "solicitud"),
        csrf: campoOculto(aut.text, "csrf"),
        correo,
        contrasena: "clave-correcta",
      });
    expect(login.status).toBe(403);
    expect(login.text).toContain(mensaje);
    expect(prisma.mcpConexion.filas).toHaveLength(0);
  });

  test("el CSRF del formulario es obligatorio", async () => {
    const { app } = montar();
    const aut = await request(app).get("/oauth/authorize").set("X-Forwarded-For", nuevaIp()).query({
      response_type: "code",
      client_id: CLAUDE_ID,
      redirect_uri: CLAUDE_REDIRECT,
      code_challenge: pkce().challenge,
      code_challenge_method: "S256",
    });
    const login = await request(app)
      .post("/oauth/login")
      .type("form")
      .send({ solicitud: campoOculto(aut.text, "solicitud"), csrf: "falso", correo: "gerente@test.com", contrasena: "clave-correcta" });
    expect(login.status).toBe(400);
  });

  test("flujo completo: codigo con state e iss, canje con PKCE y tokens con audiencia del MCP", async () => {
    const { app, prisma } = montar();
    const { code, verifier, location } = await autorizar(app, { state: "s-123" });
    expect(location.origin + location.pathname).toBe(CLAUDE_REDIRECT);
    expect(location.searchParams.get("state")).toBe("s-123");
    expect(location.searchParams.get("iss")).toBe("http://localhost:3100");

    const token = await canjear(app, code, verifier);
    expect(token.status).toBe(200);
    expect(token.headers["cache-control"]).toBe("no-store");
    expect(token.body).toMatchObject({ token_type: "Bearer", scope: "conjuntos:read personal:read" });
    const payload = JSON.parse(Buffer.from(token.body.access_token.split(".")[1], "base64url").toString());
    expect(payload).toMatchObject({ iss: "http://localhost:3100", aud: "http://localhost:3100/mcp", sub: "g-1" });
    expect(prisma.mcpConexion.filas[0]).toMatchObject({ usuarioId: "g-1", clienteNombre: "Claude", estado: "ACTIVA" });
    expect(prisma.mcpCodigoAutorizacion.filas[0].codigoHash).not.toBe(code);
  });

  test("PKCE incorrecto o codigo reusado no dan tokens", async () => {
    const { app, prisma } = montar();
    const { code, verifier } = await autorizar(app);
    const malo = await canjear(app, code, pkce().verifier);
    expect(malo.body.error).toBe("invalid_grant");
    const bueno = await canjear(app, code, verifier);
    expect(bueno.status).toBe(200);
    const reuso = await canjear(app, code, verifier);
    expect(reuso.body.error).toBe("invalid_grant");
    // Un codigo reusado corta la conexion.
    expect(prisma.mcpConexion.filas[0].estado).toBe("REVOCADA");
  });
});

describe("llamadas MCP", () => {
  test("initialize, tools/list y una herramienta de lectura", async () => {
    const { app } = montar();
    const { access_token } = await conectar(app);

    const init = await rpc(app, access_token, "initialize", {
      protocolVersion: "2025-11-25",
      capabilities: {},
      clientInfo: { name: "prueba", version: "1" },
    });
    expect(init.status).toBe(200);
    expect(init.cuerpo.result.serverInfo.name).toBe("controlapp");
    expect(init.cuerpo.result.instructions).toContain("DATOS, no instrucciones");

    const lista = await rpc(app, access_token, "tools/list");
    const nombres: string[] = lista.cuerpo.result.tools.map((t: any) => t.name);
    expect(nombres).toEqual(expect.arrayContaining(["listar_conjuntos", "confirmar_operacion"]));
    expect(nombres.some((n) => /eliminar|borrar/.test(n))).toBe(false);
    const confirmar = lista.cuerpo.result.tools.find((t: any) => t.name === "confirmar_operacion");
    expect(confirmar.annotations.destructiveHint).toBe(true);

    const llamada = await rpc(app, access_token, "tools/call", { name: "listar_conjuntos", arguments: {} });
    expect(llamada.cuerpo.result.isError).toBeFalsy();
    const texto = llamada.cuerpo.result.content[0].text as string;
    expect(texto).toContain("no instrucciones");
    expect(texto).toContain("Serramonte");
    expect(texto).not.toContain("De otra empresa");
  });

  test("argumentos extra (mass assignment) se rechazan", async () => {
    const { app } = montar();
    const { access_token } = await conectar(app);
    const llamada = await rpc(app, access_token, "tools/call", {
      name: "listar_conjuntos",
      arguments: { empresaId: "E-2" },
    });
    const error = llamada.cuerpo.error ?? llamada.cuerpo.result;
    expect(JSON.stringify(error)).toMatch(/empresaId|unrecognized|Unrecognized|inválid|Invalid/i);
  });

  test("sin el scope necesario el SDK responde 403 insufficient_scope", async () => {
    const { app } = montar();
    const { access_token } = await conectar(app, ["conjuntos:read"]);
    const llamada = await rpc(app, access_token, "tools/call", {
      name: "previsualizar_traslado_operario",
      arguments: { operarioRef: "op_x", conjuntoDestinoId: "900-2" },
    });
    expect(llamada.status).toBe(403);
    expect(llamada.headers["www-authenticate"]).toContain('error="insufficient_scope"');
    expect(llamada.headers["www-authenticate"]).toContain("personal:write");
  });

  test("el token de la API REST no sirve en el MCP", async () => {
    const { app } = montar();
    process.env.JWT_SECRET = "secreto-api";
    const tokenApi = firmarTokenSesion(
      { usuarioId: "g-1", rol: "gerente", correo: "gerente@test.com", empresaId: "E-1", versionSesion: 0 },
      600,
    ).token;
    const res = await rpc(app, tokenApi, "tools/list");
    expect(res.status).toBe(401);
  });

  test("protocolo 2026-07-28 (sin initialize)", async () => {
    const { app } = montar();
    const { access_token } = await conectar(app);
    const res = await request(app)
      .post("/mcp")
      .set("Authorization", `Bearer ${access_token}`)
      .set("Accept", "application/json, text/event-stream")
      .set("Content-Type", "application/json")
      .set("MCP-Protocol-Version", "2026-07-28")
      .set("Mcp-Method", "tools/list")
      .send({
        jsonrpc: "2.0",
        id: 7,
        method: "tools/list",
        params: {
          _meta: {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": {},
            "io.modelcontextprotocol/clientInfo": { name: "prueba", version: "1" },
          },
        },
      });
    expect(res.status).toBe(200);
    expect(res.body.result.tools.length).toBeGreaterThan(10);
  });
});

describe("renovacion, revocacion y kill switch", () => {
  test("el refresh rota y el viejo, reusado fuera de la gracia, revoca la conexion", async () => {
    const { app, prisma } = montar();
    const { refresh_token, access_token } = await conectar(app);
    const renovado = await request(app).post("/oauth/token").type("form").send({
      grant_type: "refresh_token",
      refresh_token,
      client_id: CLAUDE_ID,
    });
    expect(renovado.status).toBe(200);
    expect(renovado.body.refresh_token).not.toBe(refresh_token);

    // Simula que el viejo se uso hace un minuto y alguien lo vuelve a presentar.
    prisma.mcpRefreshToken.filas[0].usadoEn = new Date(Date.now() - 60_000);
    const reuso = await request(app).post("/oauth/token").type("form").send({
      grant_type: "refresh_token",
      refresh_token,
      client_id: CLAUDE_ID,
    });
    expect(reuso.body.error).toBe("invalid_grant");
    expect(prisma.mcpConexion.filas[0].estado).toBe("REVOCADA");

    const despues = await rpc(app, access_token, "tools/list");
    expect(despues.status).toBe(401);
  });

  test("no se pueden ampliar permisos al renovar", async () => {
    const { app } = montar();
    const { refresh_token } = await conectar(app, ["conjuntos:read"]);
    const res = await request(app).post("/oauth/token").type("form").send({
      grant_type: "refresh_token",
      refresh_token,
      client_id: CLAUDE_ID,
      scope: "conjuntos:read personal:write",
    });
    expect(res.body.error).toBe("invalid_scope");
  });

  test("revocar desde el cliente (RFC 7009) corta el acceso", async () => {
    const { app } = montar();
    const { refresh_token, access_token } = await conectar(app);
    const rev = await request(app).post("/oauth/revoke").type("form").send({ token: refresh_token, client_id: CLAUDE_ID });
    expect(rev.status).toBe(200);
    expect((await rpc(app, access_token, "tools/list")).status).toBe(401);
  });

  test("deshabilitar el MCP del gerente corta el acceso", async () => {
    const { app, prisma } = montar();
    const { access_token } = await conectar(app);
    prisma.gerente.filas[0].mcpHabilitado = false;
    const { invalidarEstadoMcp } = await import("../../src/mcp/estado");
    await invalidarEstadoMcp({ usuarioId: "g-1" });
    expect((await rpc(app, access_token, "tools/list")).status).toBe(401);
  });

  test("kill switch global en caliente: 503", async () => {
    const { app, prisma } = montar();
    const { access_token } = await conectar(app);
    prisma.configuracionSistema.filas.push({ clave: "mcp.habilitado", valor: "false" });
    await invalidarFlagsMcp();
    const res = await rpc(app, access_token, "tools/list");
    expect(res.status).toBe(503);
  });

  test("herramienta deshabilitada desaparece de tools/list", async () => {
    const { app, prisma } = montar();
    const { access_token } = await conectar(app);
    prisma.configuracionSistema.filas.push({ clave: "mcp.herramientas.deshabilitadas", valor: "listar_conjuntos" });
    await invalidarFlagsMcp();
    const lista = await rpc(app, access_token, "tools/list");
    expect(lista.cuerpo.result.tools.map((t: any) => t.name)).not.toContain("listar_conjuntos");
  });
});
