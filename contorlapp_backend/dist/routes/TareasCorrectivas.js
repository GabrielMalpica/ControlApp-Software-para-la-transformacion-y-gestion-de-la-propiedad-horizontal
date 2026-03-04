"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const GerenteServices_1 = require("../services/GerenteServices");
const prisma_1 = require("../db/prisma");
const svc = new GerenteServices_1.GerenteService(prisma_1.prisma);
const router = (0, express_1.Router)();
// Crear correctiva
router.post("/conjuntos/:nit/tareas", async (req, res, next) => {
    try {
        const conjuntoId = req.params.nit;
        const out = await svc.asignarTarea({ ...req.body, conjuntoId, tipo: "CORRECTIVA" });
        res.status(201).json(out);
    }
    catch (e) {
        next(e);
    }
});
// Editar correctiva
router.patch("/tareas/:id", async (req, res, next) => {
    try {
        const id = Number(req.params.id);
        const out = await svc.editarTarea(id, req.body); // aquí puedes validar estado/solapes
        res.json(out);
    }
    catch (e) {
        next(e);
    }
});
// Listar por rango (mixto o filtra tipo)
router.get("/conjuntos/:nit/tareas", async (req, res, next) => {
    try {
        const conjuntoId = req.params.nit;
        const { desde, hasta, tipo } = req.query;
        const where = {
            conjuntoId,
            ...(tipo ? { tipo } : {}),
            ...(desde || hasta ? { fechaFin: { gte: new Date(desde) }, fechaInicio: { lte: new Date(hasta) } } : {}),
        };
        const list = await prisma_1.prisma.tarea.findMany({ where, orderBy: [{ fechaInicio: "asc" }] });
        res.json(list);
    }
    catch (e) {
        next(e);
    }
});
exports.default = router;
