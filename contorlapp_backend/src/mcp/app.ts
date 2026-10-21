// src/mcp/app.ts
//
// Aplicacion Express del servicio MCP (proceso aparte de la API: se puede
// apagar o escalar a 0 sin tocar la app). Sirve el servidor de autorizacion
// OAuth y el endpoint /mcp. Sin CORS: lo llaman los servidores de Anthropic y
// OpenAI, no navegadores; y la API REST nunca acepta estos tokens.
import express, { type ErrorRequestHandler } from "express";
import helmet from "helmet";
import type { PrismaClient } from "@prisma/client";

import { registroDeAcceso } from "../middlewares/access-log.middleware";
import { distributedRateLimit } from "../middlewares/rate-limit.middleware";
import type { ConfigMcp } from "./config";
import { crearRouterOAuth, type DependenciasOAuth } from "./oauth/servidorAutorizacion";
import { montarMcp } from "./servidorMcp";

export function crearAppMcp(deps: DependenciasOAuth & { prisma: PrismaClient; config: ConfigMcp }) {
  const app = express();
  app.set("trust proxy", 1);
  app.disable("x-powered-by");
  // Las paginas de login/consentimiento ponen su propia CSP (con nonce).
  app.use(helmet({ contentSecurityPolicy: false, crossOriginResourcePolicy: { policy: "same-origin" } }));
  app.use(registroDeAcceso);

  app.get("/healthz", (_req, res) => {
    res.json({ ok: true });
  });
  app.get("/readyz", async (_req, res) => {
    try {
      await deps.prisma.$queryRaw`SELECT 1`;
      res.json({ ok: true, mcpHabilitado: deps.config.habilitado });
    } catch {
      res.status(503).json({ ok: false });
    }
  });
  app.get("/", (_req, res) => {
    res
      .type("text/plain")
      .send(
        "ControlApp MCP. Conecta tu asistente de IA (Claude o ChatGPT) con esta URL terminada en /mcp. Solo gerentes habilitados.",
      );
  });

  app.use(crearRouterOAuth(deps));

  const limiteMcp = distributedRateLimit({
    name: "mcp:http:ip",
    windowMs: 60_000,
    limit: 600,
    key: (req) => req.ip ?? "sin-ip",
  });
  app.all("/mcp", limiteMcp, express.json({ limit: "1mb" }), montarMcp(deps));

  const manejarError: ErrorRequestHandler = (err, req, res, _next) => {
    console.error("[mcp-error]", {
      ruta: `${req.method} ${req.originalUrl.split("?")[0]}`,
      nombre: err instanceof Error ? err.name : "Error",
    });
    if (res.headersSent) return;
    const status = typeof err?.status === "number" && err.status < 500 ? err.status : 500;
    res.status(status).json({
      error: status === 400 ? "invalid_request" : "server_error",
      error_description: status === 400 ? "Solicitud inválida." : "Ocurrió un error inesperado.",
    });
  };
  app.use(manejarError);
  return app;
}
