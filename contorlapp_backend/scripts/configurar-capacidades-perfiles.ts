// Configura las capacidades (categorías permitidas) de los perfiles operativos
// con los valores acordados:
//   Todero             → Mantenimiento de piscinas, Poda, Jardinería, Aseo, Mantenimientos básicos
//   Todero-Salvavidas  → Poda, Jardinería, Aseo, Mantenimientos básicos, Salvamento acuático
//   Salvavidas         → Salvamento acuático
//   Aseo               → Aseo
//   Todero-Aseo        → Poda, Jardinería, Aseo, Mantenimientos básicos
//
// Solo toca perfiles que hoy NO tienen ninguna categoría (nunca pisa lo que
// ya configuraste) y que se llamen exactamente así. Es idempotente.
//
// Uso (desde contorlapp_backend):
//   npx tsx scripts/configurar-capacidades-perfiles.ts            (simulación)
//   npx tsx scripts/configurar-capacidades-perfiles.ts --apply    (aplica)
// Contra una base que no sea local exige además --permitir-remoto.
import "dotenv/config";
import { PrismaClient } from "@prisma/client";

import { normalizarTexto } from "../src/utils/perfilOperativo";

const prisma = new PrismaClient();
const APPLY = process.argv.includes("--apply");
const PERMITIR_REMOTO = process.argv.includes("--permitir-remoto");

const P = "Mantenimiento de piscinas";
const PODA = "Poda";
const JARD = "Jardinería";
const ASEO = "Aseo";
const BAS = "Mantenimientos básicos";
const SALV = "Salvamento acuático";

const CAPACIDADES: Record<string, string[]> = {
  Todero: [P, PODA, JARD, ASEO, BAS],
  "Todero-Salvavidas": [PODA, JARD, ASEO, BAS, SALV],
  Salvavidas: [SALV],
  Aseo: [ASEO],
  "Todero-Aseo": [PODA, JARD, ASEO, BAS],
};

async function main() {
  let host = "?";
  let base = "?";
  try {
    const u = new URL(process.env.DATABASE_URL ?? "");
    host = u.hostname;
    base = u.pathname.replace(/^\//, "");
  } catch {
    /* se reporta abajo */
  }
  console.log(`Base: ${base} @ ${host} · modo: ${APPLY ? "APLICAR" : "simulación"}`);
  if (!["localhost", "127.0.0.1", "::1"].includes(host) && !PERMITIR_REMOTO) {
    console.error("La base no es local. Para correrlo aquí agrega --permitir-remoto (con respaldo previo).");
    process.exit(1);
  }

  const perfiles = await prisma.perfilOperativo.findMany({
    include: { categorias: { select: { categoriaId: true } } },
    orderBy: [{ empresaId: "asc" }, { nombre: "asc" }],
  });
  let cambios = 0;
  for (const perfil of perfiles) {
    const deseadas = CAPACIDADES[perfil.nombre];
    if (!deseadas) {
      console.log(`- ${perfil.nombre}: sin regla acordada, no se toca.`);
      continue;
    }
    if (perfil.categorias.length > 0) {
      console.log(`- ${perfil.nombre}: ya tiene ${perfil.categorias.length} categoría(s) configurada(s), no se toca.`);
      continue;
    }
    const categorias = await prisma.categoriaTarea.findMany({ where: { empresaId: perfil.empresaId } });
    const porNombre = new Map(categorias.map((c) => [normalizarTexto(c.nombre), c.id]));
    const ids = deseadas.map((n) => porNombre.get(normalizarTexto(n))).filter((id): id is number => id != null);
    if (ids.length !== deseadas.length) {
      console.log(`- ${perfil.nombre}: faltan categorías en la empresa (${ids.length}/${deseadas.length}), no se toca.`);
      continue;
    }
    console.log(`- ${perfil.nombre}: ${APPLY ? "configurando" : "configuraría"} → ${deseadas.join(", ")}`);
    cambios++;
    if (APPLY) {
      await prisma.perfilOperativoCategoria.createMany({
        data: ids.map((categoriaId) => ({ perfilId: perfil.id, categoriaId })),
        skipDuplicates: true,
      });
    }
  }
  console.log(`\n${cambios} perfil(es) ${APPLY ? "configurado(s)" : "por configurar"}.`);
  if (!APPLY) console.log("No se escribió nada. Corre con --apply para aplicar.");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
