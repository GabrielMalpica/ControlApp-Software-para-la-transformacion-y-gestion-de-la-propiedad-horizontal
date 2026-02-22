#!/usr/bin/env node

const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcrypt');

const prisma = new PrismaClient();

const defaultPassword = process.env.SEED_DEFAULT_PASSWORD || 'ControlApp123*';

const gerentes = [
  {
    id: '1019043425',
    nombre: 'Frank Rojas',
    correo: 'stevenrojascruz@gmail.com',
    telefono: '3192578670',
    fechaNacimiento: '1990-01-01',
    rol: 'gerente',
  },
  {
    id: '1121851393',
    nombre: 'Jaivert Mathias',
    correo: 'Jathmati@hotmail.com',
    telefono: '3187140247',
    fechaNacimiento: '1990-01-01',
    rol: 'gerente',
  },
];

async function seedGerente(persona, passwordHash) {
  const existingByEmail = await prisma.usuario.findUnique({
    where: { correo: persona.correo },
    select: { id: true },
  });

  if (existingByEmail && existingByEmail.id !== persona.id) {
    console.warn(
      `[seed] Omitiendo ${persona.nombre}: correo ${persona.correo} ya pertenece al usuario ${existingByEmail.id}.`,
    );
    return;
  }

  await prisma.usuario.upsert({
    where: { id: persona.id },
    update: {
      nombre: persona.nombre,
      correo: persona.correo,
      telefono: BigInt(persona.telefono),
      fechaNacimiento: new Date(persona.fechaNacimiento),
      rol: persona.rol,
      activo: true,
    },
    create: {
      id: persona.id,
      nombre: persona.nombre,
      correo: persona.correo,
      contrasena: passwordHash,
      rol: persona.rol,
      activo: true,
      telefono: BigInt(persona.telefono),
      fechaNacimiento: new Date(persona.fechaNacimiento),
    },
  });

  await prisma.gerente.upsert({
    where: { id: persona.id },
    update: {},
    create: { id: persona.id },
  });

  console.log(`[seed] Gerente listo: ${persona.nombre} (${persona.id})`);
}

async function main() {
  const passwordHash = await bcrypt.hash(defaultPassword, 10);

  for (const persona of gerentes) {
    await seedGerente(persona, passwordHash);
  }
}

main()
  .catch((error) => {
    console.error('[seed] Error creando gerentes iniciales:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
