import { spawn, type ChildProcess } from "child_process";
import { createHash, timingSafeEqual } from "crypto";
import { existsSync, readdirSync } from "fs";
import path from "path";
import type { Readable } from "stream";
import { Router } from "express";

type DumpProcess = ChildProcess & {
  stdout: Readable;
  stderr: Readable;
};

type StartDump = (databaseUrl: string) => DumpProcess;

type TemporaryDatabaseExportOptions = {
  env?: NodeJS.ProcessEnv;
  now?: () => Date;
  startDump?: StartDump;
};

function secureTokenEquals(received: string, expected: string) {
  const receivedDigest = createHash("sha256").update(received).digest();
  const expectedDigest = createHash("sha256").update(expected).digest();
  return timingSafeEqual(receivedDigest, expectedDigest);
}

function bearerToken(authorization: string | undefined) {
  if (!authorization?.startsWith("Bearer ")) return "";
  return authorization.slice("Bearer ".length).trim();
}

function pgDumpExecutable() {
  const configuredPath = process.env.PG_DUMP_PATH?.trim();
  if (configuredPath) return configuredPath;

  // Debian installs versioned PostgreSQL binaries here. Normally it also adds
  // /usr/bin/pg_dump, but this fallback covers minimal deployment images.
  const postgresLib = "/usr/lib/postgresql";
  if (existsSync(postgresLib)) {
    const versions = readdirSync(postgresLib, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort((a, b) => Number(b) - Number(a));

    for (const version of versions) {
      const candidate = path.join(postgresLib, version, "bin", "pg_dump");
      if (existsSync(candidate)) return candidate;
    }
  }

  return "pg_dump";
}

const libpqQueryParameters = new Set([
  "application_name",
  "channel_binding",
  "client_encoding",
  "connect_timeout",
  "fallback_application_name",
  "gssencmode",
  "gsslib",
  "host",
  "hostaddr",
  "keepalives",
  "keepalives_count",
  "keepalives_idle",
  "keepalives_interval",
  "krbsrvname",
  "load_balance_hosts",
  "options",
  "passfile",
  "port",
  "requirepeer",
  "service",
  "sslcert",
  "sslcompression",
  "sslcrl",
  "sslcrldir",
  "sslkey",
  "ssl_max_protocol_version",
  "ssl_min_protocol_version",
  "sslmode",
  "sslpassword",
  "sslrootcert",
  "sslsni",
  "target_session_attrs",
  "tcp_user_timeout",
  "user",
]);

export function databaseUrlForPgDump(databaseUrl: string) {
  const url = new URL(databaseUrl);
  if (url.protocol !== "postgresql:" && url.protocol !== "postgres:") {
    throw new Error("DATABASE_URL no usa PostgreSQL");
  }

  // Prisma accepts parameters such as connection_limit, pool_timeout, schema
  // and pgbouncer. libpq rejects unknown URI parameters before connecting, so
  // only its documented connection parameters may reach pg_dump.
  for (const key of [...url.searchParams.keys()]) {
    if (!libpqQueryParameters.has(key)) url.searchParams.delete(key);
  }

  return url.toString();
}

function safePgDumpFailureReason(stderr: string) {
  const versionMismatch = stderr.match(
    /server version:\s*([\d.]+)[\s\S]*pg_dump version:\s*([\d.]+)/i,
  );
  if (versionMismatch) {
    return `Version incompatible: PostgreSQL ${versionMismatch[1]}, pg_dump ${versionMismatch[2]}`;
  }

  const invalidParameter = stderr.match(/invalid URI query parameter:\s*["']([^"']+)["']/i);
  if (invalidParameter) {
    return `Parametro de conexion incompatible: ${invalidParameter[1]}`;
  }
  if (/password authentication failed/i.test(stderr)) {
    return "PostgreSQL rechazo las credenciales configuradas";
  }
  if (/could not translate host name|name or service not known/i.test(stderr)) {
    return "El servidor no pudo resolver el host de PostgreSQL";
  }
  if (/connection refused|could not connect to server/i.test(stderr)) {
    return "El servidor no pudo conectarse a PostgreSQL";
  }
  if (/SSL|certificate verify failed/i.test(stderr)) {
    return "Fallo la configuracion SSL de PostgreSQL";
  }

  return "pg_dump termino con error; revisa el evento temporary-db-export en Railway";
}

function startPostgresDump(databaseUrl: string): DumpProcess {
  const dumpEnvironment = { ...process.env };
  for (const key of Object.keys(dumpEnvironment)) {
    if (
      /(SECRET|TOKEN|PASSWORD|CREDENTIAL|API_KEY|DATABASE.*URL|REDIS_URL)/i.test(key)
    ) {
      delete dumpEnvironment[key];
    }
  }
  dumpEnvironment.PGDATABASE = databaseUrl;

  return spawn(
    pgDumpExecutable(),
    [
      "--format=custom",
      "--compress=6",
      "--no-owner",
      "--no-privileges",
    ],
    {
      // libpq accepts a connection URI in PGDATABASE. Keeping it out of the
      // command arguments prevents credentials from appearing in process lists.
      // Other application secrets are removed from the child environment.
      env: dumpEnvironment,
      stdio: ["ignore", "pipe", "pipe"],
    },
  ) as DumpProcess;
}

function parseTimeoutMs(value: string | undefined) {
  const minutes = Number(value ?? "30");
  if (!Number.isFinite(minutes)) return 30 * 60_000;
  return Math.min(Math.max(minutes, 1), 60) * 60_000;
}

/**
 * TEMPORARY: remove this router and its registration after cloning production.
 * It remains invisible unless all TEMP_DB_EXPORT_* controls are valid.
 */
export function createTemporaryDatabaseExportRouter(
  options: TemporaryDatabaseExportOptions = {},
) {
  const router = Router();
  const env = options.env ?? process.env;
  const now = options.now ?? (() => new Date());
  const startDump = options.startDump ?? startPostgresDump;
  let exportInProgress = false;

  router.get("/", (req, res) => {
    const enabled = env.TEMP_DB_EXPORT_ENABLED === "true";
    const expectedToken = env.TEMP_DB_EXPORT_TOKEN?.trim() ?? "";
    const expiresAt = Date.parse(env.TEMP_DB_EXPORT_EXPIRES_AT ?? "");
    const databaseUrl = env.DATABASE_URL?.trim() ?? "";
    const currentTime = now().getTime();
    const maximumActivationWindowMs = 24 * 60 * 60_000;

    // A missing, invalid, or expired configuration looks exactly like no route.
    if (
      !enabled ||
      expectedToken.length < 32 ||
      !Number.isFinite(expiresAt) ||
      currentTime >= expiresAt ||
      expiresAt - currentTime > maximumActivationWindowMs ||
      !databaseUrl
    ) {
      res.status(404).json({ message: "Recurso no encontrado" });
      return;
    }

    const receivedToken = bearerToken(req.headers.authorization);
    if (!receivedToken || !secureTokenEquals(receivedToken, expectedToken)) {
      res.status(401).json({ message: "Token temporal invalido" });
      return;
    }

    if (exportInProgress) {
      res.status(409).json({ message: "Ya hay una exportacion en curso" });
      return;
    }

    let dumpDatabaseUrl: string;
    try {
      dumpDatabaseUrl = databaseUrlForPgDump(databaseUrl);
    } catch {
      res.status(500).json({
        message: "DATABASE_URL no es una conexion PostgreSQL valida",
      });
      return;
    }

    exportInProgress = true;
    let child: DumpProcess;

    try {
      child = startDump(dumpDatabaseUrl);
    } catch {
      exportInProgress = false;
      res.status(503).json({
        message: "La herramienta de respaldo no esta disponible en el servidor",
      });
      return;
    }

    let handled = false;
    let stderrBytes = 0;
    let stderr = "";
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
    }, parseTimeoutMs(env.TEMP_DB_EXPORT_TIMEOUT_MINUTES));
    timeout.unref();

    const finish = () => {
      if (handled) return false;
      handled = true;
      clearTimeout(timeout);
      exportInProgress = false;
      return true;
    };

    const cancelIfDisconnected = () => {
      if (!handled && child.exitCode === null) child.kill("SIGTERM");
    };

    req.once("aborted", cancelIfDisconnected);
    res.once("close", () => {
      if (!res.writableEnded) cancelIfDisconnected();
    });

    child.stderr.on("data", (chunk: Buffer | string) => {
      stderrBytes += Buffer.byteLength(chunk);
      // The raw text is never logged or returned because it may include host or
      // user details. It is kept only to derive a safe error category.
      if (stderr.length < 16_000) stderr += chunk.toString();
    });

    child.once("spawn", () => {
      const timestamp = now().toISOString().replace(/[:.]/g, "-");
      res.status(200);
      res.setHeader("Content-Type", "application/octet-stream");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="controlapp-production-${timestamp}.dump"`,
      );
      res.setHeader("Cache-Control", "no-store, max-age=0");
      res.setHeader("Pragma", "no-cache");
      child.stdout.pipe(res, { end: false });
    });

    child.once("error", () => {
      if (!finish()) return;
      if (!res.headersSent) {
        res.status(503).json({
          message: "La herramienta de respaldo no esta disponible en el servidor",
        });
        return;
      }
      res.destroy();
    });

    child.once("close", (code, signal) => {
      if (!finish()) return;
      if (code === 0) {
        res.end();
        return;
      }

      console.error("[temporary-db-export] pg_dump no pudo completar el respaldo", {
        code,
        signal,
        stderrBytes,
      });
      if (!res.headersSent) {
        res.removeHeader("Content-Disposition");
        res.type("json").status(500).json({
          message: "No se pudo generar el respaldo",
          reason: safePgDumpFailureReason(stderr),
        });
        return;
      }
      res.destroy();
    });
  });

  return router;
}

export default createTemporaryDatabaseExportRouter();
