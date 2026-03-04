"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.crearUsoMaquinaria = exports.validarMaquinariaDisponible = void 0;
const validarMaquinariaDisponible = async (tx, maquinariaIds, ini, fin) => {
    if (!maquinariaIds?.length)
        return;
    for (const mid of maquinariaIds) {
        const choque = await tx.usoMaquinaria.findFirst({
            where: {
                maquinariaId: mid,
                // solape: [ini, fin] cruza con [fechaInicio, fechaFin]
                fechaInicio: { lt: fin },
                OR: [
                    { fechaFin: { gt: ini } }, // rango cerrado
                    { fechaFin: null }, // aún prestada (sin devolver)
                ],
            },
            select: {
                id: true,
                tareaId: true,
                fechaInicio: true,
                fechaFin: true,
            },
        });
        if (choque) {
            throw new Error(`La maquinaria ${mid} está ocupada y se cruza con el horario solicitado.`);
        }
    }
};
exports.validarMaquinariaDisponible = validarMaquinariaDisponible;
const crearUsoMaquinaria = async (tx, tareaId, maquinariaIds, ini, fin) => {
    if (!maquinariaIds?.length)
        return;
    for (const mid of maquinariaIds) {
        await tx.usoMaquinaria.create({
            data: {
                tarea: { connect: { id: tareaId } },
                maquinaria: { connect: { id: mid } },
                fechaInicio: ini,
                fechaFin: fin, // 🔥 aquí la reservas por ese bloque
                observacion: `Reservada al crear tarea #${tareaId}`,
            },
        });
    }
};
exports.crearUsoMaquinaria = crearUsoMaquinaria;
