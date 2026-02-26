#!/usr/bin/env node

const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  console.log('[clear-maquinaria] Eliminando relaciones de maquinaria...');

  await prisma.usoMaquinaria.deleteMany();
  await prisma.solicitudMaquinaria.deleteMany();
  await prisma.maquinariaConjunto.deleteMany();

  const deleted = await prisma.maquinaria.deleteMany();

  console.log(
    `[clear-maquinaria] Maquinarias eliminadas: ${deleted.count}. Dependencias limpiadas correctamente.`,
  );
}

main()
  .catch((error) => {
    console.error('[clear-maquinaria] Error:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
