// src/mcp/servidor.ts
//
// Punto de entrada del servicio MCP (`npm run start:mcp`). No aplica
// migraciones: eso lo hace solo el servicio de la API (`npm start`).
import "dotenv/config";

process.env.TZ = process.env.TZ || "America/Bogota";

import { prisma } from "../db/prisma";
import { AuthService } from "../services/authService";
import { crearAppMcp } from "./app";
import { ErrorConfigMcp, leerConfigMcp } from "./config";

function arrancar() {
  let config;
  try {
    config = leerConfigMcp();
  } catch (error) {
    if (error instanceof ErrorConfigMcp) {
      console.error(`[mcp] configuracion invalida: ${error.message}`);
      process.exit(1);
    }
    throw error;
  }

  if (!config.habilitado) {
    console.warn("[mcp] MCP_ENABLED no es 'true': el servicio responde 503 hasta habilitarlo.");
  }
  if (process.env.NODE_ENV === "production" && !String(process.env.REDIS_URL ?? "").trim()) {
    console.warn("[mcp] REDIS_URL no esta configurada: revocaciones y limites solo locales a este proceso.");
  }

  const auth = new AuthService(prisma);
  const app = crearAppMcp({
    config,
    prisma,
    verificarCredenciales: (correo, contrasena) => auth.verificarCredenciales(correo, contrasena),
  });

  const puerto = Number(process.env.PORT) || 3100;
  const host = process.env.HOST || "0.0.0.0";
  const servidor = app.listen(puerto, host, () => {
    console.log(`[mcp] escuchando en http://${host}:${puerto} (emisor ${config.emisor})`);
  });

  const cerrar = async () => {
    servidor.close();
    await prisma.$disconnect();
    process.exit(0);
  };
  process.on("SIGINT", cerrar);
  process.on("SIGTERM", cerrar);
}

arrancar();
