const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const { pipeline } = require("stream/promises");
const { Readable } = require("stream");
const dotenv = require("dotenv");

const backendRoot = path.resolve(__dirname, "..");
dotenv.config({ path: path.join(backendRoot, ".env"), quiet: true });

function usage() {
  console.log(`Uso:
  $env:TEMP_DB_EXPORT_TOKEN="token-de-railway"
  npm run db:clone-production -- --api-url https://tu-api.up.railway.app --yes-replace-local

Opciones:
  --api-url URL             URL base de la API o URL completa del endpoint
  --yes-replace-local       Confirma que se reemplazara la base local
  --download-only           Solo descarga y valida el .dump
  --keep-dump               Conserva los respaldos en contorlapp_backend/tmp
  --help                    Muestra esta ayuda

Tambien puedes definir TEMP_DB_EXPORT_URL en lugar de --api-url.
El token solo se lee desde TEMP_DB_EXPORT_TOKEN para no dejarlo en el historial.`);
}

function parseArguments(argv) {
  const options = {
    apiUrl: process.env.TEMP_DB_EXPORT_URL ?? "",
    confirmReplace: false,
    downloadOnly: false,
    keepDump: false,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--api-url") {
      options.apiUrl = argv[index + 1] ?? "";
      index += 1;
    } else if (argument === "--yes-replace-local") {
      options.confirmReplace = true;
    } else if (argument === "--download-only") {
      options.downloadOnly = true;
    } else if (argument === "--keep-dump") {
      options.keepDump = true;
    } else if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else {
      throw new Error(`Opcion desconocida: ${argument}`);
    }
  }

  return options;
}

function exportEndpoint(rawUrl) {
  const url = new URL(rawUrl);
  const localHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);
  if (url.protocol !== "https:" && !localHosts.has(url.hostname)) {
    throw new Error("La descarga remota debe usar HTTPS");
  }

  const endpointPath = "/internal/temporary/database-export";
  if (!url.pathname.endsWith(endpointPath)) {
    url.pathname = `${url.pathname.replace(/\/$/, "")}${endpointPath}`;
  }
  url.search = "";
  url.hash = "";
  return url.toString();
}

function decodeUrlPart(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function localDatabaseConfig(rawUrl) {
  const url = new URL(rawUrl);
  if (url.protocol !== "postgresql:" && url.protocol !== "postgres:") {
    throw new Error("DATABASE_URL local debe ser una URL de PostgreSQL");
  }

  const localHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);
  if (!localHosts.has(url.hostname)) {
    throw new Error(
      `Proteccion activada: DATABASE_URL apunta a ${url.hostname}, no a localhost`,
    );
  }

  const database = decodeUrlPart(url.pathname.replace(/^\//, ""));
  if (!database || ["postgres", "template0", "template1"].includes(database)) {
    throw new Error(`No se permite reemplazar la base local "${database}"`);
  }

  const sslMode = url.searchParams.get("sslmode");
  return {
    host: url.hostname === "[::1]" ? "::1" : url.hostname,
    port: url.port || "5432",
    user: decodeUrlPart(url.username),
    password: decodeUrlPart(url.password),
    database,
    sslMode,
  };
}

function executableName(name) {
  return process.platform === "win32" ? `${name}.exe` : name;
}

function findPostgresBin() {
  const candidates = [];
  if (process.env.PG_BIN) candidates.push(process.env.PG_BIN);

  if (process.platform === "win32") {
    const programFiles = process.env.ProgramFiles ?? "C:\\Program Files";
    const postgresRoot = path.join(programFiles, "PostgreSQL");
    if (fs.existsSync(postgresRoot)) {
      const versions = fs
        .readdirSync(postgresRoot, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name)
        .sort((a, b) => Number(b) - Number(a));
      for (const version of versions) {
        candidates.push(path.join(postgresRoot, version, "bin"));
      }
    }
  } else {
    for (const directory of (process.env.PATH ?? "").split(path.delimiter)) {
      candidates.push(directory);
    }
  }

  const required = ["pg_dump", "pg_restore", "dropdb", "createdb"];
  for (const directory of candidates) {
    if (
      directory &&
      required.every((name) => fs.existsSync(path.join(directory, executableName(name))))
    ) {
      return directory;
    }
  }

  throw new Error(
    "No se encontraron pg_dump, pg_restore, dropdb y createdb. Define PG_BIN con la carpeta bin de PostgreSQL.",
  );
}

function connectionArguments(config) {
  const args = ["--host", config.host, "--port", config.port];
  if (config.user) args.push("--username", config.user);
  return args;
}

function postgresEnvironment(config) {
  const env = sanitizedProcessEnvironment();
  if (config.password) env.PGPASSWORD = config.password;
  if (config.sslMode) env.PGSSLMODE = config.sslMode;
  return env;
}

function sanitizedProcessEnvironment() {
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    if (/(SECRET|TOKEN|PASSWORD|CREDENTIAL|API_KEY|DATABASE.*URL|REDIS_URL)/i.test(key)) {
      delete env[key];
    }
  }
  return env;
}

function runTool(executable, args, env, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      env,
      stdio: ["ignore", options.showOutput ? "inherit" : "ignore", "pipe"],
      windowsHide: true,
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => {
      if (stderr.length < 16_000) stderr += chunk.toString();
    });
    child.once("error", reject);
    child.once("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(stderr.trim() || `${path.basename(executable)} termino con codigo ${code}`));
    });
  });
}

