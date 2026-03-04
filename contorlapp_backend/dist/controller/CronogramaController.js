"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CronogramaController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const CronogramaServices_1 = require("../services/CronogramaServices"); // <- singular
// Schemas para params/query
const NitSchema = zod_1.z.object({ nit: zod_1.z.string().min(3) });
const OperarioIdSchema = zod_1.z.object({
    operarioId: zod_1.z.coerce.number().int().positive(),
});
const FechaSchema = zod_1.z.object({ fecha: zod_1.z.coerce.date() });
const RangoSchema = zod_1.z
    .object({
    inicio: zod_1.z.coerce.date(),
    fin: zod_1.z.coerce.date(),
})
    .refine((d) => d.fin >= d.inicio, {
    message: "fin debe ser mayor o igual a inicio",
    path: ["fin"],
});
const UbicacionSchema = zod_1.z.object({ ubicacion: zod_1.z.string().min(1) });
const FiltroBodySchema = zod_1.z
    .object({
    operarioId: zod_1.z.number().int().positive().optional(),
    fechaExacta: zod_1.z.coerce.date().optional(),
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
    ubicacion: zod_1.z.string().optional(),
})
    .refine((d) => {
    if (d.fechaExacta)
        return true;
    return ((!d.fechaInicio && !d.fechaFin) ||
        (Boolean(d.fechaInicio) && Boolean(d.fechaFin)));
}, { message: "Debe enviar fechaExacta o un rango (fechaInicio y fechaFin)." });
// Resolver NIT (conjuntoId)
function resolveConjuntoId(req) {
    const headerNit = (req.header("x-conjunto-id") ?? req.header("x-nit"))?.trim();
    const queryNit = typeof req.query.nit === "string" ? req.query.nit : undefined;
    const paramsNit = req.params?.nit;
    const nit = headerNit || queryNit || paramsNit;
    const parsed = NitSchema.safeParse({ nit });
    if (!parsed.success) {
        const e = new Error("Falta o es inválido el NIT del conjunto.");
        e.status = 400;
        throw e;
    }
    return parsed.data.nit;
}
class CronogramaController {
    constructor() {
        // GET /conjuntos/:nit/operarios/sugerir?inicio=...&fin=...&max=5&requiereFuncion=...
        this.sugerirOperarios = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const inicio = new Date(String(req.query.inicio ?? ""));
                const fin = new Date(String(req.query.fin ?? ""));
                const max = req.query.max ? Number(req.query.max) : undefined;
                const requiereFuncion = req.query.requiereFuncion;
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const out = await service.sugerirOperarios({
                    fechaInicio: inicio,
                    fechaFin: fin,
                    max,
                    requiereFuncion,
                });
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/cronograma?anio=2025&mes=11&borrador=true|false
        this.cronogramaMensual = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const anio = Number(req.query.anio);
                const mes = Number(req.query.mes);
                const borrador = req.query.borrador === undefined
                    ? false
                    : String(req.query.borrador) === "true";
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const list = await service.cronogramaMensual({ anio, mes, borrador });
                res.json(list);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/cronograma/mes?anio=2025&mes=10&operarioId=&tipo=&borrador=
        this.calendarioMensual = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const anio = Number(req.query.anio);
                const mes = Number(req.query.mes);
                const operarioId = req.query.operarioId
                    ? Number(req.query.operarioId)
                    : undefined;
                const tipo = req.query.tipo;
                const borrador = req.query.borrador == null
                    ? false
                    : String(req.query.borrador) === "true";
                if (!Number.isFinite(anio) ||
                    !Number.isFinite(mes) ||
                    mes < 1 ||
                    mes > 12) {
                    res.status(400).json({ error: "anio/mes inválidos" });
                    return; // <- clave: no retornes el Response
                }
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const out = await service.calendarioMensual({
                    anio,
                    mes,
                    operarioId,
                    tipo,
                    borrador,
                });
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/cronograma/tareas/por-operario/:operarioId
        this.tareasPorOperario = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const { operarioId } = OperarioIdSchema.parse(req.params);
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const tareas = await service.tareasPorOperario({ operarioId });
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/cronograma/tareas/por-fecha?fecha=YYYY-MM-DD
        this.tareasPorFecha = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const { fecha } = FechaSchema.parse({ fecha: req.query.fecha ?? "" });
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const tareas = await service.tareasPorFecha({ fecha });
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/cronograma/tareas/en-rango?inicio=YYYY-MM-DD&fin=YYYY-MM-DD
        this.tareasEnRango = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const { inicio, fin } = RangoSchema.parse({
                    inicio: req.query.inicio ?? "",
                    fin: req.query.fin ?? "",
                });
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const tareas = await service.tareasEnRango({
                    fechaInicio: inicio,
                    fechaFin: fin,
                });
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/cronograma/tareas/por-ubicacion?ubicacion=...
        this.tareasPorUbicacion = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const { ubicacion } = UbicacionSchema.parse({
                    ubicacion: req.query.ubicacion,
                });
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const tareas = await service.tareasPorUbicacion({ ubicacion });
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /conjuntos/:nit/cronograma/tareas/filtrar
        this.tareasPorFiltro = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const filtro = FiltroBodySchema.parse(req.body);
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const tareas = await service.tareasPorFiltro(filtro);
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/cronograma/eventos
        this.exportarComoEventosCalendario = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId);
                const eventos = await service.exportarComoEventosCalendario();
                res.json(eventos);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.CronogramaController = CronogramaController;
