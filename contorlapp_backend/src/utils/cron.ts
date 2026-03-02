// src/utils/cron.ts
import cron from "node-cron";
import { PrismaClient } from "@prisma/client";
import { DefinicionTareaPreventivaService } from "../services/DefinicionTareaPreventivaService";

const prisma = new PrismaClient();
const service = new DefinicionTareaPreventivaService(prisma);

// === OPCIÓN A: 1er día de cada mes a MEDIANOCHE (00:00) Bogotá ===
// cron.schedule("0 0 1 * *", async () => {

// === OPCIÓN B: 1er día de cada mes a MEDIODÍA (12:00) Bogotá ===
cron.schedule("0 0 1 * *", async () => {
  const now = new Date();
  const anio = now.getFullYear();
  const mes = now.getMonth() + 1;

  console.log(`[CRON] Generando borrador preventivas ${anio}-${mes} (America/Bogota)...`);

  const conjuntos = await prisma.conjunto.findMany({ select: { nit: true } });

  for (const c of conjuntos) {
    try {
      const { creadas } = await service.generarCronograma({
        conjuntoId: c.nit,
        anio,
        mes,
        tamanoBloqueHoras: 1,
      });
      console.log(`[CRON] ${c.nit}: creadas ${creadas}`);
    } catch (e: any) {
      console.error(`[CRON] Error en ${c.nit}:`, e?.message ?? e);
    }
  }

  console.log(`[CRON] Listo ${anio}-${mes}`);
}, { timezone: "America/Bogota" });
