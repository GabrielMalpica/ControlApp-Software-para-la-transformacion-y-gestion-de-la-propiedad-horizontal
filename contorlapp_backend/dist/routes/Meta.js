"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const client_1 = require("@prisma/client");
const router = (0, express_1.Router)();
router.get("/enums/usuario", (_req, res) => {
    res.json({
        rol: Object.values(client_1.Rol),
        estadoCivil: Object.values(client_1.EstadoCivil),
        eps: Object.values(client_1.EPS),
        fondoPensiones: Object.values(client_1.FondoPension),
        jornadaLaboral: Object.values(client_1.JornadaLaboral),
        tipoSangre: Object.values(client_1.TipoSangre),
        tallaCamisa: Object.values(client_1.TallaCamisa),
        tallaPantalon: Object.values(client_1.TallaPantalon),
        tallaCalzado: Object.values(client_1.TallaCalzado),
        tipoContrato: Object.values(client_1.TipoContrato),
        tipoFuncion: Object.values(client_1.TipoFuncion),
        patronesJornada: Object.values(client_1.PatronJornada)
    });
});
exports.default = router;
