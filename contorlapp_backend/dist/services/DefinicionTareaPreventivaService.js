"use strict";
// src/services/DefinicionTareaPreventivaService.ts
Object.defineProperty(exports, "__esModule", { value: true });
exports.DefinicionTareaPreventivaService = void 0;
exports.buildBloqueosPorDescanso = buildBloqueosPorDescanso;
exports.buildBloqueosPorPatronJornada = buildBloqueosPorPatronJornada;
exports.getLimiteMinSemanaPorOperario = getLimiteMinSemanaPorOperario;
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const DefinicionTareaPreventiva_1 = require("../model/DefinicionTareaPreventiva");
const schedulerUtils_1 = require("../utils/schedulerUtils");
const errorFormat_1 = require("../utils/errorFormat");
const elementoHierarchy_1 = require("../utils/elementoHierarchy");
const operarioAvailability_1 = require("../utils/operarioAvailability");
const dayKey = (d) => (0, schedulerUtils_1.ymdLocal)(d);
/* =========================================================
 * DTOs internos (Zod)
 * ======================================================= */
const DividirTareaBorradorDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    tareaId: zod_1.z.number().int().positive(),
    bloques: zod_1.z
        .array(zod_1.z.object({
        fechaInicio: zod_1.z.coerce.date(),
        fechaFin: zod_1.z.coerce.date(),
    }))
        .min(2, "Debe dividirse en al menos 2 bloques"),
});
const EditarBorradorDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    tareaId: zod_1.z.number().int().positive(),
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
    duracionMinutos: zod_1.z.number().int().min(1).optional(),
    operariosIds: zod_1.z.array(zod_1.z.number().int().positive()).optional(),
});
const CrearBloqueBorradorDTO = zod_1.z.object({
    descripcion: zod_1.z.string().min(3),
    fechaInicio: zod_1.z.coerce.date(),
    fechaFin: zod_1.z.coerce.date(),
    ubicacionId: zod_1.z.number().int().positive(),
    elementoId: zod_1.z.number().int().positive(),
    operariosIds: zod_1.z.array(zod_1.z.number().int().positive()).optional(),
    supervisorId: zod_1.z.number().int().positive().nullable().optional(),
    tiempoEstimadoMinutos: zod_1.z.number().positive().optional(),
});
const DividirBloqueDTO = zod_1.z.object({
    fechaInicio1: zod_1.z.coerce.date(),
    fechaFin1: zod_1.z.coerce.date(),
    fechaInicio2: zod_1.z.coerce.date(),
    fechaFin2: zod_1.z.coerce.date(),
});
const EditarBloqueBorradorDTO = zod_1.z.object({
    descripcion: zod_1.z.string().min(3).optional(),
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
    duracionMinutos: zod_1.z.number().int().positive().optional(),
    ubicacionId: zod_1.z.number().int().positive().optional(),
    elementoId: zod_1.z.number().int().positive().optional(),
    operariosIds: zod_1.z.array(zod_1.z.number().int().positive()).optional(),
    supervisorId: zod_1.z.number().int().positive().nullable().optional(),
    tiempoEstimadoMinutos: zod_1.z.number().positive().nullable().optional(),
});
/* =========================================================
 * Service
 * ======================================================= */
