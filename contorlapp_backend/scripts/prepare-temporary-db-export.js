const { randomBytes } = require("crypto");

const minutesArgument = process.argv[2] ?? "60";
const minutes = Number(minutesArgument);

if (!Number.isInteger(minutes) || minutes < 10 || minutes > 1440) {
  console.error("Uso: npm run db:prepare-production-export -- [minutos: 10-1440]");
  process.exitCode = 1;
} else {
  const expiresAt = new Date(Date.now() + minutes * 60_000).toISOString();
  const token = randomBytes(32).toString("base64url");

  console.log("Copia estas tres variables en el servicio del backend en Railway:");
  console.log("");
  console.log("TEMP_DB_EXPORT_ENABLED=true");
  console.log(`TEMP_DB_EXPORT_TOKEN=${token}`);
  console.log(`TEMP_DB_EXPORT_EXPIRES_AT=${expiresAt}`);
  console.log("");
  console.log("No guardes el token en Git. Al terminar, elimina las tres variables.");
}
