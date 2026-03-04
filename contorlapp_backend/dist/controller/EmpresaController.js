"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.EmpresaController = void 0;
const zod_1 = require("zod");
const EmpresaServices_1 = require("../services/EmpresaServices");
const IdParamSchema = zod_1.z.object({ id: zod_1.z.coerce.number().int().positive() });
const NitHeaderSchema = zod_1.z.object({ nit: zod_1.z.string().min(3) });
function resolveEmpresaId(req) {
    const headersNit = (req.header("x-empresa-id") ?? req.header("x-nit"))?.trim();
    const queryNit = typeof req.query.nit === "string" ? req.query.nit : undefined;
    const paramsNit = req.params?.nit;
    const nit = headersNit || queryNit || paramsNit;
    if (!nit) {
        // lanza con status para que tu error middleware lo tome
        const e = new Error("Falta el NIT de la empresa.");
        e.status = 400;
        throw e;
    }
    return NitHeaderSchema.parse({ nit }).nit;
}
class EmpresaController {
    constructor() {
        this.crearEmpresa = async (req, res, next) => {
            try {
                const service = new EmpresaServices_1.EmpresaService("901191875-4");
                const creada = await service.crearEmpresa(req.body);
                res.status(201).json(creada);
            }
            catch (err) {
                next(err);
            }
        };
        this.getLimiteMinSemanaPorConjunto = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const { nit } = req.params;
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const out = await service.getLimiteMinSemanaPorConjunto(nit);
                res.status(200).json({ limiteMinSemana: out });
            }
            catch (err) {
                next(err);
            }
        };
        this.listarFestivos = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const { desde, hasta, pais } = req.query;
                const out = await service.listarFestivos(desde, hasta, pais ?? "CO");
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.reemplazarFestivosEnRango = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const out = await service.reemplazarFestivosEnRango(req.body);
                res.status(200).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.agregarMaquinaria = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const creada = await service.agregarMaquinaria(req.body);
                res.status(201).json(creada);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarMaquinariaCatalogo = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const items = await service.listarMaquinariaCatalogo(req.query);
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.editarMaquinaria = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const { id } = IdParamSchema.parse(req.params);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const upd = await service.editarMaquinaria(id, req.body);
                res.json(upd);
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarMaquinaria = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const { id } = IdParamSchema.parse(req.params);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                await service.eliminarMaquinaria(id);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.listarMaquinariaDisponible = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const items = await service.listarMaquinariaDisponible();
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.obtenerMaquinariaPrestada = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const items = await service.obtenerMaquinariaPrestada();
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.agregarJefeOperaciones = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const jefe = await service.agregarJefeOperaciones(req.body);
                res.status(201).json(jefe);
            }
            catch (err) {
                next(err);
            }
        };
        this.recibirSolicitudTarea = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const { id } = IdParamSchema.parse(req.params);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const upd = await service.recibirSolicitudTarea({ id });
                res.json(upd);
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarSolicitudTarea = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const { id } = IdParamSchema.parse(req.params);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                await service.eliminarSolicitudTarea({ id });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.solicitudesTareaPendientes = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const list = await service.solicitudesTareaPendientes();
                res.json(list);
            }
            catch (err) {
                next(err);
            }
        };
        this.agregarInsumoAlCatalogo = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const insumo = await service.agregarInsumoAlCatalogo(req.body);
                res.status(201).json(insumo);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarCatalogo = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const items = await service.listarCatalogo(req.query); // opcional
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.buscarInsumoPorId = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const { id } = IdParamSchema.parse(req.params);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const item = await service.buscarInsumoPorId({ id });
                if (!item) {
                    res.status(404).json({ message: "Insumo no encontrado" });
                    return;
                }
                res.json(item);
            }
            catch (err) {
                next(err);
            }
        };
        this.editarInsumoCatalogo = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const { id } = IdParamSchema.parse(req.params);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                const upd = await service.editarInsumoCatalogo(id, req.body);
                res.json(upd);
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarInsumoCatalogo = async (req, res, next) => {
            try {
                const empresaId = resolveEmpresaId(req);
                const { id } = IdParamSchema.parse(req.params);
                const service = new EmpresaServices_1.EmpresaService(empresaId);
                await service.eliminarInsumoCatalogo(id);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.EmpresaController = EmpresaController;