class DefinicionTareaPreventivaService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async resolverSupervisorId(supervisorId) {
        const sid = supervisorId.toString();
        const supervisor = await this.prisma.supervisor.findUnique({
            where: { id: sid },
            select: { id: true },
        });
        if (supervisor)
            return sid;
        const usuario = await this.prisma.usuario.findUnique({
            where: { id: sid },
            select: { id: true, rol: true },
        });
        if (!usuario) {
            const e = new Error("El supervisor seleccionado no existe. Actualiza la lista e inténtalo de nuevo.");
            e.status = 400;
            throw e;
        }
        if (usuario.rol !== client_1.Rol.supervisor) {
            const e = new Error("El usuario seleccionado no tiene perfil de supervisor. Verifica la selección.");
            e.status = 400;
            throw e;
        }
        const empresa = await this.prisma.empresa.findFirst({ select: { nit: true } });
        if (!empresa) {
            const e = new Error("No hay una empresa configurada para asociar el supervisor. Si el problema continúa, contacta al área de TI.");
            e.status = 500;
            throw e;
        }
        try {
            await this.prisma.supervisor.create({
                data: {
                    id: sid,
                    empresaId: empresa.nit,
                },
            });
        }
        catch (err) {
            if (!(err instanceof client_1.Prisma.PrismaClientKnownRequestError) || err.code !== "P2002") {
                throw err;
            }
        }
        return sid;
    }
    validarVentanaPublicacion(params) {
        const { anio, mes, diasAnticipacion = 7, ahora = new Date() } = params;
        const inicioPeriodo = new Date(anio, mes - 1, 1, 0, 0, 0, 0);
        const apertura = new Date(inicioPeriodo);
        apertura.setDate(apertura.getDate() - diasAnticipacion);
        if (+ahora < +apertura) {
            const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
            throw new Error(`El cronograma ${anio}-${String(mes).padStart(2, "0")} solo se puede publicar desde ${ymd(apertura)} (7 días antes del inicio del periodo: ${ymd(inicioPeriodo)}).`);
        }
    }
    /* =========================
     * CRUD BÁSICO
     * ======================= */
    async crear(payload) {
        const dto = DefinicionTareaPreventiva_1.CrearDefinicionPreventivaDTO.parse(payload);
        const supervisorIdResuelto = dto.supervisorId != null
            ? await this.resolverSupervisorId(dto.supervisorId)
            : null;
        const duracionMinutosFija = dto.duracionMinutosFija ??
            (dto.duracionHorasFija != null
                ? Math.max(1, Math.round(Number(dto.duracionHorasFija) * 60))
                : null);
        const data = {
            conjunto: { connect: { nit: dto.conjuntoId } },
            ubicacion: { connect: { id: dto.ubicacionId } },
            elemento: { connect: { id: dto.elementoId } },
            descripcion: dto.descripcion,
            frecuencia: dto.frecuencia,
            prioridad: dto.prioridad ?? 2,
            diaSemanaProgramado: dto.diaSemanaProgramado ?? null,
            diaMesProgramado: dto.diaMesProgramado ?? null,
            duracionMinutosFija,
            diasParaCompletar: dto.diasParaCompletar ?? null,
            rendimientoTiempoBase: dto.rendimientoTiempoBase ?? "POR_MINUTO",
            unidadCalculo: dto.unidadCalculo ?? null,
            areaNumerica: dto.areaNumerica != null ? new client_1.Prisma.Decimal(dto.areaNumerica) : null,
            rendimientoBase: dto.rendimientoBase != null
                ? new client_1.Prisma.Decimal(dto.rendimientoBase)
                : null,
            // Insumo principal
            insumoPrincipal: dto.insumoPrincipalId
                ? { connect: { id: dto.insumoPrincipalId } }
                : undefined,
            consumoPrincipalPorUnidad: dto.consumoPrincipalPorUnidad != null
                ? new client_1.Prisma.Decimal(dto.consumoPrincipalPorUnidad)
                : null,
            // JSONs
            insumosPlanJson: dto.insumosPlanJson
                ? dto.insumosPlanJson
                : undefined,
            maquinariaPlanJson: dto.maquinariaPlanJson
                ? dto.maquinariaPlanJson
                : undefined,
            herramientasPlanJson: dto.herramientasPlanJson
                ? dto.herramientasPlanJson
                : undefined,
            // supervisor (relación)
            supervisor: supervisorIdResuelto
                ? { connect: { id: supervisorIdResuelto } }
                : undefined,
            activo: dto.activo ?? true,
        };
        // Operarios: operariosIds > responsableSugeridoId
        if (dto.operariosIds?.length) {
            data.operarios = {
                connect: dto.operariosIds.map((id) => ({ id: id.toString() })),
            };
        }
        else if (dto.responsableSugeridoId != null) {
            data.operarios = {
                connect: { id: dto.responsableSugeridoId.toString() },
            };
        }
        return this.prisma.definicionTareaPreventiva.create({ data });
    }
    async listar(payload) {
        const f = DefinicionTareaPreventiva_1.FiltroDefinicionPreventivaDTO.parse(payload);
        return this.prisma.definicionTareaPreventiva.findMany({
            where: {
                conjuntoId: f.conjuntoId,
                ubicacionId: f.ubicacionId,
                elementoId: f.elementoId,
                frecuencia: f.frecuencia,
                activo: f.activo,
            },
            include: {
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
                operarios: { include: { usuario: true } },
                supervisor: { include: { usuario: true } },
            },
            orderBy: [{ prioridad: "asc" }, { id: "asc" }],
        });
    }
    async listarPorConjunto(conjuntoId) {
        return this.prisma.definicionTareaPreventiva.findMany({
            where: { conjuntoId },
            include: {
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
                operarios: { include: { usuario: true } },
                supervisor: { include: { usuario: true } },
            },
            orderBy: [{ prioridad: "asc" }, { id: "asc" }],
        });
    }
    async actualizar(conjuntoId, id, payload) {
        const dto = DefinicionTareaPreventiva_1.EditarDefinicionPreventivaDTO.parse(payload);
        const def = await this.prisma.definicionTareaPreventiva.findUnique({
            where: { id },
            select: { id: true, conjuntoId: true },
        });
        if (!def || def.conjuntoId !== conjuntoId) {
            throw new Error("Definición no encontrada para este conjunto.");
        }
        // recalcular duración si vienen campos
        const durMinFija = dto.duracionMinutosFija === undefined &&
            dto.duracionHorasFija === undefined
            ? undefined
            : (dto.duracionMinutosFija ??
                (dto.duracionHorasFija != null
                    ? Math.round(Number(dto.duracionHorasFija) * 60)
                    : null));
        const data = {
            descripcion: dto.descripcion,
            frecuencia: dto.frecuencia,
            prioridad: dto.prioridad,
            activo: dto.activo,
            ubicacion: dto.ubicacionId === undefined
                ? undefined
                : { connect: { id: dto.ubicacionId } },
            elemento: dto.elementoId === undefined
                ? undefined
                : { connect: { id: dto.elementoId } },
            unidadCalculo: dto.unidadCalculo ?? undefined,
            areaNumerica: dto.areaNumerica === undefined
                ? undefined
                : dto.areaNumerica === null
                    ? null
                    : new client_1.Prisma.Decimal(dto.areaNumerica),
            rendimientoBase: dto.rendimientoBase === undefined
                ? undefined
                : dto.rendimientoBase === null
                    ? null
                    : new client_1.Prisma.Decimal(dto.rendimientoBase),
            diaSemanaProgramado: dto.diaSemanaProgramado ?? undefined,
            diaMesProgramado: dto.diaMesProgramado ?? undefined,
            duracionMinutosFija: durMinFija,
            diasParaCompletar: dto.diasParaCompletar === undefined
                ? undefined
                : (dto.diasParaCompletar ?? null),
            insumoPrincipal: dto.insumoPrincipalId === undefined
                ? undefined
                : dto.insumoPrincipalId === null
                    ? { disconnect: true }
                    : { connect: { id: dto.insumoPrincipalId } },
            consumoPrincipalPorUnidad: dto.consumoPrincipalPorUnidad === undefined
                ? undefined
                : dto.consumoPrincipalPorUnidad === null
                    ? null
                    : new client_1.Prisma.Decimal(dto.consumoPrincipalPorUnidad),
            insumosPlanJson: dto.insumosPlanJson === undefined
                ? undefined
                : dto.insumosPlanJson === null
                    ? client_1.Prisma.JsonNull
                    : dto.insumosPlanJson,
            maquinariaPlanJson: dto.maquinariaPlanJson === undefined
                ? undefined
                : dto.maquinariaPlanJson === null
                    ? client_1.Prisma.JsonNull
                    : dto.maquinariaPlanJson,
            herramientasPlanJson: dto.herramientasPlanJson === undefined
                ? undefined
                : dto.herramientasPlanJson === null
                    ? client_1.Prisma.JsonNull
                    : dto.herramientasPlanJson,
            supervisor: dto.supervisorId === undefined
                ? undefined
                : dto.supervisorId === null
                    ? { disconnect: true }
                    : {
                        connect: {
                            id: await this.resolverSupervisorId(dto.supervisorId),
                        },
                    },
        };
        // relaciones operarios
        if (dto.operariosIds !== undefined) {
            const operariosIds = dto.operariosIds ?? [];
            data.operarios = {
                set: operariosIds.map((id) => ({ id: id.toString() })),
            };
        }
        else if (dto.responsableSugeridoId !== undefined) {
            const value = dto.responsableSugeridoId;
            data.operarios =
                value === null ? { set: [] } : { set: [{ id: value.toString() }] };
        }
        return this.prisma.definicionTareaPreventiva.update({
            where: { id },
            data,
        });
    }
    async eliminar(conjuntoId, id) {
        const deleted = await this.prisma.definicionTareaPreventiva.deleteMany({
            where: { id, conjuntoId },
        });
        if (deleted.count === 0) {
            throw new Error("Definición no encontrada para este conjunto.");
        }
    }
    /* =========================
     * GENERACIÓN DE CRONOGRAMA
     * ======================= */
    async generarCronograma(payload) {
        const dto = DefinicionTareaPreventiva_1.GenerarCronogramaDTO.parse(payload);
        const tamanoBloqueMinutos = dto.tamanoBloqueMinutos ??
            (dto.tamanoBloqueHoras != null
                ? Math.round(dto.tamanoBloqueHoras * 60)
                : 60);
        const { creadas, novedades } = await this.generarBorradorMensual({
            conjuntoId: dto.conjuntoId,
            periodoAnio: dto.anio,
            periodoMes: dto.mes,
            tamanoBloqueMinutos,
            paisFestivos: "CO",
            incluirPublicadasEnAgenda: true,
            confirmacionesReemplazo: dto.confirmacionesReemplazo,
        });
        return { creadas, novedades };
    }
    /* =========================
     * TAREAS BORRADOR
     * ======================= */
    async dividirTareaBorrador(payload) {
        const { conjuntoId, tareaId, bloques } = DividirTareaBorradorDTO.parse(payload);
        const original = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            include: { operarios: true },
        });
        if (!original || !original.borrador || original.conjuntoId !== conjuntoId) {
            throw new Error("Tarea no encontrada, no es borrador o no pertenece a este conjunto.");
        }
        if (original.tipo !== client_1.TipoTarea.PREVENTIVA) {
            throw new Error("Solo se pueden dividir tareas preventivas en borrador.");
        }
        const originalMin = original.duracionMinutos ?? 0;
        const minutosBloques = bloques.reduce((acc, b) => {
            const diffMin = (+b.fechaFin - +b.fechaInicio) / 60000;
            return acc + diffMin;
        }, 0);
        const minutosBloquesRed = Math.round(minutosBloques);
        if (minutosBloquesRed !== originalMin) {
            throw new Error(`La suma de minutos de los bloques (${minutosBloquesRed} min) no coincide con la duración original (${originalMin} min).`);
        }
        const operariosIds = original.operarios.map((o) => o.id);
        const limiteMinSemana = await getLimiteMinSemanaPorConjunto(this.prisma, conjuntoId);
        await this.prisma.$transaction(async (tx) => {
            for (const opId of operariosIds) {
                for (const b of bloques) {
                    const minSemana = await minutosAsignadosEnSemana(tx, conjuntoId, opId, b.fechaInicio, false);
                    const durBloqueMin = (+b.fechaFin - +b.fechaInicio) / 60000 || 0;
                    if (minSemana + durBloqueMin > limiteMinSemana) {
                        throw new Error(`El operario ${opId} superaría el límite semanal (${limiteMinSemana} min) con este bloque.`);
                    }
                    const haySolape = await existeSolapeParaOperario(tx, {
                        conjuntoId,
                        operarioId: opId,
                        fechaInicio: b.fechaInicio,
                        fechaFin: b.fechaFin,
                        soloBorrador: true,
                        excluirTareaId: tareaId,
                    });
                    if (haySolape) {
                        const nombre = await getOperarioNombre(this.prisma, opId);
                        throw new Error(`Solape de agenda detectado para el operario ${nombre} en uno de los bloques.`);
                    }
                }
            }
            await tx.tarea.delete({ where: { id: tareaId } });
            for (const b of bloques) {
                const duracionMinutos = Math.max(1, Math.round((+b.fechaFin - +b.fechaInicio) / 60000));
                await tx.tarea.create({
                    data: {
                        descripcion: original.descripcion,
                        fechaInicio: b.fechaInicio,
                        fechaFin: b.fechaFin,
                        duracionMinutos,
                        prioridad: original.prioridad ?? 2,
                        estado: original.estado,
                        tipo: original.tipo,
                        frecuencia: original.frecuencia,
                        borrador: true,
                        periodoAnio: b.fechaInicio.getFullYear(),
                        periodoMes: b.fechaInicio.getMonth() + 1,
                        conjuntoId: original.conjuntoId,
                        ubicacionId: original.ubicacionId,
                        elementoId: original.elementoId,
                        supervisorId: original.supervisorId,
                        tiempoEstimadoMinutos: original.tiempoEstimadoMinutos,
                        insumoPrincipalId: original.insumoPrincipalId,
                        consumoPrincipalPorUnidad: original.consumoPrincipalPorUnidad,
                        consumoTotalEstimado: original.consumoTotalEstimado,
                        insumosPlanJson: original.insumosPlanJson == null
                            ? undefined
                            : original.insumosPlanJson,
                        maquinariaPlanJson: original.maquinariaPlanJson == null
                            ? undefined
                            : original.maquinariaPlanJson,
                        herramientasPlanJson: original.herramientasPlanJson == null
                            ? undefined
                            : original
                                .herramientasPlanJson,
                        grupoPlanId: null,
                        bloqueIndex: null,
                        bloquesTotales: null,
                        operarios: operariosIds.length
                            ? { connect: operariosIds.map((id) => ({ id })) }
                            : undefined,
                    },
                });
            }
        });
        return { ok: true, bloques: bloques.length };
    }
    async dividirBloqueBorrador(conjuntoId, tareaId, payload) {
        const dto = DividirBloqueDTO.parse(payload);
        if (dto.fechaFin1 < dto.fechaInicio1) {
            throw new Error("fechaFin1 debe ser >= fechaInicio1");
        }
        if (dto.fechaFin2 < dto.fechaInicio2) {
            throw new Error("fechaFin2 debe ser >= fechaInicio2");
        }
        const original = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            include: { operarios: { select: { id: true } } },
        });
        if (!original ||
            original.conjuntoId !== conjuntoId ||
            !original.borrador ||
            original.tipo !== client_1.TipoTarea.PREVENTIVA) {
            throw new Error("No es un bloque borrador preventivo de este conjunto.");
        }
        const operariosIds = original.operarios.map((o) => o.id);
        const dur1 = Math.max(1, Math.round((+dto.fechaFin1 - +dto.fechaInicio1) / 60000));
        const dur2 = Math.max(1, Math.round((+dto.fechaFin2 - +dto.fechaInicio2) / 60000));
        const limiteMinSemana = await getLimiteMinSemanaPorConjunto(this.prisma, conjuntoId);
        const semanaKey = (d) => inicioSemana(d).toISOString().slice(0, 10);
        const semana1 = semanaKey(dto.fechaInicio1);
        const semana2 = semanaKey(dto.fechaInicio2);
        for (const opId of operariosIds) {
            const extraPorSemana = {};
            extraPorSemana[semana1] = (extraPorSemana[semana1] ?? 0) + dur1;
            extraPorSemana[semana2] = (extraPorSemana[semana2] ?? 0) + dur2;
            for (const [sem, extra] of Object.entries(extraPorSemana)) {
                const ini = inicioSemana(new Date(sem));
                const minSemana = await minutosAsignadosEnSemana(this.prisma, conjuntoId, opId, ini, false);
                if (minSemana + extra > limiteMinSemana) {
                    throw new Error(`Al dividir esta tarea, el operario ${opId} superaría el límite semanal (${limiteMinSemana} min).`);
                }
            }
        }
        for (const opId of operariosIds) {
            const haySolape1 = await existeSolapeParaOperario(this.prisma, {
                conjuntoId,
                operarioId: opId,
                fechaInicio: dto.fechaInicio1,
                fechaFin: dto.fechaFin1,
                soloBorrador: true,
                excluirTareaId: tareaId,
            });
            if (haySolape1) {
                const nombre = await getOperarioNombre(this.prisma, opId);
                throw new Error(`Solape de agenda con operario ${nombre} (primer bloque).`);
            }
            const haySolape2 = await existeSolapeParaOperario(this.prisma, {
                conjuntoId,
                operarioId: opId,
                fechaInicio: dto.fechaInicio2,
                fechaFin: dto.fechaFin2,
                soloBorrador: true,
                excluirTareaId: tareaId,
            });
            if (haySolape2) {
                const nombre = await getOperarioNombre(this.prisma, opId);
                throw new Error(`Solape de agenda con operario ${nombre} (segundo bloque).`);
            }
        }
        return this.prisma.$transaction(async (tx) => {
            await tx.tarea.delete({ where: { id: tareaId } });
            const base = {
                descripcion: original.descripcion,
                estado: client_1.EstadoTarea.ASIGNADA,
                tipo: client_1.TipoTarea.PREVENTIVA,
                frecuencia: original.frecuencia,
                borrador: true,
                prioridad: original.prioridad ?? 2,
                conjuntoId,
                ubicacionId: original.ubicacionId,
                elementoId: original.elementoId,
                supervisorId: original.supervisorId,
                tiempoEstimadoMinutos: original.tiempoEstimadoMinutos,
                insumoPrincipalId: original.insumoPrincipalId,
                consumoPrincipalPorUnidad: original.consumoPrincipalPorUnidad,
                consumoTotalEstimado: original.consumoTotalEstimado,
                insumosPlanJson: original.insumosPlanJson,
                maquinariaPlanJson: original.maquinariaPlanJson,
                herramientasPlanJson: original
                    .herramientasPlanJson,
            };
            const tarea1 = await tx.tarea.create({
                data: {
                    ...base,
                    fechaInicio: dto.fechaInicio1,
                    fechaFin: dto.fechaFin1,
                    duracionMinutos: dur1,
                    periodoAnio: dto.fechaInicio1.getFullYear(),
                    periodoMes: dto.fechaInicio1.getMonth() + 1,
                    grupoPlanId: null,
                    bloqueIndex: null,
                    bloquesTotales: null,
                    operarios: operariosIds.length
                        ? { connect: operariosIds.map((id) => ({ id })) }
                        : undefined,
                },
            });
            const tarea2 = await tx.tarea.create({
                data: {
                    ...base,
                    fechaInicio: dto.fechaInicio2,
                    fechaFin: dto.fechaFin2,
                    duracionMinutos: dur2,
                    periodoAnio: dto.fechaInicio2.getFullYear(),
                    periodoMes: dto.fechaInicio2.getMonth() + 1,
                    grupoPlanId: null,
                    bloqueIndex: null,
                    bloquesTotales: null,
                    operarios: operariosIds.length
                        ? { connect: operariosIds.map((id) => ({ id })) }
                        : undefined,
                },
            });
            return { tarea1, tarea2 };
        });
    }
    async publicarCronograma(params) {
        const { conjuntoId, anio, mes } = params;
        this.validarVentanaPublicacion({ anio, mes, diasAnticipacion: 7 });
        const borradores = await this.prisma.tarea.findMany({
            where: {
                conjuntoId,
                borrador: true,
                periodoAnio: anio,
                periodoMes: mes,
                tipo: client_1.TipoTarea.PREVENTIVA,
            },
            select: {
                id: true,
                fechaInicio: true,
                fechaFin: true,
                maquinariaPlanJson: true,
                grupoPlanId: true,
                descripcion: true,
            },
            orderBy: [{ id: "asc" }],
        });
        if (!borradores.length) {
            return { ok: true, publicadas: 0, reservas: 0 };
        }
        // rango del mes + buffer
        const month0 = mes - 1;
        const inicioMes = new Date(anio, month0, 1, 0, 0, 0, 0);
        const finMes = new Date(anio, month0 + 1, 0, 23, 59, 59, 999);
        const bufferDias = 20;
        const inicioRangoFestivos = new Date(inicioMes);
        inicioRangoFestivos.setDate(inicioRangoFestivos.getDate() - bufferDias);
        const finRangoFestivos = new Date(finMes);
        finRangoFestivos.setDate(finRangoFestivos.getDate() + bufferDias);
        const festivosSet = await (0, schedulerUtils_1.getFestivosSet)({
            prisma: this.prisma,
            pais: "CO",
            inicio: inicioRangoFestivos,
            fin: finRangoFestivos,
        });
        const reservasResp = await this.crearReservasPlanificadasParaTareas({
            conjuntoId,
            tareas: borradores.map((t) => ({
                id: t.id,
                grupoPlanId: t.grupoPlanId ?? null,
                fechaInicio: t.fechaInicio,
                fechaFin: t.fechaFin,
                maquinariaPlanJson: t.maquinariaPlanJson,
                descripcion: t.descripcion,
            })),
            diasEntregaRecogida: new Set([1, 3, 6]), // L, X, S
            excluirTareaIds: [],
            festivosSet,
        });
        await this.prisma.tarea.updateMany({
            where: {
                conjuntoId,
                borrador: true,
                periodoAnio: anio,
                periodoMes: mes,
                tipo: client_1.TipoTarea.PREVENTIVA,
            },
            data: { borrador: false },
        });
        return {
            ok: true,
            publicadas: borradores.length,
            reservas: reservasResp?.creadas ?? 0,
        };
    }
    /**
     * Genera tareas PREVENTIVAS en modo borrador para un conjunto y mes.
     */
    async generarBorradorMensual(params) {
        const { conjuntoId, periodoAnio, periodoMes, tamanoBloqueMinutos = 60, paisFestivos = "CO", incluirPublicadasEnAgenda = true, confirmacionesReemplazo = [], } = params;
        const novedades = [];
        const confirmacionesMap = new Map();
        const keyConfirmacion = (defId, fecha, prioridadSolicitante, prioridadObjetivo) => `${defId}|${fecha}|${prioridadSolicitante}|${prioridadObjetivo}`;
        for (const c of confirmacionesReemplazo) {
            if (!c?.defId || !c?.fecha)
                continue;
            confirmacionesMap.set(keyConfirmacion(Number(c.defId), String(c.fecha), Number(c.prioridadSolicitante ?? 0), Number(c.prioridadObjetivo ?? 0)), {
                aceptar: Boolean(c.aceptar),
                candidataId: c.candidataId != null && Number.isFinite(Number(c.candidataId))
                    ? Number(c.candidataId)
                    : undefined,
            });
        }
        const obtenerConfirmacion = (args) => confirmacionesMap.get(keyConfirmacion(args.defId, args.fecha, args.prioridadSolicitante, args.prioridadObjetivo));
        // 1️⃣ Definiciones activas
        const defs = await this.prisma.definicionTareaPreventiva.findMany({
            where: { conjuntoId, activo: true },
            include: { operarios: true, supervisor: true },
            orderBy: [{ prioridad: "asc" }, { id: "asc" }],
        });
        if (!defs.length)
            return { creadas: 0, novedades };
        // 2️⃣ Horarios del conjunto
        const horarios = await this.prisma.conjuntoHorario.findMany({
            where: { conjuntoId },
        });
        const horariosPorDia = new Map();
        for (const h of horarios) {
            horariosPorDia.set(h.dia, {
                startMin: (0, schedulerUtils_1.toMin)(h.horaApertura),
                endMin: (0, schedulerUtils_1.toMin)(h.horaCierre),
                descansoStartMin: h.descansoInicio
                    ? (0, schedulerUtils_1.toMin)(h.descansoInicio)
                    : undefined,
                descansoEndMin: h.descansoFin ? (0, schedulerUtils_1.toMin)(h.descansoFin) : undefined,
            });
        }
        // 3️⃣ Rango del mes
        const month0 = periodoMes - 1;
        const inicioMes = new Date(periodoAnio, month0, 1, 0, 0, 0, 0);
        const finMes = new Date(periodoAnio, month0 + 1, 0, 23, 59, 59, 999);
        const fechasDelMes = enumerateDays(inicioMes, finMes);
        // 4️⃣ Festivos
        const festivosSet = await (0, schedulerUtils_1.getFestivosSet)({
            prisma: this.prisma,
            pais: paisFestivos,
            inicio: inicioMes,
            fin: finMes,
        });
        const listarCandidatasPorPrioridadDia = async (fechaDia, prioridades) => {
            if (!prioridades.length)
                return [];
            const ini = new Date(fechaDia.getFullYear(), fechaDia.getMonth(), fechaDia.getDate(), 0, 0, 0, 0);
            const fin = new Date(fechaDia.getFullYear(), fechaDia.getMonth(), fechaDia.getDate(), 23, 59, 59, 999);
            const rows = await this.prisma.tarea.findMany({
                where: {
                    conjuntoId,
                    fechaInicio: { lte: fin },
                    fechaFin: { gte: ini },
                    estado: { notIn: ["PENDIENTE_REPROGRAMACION"] },
                    prioridad: { in: prioridades },
                },
                select: { id: true },
                orderBy: [{ prioridad: "desc" }, { fechaInicio: "asc" }, { id: "asc" }],
            });
            return rows.map((r) => r.id);
        };
        // 5️⃣ Limpiar borradores previos
        await this.prisma.tarea.deleteMany({
            where: {
                conjuntoId,
                borrador: true,
                periodoAnio,
                periodoMes,
                tipo: client_1.TipoTarea.PREVENTIVA,
            },
        });
        // ✅ Cache de límite semanal por operario (para no recalcular siempre)
        const limitePorOperario = new Map();
        let creadas = 0;
        // 6️⃣ Loop definiciones (por prioridad asc)
        for (const def of defs) {
            const prioridad = Number(def.prioridad ?? 2);
            const operariosIds = def.operarios.map((o) => o.id);
            // evitar duplicar si ya fue publicada
            const yaPublicadaEstaDef = await this.prisma.tarea.count({
                where: {
                    conjuntoId,
                    periodoAnio,
                    periodoMes,
                    tipo: client_1.TipoTarea.PREVENTIVA,
                    borrador: false,
                    descripcion: def.descripcion,
                    ubicacionId: def.ubicacionId,
                    elementoId: def.elementoId,
                    frecuencia: def.frecuencia,
                },
            });
            if (yaPublicadaEstaDef > 0)
                continue;
            // días según frecuencia
            const diasBase = pickDaysByFrecuencia(fechasDelMes, def);
            // solo días con horario
            const diasValidos = diasBase.filter((d) => horariosPorDia.has(dateToDiaSemana(d)));
            for (const diaBase of diasValidos) {
                const diaProgramable = (0, schedulerUtils_1.findNextValidDay)({
                    start: diaBase,
                    periodoAnio,
                    periodoMes,
                    prioridad,
                    horariosPorDia,
                    festivosSet,
                });
                if (!diaProgramable) {
                    const diaBaseEsFestivo = festivosSet.has(dayKey(diaBase));
                    const diaBaseEsDomingo = dateToDiaSemana(diaBase) === client_1.DiaSemana.DOMINGO;
                    if (diaBaseEsFestivo || diaBaseEsDomingo) {
                        novedades.push({
                            tipo: "FESTIVO_OMITIDO",
                            defId: def.id,
                            descripcion: def.descripcion,
                            prioridad,
                            fecha: dayKey(diaBase),
                            motivo: diaBaseEsDomingo ? "DOMINGO" : "FESTIVO",
                        });
                    }
                    continue;
                }
                // ✅ log: cayó en festivo/domingo y se movió
                const diaBaseEsFestivo = festivosSet.has(dayKey(diaBase));
                const diaBaseEsDomingo = dateToDiaSemana(diaBase) === client_1.DiaSemana.DOMINGO;
                if ((diaBaseEsFestivo || diaBaseEsDomingo) &&
                    dayKey(diaProgramable) !== dayKey(diaBase)) {
                    novedades.push({
                        tipo: "FESTIVO_MOVIDO",
                        defId: def.id,
                        descripcion: def.descripcion,
                        prioridad,
                        fechaOriginal: dayKey(diaBase),
                        fechaNueva: dayKey(diaProgramable),
                    });
                }
                // ✅ Duración REAL
                const minutosEstimados = (0, DefinicionTareaPreventiva_1.calcularMinutosEstimados)({
                    cantidad: def.areaNumerica != null ? Number(def.areaNumerica) : undefined,
                    rendimiento: def.rendimientoBase != null
                        ? Number(def.rendimientoBase)
                        : undefined,
                    duracionMinutosFija: def.duracionMinutosFija ?? undefined,
                    rendimientoTiempoBase: def.rendimientoTiempoBase ?? "POR_HORA",
                }) ??
                    (def.duracionMinutosFija != null
                        ? Number(def.duracionMinutosFija)
                        : null) ??
                    (def.duracionHorasFija != null
                        ? Math.max(1, Math.round(Number(def.duracionHorasFija) * 60))
                        : null) ??
                    null;
                const durMinTotal = minutosEstimados ?? tamanoBloqueMinutos;
                // ✅ diasParaCompletar: divide minutos en N días
                const diasParaCompletar = Math.max(1, Number(def.diasParaCompletar ?? 1));
                const partesMin = (0, schedulerUtils_1.splitMinutes)(durMinTotal, diasParaCompletar);
                // Grupo si multi-día
                const grupoPlanId = partesMin.length > 1
                    ? `BOR-${def.id}-${periodoAnio}-${periodoMes}-${Math.random()
                        .toString(36)
                        .slice(2, 8)}`
                    : null;
                const totalBloquesEsperados = partesMin.length;
                let bloqueIndexCursor = 1;
                // cursor de día para las partes
                let cursorDia = new Date(diaProgramable);
                for (let p = 0; p < partesMin.length; p++) {
                    const durMinParte = partesMin[p];
                    let diaParte = (0, schedulerUtils_1.findNextValidDay)({
                        start: cursorDia,
                        periodoAnio,
                        periodoMes,
                        prioridad,
                        horariosPorDia,
                        festivosSet,
                    });
                    if (!diaParte)
                        break;
                    let agendada = false;
                    let pendienteConfirmacion = null;
                    let diasSinCandidatasP3 = 0;
                    let diasConCandidatasP3SinHueco = 0;
                    const fechasConCandidatasP3 = new Set();
                    let diasConCandidatasP3ParaP2 = 0;
                    let diasSinCandidatasP3ParaP2 = 0;
                    let intentosConfirmadosP2ConP3Fallidos = 0;
                    // Regla: para P1 y P2, buscar hueco/reemplazo en ventana movil
                    // de 7 dias (dia actual + 6), priorizando el dia mas cercano.
                    const finSemanaBusqueda = new Date(diaParte);
                    finSemanaBusqueda.setDate(finSemanaBusqueda.getDate() + 6);
                    finSemanaBusqueda.setHours(23, 59, 59, 999);
                    for (let guardDia = 0; guardDia < 8; guardDia++) {
                        if (!diaParte)
                            break;
                        if ((prioridad === 1 || prioridad === 2) && +diaParte > +finSemanaBusqueda)
                            break;
                        // Nunca crear bloques fuera del periodo solicitado.
                        if (diaParte.getFullYear() !== periodoAnio ||
                            diaParte.getMonth() + 1 !== periodoMes) {
                            diaParte = null;
                            break;
                        }
                        const diaParteKey = dayKey(diaParte);
                        const esFestivo = festivosSet.has(diaParteKey);
                        const disponibilidadOperarios = operariosIds.length
                            ? await (0, operarioAvailability_1.validarOperariosDisponiblesEnFecha)({
                                prisma: this.prisma,
                                fecha: diaParte,
                                operariosIds,
                            })
                            : { ok: true, noDisponibles: [] };
                        if (esFestivo || !disponibilidadOperarios.ok) {
                            if (prioridad === 1 || prioridad === 2) {
                                diaParte = (0, schedulerUtils_1.siguienteDiaHabil)({
                                    fecha: diaParte,
                                    festivosSet,
                                    horariosPorDia,
                                });
                                continue;
                            }
                            break;
                        }
                        const horario = horariosPorDia.get(dateToDiaSemana(diaParte));
                        if (!horario) {
                            diaParte = (0, schedulerUtils_1.siguienteDiaHabil)({
                                fecha: diaParte,
                                festivosSet,
                                horariosPorDia,
                            });
                            continue;
                        }
                        // ✅ 1) Descanso
                        const bloqueosDescanso = buildBloqueosPorDescanso(horario);
                        // ✅ 2) Patrón jornada (bloqueos por operario)
                        const bloqueosPatron = await buildBloqueosPorPatronJornada({
                            prisma: this.prisma,
                            fechaDia: diaParte,
                            horarioDia: horario,
                            operariosIds,
                        });
                        // ✅ 3) Bloqueos totales
                        const bloqueos = [...bloqueosDescanso, ...bloqueosPatron];
                        // agenda por operarios => ocupados global merged
                        let ocupadosGlobal = [];
                        if (operariosIds.length) {
                            const agenda = await (0, schedulerUtils_1.buildAgendaPorOperarioDia)({
                                prisma: this.prisma,
                                conjuntoId,
                                fechaDia: diaParte,
                                operariosIds,
                                incluirBorrador: true,
                                bloqueosGlobales: bloqueos,
                                excluirEstados: ["PENDIENTE_REPROGRAMACION"],
                            });
                            const all = [];
                            for (const opId of Object.keys(agenda))
                                all.push(...agenda[opId]);
                            ocupadosGlobal = (0, schedulerUtils_1.mergeIntervalos)(all);
                        }
                        else {
                            ocupadosGlobal = (0, schedulerUtils_1.mergeIntervalos)(bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })));
                        }
                        // buscar hueco
                        const bloquesFound = (0, schedulerUtils_1.buscarHuecoDiaConSplitEarliest)({
                            startMin: horario.startMin,
                            endMin: horario.endMin,
                            durMin: durMinParte,
                            ocupados: ocupadosGlobal,
                            bloqueos,
                            desiredStartMin: horario.startMin,
                            maxBloques: 2,
                        });
                        if (bloquesFound) {
                            // ✅ validar límite semanal (POR OPERARIO)
                            let pasaLimite = true;
                            for (const opId of operariosIds) {
                                // cache límite por operario
                                let limiteOp = limitePorOperario.get(opId);
                                if (limiteOp == null) {
                                    limiteOp = await getLimiteMinSemanaPorOperario({
                                        prisma: this.prisma,
                                        conjuntoId,
                                        operarioId: opId,
                                        horariosPorDia: horariosPorDia,
                                    });
                                    limitePorOperario.set(opId, limiteOp);
                                }
                                const minSemana = await minutosAsignadosEnSemana(this.prisma, conjuntoId, opId, (0, schedulerUtils_1.toDateAtMin)(diaParte, bloquesFound[0].i), incluirPublicadasEnAgenda);
                                if (minSemana + durMinParte > limiteOp) {
                                    pasaLimite = false;
                                    break;
                                }
                            }
                            if (!pasaLimite) {
                                if (prioridad === 1 || prioridad === 2) {
                                    diaParte = (0, schedulerUtils_1.siguienteDiaHabil)({
                                        fecha: diaParte,
                                        festivosSet,
                                        horariosPorDia,
                                    });
                                    continue;
                                }
                                break;
                            }
                            // ✅ crear tareas
                            for (const b of bloquesFound) {
                                const fechaInicio = (0, schedulerUtils_1.toDateAtMin)(diaParte, b.i);
                                const fechaFin = (0, schedulerUtils_1.toDateAtMin)(diaParte, b.f);
                                await this.prisma.tarea.create({
                                    data: {
                                        descripcion: def.descripcion,
                                        fechaInicio,
                                        fechaFin,
                                        duracionMinutos: Math.max(1, b.f - b.i),
                                        tipo: client_1.TipoTarea.PREVENTIVA,
                                        prioridad,
                                        estado: client_1.EstadoTarea.ASIGNADA,
                                        frecuencia: def.frecuencia,
                                        borrador: true,
                                        periodoAnio,
                                        periodoMes,
                                        grupoPlanId,
                                        bloqueIndex: grupoPlanId ? bloqueIndexCursor : null,
                                        bloquesTotales: grupoPlanId ? totalBloquesEsperados : null,
                                        ubicacionId: def.ubicacionId,
                                        elementoId: def.elementoId,
                                        conjuntoId,
                                        supervisorId: def.supervisorId ?? null,
                                        insumosPlanJson: def.insumosPlanJson
                                            ? def.insumosPlanJson
                                            : undefined,
                                        maquinariaPlanJson: def.maquinariaPlanJson
                                            ? def.maquinariaPlanJson
                                            : undefined,
                                        herramientasPlanJson: def.herramientasPlanJson
                                            ? def
                                                .herramientasPlanJson
                                            : undefined,
                                        operarios: operariosIds.length
                                            ? { connect: operariosIds.map((id) => ({ id })) }
                                            : undefined,
                                    },
                                });
                                creadas++;
                                if (grupoPlanId)
                                    bloqueIndexCursor++;
                            }
                            agendada = true;
                            break;
                        }
                        // ❌ No hubo hueco
                        if (prioridad === 1 || prioridad === 2) {
                            const payload = {
                                descripcion: def.descripcion,
                                tipo: client_1.TipoTarea.PREVENTIVA,
                                frecuencia: def.frecuencia ?? null,
                                prioridad,
                                supervisorId: def.supervisorId
                                    ? def.supervisorId.toString()
                                    : null,
                                ubicacionId: def.ubicacionId,
                                elementoId: def.elementoId,
                                conjuntoId,
                                borrador: true,
                                periodoAnio,
                                periodoMes,
                                insumosPlanJson: def.insumosPlanJson ?? undefined,
                                maquinariaPlanJson: def.maquinariaPlanJson ?? undefined,
                                herramientasPlanJson: def.herramientasPlanJson ?? undefined,
                                operariosIds,
                                grupoPlanId,
                                bloqueIndexBase: grupoPlanId ? bloqueIndexCursor : undefined,
                                bloquesTotalesOverride: grupoPlanId
                                    ? totalBloquesEsperados
                                    : undefined,
                                marcarComoReprogramada: false,
                            };
                            const fechaIntento = dayKey(diaParte);
                            // P1: auto reemplaza P3; P2 solo por confirmacion del usuario.
                            if (prioridad === 1) {
                                const repAutoP3 = await (0, schedulerUtils_1.intentarReemplazoPorPrioridadBaja)({
                                    prisma: this.prisma,
                                    conjuntoId,
                                    fechaDia: diaParte,
                                    startMin: horario.startMin,
                                    endMin: horario.endMin,
                                    bloqueos,
                                    durMin: durMinParte,
                                    payload,
                                    prioridadesCandidatas: [3],
                                    incluirBorradorEnAgenda: true,
                                    incluirPublicadasEnAgenda,
                                    onEvent: (ev) => {
                                        if (ev.tipo === "REEMPLAZO") {
                                            if (ev.reprogramadasIds.length) {
                                                novedades.push({
                                                    tipo: "REEMPLAZO_PRIORIDAD",
                                                    defId: def.id,
                                                    descripcion: def.descripcion,
                                                    prioridad,
                                                    fecha: dayKey(diaParte),
                                                    nuevaTareaIds: ev.nuevaTareaIds,
                                                    reprogramadasIds: ev.reprogramadasIds,
                                                });
                                            }
                                        }
                                        else if (ev.tipo === "SIN_CANDIDATAS") {
                                            diasSinCandidatasP3++;
                                        }
                                        else if (ev.tipo === "SIN_HUECO") {
                                            diasConCandidatasP3SinHueco++;
                                            fechasConCandidatasP3.add(fechaIntento);
                                        }
                                    },
                                });
                                if (repAutoP3.ok) {
                                    creadas += repAutoP3.nuevaTareaIds.length;
                                    if (grupoPlanId)
                                        bloqueIndexCursor += repAutoP3.nuevaTareaIds.length;
                                    agendada = true;
                                    break;
                                }
                                const candidatasP2 = await listarCandidatasPorPrioridadDia(diaParte, [2]);
                                const confirmP2 = obtenerConfirmacion({
                                    defId: def.id,
                                    fecha: fechaIntento,
                                    prioridadSolicitante: 1,
                                    prioridadObjetivo: 2,
                                });
                                if (confirmP2?.aceptar === true && candidatasP2.length) {
                                    const candidatasPreferidas = confirmP2.candidataId
                                        ? [confirmP2.candidataId]
                                        : candidatasP2;
                                    const repConfirmadoP2 = await (0, schedulerUtils_1.intentarReemplazoPorPrioridadBaja)({
                                        prisma: this.prisma,
                                        conjuntoId,
                                        fechaDia: diaParte,
                                        startMin: horario.startMin,
                                        endMin: horario.endMin,
                                        bloqueos,
                                        durMin: durMinParte,
                                        payload,
                                        prioridadesCandidatas: [2],
                                        candidatasIdsPreferidas: candidatasPreferidas,
                                        incluirBorradorEnAgenda: true,
                                        incluirPublicadasEnAgenda,
                                        onEvent: (ev) => {
                                            if (ev.tipo === "REEMPLAZO" &&
                                                ev.reprogramadasIds.length) {
                                                novedades.push({
                                                    tipo: "REEMPLAZO_PRIORIDAD",
                                                    defId: def.id,
                                                    descripcion: def.descripcion,
                                                    prioridad,
                                                    fecha: dayKey(diaParte),
                                                    nuevaTareaIds: ev.nuevaTareaIds,
                                                    reprogramadasIds: ev.reprogramadasIds,
                                                    mensaje: "Reemplazo confirmado por usuario sobre prioridad 2.",
                                                });
                                            }
                                        },
                                    });
                                    if (repConfirmadoP2.ok) {
                                        creadas += repConfirmadoP2.nuevaTareaIds.length;
                                        if (grupoPlanId)
                                            bloqueIndexCursor += repConfirmadoP2.nuevaTareaIds.length;
                                        agendada = true;
                                        break;
                                    }
                                }
                                else if (confirmP2 == null && candidatasP2.length) {
                                    pendienteConfirmacion ?? (pendienteConfirmacion = {
                                        fecha: fechaIntento,
                                        prioridadObjetivo: 2,
                                        candidatasIds: candidatasP2,
                                    });
                                }
                                diaParte = (0, schedulerUtils_1.siguienteDiaHabil)({
                                    fecha: diaParte,
                                    festivosSet,
                                    horariosPorDia,
                                });
                                continue;
                            }
                            // P2: no reemplaza automatico; sugiere reemplazo de P3 con confirmacion.
                            const candidatasP3 = await listarCandidatasPorPrioridadDia(diaParte, [3]);
                            if (candidatasP3.length)
                                diasConCandidatasP3ParaP2++;
                            else
                                diasSinCandidatasP3ParaP2++;
                            const confirmP3 = obtenerConfirmacion({
                                defId: def.id,
                                fecha: fechaIntento,
                                prioridadSolicitante: 2,
                                prioridadObjetivo: 3,
                            });
                            if (confirmP3?.aceptar === true && candidatasP3.length) {
                                const candidatasPreferidas = confirmP3.candidataId
                                    ? [confirmP3.candidataId]
                                    : candidatasP3;
                                const repConfirmadoP3 = await (0, schedulerUtils_1.intentarReemplazoPorPrioridadBaja)({
                                    prisma: this.prisma,
                                    conjuntoId,
                                    fechaDia: diaParte,
                                    startMin: horario.startMin,
                                    endMin: horario.endMin,
                                    bloqueos,
                                    durMin: durMinParte,
                                    payload,
                                    prioridadesCandidatas: [3],
                                    candidatasIdsPreferidas: candidatasPreferidas,
                                    incluirBorradorEnAgenda: true,
                                    incluirPublicadasEnAgenda,
                                    onEvent: (ev) => {
                                        if (ev.tipo === "REEMPLAZO" &&
                                            ev.reprogramadasIds.length) {
                                            novedades.push({
                                                tipo: "REEMPLAZO_PRIORIDAD",
                                                defId: def.id,
                                                descripcion: def.descripcion,
                                                prioridad,
                                                fecha: dayKey(diaParte),
                                                nuevaTareaIds: ev.nuevaTareaIds,
                                                reprogramadasIds: ev.reprogramadasIds,
                                                mensaje: "Reemplazo confirmado por usuario sobre prioridad 3.",
                                            });
                                        }
                                    },
                                });
                                if (repConfirmadoP3.ok) {
                                    creadas += repConfirmadoP3.nuevaTareaIds.length;
                                    if (grupoPlanId)
                                        bloqueIndexCursor += repConfirmadoP3.nuevaTareaIds.length;
                                    agendada = true;
                                    break;
                                }
                                intentosConfirmadosP2ConP3Fallidos++;
                            }
                            else if (confirmP3 == null && candidatasP3.length) {
                                pendienteConfirmacion ?? (pendienteConfirmacion = {
                                    fecha: fechaIntento,
                                    prioridadObjetivo: 3,
                                    candidatasIds: candidatasP3,
                                });
                            }
                            diaParte = (0, schedulerUtils_1.siguienteDiaHabil)({
                                fecha: diaParte,
                                festivosSet,
                                horariosPorDia,
                            });
                            continue;
                        }
                        // prioridad 3: si no cabe, se omite
                        break;
                    }
                    if (!agendada && (prioridad === 1 || prioridad === 2)) {
                        if (pendienteConfirmacion != null) {
                            const p3Contexto = prioridad === 1 && diasConCandidatasP3SinHueco > 0
                                ? ` Se evaluaron candidatas P3 en ${diasConCandidatasP3SinHueco} dia(s), pero no liberaron hueco.`
                                : "";
                            const objetivo = pendienteConfirmacion.prioridadObjetivo;
                            const msgObjetivo = objetivo === 2
                                ? "Hay opcion de reemplazo con prioridad 2 y requiere confirmacion."
                                : "Hay opcion de reemplazo con prioridad 3 y requiere confirmacion.";
                            novedades.push({
                                tipo: "REQUIERE_CONFIRMACION_REEMPLAZO",
                                defId: def.id,
                                descripcion: def.descripcion,
                                prioridad,
                                fecha: pendienteConfirmacion.fecha,
                                prioridadObjetivo: objetivo,
                                candidatasIds: pendienteConfirmacion.candidatasIds,
                                mensaje: `No se encontro hueco ni reemplazo automatico en la ventana de 7 dias.${p3Contexto} ${msgObjetivo}`,
                            });
                        }
                        else if (prioridad === 1 && diasConCandidatasP3SinHueco > 0) {
                            const fechas = Array.from(fechasConCandidatasP3).sort();
                            const fechasTxt = fechas.length > 0
                                ? ` Fechas evaluadas: ${fechas.slice(0, 4).join(", ")}${fechas.length > 4 ? ` (+${fechas.length - 4} mas)` : ""}.`
                                : "";
                            novedades.push({
                                tipo: "SIN_HUECO",
                                defId: def.id,
                                descripcion: def.descripcion,
                                prioridad,
                                fecha: dayKey(diaParte ?? cursorDia),
                                mensaje: `Se encontraron candidatas P3 en ${diasConCandidatasP3SinHueco} dia(s), pero ninguna libero hueco para ubicar la tarea dentro de la ventana de 7 dias.${fechasTxt}`,
                            });
                        }
                        else if (prioridad === 1) {
                            novedades.push({
                                tipo: "SIN_CANDIDATAS",
                                defId: def.id,
                                descripcion: def.descripcion,
                                prioridad,
                                fecha: dayKey(diaParte ?? cursorDia),
                                mensaje: `No se encontraron tareas candidatas P3 para reemplazo en la ventana de 7 dias (${diasSinCandidatasP3} dia(s) evaluados sin candidatas).`,
                            });
                        }
                        else if (diasConCandidatasP3ParaP2 > 0 ||
                            intentosConfirmadosP2ConP3Fallidos > 0) {
                            novedades.push({
                                tipo: "SIN_HUECO",
                                defId: def.id,
                                descripcion: def.descripcion,
                                prioridad,
                                fecha: dayKey(diaParte ?? cursorDia),
                                mensaje: `Se encontraron candidatas P3 para reemplazo en ${diasConCandidatasP3ParaP2} dia(s), pero no se logro agendar la tarea en la ventana de 7 dias.`,
                            });
                        }
                        else {
                            novedades.push({
                                tipo: "SIN_CANDIDATAS",
                                defId: def.id,
                                descripcion: def.descripcion,
                                prioridad,
                                fecha: dayKey(diaParte ?? cursorDia),
                                mensaje: `No se encontraron candidatas P3 para reemplazo de esta tarea de prioridad 2 en la ventana de 7 dias (${diasSinCandidatasP3ParaP2} dia(s) evaluados).`,
                            });
                        }
                    }
                    // mover cursor al siguiente día (para la siguiente parte)
                    cursorDia = new Date(diaParte ?? cursorDia);
                    cursorDia.setDate(cursorDia.getDate() + 1);
                    if (!agendada)
                        break;
                }
            }
        }
        return { creadas, novedades };
    }
    async editarTareaBorrador(payload) {
        const dto = EditarBorradorDTO.parse(payload);
        const t = await this.prisma.tarea.findUnique({
            where: { id: dto.tareaId },
            select: { id: true, borrador: true, conjuntoId: true },
        });
        if (!t || !t.borrador || t.conjuntoId !== dto.conjuntoId) {
            throw new Error("Tarea no existe, no es borrador o no pertenece a este conjunto.");
        }
        if (dto.fechaInicio && dto.fechaFin && dto.fechaFin < dto.fechaInicio) {
            throw new Error("fechaFin debe ser >= fechaInicio");
        }
        return this.prisma.tarea.update({
            where: { id: dto.tareaId },
            data: {
                fechaInicio: dto.fechaInicio ?? undefined,
                fechaFin: dto.fechaFin ?? undefined,
                duracionMinutos: dto.duracionMinutos ?? undefined,
                operarios: dto.operariosIds !== undefined
                    ? { set: dto.operariosIds.map((id) => ({ id: id.toString() })) }
                    : undefined,
            },
            include: { operarios: { select: { id: true } } },
        });
    }
    async crearBloqueBorrador(conjuntoId, payload) {
        const dto = CrearBloqueBorradorDTO.parse(payload);
        if (dto.fechaFin < dto.fechaInicio)
            throw new Error("fechaFin >= fechaInicio");
        const inicioEsFestivo = await (0, schedulerUtils_1.isFestivoDate)({
            prisma: this.prisma,
            fecha: dto.fechaInicio,
            pais: "CO",
        });
        if (inicioEsFestivo) {
            throw new Error("No se permite programar tareas preventivas en festivos.");
        }
        const disponibilidad = await (0, operarioAvailability_1.validarOperariosDisponiblesEnFecha)({
            prisma: this.prisma,
            fecha: dto.fechaInicio,
            operariosIds: (dto.operariosIds ?? []).map((id) => id.toString()),
        });
        if (!disponibilidad.ok) {
            throw new Error(`Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`);
        }
        if (dto.operariosIds?.length) {
            for (const opId of dto.operariosIds) {
                const choque = await this.prisma.tarea.findFirst({
                    where: {
                        conjuntoId,
                        borrador: true,
                        tipo: client_1.TipoTarea.PREVENTIVA,
                        fechaInicio: { lt: dto.fechaFin },
                        fechaFin: { gt: dto.fechaInicio },
                        operarios: { some: { id: opId.toString() } },
                    },
                    select: { id: true },
                });
                if (choque) {
                    const nombre = await getOperarioNombre(this.prisma, opId);
                    throw new Error(`Solape de agenda con ${nombre}`);
                }
            }
        }
        const anio = dto.fechaInicio.getFullYear();
        const mes = dto.fechaInicio.getMonth() + 1;
        return this.prisma.tarea.create({
            data: {
                descripcion: dto.descripcion,
                fechaInicio: dto.fechaInicio,
                fechaFin: dto.fechaFin,
                duracionMinutos: Math.max(1, Math.round((+dto.fechaFin - +dto.fechaInicio) / 60000)),
                estado: client_1.EstadoTarea.ASIGNADA,
                tipo: client_1.TipoTarea.PREVENTIVA,
                frecuencia: null,
                borrador: true,
                periodoAnio: anio,
                periodoMes: mes,
                grupoPlanId: null,
                ubicacionId: dto.ubicacionId,
                elementoId: dto.elementoId,
                conjuntoId,
                supervisorId: dto.supervisorId == null ? null : dto.supervisorId.toString(),
                tiempoEstimadoMinutos: dto.tiempoEstimadoMinutos === undefined
                    ? null
                    : Math.max(0, Math.round(dto.tiempoEstimadoMinutos)),
                operarios: dto.operariosIds?.length
                    ? { connect: dto.operariosIds.map((id) => ({ id: id.toString() })) }
                    : undefined,
            },
        });
    }
    async editarBloqueBorrador(conjuntoId, tareaId, payload) {
        const dto = EditarBloqueBorradorDTO.parse(payload);
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: { id: true, conjuntoId: true, borrador: true, tipo: true },
        });
        if (!tarea ||
            tarea.conjuntoId !== conjuntoId ||
            !tarea.borrador ||
            tarea.tipo !== client_1.TipoTarea.PREVENTIVA) {
            throw new Error("No es un bloque borrador preventivo de este conjunto.");
        }
        let operariosIdsFinal = [];
        if (dto.operariosIds) {
            operariosIdsFinal = dto.operariosIds.map((id) => id.toString());
        }
        else {
            const actuales = await this.prisma.tarea.findUnique({
                where: { id: tareaId },
                select: { operarios: { select: { id: true } } },
            });
            operariosIdsFinal = actuales?.operarios.map((o) => o.id) ?? [];
        }
        const fechaInicio = dto.fechaInicio ?? undefined;
        const fechaFin = dto.fechaFin ?? undefined;
        if (fechaInicio) {
            const inicioEsFestivo = await (0, schedulerUtils_1.isFestivoDate)({
                prisma: this.prisma,
                fecha: fechaInicio,
                pais: "CO",
            });
            if (inicioEsFestivo) {
                throw new Error("No se permite programar tareas preventivas en festivos.");
            }
            if (operariosIdsFinal.length) {
                const disponibilidad = await (0, operarioAvailability_1.validarOperariosDisponiblesEnFecha)({
                    prisma: this.prisma,
                    fecha: fechaInicio,
                    operariosIds: operariosIdsFinal.map(String),
                });
                if (!disponibilidad.ok) {
                    throw new Error(`Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`);
                }
            }
        }
        if (fechaInicio && fechaFin && operariosIdsFinal.length) {
            for (const opId of operariosIdsFinal) {
                const haySolape = await existeSolapeParaOperario(this.prisma, {
                    conjuntoId,
                    operarioId: opId,
                    fechaInicio,
                    fechaFin,
                    soloBorrador: true,
                    excluirTareaId: tareaId,
                });
                if (haySolape) {
                    const nombre = await getOperarioNombre(this.prisma, opId);
                    throw new Error(`Solape de agenda con operario ${nombre}`);
                }
            }
        }
        return this.prisma.tarea.update({
            where: { id: tareaId },
            data: {
                descripcion: dto.descripcion ?? undefined,
                fechaInicio,
                fechaFin,
                duracionMinutos: dto.duracionMinutos ??
                    (fechaInicio && fechaFin
                        ? Math.max(1, Math.round((+fechaFin - +fechaInicio) / 60000))
                        : undefined),
                ubicacionId: dto.ubicacionId ?? undefined,
                elementoId: dto.elementoId ?? undefined,
                supervisorId: dto.supervisorId === undefined
                    ? undefined
                    : dto.supervisorId === null
                        ? null
                        : dto.supervisorId.toString(),
                tiempoEstimadoMinutos: dto.tiempoEstimadoMinutos === undefined
                    ? undefined
                    : dto.tiempoEstimadoMinutos === null
                        ? null
                        : Math.max(0, Math.round(dto.tiempoEstimadoMinutos)),
                operarios: dto.operariosIds === undefined
                    ? undefined
                    : { set: dto.operariosIds.map((id) => ({ id: id.toString() })) },
            },
        });
    }
    /* =========================
     * MAQUINARIA DISPONIBLE
     * ======================= */
    async listarMaquinariaDisponible(params) {
        const { conjuntoId, fechaInicioUso, fechaFinUso, excluirTareaId } = params;
        if (!(fechaInicioUso instanceof Date) || isNaN(+fechaInicioUso)) {
            return { ok: false, reason: "FECHA_INICIO_INVALIDA" };
        }
        if (!(fechaFinUso instanceof Date) || isNaN(+fechaFinUso)) {
            return { ok: false, reason: "FECHA_FIN_INVALIDA" };
        }
        if (+fechaFinUso < +fechaInicioUso) {
            return { ok: false, reason: "RANGO_INVERTIDO" };
        }
        const diasEntregaRecogida = new Set([1, 3, 6]); // Lunes, Miércoles, Sábado
        const { iniReserva, finReserva, entregaDia, recogidaDia } = this.calcularRangoReserva({
            fechaInicioUso,
            fechaFinUso,
            diasEntregaRecogida,
        });
        const propias = await this.prisma.maquinaria.findMany({
            where: {
                propietarioTipo: "CONJUNTO",
                conjuntoPropietarioId: conjuntoId,
                estado: "OPERATIVA",
            },
            select: { id: true, nombre: true, tipo: true, marca: true, estado: true },
        });
        const empresa = await this.prisma.maquinaria.findMany({
            where: { propietarioTipo: "EMPRESA", estado: "OPERATIVA" },
            select: {
                id: true,
                nombre: true,
                tipo: true,
                marca: true,
                estado: true,
                empresaId: true,
            },
        });
        const idsInteres = Array.from(new Set([...propias.map((m) => m.id), ...empresa.map((m) => m.id)]));
        if (!idsInteres.length) {
            return {
                ok: true,
                rango: { entregaDia, recogidaDia, iniReserva, finReserva },
                propiasDisponibles: [],
                empresaDisponibles: [],
                ocupadas: [],
            };
        }
        const overlaps = (aIni, aFin, bIni, bFin) => aIni < bFin && bIni < aFin;
        const OPEN_END_FAR_FUTURE = new Date(2099, 11, 31, 23, 59, 59, 999);
        const ocupadasReservadas = await this.prisma.usoMaquinaria.findMany({
            where: {
                maquinariaId: { in: idsInteres },
                ...(excluirTareaId != null ? { tareaId: { not: excluirTareaId } } : {}),
                fechaInicio: { lt: finReserva },
                OR: [{ fechaFin: null }, { fechaFin: { gt: iniReserva } }],
            },
            select: {
                id: true,
                maquinariaId: true,
                tareaId: true,
                fechaInicio: true,
                fechaFin: true,
                tarea: {
                    select: {
                        id: true,
                        conjuntoId: true,
                        descripcion: true,
                        fechaInicio: true,
                        fechaFin: true,
                        borrador: true,
                    },
                },
            },
        });
        const getMaqIds = (json) => {
            if (!Array.isArray(json))
                return [];
            return json
                .map((x) => Number(x?.maquinariaId))
                .filter((n) => Number.isFinite(n) && n > 0);
        };
        const idsInteresSet = new Set(idsInteres);
        const bufferDiasBorrador = 4; // cubre corrimiento de entrega/recogida (L/X/S)
        const inicioBusquedaBorrador = new Date(iniReserva);
        inicioBusquedaBorrador.setDate(inicioBusquedaBorrador.getDate() - bufferDiasBorrador);
        const finBusquedaBorrador = new Date(finReserva);
        finBusquedaBorrador.setDate(finBusquedaBorrador.getDate() + bufferDiasBorrador);
        const borradores = await this.prisma.tarea.findMany({
            where: {
                borrador: true,
                tipo: client_1.TipoTarea.PREVENTIVA,
                fechaInicio: { lt: finBusquedaBorrador },
                fechaFin: { gt: inicioBusquedaBorrador },
                ...(excluirTareaId != null ? { id: { not: excluirTareaId } } : {}),
            },
            select: {
                id: true,
                conjuntoId: true,
                descripcion: true,
                fechaInicio: true,
                fechaFin: true,
                grupoPlanId: true,
                maquinariaPlanJson: true,
            },
            orderBy: [{ id: "asc" }],
        });
        const gruposBorrador = new Map();
        for (const t of borradores) {
            const maqIds = Array.from(new Set(getMaqIds(t.maquinariaPlanJson).filter((id) => idsInteresSet.has(id))));
            if (!maqIds.length)
                continue;
            const key = t.grupoPlanId ? `G:${t.grupoPlanId}` : `T:${t.id}`;
            const g = gruposBorrador.get(key);
            if (!g) {
                gruposBorrador.set(key, {
                    key,
                    conjuntoId: t.conjuntoId ?? null,
                    descripcion: t.descripcion ?? null,
                    tareaIdRepresentante: t.id,
                    maqIds,
                    usoIni: t.fechaInicio,
                    usoFin: t.fechaFin,
                });
            }
            else {
                g.maqIds = Array.from(new Set(g.maqIds.concat(maqIds)));
                if (+t.fechaInicio < +g.usoIni)
                    g.usoIni = t.fechaInicio;
                if (+t.fechaFin > +g.usoFin)
                    g.usoFin = t.fechaFin;
                if (t.id < g.tareaIdRepresentante) {
                    g.tareaIdRepresentante = t.id;
                    g.descripcion = t.descripcion ?? g.descripcion;
                    g.conjuntoId = t.conjuntoId ?? g.conjuntoId;
                }
            }
        }
        const ocupadasBorrador = [];
        for (const g of gruposBorrador.values()) {
            const rangoBorrador = this.calcularRangoReserva({
                fechaInicioUso: g.usoIni,
                fechaFinUso: g.usoFin,
                diasEntregaRecogida,
            });
            if (!overlaps(iniReserva, finReserva, rangoBorrador.iniReserva, rangoBorrador.finReserva)) {
                continue;
            }
            const desc = (g.descripcion ?? "Preventiva en borrador").trim();
            for (const maquinariaId of g.maqIds) {
                ocupadasBorrador.push({
                    maquinariaId,
                    ini: rangoBorrador.iniReserva,
                    fin: rangoBorrador.finReserva,
                    tareaId: g.tareaIdRepresentante,
                    conjuntoId: g.conjuntoId ?? null,
                    descripcion: `[BORRADOR] ${desc}`,
                    fuente: "BORRADOR_PREVENTIVA",
                });
            }
        }
        const ocupadasDetalle = [
            ...ocupadasReservadas.map((o) => ({
                maquinariaId: o.maquinariaId,
                ini: o.fechaInicio,
                fin: o.fechaFin ?? OPEN_END_FAR_FUTURE,
                tareaId: o.tareaId,
                conjuntoId: o.tarea?.conjuntoId ?? null,
                descripcion: o.tarea?.borrador
                    ? `[BORRADOR] ${(o.tarea?.descripcion ?? "Tarea en borrador").trim()}`
                    : o.tarea?.descripcion ?? null,
                fuente: "RESERVA_PUBLICADA",
            })),
            ...ocupadasBorrador,
        ];
        const ocupadasSet = new Set(ocupadasDetalle.map((o) => o.maquinariaId));
        const propiasDisponibles = propias
            .filter((m) => !ocupadasSet.has(m.id))
            .map((m) => ({
            id: m.id,
            nombre: m.nombre,
            tipo: m.tipo,
            marca: m.marca,
            origen: "CONJUNTO",
        }));
        const empresaDisponibles = empresa
            .filter((m) => !ocupadasSet.has(m.id))
            .map((m) => ({
            id: m.id,
            nombre: m.nombre,
            tipo: m.tipo,
            marca: m.marca,
            origen: "EMPRESA",
            empresaId: m.empresaId,
        }));
        return {
            ok: true,
            rango: { entregaDia, recogidaDia, iniReserva, finReserva },
            propiasDisponibles,
            empresaDisponibles,
            ocupadas: ocupadasDetalle,
        };
    }
    async eliminarBloqueBorrador(conjuntoId, tareaId) {
        const res = await this.prisma.tarea.deleteMany({
            where: {
                id: tareaId,
                conjuntoId,
                borrador: true,
                tipo: client_1.TipoTarea.PREVENTIVA,
            },
        });
        if (res.count === 0) {
            throw new Error("Bloque no encontrado o no es borrador preventivo.");
        }
    }
    async listarBorrador(params) {
        const { conjuntoId, anio, mes } = params;
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId,
                borrador: true,
                periodoAnio: anio,
                periodoMes: mes,
                tipo: client_1.TipoTarea.PREVENTIVA,
            },
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
                supervisor: { include: { usuario: true } },
            },
            orderBy: [{ grupoPlanId: "asc" }, { bloqueIndex: "asc" }, { id: "asc" }],
        });
    }
    /* =========================
     * Reservas de maquinaria
     * ======================= */
    async crearReservasPlanificadasParaTareas(params) {
        const { conjuntoId, tareas, diasEntregaRecogida, excluirTareaIds = [], festivosSet, } = params;
        const getMaqIds = (json) => {
            if (!Array.isArray(json))
                return [];
            return json
                .map((x) => Number(x?.maquinariaId))
                .filter((n) => Number.isFinite(n) && n > 0);
        };
        const sameDayKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
        const grupos = new Map();
        for (const t of tareas) {
            const maqIds = getMaqIds(t.maquinariaPlanJson);
            if (!maqIds.length)
                continue;
            const key = t.grupoPlanId ? `G:${t.grupoPlanId}` : `T:${t.id}`;
            const g = grupos.get(key);
            if (!g) {
                grupos.set(key, {
                    key,
                    tareaIds: [t.id],
                    tareaIdRepresentante: t.id,
                    descripcionRepresentante: t.descripcion ?? null,
                    maqIds: Array.from(new Set(maqIds)),
                    usoIni: t.fechaInicio,
                    usoFin: t.fechaFin,
                });
            }
            else {
                g.tareaIds.push(t.id);
                g.maqIds = Array.from(new Set(g.maqIds.concat(maqIds)));
                if (+t.fechaInicio < +g.usoIni)
                    g.usoIni = t.fechaInicio;
                if (+t.fechaFin > +g.usoFin)
                    g.usoFin = t.fechaFin;
                if (t.id < g.tareaIdRepresentante) {
                    g.tareaIdRepresentante = t.id;
                    g.descripcionRepresentante = t.descripcion ?? g.descripcionRepresentante;
                }
            }
        }
        // 2) Armar plan
        const plan = Array.from(grupos.values()).map((g) => {
            const { entregaDia, recogidaDia, iniReserva, finReserva } = this.calcularRangoReserva({
                fechaInicioUso: g.usoIni,
                fechaFinUso: g.usoFin,
                diasEntregaRecogida,
                festivosSet,
            });
            return {
                key: g.key,
                tareaIds: g.tareaIds,
                tareaIdRepresentante: g.tareaIdRepresentante,
                descripcion: g.descripcionRepresentante,
                maqIds: g.maqIds,
                usoIni: g.usoIni,
                usoFin: g.usoFin,
                entregaDia,
                recogidaDia,
                iniReserva,
                finReserva,
            };
        });
        if (!plan.length)
            return { ok: true, creadas: 0 };
        // 3) Query única
        const overlaps = (aIni, aFin, bIni, bFin) => aIni < bFin && bIni < aFin;
        const conflictosInternos = [];
        for (let i = 0; i < plan.length; i++) {
            const a = plan[i];
            for (let j = i + 1; j < plan.length; j++) {
                const b = plan[j];
                if (a.key === b.key)
                    continue;
                if (!overlaps(a.iniReserva, a.finReserva, b.iniReserva, b.finReserva))
                    continue;
                const solapeUsoReal = overlaps(a.usoIni, a.usoFin, b.usoIni, b.usoFin);
                // Nueva regla:
                // Si la maquinaria ya esta en el conjunto y solo se solapan ventanas
                // de entrega/recogida (no el uso real), se permite reutilizarla.
                if (!solapeUsoReal)
                    continue;
                const maqSetB = new Set(b.maqIds);
                for (const maquinariaId of a.maqIds) {
                    if (!maqSetB.has(maquinariaId))
                        continue;
                    conflictosInternos.push({
                        tareaId: a.tareaIdRepresentante,
                        maquinariaId,
                        rangoSolicitado: {
                            ini: a.iniReserva.toISOString(),
                            fin: a.finReserva.toISOString(),
                            entrega: sameDayKey(a.entregaDia),
                            recogida: sameDayKey(a.recogidaDia),
                        },
                        ocupadoPor: {
                            usoId: 0,
                            tareaId: b.tareaIdRepresentante,
                            conjuntoId,
                            descripcion: `[BORRADOR] ${(b.descripcion ?? "Preventiva en borrador").trim()}`,
                            ini: b.iniReserva.toISOString(),
                            fin: b.finReserva.toISOString(),
                        },
                    });
                }
            }
        }
        const allMaqIds = Array.from(new Set(plan.flatMap((p) => p.maqIds)));
        const minIni = new Date(Math.min(...plan.map((p) => +p.iniReserva)));
        const maxFin = new Date(Math.max(...plan.map((p) => +p.finReserva)));
        const allPlanTareaIds = Array.from(new Set(plan.flatMap((p) => p.tareaIds)));
        const conflictosDB = await this.prisma.usoMaquinaria.findMany({
            where: {
                maquinariaId: { in: allMaqIds },
                fechaInicio: { lt: maxFin },
                OR: [{ fechaFin: null }, { fechaFin: { gt: minIni } }],
                tareaId: { notIn: allPlanTareaIds.concat(excluirTareaIds) },
            },
            select: {
                id: true,
                maquinariaId: true,
                tareaId: true,
                fechaInicio: true,
                fechaFin: true,
                tarea: {
                    select: {
                        id: true,
                        conjuntoId: true,
                        descripcion: true,
                        fechaInicio: true,
                        fechaFin: true,
                        borrador: true,
                    },
                },
            },
        });
        // 4) Validación exacta
        const OPEN_END_FAR_FUTURE = new Date(2099, 11, 31, 23, 59, 59, 999);
        const byMaq = new Map();
        for (const u of conflictosDB) {
            const arr = byMaq.get(u.maquinariaId) ?? [];
            arr.push(u);
            byMaq.set(u.maquinariaId, arr);
        }
        const conflictos = [...conflictosInternos];
        for (const p of plan) {
            for (const maquinariaId of p.maqIds) {
                const ocup = byMaq.get(maquinariaId) ?? [];
                for (const u of ocup) {
                    const uFin = u.fechaFin ?? OPEN_END_FAR_FUTURE;
                    const solapeReserva = overlaps(p.iniReserva, p.finReserva, u.fechaInicio, uFin);
                    if (!solapeReserva)
                        continue;
                    const mismoConjunto = (u.tarea?.conjuntoId ?? null) === conjuntoId;
                    if (mismoConjunto) {
                        const usoOcupadoIni = u.tarea?.fechaInicio ?? u.fechaInicio;
                        const usoOcupadoFin = u.tarea?.fechaFin ?? u.fechaFin ?? OPEN_END_FAR_FUTURE;
                        const solapeUsoReal = overlaps(p.usoIni, p.usoFin, usoOcupadoIni, usoOcupadoFin);
                        // Regla nueva para mismo conjunto:
                        // si no hay solape de uso real, se permite (la maquina permanece).
                        if (!solapeUsoReal)
                            continue;
                    }
                    conflictos.push({
                        tareaId: p.tareaIdRepresentante,
                        maquinariaId,
                        rangoSolicitado: {
                            ini: p.iniReserva.toISOString(),
                            fin: p.finReserva.toISOString(),
                            entrega: sameDayKey(p.entregaDia),
                            recogida: sameDayKey(p.recogidaDia),
                        },
                        ocupadoPor: {
                            usoId: u.id,
                            tareaId: u.tareaId,
                            conjuntoId: u.tarea?.conjuntoId ?? null,
                            descripcion: u.tarea?.borrador
                                ? `[BORRADOR] ${(u.tarea?.descripcion ?? "Tarea en borrador").trim()}`
                                : u.tarea?.descripcion ?? null,
                            ini: u.fechaInicio.toISOString(),
                            fin: (u.fechaFin ?? OPEN_END_FAR_FUTURE).toISOString(),
                        },
                    });
                    break;
                }
            }
        }
        if (conflictos.length) {
            const maqIdsConflict = Array.from(new Set(conflictos.map((c) => c.maquinariaId)));
            const maqs = await this.prisma.maquinaria.findMany({
                where: { id: { in: maqIdsConflict } },
                select: { id: true, nombre: true },
            });
            const nombrePorId = new Map(maqs.map((m) => [m.id, m.nombre]));
            const first = conflictos[0];
            const maquinaNombre = nombrePorId.get(first.maquinariaId);
            throw (0, errorFormat_1.buildMaquinariaNoDisponibleError)({
                maquinariaId: first.maquinariaId,
                maquinaNombre,
                conflictos,
            });
        }
        // 5) Crear reservas (1 por grupo x máquina)
        const creadasIds = [];
        await this.prisma.$transaction(async (tx) => {
            for (const p of plan) {
                for (const maquinariaId of p.maqIds) {
                    const existe = await tx.usoMaquinaria.findFirst({
                        where: {
                            tareaId: p.tareaIdRepresentante,
                            maquinariaId,
                            fechaInicio: p.iniReserva,
                            fechaFin: p.finReserva,
                        },
                        select: { id: true },
                    });
                    if (!existe) {
                        const created = await tx.usoMaquinaria.create({
                            data: {
                                tarea: { connect: { id: p.tareaIdRepresentante } },
                                maquinaria: { connect: { id: maquinariaId } },
                                fechaInicio: p.iniReserva,
                                fechaFin: p.finReserva,
                                observacion: `Reserva preventiva (${sameDayKey(p.entregaDia)}→${sameDayKey(p.recogidaDia)})`,
                            },
                            select: { id: true },
                        });
                        creadasIds.push(created.id);
                    }
                    await tx.maquinariaConjunto.updateMany({
                        where: { conjuntoId, maquinariaId, estado: "ACTIVA" },
                        data: { tareaId: p.tareaIdRepresentante },
                    });
                }
            }
        });
        return { ok: true, creadas: creadasIds.length, ids: creadasIds };
    }
    /* =========================
     * Reserva: utilidades
     * ======================= */
    buscarDiaPermitidoAnterior(fecha, diasPermitidos, festivosSet) {
        const atStartOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
        const key = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
        let d = atStartOfDay(fecha);
        d.setDate(d.getDate() - 1);
        for (let guard = 0; guard < 62; guard++) {
            const k = key(d);
            const esFestivo = festivosSet?.has(k) ?? false;
            if (diasPermitidos.has(d.getDay()) && !esFestivo)
                return new Date(d);
            d.setDate(d.getDate() - 1);
        }
        return atStartOfDay(fecha);
    }
    buscarDiaPermitidoPosterior(fecha, diasPermitidos, festivosSet) {
        const atStartOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
        const key = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
        let d = atStartOfDay(fecha);
        d.setDate(d.getDate() + 1);
        for (let guard = 0; guard < 62; guard++) {
            const k = key(d);
            const esFestivo = festivosSet?.has(k) ?? false;
            if (diasPermitidos.has(d.getDay()) && !esFestivo)
                return new Date(d);
            d.setDate(d.getDate() + 1);
        }
        return atStartOfDay(fecha);
    }
    calcularRangoReserva(params) {
        const { fechaInicioUso, fechaFinUso, diasEntregaRecogida, festivosSet } = params;
        if (!(fechaInicioUso instanceof Date) || isNaN(+fechaInicioUso)) {
            throw new Error("fechaInicioUso inválida");
        }
        if (!(fechaFinUso instanceof Date) || isNaN(+fechaFinUso)) {
            throw new Error("fechaFinUso inválida");
        }
        const iniUso = +fechaInicioUso <= +fechaFinUso ? fechaInicioUso : fechaFinUso;
        const finUso = +fechaInicioUso <= +fechaFinUso ? fechaFinUso : fechaInicioUso;
        if (!diasEntregaRecogida || diasEntregaRecogida.size === 0) {
            throw new Error("diasEntregaRecogida vacío");
        }
        const atStartOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
        const atEndOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
        const usoInicioDia = atStartOfDay(iniUso);
        const usoFinDia = atStartOfDay(finUso);
        const entregaDia = this.buscarDiaPermitidoAnterior(usoInicioDia, diasEntregaRecogida, festivosSet);
        const recogidaDia = this.buscarDiaPermitidoPosterior(usoFinDia, diasEntregaRecogida, festivosSet);
        const iniReserva = atStartOfDay(entregaDia);
        const finReserva = atEndOfDay(recogidaDia);
        if (+finReserva < +iniReserva) {
            throw new Error("Rango de reserva inválido (fin < inicio)");
        }
        return { entregaDia, recogidaDia, iniReserva, finReserva };
    }
}
exports.DefinicionTareaPreventivaService = DefinicionTareaPreventivaService;
function enumerateDays(start, end) {
    const out = [];
    const cur = new Date(start.getFullYear(), start.getMonth(), start.getDate());
    const last = new Date(end.getFullYear(), end.getMonth(), end.getDate());
    while (cur <= last) {
        out.push(new Date(cur));
        cur.setDate(cur.getDate() + 1);
    }
    return out;
}
function buildBloqueosPorDescanso(horario) {
    const ds = horario.descansoStartMin;
    const df = horario.descansoEndMin;
    if (ds == null || df == null)
        return [];
    if (!(horario.startMin < ds && ds < df && df < horario.endMin))
        return [];
    return [{ startMin: ds, endMin: df, motivo: "DESCANSO" }];
}
function dateToDiaSemana(d) {
    switch (d.getDay()) {
        case 0:
            return client_1.DiaSemana.DOMINGO;
        case 1:
            return client_1.DiaSemana.LUNES;
        case 2:
            return client_1.DiaSemana.MARTES;
        case 3:
            return client_1.DiaSemana.MIERCOLES;
        case 4:
            return client_1.DiaSemana.JUEVES;
        case 5:
            return client_1.DiaSemana.VIERNES;
        case 6:
            return client_1.DiaSemana.SABADO;
        default:
            return client_1.DiaSemana.LUNES;
    }
}
function inicioSemana(fecha) {
    const d = new Date(fecha);
    const day = d.getDay();
    const diff = d.getDate() - day + (day === 0 ? -6 : 1); // lunes
    return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
}
async function minutosAsignadosEnSemana(prisma, conjuntoId, operarioId, fecha, incluirPublicadas) {
    const ini = inicioSemana(fecha);
    const fin = new Date(ini);
    fin.setDate(ini.getDate() + 6);
    const where = {
        conjuntoId,
        operarios: { some: { id: operarioId.toString() } },
        fechaInicio: { lte: fin },
        fechaFin: { gte: ini },
    };
    if (!incluirPublicadas)
        where.borrador = true;
    const tareas = await prisma.tarea.findMany({
        where,
        select: { duracionMinutos: true },
    });
    return tareas.reduce((acc, t) => acc + (t.duracionMinutos ?? 0), 0);
}
async function existeSolapeParaOperario(prisma, params) {
    const { conjuntoId, operarioId, fechaInicio, fechaFin, soloBorrador = true, excluirTareaId, excluirEstados = [], } = params;
    const where = {
        conjuntoId,
        tipo: { in: [client_1.TipoTarea.PREVENTIVA, client_1.TipoTarea.CORRECTIVA] },
        operarios: { some: { id: operarioId.toString() } },
        fechaInicio: { lt: fechaFin },
        fechaFin: { gt: fechaInicio },
    };
    if (soloBorrador)
        where.borrador = true;
    if (excluirEstados.length)
        where.estado = { notIn: excluirEstados };
    if (excluirTareaId != null)
        where.id = { not: excluirTareaId };
    const overlap = await prisma.tarea.findFirst({ where, select: { id: true } });
    return Boolean(overlap);
}
async function getOperarioNombre(prisma, operarioId) {
    const idStr = operarioId.toString();
    const op = await prisma.operario.findUnique({
        where: { id: idStr },
        include: { usuario: true },
    });
    return op?.usuario?.nombre ?? `Operario ${idStr}`;
}
function pickDaysByFrecuencia(days, def) {
    switch (def.frecuencia) {
        case client_1.Frecuencia.DIARIA:
            return days;
        case client_1.Frecuencia.SEMANAL: {
            const dia = def.diaSemanaProgramado ?? client_1.DiaSemana.LUNES;
            const target = diaSemanaToJsDay(dia);
            return days.filter((d) => d.getDay() === target);
        }
        case client_1.Frecuencia.MENSUAL: {
            const dd = def.diaMesProgramado ?? 1;
            return days.filter((d) => d.getDate() === dd);
        }
        default:
            return days;
    }
}
function diaSemanaToJsDay(d) {
    switch (d) {
        case client_1.DiaSemana.DOMINGO:
            return 0;
        case client_1.DiaSemana.LUNES:
            return 1;
        case client_1.DiaSemana.MARTES:
            return 2;
        case client_1.DiaSemana.MIERCOLES:
            return 3;
        case client_1.DiaSemana.JUEVES:
            return 4;
        case client_1.DiaSemana.VIERNES:
            return 5;
        case client_1.DiaSemana.SABADO:
            return 6;
    }
}
/**
 * ✅ Límite semanal (minutos) por conjunto:
 * - si Conjunto.limiteHorasSemanaOverride existe -> usa ese
 * - si no, usa Empresa.limiteHorasSemana de la empresa del conjunto
 * - fallback: 42h
 */
