"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.supervisorPublicSelect = exports.VeredictoSupervisorDTO = exports.EditarSupervisorDTO = exports.CrearSupervisorDTO = void 0;
exports.toSupervisorPublico = toSupervisorPublico;
// src/models/supervisor.ts
const zod_1 = require("zod");
/* ===================== DTOs ===================== */
/** Crear supervisor */
exports.CrearSupervisorDTO = zod_1.z.object({
    Id: zod_1.z.string().min(1, "El id (cédula) del usuario es obligatorio"),
});
/** Editar supervisor (solo empresa por ahora) */
exports.EditarSupervisorDTO = zod_1.z.object({
    empresaId: zod_1.z.string().min(3).optional(),
});
exports.VeredictoSupervisorDTO = zod_1.z.object({
    estado: zod_1.z.enum(["APROBADA", "RECHAZADA", "NO_COMPLETADA"]),
    observacionesRechazo: zod_1.z.string().min(3).max(500).optional(),
    evidencias: zod_1.z.array(zod_1.z.string()).default([]), // si el supervisor sube fotos al aprobar/rechazar
});
/* ===================== SELECT BASE ===================== */
exports.supervisorPublicSelect = {
    id: true,
    empresaId: true,
};
/** Helper para castear select de Prisma */
function toSupervisorPublico(row) {
    return row;
}
