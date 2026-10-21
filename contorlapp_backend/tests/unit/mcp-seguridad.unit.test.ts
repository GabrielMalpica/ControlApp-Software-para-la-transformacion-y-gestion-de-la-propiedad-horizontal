// Piezas de seguridad del MCP: configuracion, tokens, clientes CIMD,
// referencias opacas, scopes, errores saneados, bitacora, confirmaciones y el
// ejecutor de herramientas (interruptor, scope, limites, auditoria).
import { generateKeyPairSync, randomBytes } from "crypto";
import jwt from "jsonwebtoken";
import { z } from "zod";
import { Prisma } from "@prisma/client";

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));

import { reiniciarVentanasLocales } from "../../src/middlewares/rate-limit.middleware";
import { AuditoriaService } from "../../src/services/AuditoriaService";
import { redactar, ipTruncada } from "../../src/mcp/bitacora";
import { leerConfigMcp, ErrorConfigMcp, type ConfigMcp } from "../../src/mcp/config";
import {
  confirmarOperacion,
  crearConfirmacion,
  hashCanonico,
  type ContextoConfirmacion,
  type OperacionConfirmable,
} from "../../src/mcp/confirmaciones";
import { traducirError } from "../../src/mcp/errores";
import { invalidarFlagsMcp } from "../../src/mcp/estado";
import { ejecutarHerramienta } from "../../src/mcp/herramientas/ejecutor";
import { definirHerramienta, type ContextoHerramienta } from "../../src/mcp/herramientas/tipos";
import { herramientasConsulta } from "../../src/mcp/herramientas/consultas";
import { esClientIdCimdPermitido, limpiarCacheClientes, resolverCliente } from "../../src/mcp/oauth/clientes";
import { firmarAccessToken, verificarAccessToken, verificarPkce } from "../../src/mcp/oauth/tokens";
import { Referencias } from "../../src/mcp/referencias";
import { expandirScopes, parsearScopes, tieneScope } from "../../src/mcp/scopes";
import { crearFakeMcpPrisma } from "../helpers/fakeMcpPrisma";

function pemEc(curva = "prime256v1") {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: curva });
  return privateKey.export({ type: "pkcs8", format: "pem" }).toString();
}

function config(extra: Record<string, string> = {}): ConfigMcp {
  return leerConfigMcp({
    NODE_ENV: "test",
    MCP_ENABLED: "true",
    MCP_ISSUER: "https://mcp.ejemplo.co",
    MCP_JWT_PRIVATE_KEY: pemEc(),
    MCP_REF_KEY: randomBytes(32).toString("base64"),
    ...extra,
  } as NodeJS.ProcessEnv);
}

beforeEach(async () => {
  reiniciarVentanasLocales();
  limpiarCacheClientes();
  await invalidarFlagsMcp();
});

describe("configuracion", () => {
  test("exige emisor https, clave EC P-256 y clave de referencias de 32 bytes", () => {
    expect(() => config({ MCP_ISSUER: "" })).toThrow(ErrorConfigMcp);
    expect(() => config({ MCP_ISSUER: "http://mcp.ejemplo.co" })).toThrow(/https/);
    expect(() => config({ MCP_JWT_PRIVATE_KEY: "" })).toThrow(/MCP_JWT_PRIVATE_KEY/);
    expect(() => config({ MCP_JWT_PRIVATE_KEY: pemEc("secp384r1") })).toThrow(/P-256/);
    expect(() => config({ MCP_REF_KEY: "corta" })).toThrow(/32 bytes/);
    expect(() => config({ MCP_CLIENTES_PERMITIDOS: "http://claude.ai/" })).toThrow(/https/);
  });

  test("apagado por defecto y recurso canonico /mcp", () => {
    const c = config({ MCP_ENABLED: "", MCP_ISSUER: "https://mcp.ejemplo.co/" });
    expect(c.habilitado).toBe(false);
    expect(c.recurso).toBe("https://mcp.ejemplo.co/mcp");
  });
});

