"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ConjuntoService = void 0;
const zod_1 = require("zod");
const Ubicacion_1 = require("../model/Ubicacion");
const InventarioServices_1 = require("./InventarioServices");
// DTOs locales
const AsignarOperarioDTO = zod_1.z.object({
    operarioId: zod_1.z.number().int().positive(),
});
const AsignarAdministradorDTO = zod_1.z.object({
    administradorId: zod_1.z.number().int().positive(),
});
const AgregarMaquinariaDTO = zod_1.z.object({
    maquinariaId: zod_1.z.number().int().positive(),
});
const TareaIdDTO = zod_1.z.object({
    tareaId: zod_1.z.number().int().positive(),
});
const FechaDTO = zod_1.z.object({
    fecha: zod_1.z.coerce.date(),
});
const TareasPorOperarioDTO = zod_1.z.object({
    operarioId: zod_1.z.number().int().positive(),
});
const TareasPorUbicacionDTO = zod_1.z.object({
    nombreUbicacion: zod_1.z.string().min(1),
});
class ConjuntoService {
    constructor(prisma, conjuntoId // nit
    ) {
        this.prisma = prisma;
        this.conjuntoId = conjuntoId;
    }
    async getOrCreateInventarioId() {
        const inv = await this.prisma.inventario.upsert({
            where: { conjuntoId: this.conjuntoId },
            update: {},
            create: { conjuntoId: this.conjuntoId },
            select: { id: true },
        });
        return inv.id;
    }
    async listarInventario(filtro) {
        const inventarioId = await this.getOrCreateInventarioId();
        const invService = new InventarioServices_1.InventarioService(this.prisma, inventarioId);
        return invService.listarInsumosDetallado(filtro);
    }
    async listarInsumosBajos(filtro) {
        const inventarioId = await this.getOrCreateInventarioId();
        const invService = new InventarioServices_1.InventarioService(this.prisma, inventarioId);
        return invService.listarInsumosBajos(filtro);
    }
    async agregarStock(payload) {
        const inventarioId = await this.getOrCreateInventarioId();
        const invService = new InventarioServices_1.InventarioService(this.prisma, inventarioId);
        return invService.agregarStock(payload);
    }
    async consumirStock(payload) {
        const inventarioId = await this.getOrCreateInventarioId();
        const invService = new InventarioServices_1.InventarioService(this.prisma, inventarioId);
        return invService.consumirStock(payload);
    }
    async buscarInsumoPorId(payload) {
        const inventarioId = await this.getOrCreateInventarioId();
        const invService = new InventarioServices_1.InventarioService(this.prisma, inventarioId);
        return invService.buscarInsumoPorId(payload);
    }
    async setUmbralMinimo(payload) {
        const inventarioId = await this.getOrCreateInventarioId();
        const invService = new InventarioServices_1.InventarioService(this.prisma, inventarioId);
        return invService.setUmbralMinimo(payload);
    }
    async unsetUmbralMinimo(payload) {
        const inventarioId = await this.getOrCreateInventarioId();
        const invService = new InventarioServices_1.InventarioService(this.prisma, inventarioId);
        return invService.unsetUmbralMinimo(payload);
    }
    /** Activa/Inactiva el conjunto y retorna el valor actualizado */
    async setActivo(activo) {
        const existe = await this.prisma.conjunto.findUnique({
            where: { nit: this.conjuntoId },
            select: { nit: true },
        });
        if (!existe)
            throw new Error("Conjunto no encontrado.");
        const updated = await this.prisma.conjunto.update({
            where: { nit: this.conjuntoId },
            data: { activo },
            select: { activo: true },
        });
        return updated.activo;
    }
    async listarMaquinariaDelConjunto() {
        const [propia, prestada] = await Promise.all([
            this.prisma.maquinaria.findMany({
                where: {
                    propietarioTipo: "CONJUNTO",
                    conjuntoPropietarioId: this.conjuntoId,
                },
                select: {
                    id: true,
                    nombre: true,
                    marca: true,
                    tipo: true,
                    estado: true,
                    propietarioTipo: true,
                    conjuntoPropietarioId: true,
                },
            }),
            // 2️⃣ Maquinaria prestada (asignación ACTIVA)
            this.prisma.maquinariaConjunto.findMany({
                where: {
                    conjuntoId: this.conjuntoId,
                    estado: "ACTIVA",
                },
                select: {
                    tipoTenencia: true,
                    fechaDevolucionEstimada: true,
                    maquinaria: {
                        select: {
                            id: true,
                            nombre: true,
                            marca: true,
                            tipo: true,
                            estado: true,
                            propietarioTipo: true,
                            empresaId: true,
                        },
                    },
                },
            }),
        ]);
        // 🔄 Normalizamos a un solo formato
        return [
            ...propia.map((m) => ({
                ...m,
                origen: "PROPIA",
            })),
            ...prestada.map((p) => ({
                ...p.maquinaria,
                origen: "PRESTADA",
                tipoTenencia: p.tipoTenencia,
                fechaDevolucionEstimada: p.fechaDevolucionEstimada,
            })),
        ];
    }
    async asignarOperario(payload) {
        const { operarioId } = AsignarOperarioDTO.parse(payload);
        try {
            const existeOperario = await this.prisma.operario.findUnique({
                where: { id: operarioId.toString() },
                select: { id: true },
            });
            if (!existeOperario)
                throw new Error("Operario no encontrado.");
            await this.prisma.conjunto.update({
                where: { nit: this.conjuntoId },
                data: { operarios: { connect: { id: operarioId.toString() } } },
            });
        }
        catch (error) {
            console.error("Error al asignar operario:", error);
            throw new Error("No se pudo asignar el operario.");
        }
    }
    async asignarAdministrador(payload) {
        const { administradorId } = AsignarAdministradorDTO.parse(payload);
        try {
            const existeAdmin = await this.prisma.administrador.findUnique({
                where: { id: administradorId.toString() },
                select: { id: true },
            });
            if (!existeAdmin)
                throw new Error("Administrador no encontrado.");
            await this.prisma.conjunto.update({
                where: { nit: this.conjuntoId },
                data: {
                    administrador: { connect: { id: administradorId.toString() } },
                },
            });
        }
        catch (error) {
            console.error("Error al asignar administrador:", error);
            throw new Error("No se pudo asignar el administrador.");
        }
    }
    async eliminarAdministrador() {
        try {
            await this.prisma.conjunto.update({
                where: { nit: this.conjuntoId },
                data: { administradorId: null },
            });
        }
        catch (error) {
            console.error("Error al eliminar administrador:", error);
            throw new Error("No se pudo eliminar el administrador.");
        }
    }
    async agregarMaquinaria(payload) {
        const { maquinariaId } = AgregarMaquinariaDTO.parse(payload);
        try {
            // 1) validar que la maquinaria exista
            const maq = await this.prisma.maquinaria.findUnique({
                where: { id: maquinariaId },
                select: { id: true },
            });
            if (!maq)
                throw new Error("Maquinaria no encontrada.");
            // 2) validar que no esté ACTIVA en otro conjunto
            const asignacionActiva = await this.prisma.maquinariaConjunto.findFirst({
                where: { maquinariaId, estado: "ACTIVA" },
                select: { id: true, conjuntoId: true },
            });
            if (asignacionActiva) {
                if (asignacionActiva.conjuntoId === this.conjuntoId) {
                    throw new Error("La maquinaria ya está asignada a este conjunto.");
                }
                throw new Error("La maquinaria ya está asignada a otro conjunto.");
            }
            // 3) crear asignación (inventario de maquinaria del conjunto)
            await this.prisma.maquinariaConjunto.create({
                data: {
                    conjunto: { connect: { nit: this.conjuntoId } },
                    maquinaria: { connect: { id: maquinariaId } },
                    tipoTenencia: "PRESTADA",
                    estado: "ACTIVA",
                    fechaInicio: new Date(),
                },
            });
        }
        catch (error) {
            console.error("Error al agregar maquinaria al conjunto:", error);
            throw new Error("No se pudo asignar la maquinaria al conjunto.");
        }
    }
    async entregarMaquinaria(payload) {
        const { maquinariaId } = AgregarMaquinariaDTO.parse(payload);
        try {
            const asignacion = await this.prisma.maquinariaConjunto.findFirst({
                where: {
                    maquinariaId,
                    conjuntoId: this.conjuntoId,
                    estado: "ACTIVA",
                },
                select: { id: true },
            });
            if (!asignacion) {
                throw new Error("No hay una asignación ACTIVA de esa maquinaria en este conjunto.");
            }
            await this.prisma.maquinariaConjunto.update({
                where: { id: asignacion.id },
                data: {
                    estado: "DEVUELTA",
                    fechaFin: new Date(),
                },
            });
        }
        catch (error) {
            console.error("Error al devolver maquinaria:", error);
            throw new Error("No se pudo devolver la maquinaria.");
        }
    }
    async agregarUbicacion(payload) {
        const dto = Ubicacion_1.CrearUbicacionDTO.parse({
            ...payload,
            conjuntoId: this.conjuntoId,
        });
        try {
            const yaExiste = await this.prisma.ubicacion.findFirst({
                where: { nombre: dto.nombre, conjuntoId: this.conjuntoId },
                select: { id: true },
            });
            if (!yaExiste) {
                await this.prisma.ubicacion.create({
                    data: {
                        nombre: dto.nombre,
                        conjunto: { connect: { nit: this.conjuntoId } },
                    },
                });
            }
        }
        catch (error) {
            console.error("Error al agregar ubicación:", error);
            throw new Error("No se pudo agregar la ubicación.");
        }
    }
    async buscarUbicacion(payload) {
        const dto = Ubicacion_1.FiltroUbicacionDTO.parse({
            ...payload,
            conjuntoId: this.conjuntoId,
        });
        return this.prisma.ubicacion.findFirst({
            where: { conjuntoId: this.conjuntoId, nombre: dto.nombre },
            select: { id: true, nombre: true },
        });
    }
    async agregarTareaACronograma(payload) {
        const { tareaId } = TareaIdDTO.parse(payload);
        try {
            const tarea = await this.prisma.tarea.findUnique({
                where: { id: tareaId },
                select: { id: true },
            });
            if (!tarea)
                throw new Error("Tarea no encontrada.");
            await this.prisma.tarea.update({
                where: { id: tareaId },
                data: { conjunto: { connect: { nit: this.conjuntoId } } },
            });
        }
        catch (error) {
            console.error("Error al agregar tarea al cronograma:", error);
            throw new Error("No se pudo agregar la tarea al cronograma.");
        }
    }
    async tareasPorFecha(payload) {
        const { fecha } = FechaDTO.parse(payload);
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
                fechaInicio: { lte: fecha },
                fechaFin: { gte: fecha },
            },
        });
    }
    async tareasPorOperario(payload) {
        const { operarioId } = TareasPorOperarioDTO.parse(payload);
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
                operarios: { some: { id: operarioId.toString() } },
            },
        });
    }
    async tareasPorUbicacion(payload) {
        const { nombreUbicacion } = TareasPorUbicacionDTO.parse(payload);
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
                ubicacion: { nombre: { equals: nombreUbicacion, mode: "insensitive" } },
            },
        });
    }
}
exports.ConjuntoService = ConjuntoService;
