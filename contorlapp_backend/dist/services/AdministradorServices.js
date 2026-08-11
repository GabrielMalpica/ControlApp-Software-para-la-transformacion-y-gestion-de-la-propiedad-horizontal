"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdministradorService = void 0;
const SolicitudTarea_1 = require("../model/SolicitudTarea");
const SolicitudInsumo_1 = require("../model/SolicitudInsumo");
const SolicitudMaquinaria_1 = require("../model/SolicitudMaquinaria");
const CompromisoConjuntoService_1 = require("./CompromisoConjuntoService");
const NotificacionService_1 = require("./NotificacionService");
class AdministradorService {
    constructor(prisma, administradorId) {
        this.prisma = prisma;
        this.administradorId = administradorId;
    }
    get adminIdAsString() {
        return this.administradorId;
    }
    async validarConjuntoAsignado(conjuntoId) {
        const conjunto = await this.prisma.conjunto.findFirst({
            where: {
                nit: conjuntoId,
                administradorId: this.adminIdAsString,
            },
            select: { nit: true, nombre: true, empresaId: true },
        });
        if (!conjunto?.empresaId) {
            throw new Error("No tienes acceso a ese conjunto.");
        }
        return { ...conjunto, empresaId: conjunto.empresaId };
    }
    async validarCompromisoAsignado(id) {
        const compromiso = await this.prisma.compromisoConjunto.findFirst({
            where: {
                id,
                conjunto: { administradorId: this.adminIdAsString },
            },
            select: { id: true, conjuntoId: true },
        });
        if (!compromiso) {
            throw new Error("No tienes acceso a esa PQRS.");
        }
        return compromiso;
    }
    async verConjuntos() {
        try {
            const conjuntos = await this.prisma.conjunto.findMany({
                where: { administradorId: this.administradorId, activo: true },
                select: {
                    nombre: true,
                    nit: true,
                    direccion: true,
                    correo: true,
                    activo: true,
                    tipoServicio: true,
                    consignasEspeciales: true,
                    valorAgregado: true,
                    horarios: {
                        select: {
                            dia: true,
                            horaApertura: true,
                            horaCierre: true,
                            descansoInicio: true,
                            descansoFin: true,
                        },
                        orderBy: { dia: "asc" },
                    },
                },
            });
            return conjuntos;
        }
        catch (error) {
            console.error("Error al obtener conjuntos:", error);
            throw new Error("No se pudieron obtener los conjuntos.");
        }
    }
    async listarCompromisosConjunto(conjuntoId) {
        await this.validarConjuntoAsignado(conjuntoId);
        const service = new CompromisoConjuntoService_1.CompromisoConjuntoService(this.prisma);
        return service.listarPorConjunto(conjuntoId);
    }
    async crearCompromisoConjunto(input) {
        await this.validarConjuntoAsignado(input.conjuntoId);
        const service = new CompromisoConjuntoService_1.CompromisoConjuntoService(this.prisma);
        const creado = await service.crear(input);
        try {
            const notificaciones = new NotificacionService_1.NotificacionService(this.prisma);
            await notificaciones.notificarPqrsCreadaPorAdministrador({
                compromisoId: creado.id,
                conjuntoId: input.conjuntoId,
                titulo: creado.titulo,
                actorId: input.creadoPorId ?? this.adminIdAsString,
            });
        }
        catch (error) {
            console.error("No se pudo notificar la PQRS creada por administrador:", error);
        }
        return creado;
    }
    async actualizarCompromiso(id, data) {
        await this.validarCompromisoAsignado(id);
        const service = new CompromisoConjuntoService_1.CompromisoConjuntoService(this.prisma);
        return service.actualizar(id, data);
    }
    async eliminarCompromiso(id) {
        await this.validarCompromisoAsignado(id);
        const service = new CompromisoConjuntoService_1.CompromisoConjuntoService(this.prisma);
        return service.eliminar(id);
    }
    /**
     * Solicitar una tarea (SolicitudTarea) para un conjunto/ubicación/elemento.
     * Valida payload con Zod y además verifica coherencia:
     * - Ubicación pertenece al Conjunto
     * - Elemento pertenece a la Ubicación
     */
    async solicitarTarea(payload) {
        try {
            const dto = SolicitudTarea_1.CrearSolicitudTareaDTO.parse(payload);
            const conjunto = await this.validarConjuntoAsignado(dto.conjuntoId);
            // Validaciones de coherencia relacional
            const ubicacion = await this.prisma.ubicacion.findFirst({
                where: { id: dto.ubicacionId, conjuntoId: dto.conjuntoId },
                select: { id: true, conjuntoId: true },
            });
            if (!ubicacion || ubicacion.conjuntoId !== dto.conjuntoId) {
                throw new Error("La ubicación no pertenece al conjunto indicado.");
            }
            const elemento = await this.prisma.elemento.findUnique({
                where: { id: dto.elementoId },
                select: { id: true, ubicacionId: true },
            });
            if (!elemento || elemento.ubicacionId !== dto.ubicacionId) {
                throw new Error("El elemento no pertenece a la ubicación indicada.");
            }
            return await this.prisma.solicitudTarea.create({
                data: {
                    descripcion: dto.descripcion,
                    duracionHoras: dto.duracionHoras,
                    estado: "PENDIENTE",
                    observaciones: dto.observaciones ?? null,
                    conjunto: { connect: { nit: dto.conjuntoId } },
                    ubicacion: { connect: { id: dto.ubicacionId } },
                    elemento: { connect: { id: dto.elementoId } },
                    empresa: { connect: { nit: conjunto.empresaId } },
                },
            });
        }
        catch (error) {
            console.error("Error al crear solicitud de tarea:", error);
            throw new Error("No se pudo registrar la solicitud de tarea.");
        }
    }
    /**
     * Solicitar insumos (SolicitudInsumo + items).
     * Valida con Zod y asegura que el array de items no esté vacío.
     */
    async solicitarInsumos(payload) {
        try {
            // Validación principal
            const dto = SolicitudInsumo_1.CrearSolicitudInsumoDTO.parse(payload);
            const conjuntoAsignado = await this.validarConjuntoAsignado(dto.conjuntoId);
            // (Opcional) Validación por item si llega desde múltiples sitios
            dto.items.forEach((i) => SolicitudInsumo_1.SolicitudInsumoItemDTO.parse(i));
            // Validar que el conjunto exista (y empresa opcional)
            const insumoIds = [...new Set(dto.items.map((item) => item.insumoId))];
            const insumosValidos = await this.prisma.insumo.count({
                where: { id: { in: insumoIds }, empresaId: conjuntoAsignado.empresaId },
            });
            if (insumosValidos !== insumoIds.length) {
                throw new Error("Uno o mas insumos no pertenecen a la empresa del conjunto.");
            }
            return await this.prisma.solicitudInsumo.create({
                data: {
                    conjunto: { connect: { nit: dto.conjuntoId } },
                    empresa: { connect: { nit: conjuntoAsignado.empresaId } },
                    fechaSolicitud: new Date(),
                    aprobado: false,
                    insumosSolicitados: {
                        create: dto.items.map(({ insumoId, cantidad }) => ({
                            insumo: { connect: { id: insumoId } },
                            cantidad,
                        })),
                    },
                },
                include: {
                    insumosSolicitados: true,
                },
            });
        }
        catch (error) {
            console.error("Error al crear solicitud de insumos:", error);
            throw new Error("No se pudo registrar la solicitud de insumos.");
        }
    }
    /**
     * Solicitar maquinaria (SolicitudMaquinaria).
     * Valida con Zod y comprueba existencia de relaciones clave.
     */
    async solicitarMaquinaria(payload) {
        const dto = SolicitudMaquinaria_1.CrearSolicitudMaquinariaDTO.parse(payload);
        const conjunto = await this.validarConjuntoAsignado(dto.conjuntoId);
        const [maquinaria, operario] = await Promise.all([
            this.prisma.maquinaria.findFirst({
                where: {
                    id: dto.maquinariaId,
                    OR: [
                        { empresaId: conjunto.empresaId },
                        { conjuntoPropietario: { empresaId: conjunto.empresaId } },
                    ],
                },
                select: { id: true },
            }),
            this.prisma.operario.findFirst({
                where: {
                    id: dto.operarioId.toString(),
                    empresaId: conjunto.empresaId,
                    conjuntos: { some: { nit: conjunto.nit } },
                },
                select: { id: true },
            }),
        ]);
        if (!maquinaria)
            throw new Error("Maquinaria no encontrada.");
        if (!operario)
            throw new Error("Operario responsable no encontrado.");
        // (opcional) evitar pedir una maquinaria ya ACTIVA en algún conjunto
        const activa = await this.prisma.maquinariaConjunto.findFirst({
            where: { maquinariaId: dto.maquinariaId, estado: "ACTIVA" },
            select: { id: true },
        });
        if (activa)
            throw new Error("❌ Esa maquinaria ya está asignada (ACTIVA) a un conjunto.");
        return this.prisma.solicitudMaquinaria.create({
            data: {
                conjunto: { connect: { nit: dto.conjuntoId } },
                maquinaria: { connect: { id: dto.maquinariaId } },
                responsable: { connect: { id: dto.operarioId.toString() } },
                empresa: { connect: { nit: conjunto.empresaId } },
                fechaUso: dto.fechaUso,
                fechaDevolucionEstimada: dto.fechaDevolucionEstimada,
                estado: "PENDIENTE",
            },
        });
    }
}
exports.AdministradorService = AdministradorService;