describe("tokens", () => {
  const c = config();
  const datos = { usuarioId: "g-1", clienteId: "https://claude.ai/x", conexionId: "c-1", scopes: ["conjuntos:read"] };

  test("ES256 con emisor y audiencia del MCP", () => {
    const { token } = firmarAccessToken(c, datos);
    const claims = verificarAccessToken(c, token);
    expect(claims).toMatchObject({ sub: "g-1", cid: "c-1", aud: c.recurso, iss: c.emisor });
    expect(JSON.parse(Buffer.from(token.split(".")[0], "base64url").toString())).toMatchObject({
      alg: "ES256",
      typ: "at+jwt",
    });
  });

  test("rechaza otra clave, otra audiencia, HS256 y alg none", () => {
    const otro = config();
    expect(() => verificarAccessToken(c, firmarAccessToken(otro, datos).token)).toThrow();
    const otraAud = jwt.sign({ cid: "c-1", client_id: "x", scope: "" }, c.clavePrivada, {
      algorithm: "ES256",
      issuer: c.emisor,
      audience: "https://otra.example/mcp",
      subject: "g-1",
      expiresIn: 60,
    });
    expect(() => verificarAccessToken(c, otraAud)).toThrow();
    const hs = jwt.sign({ cid: "c-1", client_id: "x", scope: "" }, "secreto", {
      issuer: c.emisor,
      audience: c.recurso,
      subject: "g-1",
    });
    expect(() => verificarAccessToken(c, hs)).toThrow();
    const none = jwt.sign({ cid: "c-1", client_id: "x", scope: "" }, "", {
      algorithm: "none",
      issuer: c.emisor,
      audience: c.recurso,
      subject: "g-1",
    });
    expect(() => verificarAccessToken(c, none)).toThrow();
  });

  test("PKCE S256", () => {
    expect(verificarPkce("x".repeat(43), "no")).toBe(false);
    expect(verificarPkce("corto", "corto")).toBe(false);
  });
});

describe("clientes (CIMD)", () => {
  const c = config();

  test.each([
    ["https://claude.ai/oauth/client", true],
    ["https://chatgpt.com/oauth/client.json", true],
    ["https://claude.ai.evil.com/oauth", false],
    ["https://user@claude.ai/oauth", false],
    ["https://claude.ai:8443/oauth", false],
    ["http://claude.ai/oauth", false],
    ["https://evil.example/claude.ai/", false],
  ])("%s permitido=%s", (id, esperado) => {
    expect(esClientIdCimdPermitido(c, id)).toBe(esperado);
  });

  test("el documento debe declarar el mismo client_id y ser cliente publico", async () => {
    const id = "https://chatgpt.com/oauth/client.json";
    const responder = (doc: object) => (async () => new Response(JSON.stringify(doc))) as unknown as typeof fetch;
    const prisma = crearFakeMcpPrisma();
    expect(await resolverCliente(c, prisma, id, responder({ client_id: "otro", redirect_uris: ["https://chatgpt.com/x"] }))).toBeNull();
    limpiarCacheClientes();
    expect(
      await resolverCliente(c, prisma, id, responder({ client_id: id, redirect_uris: ["https://chatgpt.com/x"], token_endpoint_auth_method: "client_secret_basic" })),
    ).toBeNull();
    limpiarCacheClientes();
    const ok = await resolverCliente(c, prisma, id, responder({ client_id: id, client_name: "ChatGPT", redirect_uris: ["https://chatgpt.com/connector_platform_oauth_redirect"] }));
    expect(ok).toMatchObject({ nombre: "ChatGPT", origen: "cimd" });
  });

  test("acepta un cliente que prefiere otro metodo pero soporta 'none' (documento real de ChatGPT)", async () => {
    const id = "https://chatgpt.com/oauth/client.json";
    const responder = (doc: object) => (async () => new Response(JSON.stringify(doc))) as unknown as typeof fetch;
    const prisma = crearFakeMcpPrisma();
    const ok = await resolverCliente(
      c,
      prisma,
      id,
      responder({
        client_id: id,
        client_name: "ChatGPT",
        redirect_uris: ["https://chatgpt.com/connector_platform_oauth_redirect"],
        token_endpoint_auth_method: "private_key_jwt",
        token_endpoint_auth_methods_supported: ["none", "private_key_jwt"],
      }),
    );
    expect(ok).toMatchObject({ nombre: "ChatGPT", origen: "cimd" });
    limpiarCacheClientes();
    expect(
      await resolverCliente(
        c,
        prisma,
        id,
        responder({
          client_id: id,
          redirect_uris: ["https://chatgpt.com/connector_platform_oauth_redirect"],
          token_endpoint_auth_method: "private_key_jwt",
          token_endpoint_auth_methods_supported: ["private_key_jwt"],
        }),
      ),
    ).toBeNull();
  });

  test("un client_id fuera de la lista ni se descarga", async () => {
    const fetchEspia = jest.fn() as unknown as typeof fetch;
    expect(await resolverCliente(c, crearFakeMcpPrisma(), "https://evil.example/c.json", fetchEspia)).toBeNull();
    expect(fetchEspia).not.toHaveBeenCalled();
  });
});

