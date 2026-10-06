/**
 * Informa a qué base de datos se conecta el servidor (sin credenciales) y
 * avisa cuando un servidor de desarrollo apunta a una base remota.
 *
 * Caso real: una variable DATABASE_URL ya definida en la terminal le gana al
 * `.env` (dotenv no la sobrescribe), y `npm run dev` termina escribiendo en la
 * base de producción sin que se note.
 */
export function describirBaseDeDatos(url: string | undefined): {
  host: string;
  base: string;
  local: boolean;
} | null {
  if (!url) return null;
  try {
    const u = new URL(url);
    const host = `${u.hostname}${u.port ? `:${u.port}` : ""}`;
    const local = ["localhost", "127.0.0.1", "::1", "[::1]", "host.docker.internal"].includes(
      u.hostname,
    );
    return { host, base: u.pathname.replace(/^\//, ""), local };
  } catch {
    return null;
  }
}

export function avisarBaseDeDatos(env: NodeJS.ProcessEnv = process.env): void {
  const info = describirBaseDeDatos(env.DATABASE_URL);
  if (!info) return;

  console.log(`[db] Base de datos: ${info.base} @ ${info.host}${info.local ? " (local)" : " (REMOTA)"}`);

  const enNube = env.NODE_ENV === "production" || Boolean(env.RAILWAY_ENVIRONMENT);
  if (!info.local && !enNube) {
    console.warn(
      "[db] ATENCION: este servidor NO es de produccion pero apunta a una base REMOTA. " +
        "Si no era a proposito, tu terminal tiene DATABASE_URL definida y le gana al .env: " +
        "ejecuta `Remove-Item Env:DATABASE_URL` (PowerShell) o abre una terminal nueva y reinicia.",
    );
  }
}