async function downloadDump(endpoint, token, destination) {
  console.log("Descargando respaldo cifrado en transito desde produccion...");
  const response = await fetch(endpoint, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/octet-stream",
    },
    signal: AbortSignal.timeout(30 * 60_000),
  });

  if (!response.ok || !response.body) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`La API respondio ${response.status}: ${detail}`);
  }

  await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(destination));
  const magic = Buffer.alloc(5);
  const handle = await fs.promises.open(destination, "r");
  try {
    await handle.read(magic, 0, magic.length, 0);
  } finally {
    await handle.close();
  }

  if (magic.toString("ascii") !== "PGDMP") {
    throw new Error("El archivo recibido no es un respaldo valido de PostgreSQL");
  }
}

async function recreateDatabase(tools, config, env) {
  const connection = connectionArguments(config);
  await runTool(
    tools.dropdb,
    [...connection, "--maintenance-db", "postgres", "--if-exists", "--force", config.database],
    env,
  );
  await runTool(
    tools.createdb,
    [...connection, "--maintenance-db", "postgres", config.database],
    env,
  );
}

async function restoreDump(tools, config, env, dumpPath) {
  await runTool(
    tools.pgRestore,
    [
      ...connectionArguments(config),
      "--dbname",
      config.database,
      "--exit-on-error",
      "--no-owner",
      "--no-privileges",
      dumpPath,
    ],
    env,
  );
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) {
    usage();
    return;
  }

  if (!options.apiUrl) throw new Error("Falta --api-url o TEMP_DB_EXPORT_URL");
  const token = process.env.TEMP_DB_EXPORT_TOKEN?.trim() ?? "";
  if (token.length < 32) {
    throw new Error("Falta TEMP_DB_EXPORT_TOKEN o tiene menos de 32 caracteres");
  }
  if (!options.downloadOnly && !options.confirmReplace) {
    throw new Error(
      "Debes agregar --yes-replace-local para confirmar el reemplazo de la base local",
    );
  }

  const endpoint = exportEndpoint(options.apiUrl);
  const localConfig = options.downloadOnly
    ? null
    : localDatabaseConfig(process.env.DATABASE_URL ?? "");
  const pgBin = findPostgresBin();
  const tools = {
    pgDump: path.join(pgBin, executableName("pg_dump")),
    pgRestore: path.join(pgBin, executableName("pg_restore")),
    dropdb: path.join(pgBin, executableName("dropdb")),
    createdb: path.join(pgBin, executableName("createdb")),
  };

  const tempDirectory = path.join(backendRoot, "tmp");
  await fs.promises.mkdir(tempDirectory, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const productionDump = path.join(tempDirectory, `production-${stamp}.dump`);
  const localSafetyDump = path.join(tempDirectory, `local-before-clone-${stamp}.dump`);
  let localBackupCreated = false;
  let restoreCompleted = false;

  try {
    await downloadDump(endpoint, token, productionDump);
    await runTool(
      tools.pgRestore,
      ["--list", productionDump],
      sanitizedProcessEnvironment(),
    );
    console.log("Respaldo de produccion descargado y validado.");

    if (options.downloadOnly) {
      console.log(`Archivo conservado en: ${productionDump}`);
      return;
    }

    const env = postgresEnvironment(localConfig);
    console.log(`Creando respaldo de seguridad de la base local "${localConfig.database}"...`);
    await runTool(
      tools.pgDump,
      [
        ...connectionArguments(localConfig),
        "--dbname",
        localConfig.database,
        "--format=custom",
        "--compress=6",
        "--no-owner",
        "--no-privileges",
        "--file",
        localSafetyDump,
      ],
      env,
    );
    localBackupCreated = true;

    console.log(`Reemplazando solamente la base local "${localConfig.database}"...`);
    await recreateDatabase(tools, localConfig, env);
    try {
      await restoreDump(tools, localConfig, env, productionDump);
      restoreCompleted = true;
    } catch (restoreError) {
      console.error("La restauracion fallo; recuperando automaticamente la base local anterior...");
      await recreateDatabase(tools, localConfig, env);
      await restoreDump(tools, localConfig, env, localSafetyDump);
      throw restoreError;
    }

    console.log("Base de produccion clonada correctamente en desarrollo local.");
  } finally {
    if (restoreCompleted && !options.keepDump) {
      await fs.promises.rm(productionDump, { force: true });
      if (localBackupCreated) await fs.promises.rm(localSafetyDump, { force: true });
      console.log("Los archivos temporales sensibles fueron eliminados.");
    } else if (fs.existsSync(productionDump) && !options.downloadOnly) {
      console.log(`El respaldo descargado se conservo para diagnostico: ${productionDump}`);
      if (localBackupCreated) {
        console.log(`El respaldo local de seguridad se conservo en: ${localSafetyDump}`);
      }
    }
  }
}

main().catch((error) => {
  console.error(`ERROR: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
