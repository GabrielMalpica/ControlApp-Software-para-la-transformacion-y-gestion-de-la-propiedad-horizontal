"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.UbicacionService = void 0;
const zod_1 = require("zod");
const NombreDTO = zod_1.z.object({ nombre: zod_1.z.string().min(1) });
class UbicacionService {
    constructor(prisma, ubicacionId) {
        this.prisma = prisma;
        this.ubicacionId = ubicacionId;
    }
    async agregarElemento(payload) {
        const { nombre } = NombreDTO.parse(payload);
        await this.prisma.elemento.create({
            data: {
                nombre,
                ubicacion: { connect: { id: this.ubicacionId } },
            },
        });
    }
    async listarElementos() {
        const elementos = await this.prisma.elemento.findMany({
            where: { ubicacionId: this.ubicacionId },
            select: { nombre: true },
        });
        return elementos.map((e) => e.nombre);
    }
    async buscarElementoPorNombre(payload) {
        const { nombre } = NombreDTO.parse(payload);
        return this.prisma.elemento.findFirst({
            where: {
                ubicacionId: this.ubicacionId,
                nombre: { equals: nombre, mode: "insensitive" },
            },
            select: { id: true, nombre: true },
        });
    }
}
exports.UbicacionService = UbicacionService;
