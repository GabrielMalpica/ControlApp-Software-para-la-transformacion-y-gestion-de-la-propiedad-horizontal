// Asigna categoría a las preventivas activas que todavía no la tienen, con las
// reglas de src/utils/clasificarPreventiva.ts (piscinas, jardinería -incluye
// poda y guadaña-, aseo, mantenimientos básicos, salvamento).
//
// - NUNCA cambia una categoría ya asignada (las que se pusieron a mano se respetan).
// - Respeta las capacidades: si la plaza responsable tiene un perfil con
//   categorías configuradas que no incluyen la categoría, esa preventiva se
//   omite y se reporta (igual que en la API).
// - Lo que ninguna regla reconoce se deja sin categoría y se lista.
// - Además copia la categoría y el orden interno de cada preventiva a sus TAREAS
//   ya generadas (borrador y publicadas) que aún no la tienen; antes solo se
//   copiaba al generar. No cambia fechas, operarios ni estado.
// - Es idempotente.
//
// Uso (desde contorlapp_backend):
//   npx tsx scripts/categorizar-preventivas.ts                    (simulación, no escribe)
//   npx tsx scripts/categorizar-preventivas.ts --apply            (aplica)
//   npx tsx scripts/categorizar-preventivas.ts --conjunto <nit>   (un solo conjunto)
// Contra una base que no sea local exige además --permitir-remoto.
import "dotenv/config";
import { PrismaClient } from "@prisma/client";

import { CatalogoOperativoService } from "../src/services/CatalogoOperativoService";
import { clasificarCategoriaPreventiva } from "../src/utils/clasificarPreventiva";
import { normalizarTexto } from "../src/utils/perfilOperativo";

const prisma = new PrismaClient();
const APPLY = process.argv.includes("--apply");
const PERMITIR_REMOTO = process.argv.includes("--permitir-remoto");
const idx = process.argv.indexOf("--conjunto");
const SOLO_CONJUNTO = idx >= 0 ? process.argv[idx + 1] : undefined;

