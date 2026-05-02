"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupervisorService = exports.CerrarDTO = void 0;
// src/services/SupervisorService.ts
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const InventarioServices_1 = require("./InventarioServices");
const drive_evidencias_1 = require("../utils/drive_evidencias");
const fs_1 = __importDefault(require("fs"));
const NotificacionService_1 = require("./NotificacionService");
const elementoHierarchy_1 = require("../utils/elementoHierarchy");
function parseInsumosPlanJson(raw) {
    if (!raw)
        return [];
    try {
        // Prisma Json puede venir como object/array ya parseado
        const v = raw;
        if (Array.isArray(v))
            return v;
        if (typeof v === "string") {
            const parsed = JSON.parse(v);
            return Array.isArray(parsed) ? parsed : [];
        }
        // si viene como {items:[...]} o similar, intenta detectar
        if (typeof v === "object") {
            if (Array.isArray(v.items))
                return v.items;
        }
        return [];
    }
    catch {
        return [];
    }
}
const ListarDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    operarioId: zod_1.z.string().optional(),
    estado: zod_1.z.nativeEnum(client_1.EstadoTarea).optional(),
    desde: zod_1.z.coerce.date().optional(),
    hasta: zod_1.z.coerce.date().optional(),
    borrador: zod_1.z.coerce.boolean().optional(),
});
const CerrarMultipartDTO = zod_1.z.object({
    accion: zod_1.z.enum(["COMPLETADA", "NO_COMPLETADA"]).optional(),
    observaciones: zod_1.z.string().optional(),
    fechaFinalizarTarea: zod_1.z.string().optional(), // viene string ISO
    insumosUsados: zod_1.z.string().optional(), // JSON string
});
exports.CerrarDTO = zod_1.z.object({
    evidencias: zod_1.z.array(zod_1.z.string()).optional().default([]),
    fechaFinalizarTarea: zod_1.z.coerce.date().optional(),
    observaciones: zod_1.z.string().max(500).optional(),
    // 1) ✅ insumos usados
    insumosUsados: zod_1.z
        .array(zod_1.z.object({
        insumoId: zod_1.z.number().int().positive(),
        cantidad: zod_1.z.coerce.number().positive(),
    }))
        .optional()
        .default([]),
    // 2) ✅ maquinaria usada
    maquinariasUsadas: zod_1.z
        .array(zod_1.z.object({
        maquinariaId: zod_1.z.number().int().positive(),
        observacion: zod_1.z.string().max(300).optional(),
    }))
        .optional()
        .default([]),
    // 3) ✅ herramientas usadas
    herramientasUsadas: zod_1.z
        .array(zod_1.z.object({
        herramientaId: zod_1.z.number().int().positive(),
        cantidad: zod_1.z.coerce.number().positive().optional().default(1),
        observacion: zod_1.z.string().max(300).optional(),
    }))
        .optional()
        .default([]),
});
const VeredictoDTO = zod_1.z.object({
    accion: zod_1.z.enum(["APROBAR", "RECHAZAR", "NO_COMPLETADA"]),
    observacionesRechazo: zod_1.z.string().min(3).max(500).optional(),
    fechaVerificacion: zod_1.z.coerce.date().optional(),
});
class SupervisorService {
    constructor(prisma, supervisorId, actorRol = "SUPERVISOR") {
        this.prisma = prisma;
        this.supervisorId = supervisorId;
        this.actorRol = actorRol;
    }
    actorRolDb() {
        return this.actorRol;
    }
    actorRolLabel() {
        switch (this.actorRol) {
            case "GERENTE":
                return "gerente";
            case "JEFE_OPERACIONES":
                return "jefe de operaciones";
            default:
                return "supervisor";
        }
    }
    assertPuedeCerrarTarea(tarea) {
        if (this.actorRol !== "SUPERVISOR")
            return;
        if (!tarea.supervisorId || tarea.supervisorId !== this.supervisorId) {
            const err = new Error("No tiene autorizacion para cerrar esta tarea.");
            err.status = 403;
            throw err;
        }
    }
    /** Lista tareas para el supervisor (por conjunto/operario/estado y rango) */
    async listarTareas(payload) {
        const dto = ListarDTO.parse(payload ?? {});
        const where = {};
        if (dto.conjuntoId)
            where.conjuntoId = dto.conjuntoId;
        if (dto.estado)
            where.estado = dto.estado;
        where.borrador = dto.borrador ?? false;
        if (dto.operarioId)
            where.operarios = { some: { id: dto.operarioId } };
        if (dto.desde || dto.hasta) {
            where.fechaInicio = {};
            if (dto.desde)
                where.fechaInicio.gte = dto.desde;
            if (dto.hasta)
                where.fechaInicio.lte = dto.hasta;
        }
        const rows = await this.prisma.tarea.findMany({
            where,
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
            include: {
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
                conjunto: true,
                operarios: { include: { usuario: true } },
                supervisor: { include: { usuario: true } },
                insumoPrincipal: { select: { id: true, nombre: true, unidad: true } },
                usoHerramientas: {
                    include: { herramienta: { select: { id: true, nombre: true } } },
                },
                usoMaquinarias: {
                    include: { maquinaria: { select: { id: true, nombre: true } } },
                },
            },
        });
        const byGP = new Map();
        for (const t of rows) {
            const gp = t.grupoPlanId;
            if (!gp)
                continue;
            const herramientas = t.usoHerramientas.map((u) => ({
                herramientaId: u.herramientaId,
                nombre: u.herramienta?.nombre ?? "",
                cantidad: Number(u.cantidad),
                estado: u.estado,
            }));
            const maquinarias = t.usoMaquinarias.map((u) => ({
                maquinariaId: u.maquinariaId,
                nombre: u.maquinaria?.nombre ?? "",
            }));
            const insumos = parseInsumosPlanJson(t.insumosPlanJson);
            const cur = byGP.get(gp) ?? {
                herramientas: [],
                maquinarias: [],
                insumos: [],
            };
            if (herramientas.length)
                cur.herramientas = herramientas;
            if (maquinarias.length)
                cur.maquinarias = maquinarias;
            if (insumos.length)
                cur.insumos = insumos;
            byGP.set(gp, cur);
        }
        return rows.map((t) => {
            const gp = t.grupoPlanId;
            let herramientasAsignadas = t.usoHerramientas.map((u) => ({
                herramientaId: u.herramientaId,
                nombre: u.herramienta?.nombre ?? "",
                cantidad: Number(u.cantidad),
                estado: u.estado,
            }));
            let maquinariasAsignadas = t.usoMaquinarias.map((u) => ({
                maquinariaId: u.maquinariaId,
                nombre: u.maquinaria?.nombre ?? "",
            }));
            let insumosProgramados = parseInsumosPlanJson(t.insumosPlanJson);
            if (gp) {
                const ref = byGP.get(gp);
                if (ref) {
                    if (!herramientasAsignadas.length)
                        herramientasAsignadas = ref.herramientas;
                    if (!maquinariasAsignadas.length)
                        maquinariasAsignadas = ref.maquinarias;
                    if (!insumosProgramados.length)
                        insumosProgramados = ref.insumos;
                }
            }
            return {
                id: t.id,
                descripcion: t.descripcion,
                fechaInicio: t.fechaInicio,
                fechaFin: t.fechaFin,
                duracionMinutos: t.duracionMinutos,
                prioridad: t.prioridad,
                estado: t.estado,
                evidencias: t.evidencias ?? [],
                observaciones: t.observaciones,
                observacionesRechazo: t.observacionesRechazo,
                borrador: t.borrador,
                conjuntoId: t.conjuntoId ?? null,
                conjuntoNombre: t.conjunto?.nombre ?? null,
                supervisorId: t.supervisorId ?? null,
                supervisorNombre: t.supervisor?.usuario?.nombre ?? null,
                ubicacionId: t.ubicacionId,
                ubicacionNombre: t.ubicacion?.nombre ?? null,
                elementoId: t.elementoId,
                elementoNombre: (0, elementoHierarchy_1.construirRutaElemento)(t.elemento) ?? null,
                operariosIds: t.operarios.map((o) => o.id),
                operariosNombres: t.operarios.map((o) => o.usuario?.nombre ?? ""),
                herramientasAsignadas,
                maquinariasAsignadas,
                // ✅ insumos
                insumoPrincipalNombre: t.insumoPrincipal?.nombre ?? null,
                insumoPrincipalUnidad: t.insumoPrincipal?.unidad ?? null,
                consumoPrincipalPorUnidad: t.consumoPrincipalPorUnidad ?? null,
                consumoTotalEstimado: t.consumoTotalEstimado ?? null,
                insumosProgramados,
            };
        });
    }
    // dentro de SupervisorService
    async cronogramaImprimible(payload) {
        // Reutiliza tu listarTareas
        const tareas = await this.listarTareas({
            conjuntoId: payload.conjuntoId,
            operarioId: payload.operarioId,
            desde: payload.desde,
            hasta: payload.hasta,
            // normalmente imprimimos ASIGNADA/EN_PROCESO (tú decides)
        });
        // Datos operario / conjunto (opcional pero recomendado)
        const operario = await this.prisma.operario.findUnique({
            where: { id: payload.operarioId },
            include: { usuario: true },
        });
        const conjunto = await this.prisma.conjunto.findUnique({
            where: { nit: payload.conjuntoId },
            select: { nit: true, nombre: true },
        });
        // Agrupar por día (ISO yyyy-mm-dd)
        const diasMap = new Map();
        for (const t of tareas) {
            const key = this.isoDate(this.dayOnly(new Date(t.fechaInicio)));
            const arr = diasMap.get(key) ?? [];
            arr.push({
                id: t.id,
                hora: `${String(new Date(t.fechaInicio).getHours()).padStart(2, "0")}:${String(new Date(t.fechaInicio).getMinutes()).padStart(2, "0")}` +
                    " - " +
                    `${String(new Date(t.fechaFin).getHours()).padStart(2, "0")}:${String(new Date(t.fechaFin).getMinutes()).padStart(2, "0")}`,
                descripcion: t.descripcion ?? "",
                ubicacion: t.ubicacionNombre ?? "",
                elemento: t.elementoNombre ?? "",
                prioridad: t.prioridad ?? null,
                herramientas: (t.herramientasAsignadas ?? []).map((h) => `${h.nombre} x${h.cantidad}`),
                maquinarias: (t.maquinariasAsignadas ?? []).map((m) => `${m.nombre}`),
            });
            diasMap.set(key, arr);
        }
        // Ordenar días y tareas por hora
        const dias = Array.from(diasMap.entries())
            .sort((a, b) => a[0].localeCompare(b[0]))
            .map(([fecha, tareasDia]) => ({
            fecha,
            tareas: tareasDia.sort((a, b) => a.hora.localeCompare(b.hora)),
        }));
        return {
            ok: true,
            conjuntoId: payload.conjuntoId,
            conjuntoNombre: conjunto?.nombre ?? null,
            operarioId: payload.operarioId,
            operarioNombre: operario?.usuario?.nombre ?? null,
            desde: payload.desde,
            hasta: payload.hasta,
            dias,
        };
    }
    /**
     * Cerrar tarea por supervisor (operario SIN app):
     * - Solo si está ASIGNADA / EN_PROCESO / COMPLETADA
     * - Guarda evidencias
     * - estado -> PENDIENTE_APROBACION
     * - fechaFinalizarTarea -> now (o la enviada)
     * - descuenta insumos + registra usos de maquinaria/herramientas y libera lo prestado
     */
    async cerrarTarea(tareaId, payload) {
        const dto = exports.CerrarDTO.parse(payload ?? {});
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: {
                id: true,
                estado: true,
                evidencias: true,
                conjuntoId: true,
                supervisorId: true,
                operarios: { select: { id: true } },
            },
        });
        if (!tarea)
            throw new Error("❌ Tarea no encontrada.");
        this.assertPuedeCerrarTarea(tarea);
        const permitidos = new Set([
            client_1.EstadoTarea.ASIGNADA,
            client_1.EstadoTarea.EN_PROCESO,
            client_1.EstadoTarea.COMPLETADA,
        ]);
        if (!permitidos.has(tarea.estado)) {
            throw new Error(`No puedes cerrar una tarea en estado ${tarea.estado}.`);
        }
        if (!tarea.conjuntoId) {
            throw new Error("❌ La tarea no tiene conjunto asignado (no puedo afectar inventario/stock).");
        }
        const inv = await this.prisma.inventario.findUnique({
            where: { conjuntoId: tarea.conjuntoId },
            select: { id: true },
        });
        if (!inv) {
            throw new Error(`❌ El conjunto ${tarea.conjuntoId} no tiene inventario creado.`);
        }
        const ahora = dto.fechaFinalizarTarea ?? new Date();
        const actuales = tarea.evidencias ?? [];
        const mergeEvidencias = [...actuales, ...(dto.evidencias ?? [])];
        const insumosUsados = dto.insumosUsados ?? [];
        const maquinariasUsadas = dto.maquinariasUsadas ?? [];
        const herramientasUsadas = dto.herramientasUsadas ?? [];
        // opcional: trazabilidad
        const operarioId = tarea.operarios?.[0]?.id ?? null;
        await this.prisma.$transaction(async (tx) => {
            // 1) ✅ DESCONTAR INSUMOS
            const inventarioSvc = new InventarioServices_1.InventarioService(tx, inv.id);
            for (const it of insumosUsados) {
                await inventarioSvc.consumirInsumoPorId({
                    insumoId: it.insumoId,
                    cantidad: it.cantidad,
                });
            }
            // 2) ✅ MAQUINARIA: asegurar uso abierto + cerrar + liberar maquinariaConjunto
            for (const m of maquinariasUsadas) {
                // 2.0 Asegurar uso abierto
                const existeUsoAbierto = await tx.usoMaquinaria.findFirst({
                    where: {
                        tareaId,
                        maquinariaId: m.maquinariaId,
                        fechaFin: null,
                    },
                    select: { id: true },
                });
                if (!existeUsoAbierto) {
                    await tx.usoMaquinaria.create({
                        data: {
                            tarea: { connect: { id: tareaId } },
                            maquinaria: { connect: { id: m.maquinariaId } },
                            ...(operarioId
                                ? { operario: { connect: { id: operarioId } } }
                                : {}),
                            fechaInicio: ahora,
                            observacion: m.observacion ?? null,
                        },
                    });
                }
                // 2.1 Cerrar usos abiertos
                await tx.usoMaquinaria.updateMany({
                    where: {
                        tareaId,
                        maquinariaId: m.maquinariaId,
                        fechaFin: null,
                    },
                    data: {
                        fechaFin: ahora,
                        // si viene observación, la guardamos; si no, no pisamos con null
                        ...(m.observacion ? { observacion: m.observacion } : {}),
                        ...(operarioId ? { operarioId } : {}),
                    },
                });
                // 2.2 Liberar maquinaria del conjunto (si estaba amarrada a esta tarea)
                await tx.maquinariaConjunto.updateMany({
                    where: {
                        conjuntoId: tarea.conjuntoId,
                        maquinariaId: m.maquinariaId,
                        tareaId: tareaId,
                    },
                    data: {
                        tareaId: null,
                        operarioId: null,
                        fechaDevolucionEstimada: null,
                    },
                });
            }
            // 3) ✅ HERRAMIENTAS: asegurar uso abierto + cerrar + marcar DEVUELTA
            for (const h of herramientasUsadas) {
                const existeUsoAbierto = await tx.usoHerramienta.findFirst({
                    where: {
                        tareaId,
                        herramientaId: h.herramientaId,
                        fechaFin: null,
                    },
                    select: { id: true },
                });
                if (!existeUsoAbierto) {
                    await tx.usoHerramienta.create({
                        data: {
                            tarea: { connect: { id: tareaId } },
                            herramienta: { connect: { id: h.herramientaId } },
                            cantidad: h.cantidad ?? 1,
                            estado: client_1.EstadoUsoHerramienta.EN_USO,
                            ...(operarioId
                                ? { operario: { connect: { id: operarioId } } }
                                : {}),
                            fechaInicio: ahora,
                            observacion: h.observacion ?? null,
                        },
                    });
                }
                await tx.usoHerramienta.updateMany({
                    where: {
                        tareaId,
                        herramientaId: h.herramientaId,
                        fechaFin: null,
                    },
                    data: {
                        fechaFin: ahora,
                        estado: client_1.EstadoUsoHerramienta.DEVUELTA,
                        ...(h.observacion ? { observacion: h.observacion } : {}),
                        ...(operarioId ? { operarioId } : {}),
                    },
                });
            }
            // 4) ✅ ACTUALIZAR TAREA: evidencias + observaciones + estado pendiente aprobación
            await tx.tarea.update({
                where: { id: tareaId },
                data: {
                    evidencias: mergeEvidencias,
                    observaciones: dto.observaciones ?? undefined,
                    estado: client_1.EstadoTarea.PENDIENTE_APROBACION,
                    fechaFinalizarTarea: ahora,
                    supervisorId: this.actorRol === "SUPERVISOR" ? this.supervisorId : undefined,
                    finalizadaPorId: this.supervisorId,
                    finalizadaPorRol: this.actorRolDb(),
                },
            });
        });
    }
    async cerrarTareaConEvidencias(tareaId, payload, files) {
        const dto = CerrarMultipartDTO.parse(payload ?? {});
        const accion = dto.accion ?? "COMPLETADA";
        const fechaCierre = dto.fechaFinalizarTarea
            ? new Date(dto.fechaFinalizarTarea)
            : new Date();
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: {
                id: true,
                descripcion: true,
                estado: true,
                evidencias: true,
                conjuntoId: true,
                supervisorId: true,
                conjunto: { select: { nit: true, nombre: true } },
            },
        });
        if (!tarea)
            throw new Error("❌ Tarea no encontrada.");
        const permitidos = new Set([
            client_1.EstadoTarea.ASIGNADA,
            client_1.EstadoTarea.EN_PROCESO,
            client_1.EstadoTarea.COMPLETADA,
        ]);
        if (!permitidos.has(tarea.estado)) {
            throw new Error(`No puedes cerrar una tarea en estado ${tarea.estado}.`);
        }
        if (accion === "COMPLETADA" && !tarea.conjuntoId) {
            throw new Error("La tarea no tiene conjunto asignado, no puedo descontar inventario.");
        }
        // 1) Parse insumosUsados (JSON string)
        let insumosUsados = [];
        if (accion === "COMPLETADA" && dto.insumosUsados && dto.insumosUsados.trim().length) {
            try {
                const parsed = JSON.parse(dto.insumosUsados);
                insumosUsados = zod_1.z
                    .array(zod_1.z.object({
                    insumoId: zod_1.z.number().int().positive(),
                    cantidad: zod_1.z.number().positive(),
                }))
                    .parse(parsed);
            }
            catch {
                throw new Error("insumosUsados debe ser un JSON válido: [{insumoId, cantidad}]");
            }
        }
        // 2) Subir evidencias a Drive
        const urls = [];
        try {
            for (const f of files ?? []) {
                const url = await (0, drive_evidencias_1.uploadEvidenciaToDrive)({
                    filePath: f.path,
                    fileName: `Tarea_${tareaId}_${fechaCierre
                        .toISOString()
                        .replace(/[:.]/g, "-")}_${f.originalname}`,
                    mimeType: f.mimetype,
                    conjuntoNit: tarea.conjunto?.nit ?? tarea.conjuntoId ?? "SIN_CONJUNTO",
                    conjuntoNombre: tarea.conjunto?.nombre ?? undefined,
                    fecha: fechaCierre,
                });
                urls.push(url);
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
        const evidenciasMerge = [...(tarea.evidencias ?? []), ...urls];
        // 3) Transacción: descontar inventario + registrar consumo + liberar usos + cerrar tarea
        await this.prisma.$transaction(async (tx) => {
            const inventario = accion === "COMPLETADA"
                ? await tx.inventario.findUnique({
                    where: { conjuntoId: tarea.conjuntoId },
                    select: { id: true },
                })
                : null;
            if (accion === "COMPLETADA" && !inventario) {
                throw new Error("No existe inventario para este conjunto.");
            }
            // ✅ descontar parcial: resta SOLO lo usado
            for (const item of insumosUsados) {
                const invItem = await tx.inventarioInsumo.findUnique({
                    where: {
                        inventarioId_insumoId: {
                            inventarioId: inventario.id,
                            insumoId: item.insumoId,
                        },
                    },
                    select: { id: true, cantidad: true },
                });
                if (!invItem) {
                    throw new Error(`El insumo ${item.insumoId} no existe en inventario del conjunto.`);
                }
                const actual = invItem.cantidad; // Prisma.Decimal
                const usar = new client_1.Prisma.Decimal(item.cantidad);
                if (usar.lte(0))
                    continue;
                if (actual.lt(usar)) {
                    throw new Error(`Stock insuficiente para insumo ${item.insumoId}. Stock=${actual.toString()} / Usar=${usar.toString()}`);
                }
                await tx.inventarioInsumo.update({
                    where: { id: invItem.id },
                    data: { cantidad: actual.minus(usar) },
                });
                await tx.consumoInsumo.create({
                    data: {
                        inventario: { connect: { id: inventario.id } },
                        insumo: { connect: { id: item.insumoId } },
                        tipo: client_1.TipoMovimientoInsumo.SALIDA,
                        tarea: { connect: { id: tareaId } },
                        cantidad: usar,
                        fecha: fechaCierre,
                        observacion: `Consumo en cierre de tarea #${tareaId} por ${this.actorRolLabel()} ${this.supervisorId}`,
                        // operarioId NO se manda (undefined) para no chocar con tu modelo
                    },
                });
            }
            // ✅ liberar maquinaria en uso (UsoMaquinaria)
            await tx.usoMaquinaria.updateMany({
                where: { tareaId, fechaFin: null },
                data: {
                    fechaFin: fechaCierre,
                    observacion: "Devuelta al cerrar tarea",
                },
            });
            // ✅ liberar herramientas en uso (UsoHerramienta)
            await tx.usoHerramienta.updateMany({
                where: { tareaId, fechaFin: null },
                data: {
                    fechaFin: fechaCierre,
                    estado: client_1.EstadoUsoHerramienta.DEVUELTA,
                    observacion: "Devuelta al cerrar tarea",
                },
            });
            // ✅ MUY IMPORTANTE: si tu ocupación depende de MaquinariaConjunto.tareaId
            await tx.maquinariaConjunto.updateMany({
                where: { tareaId },
                data: { tareaId: null },
            });
            // ✅ cerrar tarea
            if (accion === "NO_COMPLETADA" && (!dto.observaciones || dto.observaciones.trim().length < 3)) {
                throw new Error("Debes indicar el motivo u observación de por qué no se realizó la tarea.");
            }
            await tx.tarea.update({
                where: { id: tareaId },
                data: {
                    evidencias: evidenciasMerge,
                    observaciones: dto.observaciones ?? undefined,
                    insumosUsados: accion === "COMPLETADA" ? insumosUsados : undefined,
                    estado: accion === "NO_COMPLETADA"
                        ? client_1.EstadoTarea.NO_COMPLETADA
                        : client_1.EstadoTarea.PENDIENTE_APROBACION,
                    fechaFinalizarTarea: fechaCierre,
                    supervisorId: this.actorRol === "SUPERVISOR" ? this.supervisorId : undefined,
                    finalizadaPorId: this.supervisorId,
                    finalizadaPorRol: this.actorRolDb(),
                },
            });
        });
        try {
            const notificaciones = new NotificacionService_1.NotificacionService(this.prisma);
            if (tarea.conjuntoId) {
                await notificaciones.notificarCierreTarea({
                    tareaId,
                    descripcionTarea: tarea.descripcion,
                    conjuntoId: tarea.conjuntoId,
                    actorId: this.supervisorId,
                    actorRol: this.actorRolDb(),
                    supervisorId: tarea.supervisorId,
                });
            }
        }
        catch (e) {
            console.error("No se pudo notificar cierre de tarea (supervisor):", e);
        }
    }
    /**
     * Veredicto del supervisor:
     * - APROBAR => APROBADA
     * - RECHAZAR => RECHAZADA + observacionesRechazo
     * - NO_COMPLETADA => NO_COMPLETADA
     *
     * Solo aplica si está PENDIENTE_APROBACION.
     */
    async veredicto(tareaId, payload) {
        const dto = VeredictoDTO.parse(payload);
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: { estado: true },
        });
        if (!tarea)
            throw new Error("❌ Tarea no encontrada.");
        if (tarea.estado !== client_1.EstadoTarea.PENDIENTE_APROBACION) {
            throw new Error("Solo puedes dar veredicto a tareas en PENDIENTE_APROBACION.");
        }
        const fechaVer = dto.fechaVerificacion ?? new Date();
        if (dto.accion === "APROBAR") {
            await this.prisma.tarea.update({
                where: { id: tareaId },
                data: {
                    estado: client_1.EstadoTarea.APROBADA,
                    fechaVerificacion: fechaVer,
                    supervisorId: this.supervisorId,
                },
            });
            return;
        }
        if (dto.accion === "NO_COMPLETADA") {
            await this.prisma.tarea.update({
                where: { id: tareaId },
                data: {
                    estado: client_1.EstadoTarea.NO_COMPLETADA,
                    fechaVerificacion: fechaVer,
                    supervisorId: this.supervisorId,
                },
            });
            return;
        }
        // RECHAZAR
        if (!dto.observacionesRechazo ||
            dto.observacionesRechazo.trim().length < 3) {
            throw new Error("Para rechazar debes enviar observacionesRechazo.");
        }
        await this.prisma.tarea.update({
            where: { id: tareaId },
            data: {
                estado: client_1.EstadoTarea.RECHAZADA,
                observacionesRechazo: dto.observacionesRechazo,
                fechaVerificacion: fechaVer,
                supervisorId: this.supervisorId,
            },
        });
    }
    dayOnly(d) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }
    isoDate(d) {
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        const day = String(d.getDate()).padStart(2, "0");
        return `${y}-${m}-${day}`;
    }
}
exports.SupervisorService = SupervisorService;
