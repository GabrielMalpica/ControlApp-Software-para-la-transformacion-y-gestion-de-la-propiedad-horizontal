"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.JefeOperacionesService = void 0;
// src/services/JefeOperacionesService.ts
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const drive_evidencias_1 = require("../utils/drive_evidencias");
const fs_1 = __importDefault(require("fs"));
const elementoHierarchy_1 = require("../utils/elementoHierarchy");
const ConjuntoIdSchema = zod_1.z.string().trim().min(1).optional();
const VeredictoDTO = zod_1.z.object({
    accion: zod_1.z.enum(["APROBAR", "RECHAZAR", "NO_COMPLETADA"]),
    observacionesRechazo: zod_1.z.string().min(3).max(500).optional(),
    fechaVerificacion: zod_1.z.coerce.date().optional(),
});
const VeredictoMultipartDTO = zod_1.z.object({
    accion: zod_1.z.enum(["APROBAR", "RECHAZAR", "NO_COMPLETADA"]),
    observacionesRechazo: zod_1.z.string().optional(),
    fechaVerificacion: zod_1.z.string().optional(),
    evidenciasExtra: zod_1.z.string().optional(),
});
class JefeOperacionesService {
    constructor(prisma, empresaId) {
        this.prisma = prisma;
        const n = Number(empresaId);
        this.empresaIdNum = Number.isFinite(n) && n > 0 ? n : null;
    }
    async listarPendientes(conjuntoId) {
        const nit = ConjuntoIdSchema.parse(conjuntoId);
        return this.prisma.tarea.findMany({
            where: {
                estado: client_1.EstadoTarea.PENDIENTE_APROBACION,
                ...(nit ? { conjuntoId: nit } : {}),
            },
            orderBy: [{ fechaFinalizarTarea: "desc" }, { id: "desc" }],
            include: {
                conjunto: {
                    select: {
                        nit: true,
                        nombre: true,
                        direccion: true,
                        correo: true,
                        activo: true,
                    },
                },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
                operarios: { include: { usuario: true } },
                supervisor: { include: { usuario: true } },
            },
        });
    }
    async veredicto(tareaId, payload) {
        const dto = VeredictoDTO.parse(payload ?? {});
        return this._aplicarVeredictoCore({
            tareaId,
            accion: dto.accion,
            fechaVerificacion: dto.fechaVerificacion ?? new Date(),
            observacionesRechazo: dto.observacionesRechazo,
            evidenciasNuevas: [],
        });
    }
    async veredictoConEvidencias(tareaId, payload, files) {
        const dto = VeredictoMultipartDTO.parse(payload ?? {});
        const fechaVer = dto.fechaVerificacion
            ? new Date(dto.fechaVerificacion)
            : new Date();
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: {
                id: true,
                estado: true,
                evidencias: true,
                conjuntoId: true,
                conjunto: { select: { nit: true, nombre: true } },
            },
        });
        if (!tarea)
            throw new Error("❌ Tarea no encontrada.");
        if (tarea.estado !== client_1.EstadoTarea.PENDIENTE_APROBACION) {
            throw new Error("Solo puedes dar veredicto a tareas PENDIENTE_APROBACION.");
        }
        let evidenciasExtra = [];
        if (dto.evidenciasExtra?.trim()) {
            try {
                const parsed = JSON.parse(dto.evidenciasExtra);
                evidenciasExtra = zod_1.z.array(zod_1.z.string().min(3)).parse(parsed);
            }
            catch {
                throw new Error('evidenciasExtra debe ser JSON válido: ["url1","url2"]');
            }
        }
        const urlsDrive = [];
        try {
            for (const f of files ?? []) {
                const url = await (0, drive_evidencias_1.uploadEvidenciaToDrive)({
                    filePath: f.path,
                    fileName: `Aprobacion_Tarea_${tareaId}_${fechaVer.toISOString().replace(/[:.]/g, "-")}_${f.originalname}`,
                    mimeType: f.mimetype,
                    conjuntoNit: tarea.conjunto?.nit ?? tarea.conjuntoId ?? "SIN_CONJUNTO",
                    conjuntoNombre: tarea.conjunto?.nombre ?? undefined,
                    fecha: fechaVer,
                });
                urlsDrive.push(url);
            }
        }
        finally {
            for (const f of files ?? []) {
                try {
                    if (fs_1.default.existsSync(f.path))
                        fs_1.default.unlinkSync(f.path);
                }
                catch { }
            }
        }
        const actuales = tarea.evidencias ?? [];
        const merged = [...actuales, ...evidenciasExtra, ...urlsDrive]
            .map((x) => x.trim())
            .filter((x) => x.length > 0);
        const evidenciasFinal = Array.from(new Set(merged));
        return this._aplicarVeredictoCore({
            tareaId,
            accion: dto.accion,
            fechaVerificacion: fechaVer,
            observacionesRechazo: dto.observacionesRechazo,
            evidenciasNuevas: evidenciasFinal,
        });
    }
    async _aplicarVeredictoCore(params) {
        const { tareaId, accion, fechaVerificacion, observacionesRechazo, evidenciasNuevas, } = params;
        const dataEvidencias = evidenciasNuevas.length > 0 ? { evidencias: evidenciasNuevas } : {};
        if (accion === "APROBAR") {
            await this.prisma.tarea.update({
                where: { id: tareaId },
                data: {
                    ...dataEvidencias,
                    estado: client_1.EstadoTarea.APROBADA,
                    fechaVerificacion,
                    empresaAprobadaId: this.empresaIdNum, // ✅ number|null
                    empresaRechazadaId: null,
                    observacionesRechazo: null,
                },
            });
            return { ok: true, estado: client_1.EstadoTarea.APROBADA };
        }
        if (accion === "NO_COMPLETADA") {
            await this.prisma.tarea.update({
                where: { id: tareaId },
                data: {
                    ...dataEvidencias,
                    estado: client_1.EstadoTarea.NO_COMPLETADA,
                    fechaVerificacion,
                    empresaAprobadaId: null,
                    empresaRechazadaId: null,
                    observacionesRechazo: null,
                },
            });
            return { ok: true, estado: client_1.EstadoTarea.NO_COMPLETADA };
        }
        if (!observacionesRechazo?.trim()) {
            throw new Error("Para rechazar debes enviar observacionesRechazo.");
        }
        await this.prisma.tarea.update({
            where: { id: tareaId },
            data: {
                ...dataEvidencias,
                estado: client_1.EstadoTarea.RECHAZADA,
                fechaVerificacion,
                observacionesRechazo: observacionesRechazo.trim(),
                empresaRechazadaId: this.empresaIdNum, // ✅ number|null
                empresaAprobadaId: null,
            },
        });
        return { ok: true, estado: client_1.EstadoTarea.RECHAZADA };
    }
}
exports.JefeOperacionesService = JefeOperacionesService;