function destino(): { host: string; base: string } {
  try {
    const u = new URL(process.env.DATABASE_URL ?? "");
    return { host: u.hostname, base: u.pathname.replace(/^\//, "") };
  } catch {
    return { host: "?", base: "?" };
  }
}

async function main() {
  const { host, base } = destino();
  console.log(`Base: ${base} @ ${host} · modo: ${APPLY ? "APLICAR" : "simulación"}`);
  const local = ["localhost", "127.0.0.1", "::1"].includes(host);
  if (!local && !PERMITIR_REMOTO) {
    console.error("La base no es local. Para correrlo aquí agrega --permitir-remoto (con respaldo previo).");
    process.exit(1);
  }

  const servicio = new CatalogoOperativoService(prisma);
  const conjuntos = await prisma.conjunto.findMany({
    where: {
      ...(SOLO_CONJUNTO ? { nit: SOLO_CONJUNTO } : {}),
      empresaId: { not: null },
      DefinicionTareaPreventiva: { some: { activo: true, categoriaId: null } },
    },
    select: { nit: true, nombre: true, empresaId: true },
    orderBy: { nombre: "asc" },
  });
  if (!conjuntos.length) {
    console.log("Nada que categorizar: todas las preventivas activas ya tienen categoría.");
    await sincronizarTareas();
    if (!APPLY) console.log("No se escribió nada. Corre con --apply para aplicar.");
    return;
  }

  const total = { aplicables: 0, omitidas: 0, sinRegla: 0 };
  const globalPorCategoria = new Map<string, number>();
  for (const conjunto of conjuntos) {
    await servicio.asegurarCategoriasPorDefecto(conjunto.empresaId as string);
    const categorias = await prisma.categoriaTarea.findMany({
      where: { empresaId: conjunto.empresaId as string, activa: true },
      select: { id: true, nombre: true },
    });
    const idPorNombre = new Map(categorias.map((c) => [normalizarTexto(c.nombre), c]));

    const defs = await prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId: conjunto.nit, activo: true, categoriaId: null },
      select: {
        id: true,
        descripcion: true,
        elemento: { select: { nombre: true } },
        necesidades: { select: { id: true } },
        operarios: { select: { id: true } },
      },
      orderBy: { id: "asc" },
    });

    const porCategoria = new Map<number, number[]>();
    const nombreDe = new Map<number, string>();
    const sinRegla: string[] = [];
    const omitidas: string[] = [];
    for (const def of defs) {
      const nombre = clasificarCategoriaPreventiva(def.descripcion, def.elemento?.nombre ?? "");
      const categoria = nombre ? idPorNombre.get(normalizarTexto(nombre)) : undefined;
      if (!categoria) {
        sinRegla.push(`#${def.id} ${def.descripcion.slice(0, 60)}${nombre ? ` (categoría '${nombre}' no existe/está inactiva)` : ""}`);
        continue;
      }
      const incompat = await servicio.incompatibilidadesCategoria({
        conjuntoId: conjunto.nit,
        categoriaId: categoria.id,
        categoriaNombre: categoria.nombre,
        necesidadesIds: def.necesidades.map((n) => n.id),
        operariosIds: def.operarios.map((o) => o.id),
      });
      if (incompat.length) {
        omitidas.push(`#${def.id} ${def.descripcion.slice(0, 45)} → ${categoria.nombre}: ${incompat[0]}`);
        continue;
      }
      porCategoria.set(categoria.id, [...(porCategoria.get(categoria.id) ?? []), def.id]);
      nombreDe.set(categoria.id, categoria.nombre);
    }

    const aplicables = [...porCategoria.values()].reduce((a, l) => a + l.length, 0);
    total.aplicables += aplicables;
    total.omitidas += omitidas.length;
    total.sinRegla += sinRegla.length;
    console.log(`\n${conjunto.nombre} (${conjunto.nit}): ${defs.length} sin categoría → ${aplicables} a categorizar, ${omitidas.length} omitida(s) por perfil, ${sinRegla.length} sin regla`);
    for (const [catId, ids] of porCategoria) {
      const n = nombreDe.get(catId) as string;
      console.log(`  ${n}: ${ids.length}`);
      globalPorCategoria.set(n, (globalPorCategoria.get(n) ?? 0) + ids.length);
    }
    for (const o of omitidas.slice(0, 8)) console.log(`  ! omitida ${o}`);
    for (const s of sinRegla.slice(0, 8)) console.log(`  ? sin regla ${s}`);

    if (APPLY) {
      for (const [catId, ids] of porCategoria) {
        const r = await servicio.asignarCategoriaLote(conjunto.nit, { ids, categoriaId: catId });
        console.log(`  -> ${nombreDe.get(catId)}: ${r.actualizadas} actualizada(s)${r.omitidas.length ? `, ${r.omitidas.length} omitida(s)` : ""}`);
      }
    }
  }

  await sincronizarTareas();

  console.log(`\nTOTAL ${APPLY ? "(aplicado)" : "(simulación)"}: ${total.aplicables} a categorizar, ${total.omitidas} omitidas por perfil, ${total.sinRegla} sin regla.`);
  for (const [n, c] of globalPorCategoria) console.log(`  ${n}: ${c}`);
  if (!APPLY) console.log("No se escribió nada. Corre con --apply para aplicar.");
}

/**
 * Copia categoriaId/ordenEnCategoria de la preventiva a las tareas que ya
 * existen y aun no la tienen. Una sola sentencia SQL por conjunto de tareas.
 */
async function sincronizarTareas() {
  const filtroConjunto = SOLO_CONJUNTO ? `AND t."conjuntoId" = '${SOLO_CONJUNTO.replace(/'/g, "''")}'` : "";
  const pendientes = await prisma.$queryRawUnsafe<Array<{ n: bigint }>>(
    `SELECT count(*)::bigint AS n FROM "Tarea" t JOIN "DefinicionTareaPreventiva" d ON d.id = t."definicionId"
     WHERE t."categoriaId" IS NULL AND d."categoriaId" IS NOT NULL ${filtroConjunto}`,
  );
  const n = Number(pendientes[0]?.n ?? 0);
  console.log(`\nTareas ya generadas sin categoría cuya preventiva sí la tiene: ${n}`);
  if (APPLY && n > 0) {
    const actualizadas = await prisma.$executeRawUnsafe(
      `UPDATE "Tarea" t SET "categoriaId" = d."categoriaId", "ordenEnCategoria" = d."ordenEnCategoria"
       FROM "DefinicionTareaPreventiva" d
       WHERE d.id = t."definicionId" AND t."categoriaId" IS NULL AND d."categoriaId" IS NOT NULL ${filtroConjunto}`,
    );
    console.log(`  -> ${actualizadas} tarea(s) sincronizada(s)`);
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
