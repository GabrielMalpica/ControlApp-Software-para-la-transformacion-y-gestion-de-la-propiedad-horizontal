"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SolicitudTareaService = void 0;
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const IdDTO = zod_1.z.object({ id: zod_1.z.number().int().positive() });
const RechazarDTO = zod_1.z.object({
    observacion: zod_1.z.string().min(1).max(500),
});
class SolicitudTareaService {
    constructor(prisma, solicitudId) {
        this.prisma = prisma;
        this.solicitudId = solicitudId;
    }
    async aprobar() {
        const solicitud = await this.prisma.solicitudTarea.findUnique({
            where: { id: this.solicitudId },
        });
        if (!solicitud)
            throw new Error("❌ Solicitud no encontrada.");
        if (solicitud.estado !== client_1.EstadoSolicitud.PENDIENTE) {
            throw new Error("❌ Solo se pueden aprobar solicitudes pendientes.");
        }
        await this.prisma.solicitudTarea.update({
            where: { id: this.solicitudId },
            data: { estado: client_1.EstadoSolicitud.APROBADA },
        });
    }
    async rechazar(payload) {
        const { observacion } = RechazarDTO.parse(payload);
        const solicitud = await this.prisma.solicitudTarea.findUnique({
            where: { id: this.solicitudId },
        });
        if (!solicitud)
            throw new Error("❌ Solicitud no encontrada.");
        if (solicitud.estado !== client_1.EstadoSolicitud.PENDIENTE) {
            throw new Error("❌ Solo se pueden rechazar solicitudes pendientes.");
        }
        await this.prisma.solicitudTarea.update({
            where: { id: this.solicitudId },
            data: { estado: client_1.EstadoSolicitud.RECHAZADA, observaciones: observacion },
        });
    }
    async estadoActual() {
        const solicitud = await this.prisma.solicitudTarea.findUnique({
            where: { id: this.solicitudId },
        });
        if (!solicitud)
            throw new Error("❌ Solicitud no encontrada.");
        return `📋 Estado de la solicitud: ${solicitud.estado}${solicitud.observaciones ? " - Obs: " + solicitud.observaciones : ""}`;
    }
}
exports.SolicitudTareaService = SolicitudTareaService;
