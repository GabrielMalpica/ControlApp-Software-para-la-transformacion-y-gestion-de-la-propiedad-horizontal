import { spawn, type ChildProcess } from "child_process";
import { createHash, timingSafeEqual } from "crypto";
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
    "pg_dump",
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

    exportInProgress = true;
    let child: DumpProcess;

    try {
      child = startDump(databaseUrl);
    } catch {
      exportInProgress = false;
      res.status(503).json({
        message: "La herramienta de respaldo no esta disponible en el servidor",
      });
      return;
    }

    let handled = false;
    let stderrBytes = 0;
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
      // Do not log pg_dump output: connection errors can contain production
      // host/user details. The byte count is enough for operational diagnosis.
      stderrBytes += Buffer.byteLength(chunk);
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
        res.status(500).json({ message: "No se pudo generar el respaldo" });
        return;
      }
      res.destroy();
    });
  });

  return router;
}

export default createTemporaryDatabaseExportRouter();