async function getLimiteMinSemanaPorConjunto(prisma, conjuntoId) {
    const conjunto = await prisma.conjunto.findUnique({
        where: { nit: conjuntoId },
        select: {
            limiteHorasSemanaOverride: true,
            empresa: { select: { limiteHorasSemana: true } },
        },
    });
    const override = conjunto?.limiteHorasSemanaOverride;
    if (override != null)
        return override * 60;
    return (conjunto?.empresa?.limiteHorasSemana ?? 42) * 60;
}
/* =========================================================
 * Patrones de jornada -> bloqueos
 * ======================================================= */
function clampInterval(i, f, start, end) {
    const ii = Math.max(i, start);
    const ff = Math.min(f, end);
    return ff > ii ? { i: ii, f: ff } : null;
}
function bloqueosFromAllowed(params) {
    const { horario, allowed, motivo } = params;
    if (!allowed.length) {
        return [{ startMin: horario.startMin, endMin: horario.endMin, motivo }];
    }
    const a = allowed[0];
    const out = [];
    if (horario.startMin < a.i)
        out.push({ startMin: horario.startMin, endMin: a.i, motivo });
    if (a.f < horario.endMin)
        out.push({ startMin: a.f, endMin: horario.endMin, motivo });
    return out;
}
/**
 * Bloqueos por patrón (si uno NO puede, se bloquea).
 */