describe("referencias opacas", () => {
  const clave = randomBytes(32);

  test("ida y vuelta, deterministas y sin la cedula visible", () => {
    const refs = new Referencias(clave, "conexion-1");
    const ref = refs.crear("op", "1022334455");
    expect(ref).toMatch(/^op_/);
    expect(ref).not.toContain("1022334455");
    expect(refs.crear("op", "1022334455")).toBe(ref);
    expect(refs.resolver(ref, "op")).toBe("1022334455");
  });

  test("no resuelven en otra conexion, con otro tipo ni alteradas", () => {
    const ref = new Referencias(clave, "conexion-1").crear("op", "1022334455");
    expect(() => new Referencias(clave, "conexion-2").resolver(ref, "op")).toThrow();
    expect(() => new Referencias(clave, "conexion-1").resolver(ref.replace("op_", "sup_"), "sup")).toThrow();
    const alterada = `${ref.slice(0, -3)}${ref.slice(-3) === "AAA" ? "BBB" : "AAA"}`;
    expect(() => new Referencias(clave, "conexion-1").resolver(alterada, "op")).toThrow();
    expect(() => new Referencias(clave, "conexion-1").resolver("1022334455", "op")).toThrow(/Referencia/);
  });
});

describe("scopes", () => {
  test("escribir implica leer, no al reves", () => {
    expect(tieneScope(["personal:write"], "personal:read")).toBe(true);
    expect(tieneScope(["personal:read"], "personal:write")).toBe(false);
    expect([...expandirScopes(["cronograma:publicar"])]).toContain("cronograma:read");
  });

  test("ignora scopes desconocidos", () => {
    expect(parsearScopes("conjuntos:read admin:todo  conjuntos:read")).toEqual(["conjuntos:read"]);
  });
});

describe("errores y bitacora", () => {
  test("no filtra detalles tecnicos y conserva codigos de negocio", () => {
    expect(traducirError(new TypeError("Cannot read properties of undefined"))).toMatchObject({ status: 500, codigo: "ERROR_INTERNO" });
    expect(traducirError(Object.assign(new Error("x"), { status: 409, code: "TAREAS_ABIERTAS" }))).toMatchObject({ codigo: "TAREAS_ABIERTAS" });
    expect(traducirError(new Error("Operario no encontrado."))).toMatchObject({ status: 404, codigo: "NO_ENCONTRADO" });
    expect(traducirError(new Error("Ã¢ÂÅ’ Usuario no encontrado.")).mensaje).toBe("Usuario no encontrado.");
    const p2002 = new Prisma.PrismaClientKnownRequestError("dup", { code: "P2002", clientVersion: "6" });
    expect(traducirError(p2002)).toMatchObject({ codigo: "CONFLICTO" });
    expect(traducirError(new Error("Invalid `prisma.usuario.create()` invocation")).codigo).toBe("ERROR_INTERNO");
  });

  test("la bitacora redacta datos personales y trunca la IP", () => {
    expect(redactar({ cedula: "1022", correo: "a@b.co", telefono: "300", nombre: "Ana" })).toEqual({
      cedula: "[redactado]",
      correo: "[redactado]",
      telefono: "[redactado]",
      nombre: "Ana",
    });
    expect(ipTruncada("::ffff:181.50.10.7")).toBe("181.50.10.0");
  });
});

