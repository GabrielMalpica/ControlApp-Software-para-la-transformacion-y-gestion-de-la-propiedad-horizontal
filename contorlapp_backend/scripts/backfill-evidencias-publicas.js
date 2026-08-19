#!/usr/bin/env node

// Hace públicos (lector, "cualquiera con el enlace") los archivos de Drive
// que fueron subidos como evidencia ANTES de que el cierre de tarea empezara
// a asignar ese permiso automáticamente. Sin esto, las evidencias antiguas
// nunca se van a poder previsualizar en la app aunque el bug ya esté arreglado.

require('dotenv').config();

const { PrismaClient } = require('@prisma/client');
const { google } = require('googleapis');

const prisma = new PrismaClient();

function extractDriveId(raw) {
  const value = String(raw ?? '').trim();
  if (!value) return null;
  const patterns = [
    /\/d\/([a-zA-Z0-9_-]{20,})/,
    /[?&]id=([a-zA-Z0-9_-]{20,})/,
    /file\/d\/([a-zA-Z0-9_-]{20,})/,
  ];
  for (const pattern of patterns) {
    const match = value.match(pattern);
    if (match) return match[1];
  }
  if (/^[a-zA-Z0-9_-]{20,}$/.test(value)) return value;
  return null;
}

function getDrive() {
  if (!process.env.GOOGLE_CREDENTIALS) {
    throw new Error('GOOGLE_CREDENTIALS no está definida');
  }
  const credentials = JSON.parse(process.env.GOOGLE_CREDENTIALS);
  const auth = new google.auth.GoogleAuth({
    credentials: {
      ...credentials,
      private_key: (credentials.private_key || '').replace(/\\n/g, '\n'),
    },
    scopes: ['https://www.googleapis.com/auth/drive.file'],
  });
  return google.drive({ version: 'v3', auth });
}

async function main() {
  const drive = getDrive();

  const tareas = await prisma.tarea.findMany({
    where: { evidencias: { isEmpty: false } },
    select: { id: true, evidencias: true },
  });

  const ids = new Set();
  for (const t of tareas) {
    for (const raw of t.evidencias ?? []) {
      const id = extractDriveId(raw);
      if (id) ids.add(id);
    }
  }

  console.log(`[backfill-evidencias] ${ids.size} archivo(s) de Drive detectado(s) en ${tareas.length} tarea(s).`);

  let ok = 0;
  let fail = 0;
  for (const fileId of ids) {
    try {
      await drive.permissions.create({
        fileId,
        requestBody: { role: 'reader', type: 'anyone' },
      });
      ok++;
    } catch (err) {
      fail++;
      console.error(`[backfill-evidencias] No se pudo hacer público ${fileId}:`, err?.message ?? err);
    }
  }

  console.log(`[backfill-evidencias] Listo. OK=${ok} Fallidos=${fail}`);
}

main()
  .catch((error) => {
    console.error('[backfill-evidencias] Error:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
