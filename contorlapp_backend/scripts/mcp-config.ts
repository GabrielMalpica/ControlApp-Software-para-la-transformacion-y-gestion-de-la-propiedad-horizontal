// Interruptores del MCP en caliente (sin redeploy), en ConfiguracionSistema.
// Surten efecto en <=15 s en el servicio MCP.
//   npx tsx scripts/mcp-config.ts estado
//   npx tsx scripts/mcp-config.ts apagar --apply                         (kill switch global)
//   npx tsx scripts/mcp-config.ts encender --apply
//   npx tsx scripts/mcp-config.ts deshabilitar-herramienta <nombre> --apply
//   npx tsx scripts/mcp-config.ts habilitar-herramienta <nombre> --apply
// Contra una base que no sea local exige ademas --permitir-remoto.
// Ver docs/mcp/runbook-kill-switch.md.
import "dotenv/config";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const [accion, nombre] = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const APPLY = process.argv.includes("--apply");
const PERMITIR_REMOTO = process.argv.includes("--permitir-remoto");
const CLAVE_GLOBAL = "mcp.habilitado";
const CLAVE_HERRAMIENTAS = "mcp.herramientas.deshabilitadas";

async function leer(clave: string) {
  return (await prisma.configuracionSistema.findUnique({ where: { clave } }))?.valor ?? "";
}

async function escribir(clave: string, valor: string) {
  if (!APPLY) {
    console.log(`Simulación: ${clave}=${valor}. Agrega --apply para aplicar.`);
    return;
  }
  await prisma.configuracionSistema.upsert({ where: { clave }, create: { clave, valor }, update: { valor } });
  console.log(`Listo: ${clave}=${valor}`);
}

async function main() {
  const url = (() => {
    try {
      return new URL(process.env.DATABASE_URL ?? "");
    } catch {
      return null;
    }
  })();
  const local = url ? ["localhost", "127.0.0.1", "::1"].includes(url.hostname) : false;
  if (APPLY && !local && !PERMITIR_REMOTO) throw new Error("Base no local: agrega --permitir-remoto.");

  const deshabilitadas = (await leer(CLAVE_HERRAMIENTAS)).split(",").map((s) => s.trim()).filter(Boolean);
  switch (accion) {
    case "estado":
      console.log(`MCP global: ${(await leer(CLAVE_GLOBAL)) === "false" ? "APAGADO" : "encendido (si MCP_ENABLED=true)"}`);
      console.log(`Herramientas deshabilitadas: ${deshabilitadas.join(", ") || "ninguna"}`);
      return;
    case "apagar":
      return escribir(CLAVE_GLOBAL, "false");
    case "encender":
      return escribir(CLAVE_GLOBAL, "true");
    case "deshabilitar-herramienta":
      if (!nombre) throw new Error("Indica el nombre de la herramienta.");
      return escribir(CLAVE_HERRAMIENTAS, [...new Set([...deshabilitadas, nombre])].join(","));
    case "habilitar-herramienta":
      if (!nombre) throw new Error("Indica el nombre de la herramienta.");
      return escribir(CLAVE_HERRAMIENTAS, deshabilitadas.filter((h) => h !== nombre).join(","));
    default:
      throw new Error("Uso: mcp-config.ts estado | apagar | encender | deshabilitar-herramienta <n> | habilitar-herramienta <n> [--apply]");
  }
}

main()
  .catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