/* ------------------------------ confirmaciones ------------------------------ */

function contextoConfirmacion(scopes: string[] = ["personal:write"]): ContextoConfirmacion {
  return {
    accion: { actor: { id: "g-1", rol: "gerente", nombre: "Gabriela" }, empresaId: "E-1", canal: "MCP" },
    conexionId: "con-1",
    clienteNombre: "Claude",
    scopes: expandirScopes(scopes),
  };
}

function operacionPrueba(estado: { impacto: number; aprobacion?: boolean }) {
  const ejecutadas: unknown[] = [];
  const op: OperacionConfirmable<{ valor: number }> = {
    nombre: "op_prueba",
    titulo: "Prueba",
    scope: "personal:write",
    requiereAprobacionHumana: () => Boolean(estado.aprobacion),
    previsualizar: async (_p, _c, params) => ({ resumen: `Cambiar a ${params.valor}`, impacto: { afectados: estado.impacto } }),
    ejecutar: async (_p, _c, params) => {
      ejecutadas.push(params);
      return { ok: true };
    },
  };
  return { op, ejecutadas, mapa: new Map([[op.nombre, op as OperacionConfirmable]]) };
}

describe("confirmaciones", () => {
  test("ejecuta los parametros guardados una sola vez", async () => {
    const prisma = crearFakeMcpPrisma();
    const { op, ejecutadas, mapa } = operacionPrueba({ impacto: 3 });
    const vista = await crearConfirmacion(prisma, contextoConfirmacion(), op, { valor: 7 });
    expect(vista.requiereAprobacionEnControlApp).toBe(false);
    await confirmarOperacion(prisma, contextoConfirmacion(), mapa, vista.confirmacionId);
    expect(ejecutadas).toEqual([{ valor: 7 }]);
    await expect(confirmarOperacion(prisma, contextoConfirmacion(), mapa, vista.confirmacionId)).rejects.toMatchObject({
      code: "CONFIRMACION_USADA",
    });
    expect(ejecutadas).toHaveLength(1);
  });

  test("otra conexion no puede usarla", async () => {
    const prisma = crearFakeMcpPrisma();
    const { op, mapa } = operacionPrueba({ impacto: 1 });
    const vista = await crearConfirmacion(prisma, contextoConfirmacion(), op, { valor: 1 });
    const ajena = { ...contextoConfirmacion(), conexionId: "con-2" };
    await expect(confirmarOperacion(prisma, ajena, mapa, vista.confirmacionId)).rejects.toMatchObject({
      code: "CONFIRMACION_NO_ENCONTRADA",
    });
  });

  test("sin el scope de la operacion no se ejecuta", async () => {
    const prisma = crearFakeMcpPrisma();
    const { op, ejecutadas, mapa } = operacionPrueba({ impacto: 1 });
    const vista = await crearConfirmacion(prisma, contextoConfirmacion(), op, { valor: 1 });
    await expect(
      confirmarOperacion(prisma, contextoConfirmacion(["personal:read"]), mapa, vista.confirmacionId),
    ).rejects.toMatchObject({ code: "SCOPE_INSUFICIENTE" });
    expect(ejecutadas).toHaveLength(0);
  });

  test("alto riesgo: espera la aprobacion en ControlApp y avisa al gerente", async () => {
    const prisma = crearFakeMcpPrisma();
    const { op, ejecutadas, mapa } = operacionPrueba({ impacto: 1, aprobacion: true });
    const vista = await crearConfirmacion(prisma, contextoConfirmacion(), op, { valor: 2 });
    expect(vista.requiereAprobacionEnControlApp).toBe(true);
    expect(prisma._notificaciones).toHaveLength(1);
    await expect(confirmarOperacion(prisma, contextoConfirmacion(), mapa, vista.confirmacionId)).rejects.toMatchObject({
      code: "PENDIENTE_APROBACION",
    });
    prisma.mcpConfirmacion.filas[0].estado = "APROBADA";
    await confirmarOperacion(prisma, contextoConfirmacion(), mapa, vista.confirmacionId);
    expect(ejecutadas).toHaveLength(1);
  });

  test("si el impacto cambio desde la previsualizacion, aborta", async () => {
    const prisma = crearFakeMcpPrisma();
    const estado = { impacto: 1 };
    const { op, ejecutadas, mapa } = operacionPrueba(estado);
    const vista = await crearConfirmacion(prisma, contextoConfirmacion(), op, { valor: 2 });
    estado.impacto = 5;
    await expect(confirmarOperacion(prisma, contextoConfirmacion(), mapa, vista.confirmacionId)).rejects.toMatchObject({
      code: "ESTADO_CAMBIO",
    });
    expect(ejecutadas).toHaveLength(0);
    expect(prisma.mcpConfirmacion.filas[0].estado).toBe("INVALIDADA");
  });

  test("vencida no se ejecuta", async () => {
    const prisma = crearFakeMcpPrisma();
    const { op, ejecutadas, mapa } = operacionPrueba({ impacto: 1 });
    const vista = await crearConfirmacion(prisma, contextoConfirmacion(), op, { valor: 2 });
    prisma.mcpConfirmacion.filas[0].expiraEn = new Date(Date.now() - 1);
    await expect(confirmarOperacion(prisma, contextoConfirmacion(), mapa, vista.confirmacionId)).rejects.toMatchObject({
      code: "CONFIRMACION_EXPIRADA",
    });
    expect(ejecutadas).toHaveLength(0);
  });

  test("hash canonico independiente del orden de llaves", () => {
    expect(hashCanonico({ a: 1, b: [1, { c: 2, d: 3 }] })).toBe(hashCanonico({ b: [1, { d: 3, c: 2 }], a: 1 }));
  });
});