async function buildBloqueosPorPatronJornada(params) {
    const { prisma, fechaDia, horarioDia, operariosIds } = params;
    if (!operariosIds.length)
        return [];
    const dia = (0, operarioAvailability_1.diaSemanaFromDate)(fechaDia);
    const ops = await prisma.operario.findMany({
        where: { id: { in: operariosIds.map(String) } },
        select: {
            id: true,
            usuario: {
                select: {
                    jornadaLaboral: true,
                    patronJornada: true,
                },
            },
        },
    });
    const disponibilidadByOp = await (0, operarioAvailability_1.obtenerDisponibilidadActivaOperarios)({
        prisma,
        operariosIds,
        fecha: fechaDia,
    });
    const bloqueos = [];
    for (const op of ops) {
        const jl = op.usuario?.jornadaLaboral;
        const pj = op.usuario?.patronJornada;
        if (jl === "COMPLETA")
            continue;
        const allowed = (0, operarioAvailability_1.allowedIntervalsForUserWithAvailability)({
            dia,
            horario: horarioDia,
            jornadaLaboral: jl,
            patronJornada: pj,
            disponibilidad: disponibilidadByOp.get(op.id)
                ? {
                    trabajaDomingo: disponibilidadByOp.get(op.id).trabajaDomingo,
                    diaDescanso: disponibilidadByOp.get(op.id).diaDescanso,
                }
                : null,
        });
        bloqueos.push(...bloqueosFromAllowed({
            horario: horarioDia,
            allowed,
            motivo: `PATRON_${op.id}`,
        }));
    }
    return bloqueos;
}
async function getLimiteMinSemanaPorOperario(params) {
    const { prisma, operarioId, horariosPorDia, fechaReferencia } = params;
    const op = await prisma.operario.findUnique({
        where: { id: operarioId },
        select: {
            usuario: { select: { jornadaLaboral: true, patronJornada: true } },
        },
    });
    const jornada = (op?.usuario?.jornadaLaboral ?? null);
    const patron = (op?.usuario?.patronJornada ?? null);
    const ref = fechaReferencia ?? new Date();
    const monday = new Date(ref);
    monday.setHours(0, 0, 0, 0);
    monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
    // Si es COMPLETA => capacidad = total del conjunto
    if (jornada === "COMPLETA" || !jornada) {
        let total = 0;
        for (let offset = 0; offset < 7; offset++) {
            const fecha = new Date(monday);
            fecha.setDate(monday.getDate() + offset);
            const ds = dateToDiaSemana(fecha);
            const h = horariosPorDia.get(ds);
            if (!h)
                continue;
            const disponibilidad = await (0, operarioAvailability_1.obtenerDisponibilidadActivaOperarios)({
                prisma,
                operariosIds: [operarioId],
                fecha,
            });
            const periodo = disponibilidad.get(operarioId);
            const allowed = (0, operarioAvailability_1.allowedIntervalsForUserWithAvailability)({
                dia: ds,
                horario: h,
                jornadaLaboral: jornada,
                patronJornada: patron,
                disponibilidad: periodo
                    ? {
                        trabajaDomingo: periodo.trabajaDomingo,
                        diaDescanso: periodo.diaDescanso,
                    }
                    : null,
            });
            if (allowed.length === 0) {
                continue;
            }
            total += h.endMin - h.startMin;
        }
        const empresaLimite = await prisma.operario.findUnique({
            where: { id: operarioId },
            select: { empresa: { select: { limiteHorasSemana: true } } },
        });
        return Math.min(total, (empresaLimite?.empresa?.limiteHorasSemana ?? 42) * 60);
    }
    // MEDIO_TIEMPO => capacidad = lo que deja el patrón (exacto)
    if (jornada === "MEDIO_TIEMPO") {
        let total = 0;
        for (let offset = 0; offset < 7; offset++) {
            const fecha = new Date(monday);
            fecha.setDate(monday.getDate() + offset);
            const dia = dateToDiaSemana(fecha);
            const h = horariosPorDia.get(dia);
            if (!h)
                continue;
            const disponibilidad = await (0, operarioAvailability_1.obtenerDisponibilidadActivaOperarios)({
                prisma,
                operariosIds: [operarioId],
                fecha,
            });
            const allowed = (0, operarioAvailability_1.allowedIntervalsForUserWithAvailability)({
                dia,
                horario: h,
                jornadaLaboral: jornada,
                patronJornada: patron,
                disponibilidad: disponibilidad.get(operarioId)
                    ? {
                        trabajaDomingo: disponibilidad.get(operarioId).trabajaDomingo,
                        diaDescanso: disponibilidad.get(operarioId).diaDescanso,
                    }
                    : null,
            });
            for (const a of allowed)
                total += a.f - a.i;
        }
        const empresaLimite = await prisma.operario.findUnique({
            where: { id: operarioId },
            select: { empresa: { select: { limiteHorasSemana: true } } },
        });
        return Math.min(total, (empresaLimite?.empresa?.limiteHorasSemana ?? 42) * 60);
    }
    // Otros casos (por si creces luego)
    let fallback = 0;
    for (const [, h] of horariosPorDia)
        fallback += h.endMin - h.startMin;
    const empresaLimite = await prisma.operario.findUnique({
        where: { id: operarioId },
        select: { empresa: { select: { limiteHorasSemana: true } } },
    });
    return Math.min(fallback, (empresaLimite?.empresa?.limiteHorasSemana ?? 42) * 60);
}
