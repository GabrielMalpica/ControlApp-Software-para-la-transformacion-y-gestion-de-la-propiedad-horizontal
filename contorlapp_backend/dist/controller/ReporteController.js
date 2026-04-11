"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ReporteController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const ReporteService_1 = require("../services/ReporteService");
const client_1 = require("@prisma/client");
const service = new ReporteService_1.ReporteService(prisma_1.prisma);
function logPerf(nombre, inicio, detalle) {
    const duracionSeg = ((Date.now() - inicio) / 1000).toFixed(2);
    console.log(`[perf] ${nombre}${detalle ? ` ${detalle}` : ""}: ${duracionSeg} s`);
}
async function detalleConjunto(conjuntoId) {
    if (!conjuntoId) {
        return "general";
    }
    const conjunto = await prisma_1.prisma.conjunto.findUnique({
        where: { nit: conjuntoId },
        select: { nombre: true },
    });
    const nombre = (conjunto?.nombre ?? "").trim();
    return nombre.length > 0 ? `${nombre} (${conjuntoId})` : conjuntoId;
}
// ✅ Base
const RangoQueryBase = zod_1.z.object({
    desde: zod_1.z.coerce.date(),
    hasta: zod_1.z.coerce.date(),
});
// ✅ Rango solo
const RangoQuery = RangoQueryBase.refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
});
// ✅ Rango + conjunto opcional (dashboard general o filtrado)
const RangoConConjuntoOpcionalQuery = RangoQueryBase.merge(zod_1.z.object({ conjuntoId: zod_1.z.string().min(1).optional() })).refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
});
// ✅ Insumos requiere conjunto
const UsoInsumosQuery = RangoQueryBase.merge(zod_1.z.object({ conjuntoId: zod_1.z.string().min(1) })).refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
});
// ✅ Tareas por estado (requiere conjunto + estado)
const EstadoQuery = RangoQueryBase.merge(zod_1.z.object({
    conjuntoId: zod_1.z.string().min(1),
    estado: zod_1.z.nativeEnum(client_1.EstadoTarea),
})).refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
});
const ZonificacionPreventivasQuery = RangoQueryBase.merge(zod_1.z.object({
    conjuntoId: zod_1.z.string().min(1).optional(),
    soloActivas: zod_1.z.enum(["true", "false", "1", "0"]).optional(),
})).refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
});
class ReporteController {
    constructor() {
        // =========================
        // DASHBOARD (NUEVOS)
        // =========================
        // GET /reporte/kpis?desde=&hasta=&conjuntoId?
        this.kpis = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoConConjuntoOpcionalQuery.parse(req.query);
                const out = await service.kpis(q);
                logPerf("Reporte KPIs", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/serie-diaria?desde=&hasta=&conjuntoId?
        this.serieDiariaPorEstado = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoConConjuntoOpcionalQuery.parse(req.query);
                const out = await service.serieDiariaPorEstado(q);
                logPerf("Reporte serie diaria", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/por-conjunto?desde=&hasta=
        this.resumenPorConjunto = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoQuery.parse(req.query);
                const out = await service.resumenPorConjunto(q);
                logPerf("Reporte por conjunto", inicio, "general");
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/por-operario?desde=&hasta=&conjuntoId?
        this.resumenPorOperario = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoConConjuntoOpcionalQuery.parse(req.query);
                const out = await service.resumenPorOperario(q);
                logPerf("Reporte por operario", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/duracion-promedio?desde=&hasta=&conjuntoId?
        this.duracionPromedioPorEstado = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoConConjuntoOpcionalQuery.parse(req.query);
                const out = await service.duracionPromedioPorEstado(q);
                logPerf("Reporte duracion promedio", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/mensual-detalle?desde=&hasta=&conjuntoId?
        // (dataset para PDF)
        this.reporteMensualDetalle = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoConConjuntoOpcionalQuery.parse(req.query);
                const out = await service.reporteMensualDetalle(q);
                logPerf("Reporte mensual detalle", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/zonificacion/preventivas?desde=&hasta=&conjuntoId?&soloActivas=true|false
        this.zonificacionPreventivas = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const raw = ZonificacionPreventivasQuery.parse(req.query);
                const q = {
                    ...raw,
                    soloActivas: raw.soloActivas == null
                        ? undefined
                        : raw.soloActivas === "true" || raw.soloActivas === "1",
                };
                const out = await service.zonificacionPreventivas(q);
                logPerf("Reporte zonificacion preventivas", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // =========================
        // LO QUE YA TENÍAS
        // =========================
        // GET /reporte/tareas/aprobadas?desde=&hasta=
        this.tareasAprobadasPorFecha = async (req, res, next) => {
            try {
                const q = RangoQuery.parse(req.query);
                const out = await service.tareasAprobadasPorFecha(q);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/tareas/rechazadas?desde=&hasta=
        this.tareasRechazadasPorFecha = async (req, res, next) => {
            try {
                const q = RangoQuery.parse(req.query);
                const out = await service.tareasRechazadasPorFecha(q);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/insumos/uso?conjuntoId=&desde=&hasta=
        this.usoDeInsumosPorFecha = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = UsoInsumosQuery.parse(req.query);
                const out = await service.usoDeInsumosPorFecha(q);
                logPerf("Reporte insumos", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/tareas/estado?conjuntoId=&estado=&desde=&hasta=
        this.tareasPorEstado = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = EstadoQuery.parse(req.query);
                const out = await service.tareasPorEstado(q);
                logPerf(`Reporte tareas estado ${q.estado}`, inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/tareas/detalle?conjuntoId=&estado=&desde=&hasta=
        this.tareasConDetalle = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = EstadoQuery.parse(req.query);
                const out = await service.tareasConDetalle(q);
                logPerf(`Reporte tareas detalle ${q.estado}`, inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/maquinaria/top?desde=&hasta=&conjuntoId?
        this.usoMaquinariaTop = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoConConjuntoOpcionalQuery.parse(req.query);
                const out = await service.usoMaquinariaTop(q);
                logPerf("Reporte top maquinaria", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/herramientas/top?desde=&hasta=&conjuntoId?
        this.usoHerramientaTop = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoConConjuntoOpcionalQuery.parse(req.query);
                const out = await service.usoHerramientaTop(q);
                logPerf("Reporte top herramientas", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /reporte/tipos?desde=&hasta=&conjuntoId?
        this.conteoPorTipo = async (req, res, next) => {
            const inicio = Date.now();
            try {
                const q = RangoConConjuntoOpcionalQuery.parse(req.query);
                const out = await service.conteoPorTipo(q);
                logPerf("Reporte tipos", inicio, await detalleConjunto(q.conjuntoId));
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.ReporteController = ReporteController;
