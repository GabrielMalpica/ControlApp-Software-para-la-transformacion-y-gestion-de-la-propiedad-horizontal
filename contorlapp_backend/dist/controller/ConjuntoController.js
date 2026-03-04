"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ConjuntoController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const ConjuntoServices_1 = require("../services/ConjuntoServices");
const CronogramaServices_1 = require("../services/CronogramaServices");
/* ===================== Schemas mínimos ===================== */
const NitSchema = zod_1.z.object({ nit: zod_1.z.string().min(3) });
const OperarioIdSchema = zod_1.z.object({
    operarioId: zod_1.z.coerce.number().int().positive(),
});
const AdminIdSchema = zod_1.z.object({
    administradorId: zod_1.z.coerce.number().int().positive(),
});
const MaquinariaIdSchema = zod_1.z.object({
    maquinariaId: zod_1.z.coerce.number().int().positive(),
});
const TareaIdSchema = zod_1.z.object({ tareaId: zod_1.z.coerce.number().int().positive() });
const FechaSchema = zod_1.z.object({ fecha: zod_1.z.coerce.date() });
const UbicacionNombreSchema = zod_1.z.object({ nombreUbicacion: zod_1.z.string().min(1) });
const SetActivoBody = zod_1.z.object({ activo: zod_1.z.boolean() });
const RangoQuery = zod_1.z
    .object({
    fechaInicio: zod_1.z.coerce.date(),
    fechaFin: zod_1.z.coerce.date(),
})
    .refine((d) => d.fechaFin >= d.fechaInicio, {
    path: ["fechaFin"],
    message: "fechaFin debe ser >= fechaInicio",
});
const TareasPorFiltroQuery = zod_1.z
    .object({
    operarioId: zod_1.z.coerce.number().int().positive().optional(),
    fechaExacta: zod_1.z.coerce.date().optional(),
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
    ubicacion: zod_1.z.string().optional(),
})
    .refine((d) => {
    if (d.fechaExacta)
        return true;
    // si no hay fechaExacta, entonces ambos extremos o ninguno
    return ((!d.fechaInicio && !d.fechaFin) ||
        (Boolean(d.fechaInicio) && Boolean(d.fechaFin)));
}, { message: "Debe enviar fechaExacta o un rango (fechaInicio y fechaFin)." });
/* ===================== Helpers ===================== */
function resolveConjuntoId(req) {
    const headerNit = (req.header?.("x-conjunto-id") ?? req.header?.("x-nit"))?.trim();
    const queryNit = typeof req.query?.nit === "string" ? req.query.nit : undefined;
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
/* ===================== Controller ===================== */
class ConjuntoController {
    constructor() {
        // PUT /conjuntos/:nit/activo
        this.setActivo = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const { activo } = SetActivoBody.parse(req.body);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                await service.setActivo(activo);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // POST /conjuntos/:nit/operarios
        this.asignarOperario = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const body = OperarioIdSchema.parse(req.body);
                await service.asignarOperario(body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // PUT /conjuntos/:nit/administrador
        this.asignarAdministrador = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const body = AdminIdSchema.parse(req.body);
                await service.asignarAdministrador(body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // DELETE /conjuntos/:nit/administrador
        this.eliminarAdministrador = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                await service.eliminarAdministrador();
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // POST /conjuntos/:nit/maquinaria
        this.agregarMaquinaria = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const body = MaquinariaIdSchema.parse(req.body);
                await service.agregarMaquinaria(body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // POST /conjuntos/:nit/maquinaria/entregar
        this.entregarMaquinaria = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const body = MaquinariaIdSchema.parse(req.body);
                await service.entregarMaquinaria(body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.listarMaquinaria = async (req, res, next) => {
            try {
                const { nit } = req.params;
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, nit);
                const data = await service.listarMaquinariaDelConjunto();
                res.json(data);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /conjuntos/:nit/ubicaciones
        this.agregarUbicacion = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                await service.agregarUbicacion(req.body); // valida internamente con CrearUbicacionDTO
                res.status(201).json({ message: "Ubicación registrada (o ya existía)." });
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/ubicaciones/buscar?nombre=...
        this.buscarUbicacion = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const nombre = (req.query.nombre ?? req.query.nombreUbicacion);
                const payload = UbicacionNombreSchema.parse({ nombreUbicacion: nombre });
                const result = await service.buscarUbicacion({
                    nombre: payload.nombreUbicacion,
                });
                if (!result) {
                    res.status(404).json({ message: "Ubicación no encontrada" });
                    return;
                }
                res.json(result);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /conjuntos/:nit/cronograma/tareas
        this.agregarTareaACronograma = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const body = TareaIdSchema.parse(req.body);
                await service.agregarTareaACronograma(body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/tareas/por-fecha?fecha=YYYY-MM-DD
        this.tareasPorFecha = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const { fecha } = FechaSchema.parse({
                    fecha: req.query.fecha,
                });
                const tareas = await service.tareasPorFecha({ fecha });
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/tareas/por-operario/:operarioId
        this.tareasPorOperario = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const { operarioId } = OperarioIdSchema.parse(req.params);
                const tareas = await service.tareasPorOperario({ operarioId });
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/tareas/por-ubicacion?nombreUbicacion=...
        this.tareasPorUbicacion = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, conjuntoId);
                const payload = UbicacionNombreSchema.parse({
                    nombreUbicacion: req.query.nombreUbicacion,
                });
                const tareas = await service.tareasPorUbicacion({
                    nombreUbicacion: payload.nombreUbicacion,
                });
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/tareas/en-rango?fechaInicio=...&fechaFin=...
        this.tareasEnRango = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const cronograma = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId); // ⬅️ usar CronogramaService
                const { fechaInicio, fechaFin } = RangoQuery.parse({
                    fechaInicio: req.query.fechaInicio,
                    fechaFin: req.query.fechaFin,
                });
                const out = await cronograma.tareasEnRango({ fechaInicio, fechaFin });
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/tareas/filtrar?... (operarioId?, fechaExacta? o rango, ubicacion?)
        this.tareasPorFiltro = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const cronograma = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId); // ⬅️ usar CronogramaService
                const filtro = TareasPorFiltroQuery.parse(req.query);
                const out = await cronograma.tareasPorFiltro(filtro);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /conjuntos/:nit/cronograma/eventos-calendario
        this.exportarEventosCalendario = async (req, res, next) => {
            try {
                const conjuntoId = resolveConjuntoId(req);
                const cronograma = new CronogramaServices_1.CronogramaService(prisma_1.prisma, conjuntoId); // ⬅️ usar CronogramaService
                const eventos = await cronograma.exportarComoEventosCalendario();
                res.json(eventos);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.ConjuntoController = ConjuntoController;
