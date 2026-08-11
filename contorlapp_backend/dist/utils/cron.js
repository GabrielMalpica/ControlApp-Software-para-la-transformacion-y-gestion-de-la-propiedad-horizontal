"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// src/utils/cron.ts
const node_cron_1 = __importDefault(require("node-cron"));
const prisma_1 = require("../db/prisma");
const DefinicionTareaPreventivaService_1 = require("../services/DefinicionTareaPreventivaService");
const CronogramaServices_1 = require("../services/CronogramaServices");
const service = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
// === OPCIÓN A: 1er día de cada mes a MEDIANOCHE (00:00) Bogotá ===
// cron.schedule("0 0 1 * *", async () => {
// === OPCIÓN B: 1er día de cada mes a MEDIODÍA (12:00) Bogotá ===
node_cron_1.default.schedule("0 0 1 * *", async () => {
    const now = new Date();
    const anio = now.getFullYear();
    const mes = now.getMonth() + 1;
    console.log(`[CRON] Generando borrador preventivas ${anio}-${mes} (America/Bogota)...`);
    const conjuntos = await prisma_1.prisma.conjunto.findMany({ select: { nit: true } });
    for (const c of conjuntos) {
        try {
            const { creadas } = await service.generarCronograma({
                conjuntoId: c.nit,
                anio,
                mes,
                tamanoBloqueHoras: 1,
            });
            console.log(`[CRON] ${c.nit}: creadas ${creadas}`);
        }
        catch (e) {
            console.error(`[CRON] Error en ${c.nit}:`, e?.message ?? e);
        }
    }
    // Las tareas excluidas solo son visibles durante su propio mes: al entrar el
    // nuevo periodo se purgan las de meses anteriores en todos los conjuntos.
    try {
        const eliminadas = await (0, CronogramaServices_1.purgarExcluidasDeMesesAnteriores)(prisma_1.prisma, { anio, mes });
        console.log(`[CRON] Excluidas de meses anteriores eliminadas: ${eliminadas}`);
    }
    catch (e) {
        console.error("[CRON] Error purgando excluidas de meses anteriores:", e?.message ?? e);
    }
    console.log(`[CRON] Listo ${anio}-${mes}`);
}, { timezone: "America/Bogota" });
