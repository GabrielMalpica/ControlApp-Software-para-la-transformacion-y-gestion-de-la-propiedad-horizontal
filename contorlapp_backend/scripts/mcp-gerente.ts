// Habilita o deshabilita el acceso por IA (MCP) de un gerente.
//   npx tsx scripts/mcp-gerente.ts listar
//   npx tsx scripts/mcp-gerente.ts habilitar <correo-o-cedula>            (simulacion)
//   npx tsx scripts/mcp-gerente.ts habilitar <correo-o-cedula> --apply
//   npx tsx scripts/mcp-gerente.ts deshabilitar <correo-o-cedula> --apply (revoca sus conexiones)
// Contra una base que no sea local exige ademas --permitir-remoto.
import "dotenv/config";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const [accion, objetivo] = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const APPLY = process.argv.includes("--apply");
const PERMITIR_REMOTO = process.argv.includes("--permitir-remoto");

function destino() {
  try {
    const u = new URL(process.env.DATABASE_URL ?? "");
    return { host: u.hostname, base: u.pathname.replace(/^\//, "") };
  } catch {
    return { host: "?", base: "?" };
  }
}

async function main() {
  const { host, base } = destino();
  const local = ["localhost", "127.0.0.1", "::1"].includes(host);
  console.log(`Base: ${base} en ${host}`);
  if (APPLY && !local && !PERMITIR_REMOTO) {
    throw new Error("La base no es local: agrega --permitir-remoto si de verdad quieres aplicar el cambio.");
  }

  if (accion === "listar") {
    const gerentes = await prisma.gerente.findMany({
      select: { id: true, mcpHabilitado: true, usuario: { select: { nombre: true, correo: true, activo: true } } },
      orderBy: { usuario: { nombre: "asc" } },
    });
    for (const g of gerentes) {
      console.log(`${g.mcpHabilitado ? "[IA ✓]" : "[IA ✗]"} ${g.usuario.nombre} <${g.usuario.correo}>${g.usuario.activo ? "" : " (inactivo)"}`);
    }
    return;
  }

  if (!["habilitar", "deshabilitar"].includes(accion ?? "") || !objetivo) {
    throw new Error("Uso: mcp-gerente.ts listar | habilitar <correo-o-cedula> | deshabilitar <correo-o-cedula> [--apply]");
  }
  const usuario = await prisma.usuario.findFirst({
    where: { OR: [{ id: objetivo }, { correo: { equals: objetivo, mode: "insensitive" } }] },
    select: { id: true, nombre: true, rol: true, activo: true, gerente: { select: { mcpHabilitado: true } } },
  });
  if (!usuario || usuario.rol !== "gerente" || !usuario.gerente) {
    throw new Error("No existe un gerente con ese correo o cédula. Solo los gerentes pueden usar el MCP.");
  }
  const habilitar = accion === "habilitar";
  console.log(`${usuario.nombre}: acceso por IA ${usuario.gerente.mcpHabilitado ? "habilitado" : "deshabilitado"} -> ${habilitar ? "habilitado" : "deshabilitado"}`);
  if (!APPLY) {
    console.log("Simulación: no se cambió nada. Agrega --apply para aplicar.");
    return;
  }
  await prisma.$transaction(async (tx) => {
    await tx.gerente.update({ where: { id: usuario.id }, data: { mcpHabilitado: habilitar } });
    if (!habilitar) {
      const conexiones = await tx.mcpConexion.findMany({
        where: { usuarioId: usuario.id, estado: { in: ["ACTIVA", "SUSPENDIDA"] } },
        select: { id: true },
      });
      await tx.mcpRefreshToken.updateMany({
        where: { conexionId: { in: conexiones.map((c) => c.id) }, revocadoEn: null },
        data: { revocadoEn: new Date() },
      });
      await tx.mcpConexion.updateMany({
        where: { id: { in: conexiones.map((c) => c.id) } },
        data: { estado: "REVOCADA", revocadaEn: new Date(), motivoRevocacion: "MCP_DESHABILITADO_PARA_GERENTE" },
      });
      console.log(`Conexiones revocadas: ${conexiones.length}`);
    }
    await tx.auditoriaEvento.create({
      data: {
        modulo: "SEGURIDAD",
        entidad: "Gerente",
        entidadId: usuario.id,
        accion: habilitar ? "MCP_HABILITAR_GERENTE" : "MCP_DESHABILITAR_GERENTE",
        origen: "SCRIPT",
        descripcion: `Acceso por IA ${habilitar ? "habilitado" : "deshabilitado"} para ${usuario.nombre} (scripts/mcp-gerente.ts).`,
      },
    });
  });
  console.log("Listo. Surte efecto en máximo 30 segundos.");
}

main()
  .catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