/* --------------------------------- ejecutor --------------------------------- */

function contextoHerramienta(prisma: any, scopes: string[]): ContextoHerramienta {
  return {
    prisma,
    accion: { actor: { id: "g-1", rol: "gerente", nombre: "Gabriela" }, empresaId: "E-1", canal: "MCP" },
    conexionId: "con-1",
    clienteId: "https://claude.ai/x",
    clienteNombre: "Claude",
    scopes: expandirScopes(scopes),
    refs: new Referencias(randomBytes(32), "con-1"),
    ip: "181.50.10.7",
    userAgent: "Claude-User",
  };
}

const opciones = { urlMetadatosRecurso: "https://mcp.ejemplo.co/.well-known/oauth-protected-resource/mcp" };

describe("ejecutor de herramientas", () => {
  const herramienta = definirHerramienta({
    nombre: "prueba_escritura",
    titulo: "Prueba",
    descripcion: "Herramienta de prueba para el ejecutor.",
    modulo: "pruebas",
    version: 1,
    scope: "personal:write",
    riesgo: "ESCRITURA",
    entrada: z.object({ cedula: z.string() }).strict(),
    ejecutar: async (ctx) => {
      // Lo que audite un servicio durante la herramienta queda con origen MCP.
      await new AuditoriaService(ctx.prisma).registrar({
        modulo: "PERSONAL",
        entidad: "Usuario",
        entidadId: "x",
        accion: "EDITAR",
        actor: { id: "g-1", rol: "gerente" },
      });
      return { datos: { ok: true }, entidades: [{ tipo: "Usuario", id: "x" }] };
    },
  });

  test("sin scope: error con el reto para el cliente y bitacora DENEGADO", async () => {
    const prisma = crearFakeMcpPrisma();
    const res = await ejecutarHerramienta(herramienta, contextoHerramienta(prisma, ["personal:read"]), { cedula: "1" }, opciones);
    expect(res.isError).toBe(true);
    expect(JSON.stringify(res._meta)).toContain("insufficient_scope");
    expect(prisma.mcpInvocacion.filas[0]).toMatchObject({ resultado: "DENEGADO", codigo: "SCOPE_INSUFICIENTE" });
  });

  test("ok: bitacora con parametros redactados y auditoria de dominio con origen MCP", async () => {
    const prisma = crearFakeMcpPrisma();
    const res = await ejecutarHerramienta(herramienta, contextoHerramienta(prisma, ["personal:write"]), { cedula: "1022334455" }, opciones);
    expect(res.isError).toBeFalsy();
    const fila = prisma.mcpInvocacion.filas[0];
    expect(fila).toMatchObject({ resultado: "OK", herramienta: "prueba_escritura", usuarioId: "g-1", ip: "181.50.10.0" });
    expect(JSON.stringify(fila.parametrosRedactados)).not.toContain("1022334455");
    const evento = prisma.auditoriaEvento.filas[0];
    expect(evento.origen).toBe("MCP");
    expect(evento.metadataJson.canal).toMatchObject({ conexionId: "con-1", herramienta: "prueba_escritura" });
  });

  test("herramienta deshabilitada en caliente", async () => {
    const prisma = crearFakeMcpPrisma();
    prisma.configuracionSistema.filas.push({ clave: "mcp.herramientas.deshabilitadas", valor: "prueba_escritura" });
    await invalidarFlagsMcp();
    const res = await ejecutarHerramienta(herramienta, contextoHerramienta(prisma, ["personal:write"]), { cedula: "1" }, opciones);
    expect(res.structuredContent).toMatchObject({ error: { codigo: "DESHABILITADA" } });
  });

  test("limite de escrituras por minuto", async () => {
    const prisma = crearFakeMcpPrisma();
    const ctx = contextoHerramienta(prisma, ["personal:write"]);
    let ultimo: any;
    for (let i = 0; i < 21; i++) ultimo = await ejecutarHerramienta(herramienta, ctx, { cedula: "1" }, opciones);
    expect(ultimo.structuredContent).toMatchObject({ error: { codigo: "LIMITE" } });
  });

  test("listar_personal nunca devuelve cedulas ni contacto sin personal:pii", async () => {
    const prisma = crearFakeMcpPrisma();
    prisma.operario = {
      findMany: jest.fn(async ({ select }: any) => [
        {
          id: "1022334455",
          funciones: ["ASEO"],
          usuario: { nombre: "Juan Pérez", activo: true, ...(select.usuario.select.telefono ? { telefono: 3001234567n, correo: "juan@x.co" } : {}) },
          conjuntos: [{ nit: "900-1", nombre: "Serramonte" }],
          necesidadesOcupadas: [],
        },
      ]),
    };
    const listar = herramientasConsulta.find((h) => h.nombre === "listar_personal")!;
    const sinPii = await ejecutarHerramienta(listar, contextoHerramienta(prisma, ["personal:read"]), { rol: "operario" }, opciones);
    const texto = sinPii.content[0].text;
    expect(texto).not.toContain("1022334455");
    expect(texto).not.toContain("3001234567");
    expect(texto).toContain("op_");
    const conPii = await ejecutarHerramienta(listar, contextoHerramienta(prisma, ["personal:pii"]), { rol: "operario" }, opciones);
    expect(conPii.content[0].text).toContain("3001234567");
    expect(conPii.content[0].text).not.toContain("1022334455");
  });
});
