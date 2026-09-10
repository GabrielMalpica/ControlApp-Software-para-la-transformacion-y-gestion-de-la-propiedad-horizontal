// Corrige Maquinaria.tipo para que coincida con TipoMaquinariaCatalogo.tipoLegacy.
//
// Causa: al aprobar una máquina pendiente fusionándola con un catálogo ya
// existente, InventarioActivoService.aprobar() actualizaba tipoCatalogoId
// pero no el campo `tipo` de la máquina (fijo desde el momento de creación).
// La máquina quedaba con tipo=OTRO aunque su catálogo diga GUADANIA/TALADRO/
// etc., y por eso desaparecía como candidata en el cronograma/agenda de
// recursos aunque existiera físicamente en el conjunto o la empresa.
//
// El código ya no genera esta desincronización (ver InventarioActivoService.ts,
// método aprobar). Este script solo repara los registros existentes.
// Es idempotente: se puede correr varias veces sin efectos secundarios.
//
// Uso:
//   DATABASE_URL=... npx tsx scripts/backfill-tipo-maquinaria.ts          (dry-run, solo imprime)
//   DATABASE_URL=... npx tsx scripts/backfill-tipo-maquinaria.ts --apply  (aplica los cambios)
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
const APPLY = process.argv.includes("--apply");

async function main() {
  const maquinas = await prisma.maquinaria.findMany({
    where: { tipoCatalogoId: { not: null } },
    select: {
      id: true,
      nombre: true,
      tipo: true,
      empresaId: true,
      tipoCatalogo: { select: { nombre: true, tipoLegacy: true } },
    },
  });

  const desincronizadas = maquinas.filter(
    (m) => m.tipoCatalogo?.tipoLegacy && m.tipoCatalogo.tipoLegacy !== m.tipo,
  );

  if (desincronizadas.length === 0) {
    console.log("Nada que corregir: todas las máquinas coinciden con su catálogo.");
    return;
  }

  console.log(`${APPLY ? "Aplicando" : "[DRY-RUN] Encontradas"} ${desincronizadas.length} máquina(s) desincronizada(s):`);
  console.table(
    desincronizadas.map((m) => ({
      id: m.id,
      empresa: m.empresaId,
      nombre: m.nombre,
      tipoActual: m.tipo,
      tipoCorrecto: m.tipoCatalogo!.tipoLegacy,
    })),
  );

  if (!APPLY) {
    console.log("\nEjecuta con --apply para corregir estos registros.");
    return;
  }

  for (const m of desincronizadas) {
    await prisma.maquinaria.update({
      where: { id: m.id },
      data: { tipo: m.tipoCatalogo!.tipoLegacy! },
    });
  }
  console.log(`\nListo: ${desincronizadas.length} registro(s) corregido(s).`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
