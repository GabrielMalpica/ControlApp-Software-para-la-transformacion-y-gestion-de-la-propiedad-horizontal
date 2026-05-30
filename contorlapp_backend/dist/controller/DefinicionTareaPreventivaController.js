"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DefinicionTareaPreventivaController = exports.asyncHandler = void 0;
const prisma_1 = require("../db/prisma");
const DefinicionTareaPreventivaService_1 = require("../services/DefinicionTareaPreventivaService");
const DefinicionTareaPreventiva_1 = require("../model/DefinicionTareaPreventiva");
const asyncHandler = (fn) => (req, res) => fn(req, res).catch((err) => {
    console.error(err);
    res.status(400).json({ error: err?.message ?? "Error inesperado" });
});
exports.asyncHandler = asyncHandler;
class DefinicionTareaPreventivaController {
    constructor() {
        /** POST /conjuntos/:nit/preventivas */
        this.crear = async (req, res) => {
            const conjuntoId = req.params.nit;
            const dto = DefinicionTareaPreventiva_1.CrearDefinicionPreventivaDTO.parse({
                ...req.body,
                conjuntoId,
            });
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const def = await svc.crear(dto);
            res.status(201).json(def);
        };
        /** GET /conjuntos/:nit/preventivas */
        this.listar = async (req, res) => {
            const conjuntoId = req.params.nit;
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const defs = await svc.listarPorConjunto(conjuntoId);
            res.json(defs);
        };
        /** PATCH /conjuntos/:nit/preventivas/:id */
        this.actualizar = async (req, res) => {
            const conjuntoId = req.params.nit;
            const id = Number(req.params.id);
            if (!Number.isFinite(id))
                throw new Error("ID inválido");
            const dto = DefinicionTareaPreventiva_1.EditarDefinicionPreventivaDTO.parse(req.body);
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const def = await svc.actualizar(conjuntoId, id, dto);
            res.json(def);
        };
        /** DELETE /conjuntos/:nit/preventivas/:id */
        this.eliminar = async (req, res) => {
            const conjuntoId = req.params.nit;
            const id = Number(req.params.id);
            if (!Number.isFinite(id))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            await svc.eliminar(conjuntoId, id);
            res.status(204).send();
        };
        /** POST /conjuntos/:nit/preventivas/generar-cronograma */
        this.generarCronogramaMensual = async (req, res) => {
            const conjuntoId = req.params.nit;
            const dto = DefinicionTareaPreventiva_1.GenerarCronogramaDTO.parse({
                ...req.body,
                conjuntoId,
            });
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const inicio = Date.now();
            const resultado = await svc.generarCronograma(dto);
            const conjunto = await prisma_1.prisma.conjunto.findUnique({
                where: { nit: conjuntoId },
                select: { nombre: true },
            });
            const conjuntoLabel = (conjunto?.nombre ?? "").trim() || conjuntoId;
            const duracionSeg = ((Date.now() - inicio) / 1000).toFixed(2);
            console.log(`[perf] Generacion de cronograma borrador conjunto ${conjuntoLabel} (${conjuntoId}) ${dto.mes}/${dto.anio}: ${duracionSeg} s`);
            res.status(201).json(resultado);
        };
        /** POST /conjuntos/:nit/preventivas/publicar?anio=&mes=&consolidar=true|false */
        this.publicarCronograma = async (req, res) => {
            const conjuntoId = req.params.nit;
            const anio = Number(req.body.anio ?? req.query.anio);
            const mes = Number(req.body.mes ?? req.query.mes);
            const consolidarRaw = (req.body.consolidar ?? req.query.consolidar);
            const consolidar = consolidarRaw === true || consolidarRaw === "true" ? true : false;
            if (!conjuntoId ||
                !Number.isFinite(anio) ||
                !Number.isFinite(mes) ||
                mes < 1 ||
                mes > 12) {
                return res.status(400).json({
                    error: "conjuntoId (nit), anio y mes son obligatorios y válidos",
                });
            }
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const result = await svc.publicarCronograma({
                conjuntoId,
                anio,
                mes,
            });
            return res.json(result);
        };
        this.listarMaquinariaDisponible = async (req, res) => {
            const conjuntoId = String(req.params.nit || req.params.conjuntoId || "");
            if (!conjuntoId) {
                return res.status(400).json({ ok: false, reason: "FALTA_CONJUNTO" });
            }
            const fi = String(req.query.fechaInicioUso || "");
            const ff = String(req.query.fechaFinUso || "");
            if (!fi || !ff) {
                return res.status(400).json({
                    ok: false,
                    reason: "FALTAN_FECHAS",
                    message: "Debe enviar fechaInicioUso y fechaFinUso (ISO).",
                });
            }
            const fechaInicioUso = new Date(fi);
            const fechaFinUso = new Date(ff);
            if (Number.isNaN(fechaInicioUso.getTime()) ||
                Number.isNaN(fechaFinUso.getTime())) {
                return res.status(400).json({
                    ok: false,
                    reason: "FECHAS_INVALIDAS",
                    message: "Use formato ISO: 2026-01-01T00:00:00.000Z",
                });
            }
            const excluirTareaIdRaw = req.query.excluirTareaId;
            const excluirTareaId = excluirTareaIdRaw != null && String(excluirTareaIdRaw).trim() !== ""
                ? Number(excluirTareaIdRaw)
                : undefined;
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const r = await svc.listarMaquinariaDisponible({
                conjuntoId,
                fechaInicioUso,
                fechaFinUso,
                excluirTareaId: Number.isFinite(excluirTareaId)
                    ? excluirTareaId
                    : undefined,
            });
            if (!r.ok)
                return res.status(400).json(r);
            return res.status(200).json(r);
        };
        /** PATCH /conjuntos/:nit/preventivas/borrador/tareas/:id */
        this.editarBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const tareaId = Number(req.params.id);
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.editarTareaBorrador({
                conjuntoId,
                tareaId,
                ...req.body, // fechaInicio, fechaFin, duracionHoras, operariosIds
            });
            res.json(out);
        };
        /** POST /conjuntos/:nit/preventivas/borrador/tarea */
        this.crearBloqueBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.crearBloqueBorrador(conjuntoId, req.body);
            res.status(201).json(out);
        };
        /** PATCH /conjuntos/:nit/preventivas/borrador/tarea/:id */
        this.editarBloqueBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const id = Number(req.params.id);
            if (!Number.isFinite(id))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.editarBloqueBorrador(conjuntoId, id, req.body);
            res.json(out);
        };
        this.reordenarTareasDiaBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.reordenarTareasBorradorDia({
                conjuntoId,
                fecha: req.body?.fecha,
                tareaIds: req.body?.tareaIds,
            });
            res.json(out);
        };
        /** DELETE /conjuntos/:nit/preventivas/borrador/tarea/:id */
        this.eliminarBloqueBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const id = Number(req.params.id);
            if (!Number.isFinite(id))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            await svc.eliminarBloqueBorrador(conjuntoId, id);
            res.status(204).send();
        };
        /** GET /conjuntos/:nit/preventivas/borrador?anio=&mes= */
        this.listarBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const anio = Number(req.query.anio);
            const mes = Number(req.query.mes);
            if (!Number.isFinite(anio) ||
                !Number.isFinite(mes) ||
                mes < 1 ||
                mes > 12) {
                res.status(400).json({ error: "Parámetros anio/mes inválidos." });
                return;
            }
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.listarBorrador({ conjuntoId, anio, mes }); // método simple en el service
            res.json(out);
        };
        this.listarOpcionesReprogramacionBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const id = Number(req.params.id);
            if (!Number.isFinite(id))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.listarOpcionesReprogramacionBorrador(conjuntoId, id);
            res.json(out);
        };
        this.listarExcluidasBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.listarExcluidasBorrador({
                conjuntoId,
                anio: Number(req.query.anio),
                mes: Number(req.query.mes),
                fecha: req.query.fecha ? new Date(String(req.query.fecha)) : undefined,
            });
            res.json(out);
        };
        this.descartarExcluidaBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const id = Number(req.params.id);
            if (!Number.isFinite(id))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            await svc.descartarExcluidaBorrador(conjuntoId, id);
            res.status(204).send();
        };
        this.sugerirHuecosExcluida = async (req, res) => {
            const conjuntoId = req.params.nit;
            const id = Number(req.params.id);
            if (!Number.isFinite(id))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.sugerirHuecosExcluida({
                conjuntoId,
                excluidaId: id,
                fechaPreferida: req.query.fechaPreferida
                    ? new Date(String(req.query.fechaPreferida))
                    : undefined,
                maxOpciones: req.query.maxOpciones,
            });
            res.json(out);
        };
        this.agendarExcluidaBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const id = Number(req.params.id);
            if (!Number.isFinite(id))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.agendarExcluidaBorrador({
                conjuntoId,
                excluidaId: id,
                ...req.body,
            });
            res.json(out);
        };
        this.reemplazarConExcluida = async (req, res) => {
            const conjuntoId = req.params.nit;
            const tareaId = Number(req.params.id);
            if (!Number.isFinite(tareaId))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.reemplazarTareaBorradorConExcluida({
                conjuntoId,
                tareaId,
                excluidaId: Number(req.body?.excluidaId),
            });
            res.json(out);
        };
        this.reasignarOperarioBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const tareaId = Number(req.params.id);
            if (!Number.isFinite(tareaId))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.reasignarOperarioTareaBorrador({
                conjuntoId,
                tareaId,
                nuevoOperarioId: req.body?.nuevoOperarioId,
                aplicarADefinicion: req.body?.aplicarADefinicion,
            });
            res.json(out);
        };
        this.reasignarOperarioExcluidaBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const excluidaId = Number(req.params.id);
            if (!Number.isFinite(excluidaId))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.reasignarOperarioExcluidaBorrador({
                conjuntoId,
                excluidaId,
                nuevoOperarioId: req.body?.nuevoOperarioId,
                aplicarADefinicion: req.body?.aplicarADefinicion,
            });
            res.json(out);
        };
        this.dividirExcluidaManual = async (req, res) => {
            const conjuntoId = req.params.nit;
            const excluidaId = Number(req.params.id);
            if (!Number.isFinite(excluidaId))
                throw new Error("ID inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.dividirExcluidaManual({
                conjuntoId,
                excluidaId,
                bloques: req.body?.bloques,
            });
            res.json(out);
        };
        this.sugerirHuecosBloqueExcluida = async (req, res) => {
            const conjuntoId = req.params.nit;
            const excluidaId = Number(req.params.id);
            if (!Number.isFinite(excluidaId))
                throw new Error("ID inválido");
            const bloqueId = String(req.params.bloqueId ?? "").trim();
            if (!bloqueId)
                throw new Error("Bloque inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.sugerirHuecosBloqueExcluida({
                conjuntoId,
                excluidaId,
                bloqueId,
                fechaInicio: req.query.fechaPreferida
                    ? new Date(String(req.query.fechaPreferida))
                    : undefined,
            });
            res.json(out);
        };
        this.agendarBloqueExcluida = async (req, res) => {
            const conjuntoId = req.params.nit;
            const excluidaId = Number(req.params.id);
            if (!Number.isFinite(excluidaId))
                throw new Error("ID inválido");
            const bloqueId = String(req.params.bloqueId ?? "").trim();
            if (!bloqueId)
                throw new Error("Bloque inválido");
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.agendarBloqueExcluida({
                conjuntoId,
                excluidaId,
                bloqueId,
                ...req.body,
            });
            res.json(out);
        };
        this.informeActividadBorrador = async (req, res) => {
            const conjuntoId = req.params.nit;
            const anio = Number(req.query.anio);
            const mes = Number(req.query.mes);
            const svc = new DefinicionTareaPreventivaService_1.DefinicionTareaPreventivaService(prisma_1.prisma);
            const out = await svc.informeMensualActividad({
                conjuntoId,
                anio,
                mes,
                borrador: true,
            });
            res.json(out);
        };
    }
}
exports.DefinicionTareaPreventivaController = DefinicionTareaPreventivaController;
