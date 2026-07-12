"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CompromisoConjuntoService = void 0;
function makeHttpError(status, message) {
    const err = new Error(message);
    err.status = status;
    return err;
}
class CompromisoConjuntoService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    buildAns(compromiso) {
        if (compromiso.completado) {
            return {
                ansEstado: "cerrado",
                ansColor: "neutral",
                ansLabel: "Cerrado",
            };
        }
        const msAbierto = Date.now() - compromiso.creadaEn.getTime();
        const diasAbierto = Math.max(0, Math.floor(msAbierto / (1000 * 60 * 60 * 24)));
        if (diasAbierto <= 7) {
            return {
                ansEstado: "verde",
                ansColor: "green",
                ansLabel: "ANS en tiempo",
            };
        }
        if (diasAbierto <= 21) {
            return {
                ansEstado: "naranja",
                ansColor: "orange",
                ansLabel: "ANS en seguimiento",
            };
        }
        return {
            ansEstado: "rojo",
            ansColor: "red",
            ansLabel: "ANS critico",
        };
    }
    formatRol(rol) {
        const normalized = String(rol ?? "").trim().toLowerCase();
        if (normalized == "jefe_operaciones")
            return "Jefe de operaciones";
        if (normalized == "administrador")
            return "Administrador";
        if (normalized == "supervisor")
            return "Supervisor";
        if (normalized == "operario")
            return "Operario";
        if (normalized == "gerente")
            return "Gerente";
        return normalized ? normalized[0].toUpperCase() + normalized.slice(1) : null;
    }
    serializeCompromiso(item) {
        const ans = this.buildAns(item);
        return {
            id: item.id,
            conjuntoId: item.conjuntoId,
            titulo: item.titulo,
            completado: item.completado,
            creadaEn: item.creadaEn,
            cerradaEn: item.cerradaEn,
            actualizadaEn: item.actualizadaEn,
            creadoPorId: item.creadoPorId,
            creadoPorNombre: item.creadoPor?.nombre ?? null,
            creadoPorRol: this.formatRol(item.creadoPor?.rol),
            diasAbierto: Math.max(0, Math.floor((Date.now() - item.creadaEn.getTime()) / (1000 * 60 * 60 * 24))),
            ansEstado: ans.ansEstado,
            ansColor: ans.ansColor,
            ansLabel: ans.ansLabel,
            conjuntoNombre: item.conjunto?.nombre ?? item.conjuntoId,
            conjuntoNit: item.conjunto?.nit ?? item.conjuntoId,
        };
    }
    async listarPorConjunto(conjuntoId) {
        const items = await this.prisma.compromisoConjunto.findMany({
            where: { conjuntoId },
            orderBy: [{ completado: "asc" }, { creadaEn: "desc" }],
            select: {
                id: true,
                conjuntoId: true,
                titulo: true,
                completado: true,
                creadaEn: true,
                cerradaEn: true,
                actualizadaEn: true,
                creadoPorId: true,
                creadoPor: {
                    select: {
                        nombre: true,
                        rol: true,
                    },
                },
            },
        });
        return items.map((item) => this.serializeCompromiso(item));
    }
    async listarGlobal() {
        const items = await this.prisma.compromisoConjunto.findMany({
            orderBy: [
                { completado: "asc" },
                { conjunto: { nombre: "asc" } },
                { creadaEn: "desc" },
            ],
            select: {
                id: true,
                conjuntoId: true,
                titulo: true,
                completado: true,
                creadaEn: true,
                cerradaEn: true,
                actualizadaEn: true,
                creadoPorId: true,
                creadoPor: {
                    select: {
                        nombre: true,
                        rol: true,
                    },
                },
                conjunto: { select: { nit: true, nombre: true } },
            },
        });
        return items.map((item) => this.serializeCompromiso(item));
    }
    async crear(input) {
        const titulo = input.titulo.trim();
        if (!titulo) {
            throw makeHttpError(400, "El compromiso no puede estar vacio");
        }
        const created = await this.prisma.compromisoConjunto.create({
            data: {
                conjuntoId: input.conjuntoId,
                titulo,
                creadoPorId: input.creadoPorId ?? null,
            },
            select: {
                id: true,
                conjuntoId: true,
                titulo: true,
                completado: true,
                creadaEn: true,
                cerradaEn: true,
                actualizadaEn: true,
                creadoPorId: true,
                creadoPor: {
                    select: {
                        nombre: true,
                        rol: true,
                    },
                },
            },
        });
        return this.serializeCompromiso(created);
    }
    async actualizar(id, data) {
        const current = await this.prisma.compromisoConjunto.findUnique({ where: { id } });
        if (!current) {
            throw makeHttpError(404, "Compromiso no encontrado");
        }
        const payload = {};
        if (typeof data.titulo === "string") {
            const titulo = data.titulo.trim();
            if (!titulo) {
                throw makeHttpError(400, "El compromiso no puede estar vacio");
            }
            payload.titulo = titulo;
        }
        if (typeof data.completado === "boolean") {
            payload.completado = data.completado;
            if (data.completado && !current.completado) {
                payload.cerradaEn = new Date();
            }
            if (!data.completado && current.completado) {
                payload.cerradaEn = null;
            }
        }
        const updated = await this.prisma.compromisoConjunto.update({
            where: { id },
            data: payload,
            select: {
                id: true,
                conjuntoId: true,
                titulo: true,
                completado: true,
                creadaEn: true,
                cerradaEn: true,
                actualizadaEn: true,
                creadoPorId: true,
                creadoPor: {
                    select: {
                        nombre: true,
                        rol: true,
                    },
                },
            },
        });
        return this.serializeCompromiso(updated);
    }
    async eliminar(id) {
        const current = await this.prisma.compromisoConjunto.findUnique({ where: { id } });
        if (!current) {
            throw makeHttpError(404, "Compromiso no encontrado");
        }
        await this.prisma.compromisoConjunto.delete({ where: { id } });
        return { ok: true };
    }
}
exports.CompromisoConjuntoService = CompromisoConjuntoService;
