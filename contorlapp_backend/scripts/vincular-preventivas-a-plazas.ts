// Migra las preventivas del "viejo estándar" (operarios directos) al modelo de
// plazas (necesidades): para cada conjunto
//   1) crea una plaza por cada operario del conjunto que aún no ocupa una
//      (roles = funciones del operario, perfil del catálogo de su combinación;
//      horario general del conjunto, sin horario especial: la generación
//      queda igual que antes), y
//   2) vincula cada preventiva activa a la(s) plaza(s) de sus operarios.
//
// Las preventivas conservan sus operarios directos como respaldo. Con la plaza
// vinculada, el generador resuelve el responsable por la plaza (reemplazar al
// titular ya no requiere editar preventivas) y las capacidades del perfil
// aplican igual. Las tareas ya generadas/publicadas NO se modifican.
//
// Reutiliza ConjuntoNecesidadService (migrarDesdeOperariosActuales y
// vincularDefinicionesConNecesidades). Es idempotente: se puede correr varias veces.
// Una preventiva se vincula solo si TODOS sus operarios tienen plaza; las demás
// se reportan con el motivo.
//
// Uso (desde contorlapp_backend):
//   npx tsx scripts/vincular-preventivas-a-plazas.ts                    (simulación, no escribe)
//   npx tsx scripts/vincular-preventivas-a-plazas.ts --apply            (aplica)
//   npx tsx scripts/vincular-preventivas-a-plazas.ts --conjunto <nit>   (un solo conjunto)
// Por seguridad, contra una base que no sea local exige además --permitir-remoto.
import "dotenv/config";
import { PrismaClient } from "@prisma/client";

import { ConjuntoNecesidadService } from "../src/services/ConjuntoNecesidadService";
import { planificarMigracionPlazas } from "../src/utils/migracionPlazas";

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
    console.error(
      "La base no es local. Si de verdad quieres correrlo aquí, agrega --permitir-remoto (haz un respaldo antes).",
    );
    process.exit(1);
  }

  const conjuntos = await prisma.conjunto.findMany({
    where: {
      ...(SOLO_CONJUNTO ? { nit: SOLO_CONJUNTO } : {}),
      DefinicionTareaPreventiva: {
        some: { activo: true, necesidades: { none: {} }, operarios: { some: {} } },
      },
    },
    select: { nit: true, nombre: true },
    orderBy: { nombre: "asc" },
  });
  if (!conjuntos.length) {
    console.log("Nada que migrar: no hay preventivas activas con operarios directos y sin plaza.");
    return;
  }

  let totalPlazas = 0;
  let totalVincular = 0;
  let totalSaltadas = 0;
  for (const conjunto of conjuntos) {
    const [operarios, plazas, defs] = await Promise.all([
      prisma.operario.findMany({
        where: { conjuntos: { some: { nit: conjunto.nit } } },
        select: { id: true, funciones: true },
      }),
      prisma.conjuntoNecesidadOperario.findMany({
        where: { conjuntoId: conjunto.nit },
        select: { operarioId: true },
      }),
      prisma.definicionTareaPreventiva.findMany({
        where: {
          conjuntoId: conjunto.nit,
          activo: true,
          necesidades: { none: {} },
          operarios: { some: {} },
        },
        select: { id: true, descripcion: true, operarios: { select: { id: true } } },
      }),
    ]);
    const plan = planificarMigracionPlazas({
      operarios,
      plazas,
      defs: defs.map((d) => ({
        id: d.id,
        descripcion: d.descripcion,
        operariosIds: d.operarios.map((o) => o.id),
      })),
    });
    totalPlazas += plan.plazasACrear.length;
    totalVincular += plan.defsVincular.length;
    totalSaltadas += plan.defsSaltadas.length;

    console.log(
      `\n${conjunto.nombre} (${conjunto.nit}): ${plan.plazasACrear.length} plaza(s) por crear, ` +
        `${plan.defsVincular.length} preventiva(s) por vincular, ${plan.defsSaltadas.length} saltada(s)`,
    );
    for (const p of plan.plazasACrear) console.log(`  + plaza para ${p.operarioId} [${p.roles.join("+")}]`);
    for (const s of plan.defsSaltadas.slice(0, 10)) {
      console.log(`  ! preventiva ${s.id} "${s.descripcion.slice(0, 50)}": ${s.motivo}`);
    }
    if (plan.defsSaltadas.length > 10) console.log(`  ! …y ${plan.defsSaltadas.length - 10} saltada(s) más`);

    if (APPLY) {
      const servicio = new ConjuntoNecesidadService(prisma, conjunto.nit);
      const creadas = await servicio.migrarDesdeOperariosActuales();
      const vinculo = await servicio.vincularDefinicionesConNecesidades();
      console.log(
        `  -> aplicado: ${creadas.creadas.length} plaza(s) creada(s), ` +
          `${vinculo.vinculadas.length} preventiva(s) vinculada(s), ${vinculo.saltadas.length} saltada(s)`,
      );
    }
  }

  await reportarDesfases();

  console.log(
    `\nTOTAL ${APPLY ? "(aplicado)" : "(simulación)"}: ${totalPlazas} plaza(s), ` +
      `${totalVincular} preventiva(s) a vincular, ${totalSaltadas} saltada(s).`,
  );
  if (!APPLY) console.log("No se escribió nada. Corre con --apply para aplicar.");
}

/**
 * Solo informa (no cambia nada): preventivas que YA tienen plazas pero cuyo
 * equipo efectivo (ocupantes de las plazas) no coincide con sus operarios
 * directos. El generador usa las plazas, no los operarios directos; si fue
 * una edicion a medias (p. ej. se eligio un solo cargo de una cuadrilla de 3),
 * conviene revisarla.
 */
async function reportarDesfases() {
  const defs = await prisma.definicionTareaPreventiva.findMany({
    where: {
      activo: true,
      necesidades: { some: {} },
      operarios: { some: {} },
      ...(SOLO_CONJUNTO ? { conjuntoId: SOLO_CONJUNTO } : {}),
    },
    select: {
      id: true,
      descripcion: true,
      conjunto: { select: { nombre: true } },
      operarios: { select: { id: true, usuario: { select: { nombre: true } } } },
      necesidades: { select: { etiqueta: true, operarioId: true } },
    },
    orderBy: [{ conjuntoId: "asc" }, { id: "asc" }],
  });
  const desfasadas = defs.filter((d) => {
    const directos = new Set(d.operarios.map((o) => o.id));
    const efectivos = new Set(
      d.necesidades.map((n) => n.operarioId).filter((id): id is string => id != null),
    );
    return (
      directos.size !== efectivos.size ||
      [...directos].some((id) => !efectivos.has(id)) ||
      d.necesidades.some((n) => n.operarioId == null)
    );
  });
  if (!desfasadas.length) return;
  console.log(
    `\n== A REVISAR: ${desfasadas.length} preventiva(s) con plazas distintas a sus operarios directos (no se modifican)`,
  );
  for (const d of desfasadas) {
    console.log(
      `  #${d.id} [${d.conjunto?.nombre}] "${d.descripcion.slice(0, 45)}": ` +
        `directos = ${d.operarios.map((o) => o.usuario?.nombre?.split(" ")[0]).join("+")} - ` +
        `plazas = ${d.necesidades.map((n) => n.etiqueta).join("+")}`,
    );
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
