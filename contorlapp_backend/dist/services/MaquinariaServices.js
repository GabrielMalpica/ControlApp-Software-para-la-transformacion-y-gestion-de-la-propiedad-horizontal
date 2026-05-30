"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MaquinariaService = void 0;
exports.startOfDayLocal = startOfDayLocal;
exports.addDaysLocal = addDaysLocal;
exports.isDeliveryPickupDay = isDeliveryPickupDay;
exports.prevDeliveryDayInclusive = prevDeliveryDayInclusive;
exports.nextPickupDayInclusive = nextPickupDayInclusive;
exports.calcularVentanaPrestamoLogistico = calcularVentanaPrestamoLogistico;
exports.validarMaquinariaDisponibleEnVentana = validarMaquinariaDisponibleEnVentana;
exports.crearReservasMaquinariaParaTarea = crearReservasMaquinariaParaTarea;
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const elementoHierarchy_1 = require("../utils/elementoHierarchy");
const AsignarAConjuntoDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    responsableId: zod_1.z.string().optional(), // ✅ Operario.id es String en tu schema
    diasPrestamo: zod_1.z.number().int().positive().default(7),
});
const DELIVERY_PICKUP_DOW = new Set([1, 3, 6]); // Lun, Mie, Sab
class MaquinariaService {
    constructor(prisma, maquinariaId) {
        this.prisma = prisma;
        this.maquinariaId = maquinariaId;
    }
    async asignarAConjunto(payload) {
        const { conjuntoId, responsableId, diasPrestamo } = AsignarAConjuntoDTO.parse(payload);
        const fechaInicio = new Date();
        const fechaDevolucionEstimada = new Date(fechaInicio.getTime() + diasPrestamo * 24 * 60 * 60 * 1000);
        // 1) Validar existencia maquinaria y conjunto
        const [maq, conj] = await Promise.all([
            this.prisma.maquinaria.findUnique({
                where: { id: this.maquinariaId },
                select: { id: true },
            }),
            this.prisma.conjunto.findUnique({
                where: { nit: conjuntoId },
                select: { nit: true },
            }),
        ]);
        if (!maq)
            throw new Error("Maquinaria no encontrada");
        if (!conj)
            throw new Error("Conjunto no encontrado");
        // 2) Validar que NO esté ACTIVA en otro conjunto
        const activa = await this.prisma.maquinariaConjunto.findFirst({
            where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
            select: { id: true, conjuntoId: true },
        });
        if (activa) {
            throw new Error(`La maquinaria ya está asignada (ACTIVA) al conjunto ${activa.conjuntoId}.`);
        }
        // 3) Crear asignación (inventario del conjunto)
        return this.prisma.maquinariaConjunto.create({
            data: {
                conjunto: { connect: { nit: conjuntoId } },
                maquinaria: { connect: { id: this.maquinariaId } },
                tipoTenencia: "PRESTADA",
                estado: "ACTIVA",
                fechaInicio,
                fechaDevolucionEstimada,
                ...(responsableId
                    ? { responsable: { connect: { id: responsableId } } }
                    : {}),
            },
            include: {
                conjunto: { select: { nit: true, nombre: true } },
                maquinaria: {
                    select: { id: true, nombre: true, marca: true, estado: true },
                },
                responsable: { include: { usuario: { select: { nombre: true } } } },
            },
        });
    }
    async devolver(conjuntoId) {
        // 1) Buscar asignación ACTIVA en ese conjunto
        const activa = await this.prisma.maquinariaConjunto.findFirst({
            where: {
                maquinariaId: this.maquinariaId,
                conjuntoId,
                estado: "ACTIVA",
            },
            select: { id: true },
        });
        if (!activa) {
            throw new Error("No existe una asignación ACTIVA de esta maquinaria en ese conjunto.");
        }
        // 2) Cerrar asignación
        return this.prisma.maquinariaConjunto.update({
            where: { id: activa.id },
            data: {
                estado: "DEVUELTA",
                fechaFin: new Date(),
            },
        });
    }
    async estaDisponible() {
        // Disponible si NO tiene asignación ACTIVA
        const activa = await this.prisma.maquinariaConjunto.findFirst({
            where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
            select: { id: true },
        });
        return !activa;
    }
    async obtenerResponsableEnConjunto(conjuntoId) {
        const activa = await this.prisma.maquinariaConjunto.findFirst({
            where: {
                maquinariaId: this.maquinariaId,
                conjuntoId,
                estado: "ACTIVA",
            },
            include: { responsable: { include: { usuario: true } } },
        });
        return activa?.responsable?.usuario?.nombre ?? "Sin asignar";
    }
    async agendaMaquinariaPorMaquina(params) {
        const { conjuntoId, maquinariaId, desde, hasta } = params;
        // maquinaria propia del conjunto (para marcar "propia")
        const propias = await this.prisma.maquinariaConjunto.findMany({
            where: { conjuntoId, estado: "ACTIVA", maquinariaId },
            select: { maquinariaId: true },
        });
        const esPropiaConjunto = propias.length > 0;
        const usos = await this.prisma.usoMaquinaria.findMany({
            where: {
                maquinariaId: this.maquinariaId,
                fechaInicio: { lt: hasta },
                fechaFin: { gt: desde },
            },
            include: {
                maquinaria: { select: { id: true, nombre: true } },
                tarea: {
                    select: {
                        id: true,
                        descripcion: true,
                        fechaInicio: true,
                        fechaFin: true,
                        estado: true,
                        tipo: true,
                        prioridad: true,
                        borrador: true,
                        conjuntoId: true,
                        conjunto: { select: { nombre: true } },
                        ubicacion: { select: { nombre: true } },
                        elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
                    },
                },
            },
            orderBy: [{ fechaInicio: "asc" }],
        });
        const getMaqIds = (json) => {
            if (!Array.isArray(json))
                return [];
            return json
                .map((x) => Number(x?.maquinariaId))
                .filter((n) => Number.isFinite(n) && n > 0);
        };
        const borradores = await this.prisma.tarea.findMany({
            where: {
                borrador: true,
                tipo: "PREVENTIVA",
                fechaInicio: { lt: hasta },
                fechaFin: { gt: desde },
            },
            select: {
                id: true,
                descripcion: true,
                fechaInicio: true,
                fechaFin: true,
                conjuntoId: true,
                conjunto: { select: { nombre: true } },
                maquinariaPlanJson: true,
            },
            orderBy: [{ fechaInicio: "asc" }],
        });
        const definiciones = await this.prisma.definicionTareaPreventiva.findMany({
            where: { activo: true },
            select: {
                id: true,
                descripcion: true,
                frecuencia: true,
                diaSemanaProgramado: true,
                diaMesProgramado: true,
                fechasProgramadasJson: true,
                creadoEn: true,
                diasParaCompletar: true,
                conjuntoId: true,
                conjunto: { select: { nombre: true } },
                maquinariaPlanJson: true,
            },
            orderBy: [{ descripcion: "asc" }],
        });
        const diaSemanaToJs = {
            LUNES: 1,
            MARTES: 2,
            MIERCOLES: 3,
            JUEVES: 4,
            VIERNES: 5,
            SABADO: 6,
            DOMINGO: 0,
        };
        const definicionReservas = definiciones.flatMap((def) => {
            const maqIds = new Set(getMaqIds(def.maquinariaPlanJson));
            if (!maqIds.has(maquinariaId))
                return [];
            const items = [];
            const duracionDias = Math.max(1, def.diasParaCompletar ?? 1);
            const pushReserva = (fechaBase) => {
                const ini = startOfDayLocal(fechaBase);
                const fin = addDaysLocal(ini, duracionDias - 1);
                if (ini >= hasta || fin < desde)
                    return;
                items.push({
                    id: -def.id,
                    fechaInicio: ini,
                    fechaFin: new Date(fin.getFullYear(), fin.getMonth(), fin.getDate(), 23, 59, 59),
                    tareaId: null,
                    tarea: {
                        id: def.id,
                        descripcion: def.descripcion,
                        estado: "DEFINICION",
                        tipo: "PREVENTIVA",
                        prioridad: 0,
                        ubicacion: null,
                        elemento: null,
                        fechaInicio: ini,
                        fechaFin: fin,
                        conjuntoId: def.conjuntoId,
                        conjuntoNombre: def.conjunto?.nombre ?? null,
                    },
                    observacion: "Preventiva en definicion",
                    fuente: "DEFINICION",
                });
            };
            const cursor = new Date(desde.getFullYear(), desde.getMonth(), 1);
            const finMes = new Date(hasta.getFullYear(), hasta.getMonth(), 0);
            for (const fecha of pickReservasDefinicionMes(def, cursor, finMes)) {
                pushReserva(fecha);
            }
            return items;
        });
        return {
            maquinariaId,
            nombre: usos[0]?.maquinaria?.nombre ?? "",
            esPropiaConjunto,
            reservas: [
                ...usos.map((u) => ({
                    id: u.id,
                    fechaInicio: u.fechaInicio,
                    fechaFin: u.fechaFin,
                    tareaId: u.tareaId,
                    tarea: u.tarea
                        ? {
                            id: u.tarea.id,
                            descripcion: u.tarea.descripcion,
                            estado: u.tarea.estado,
                            tipo: u.tarea.tipo,
                            prioridad: u.tarea.prioridad,
                            ubicacion: u.tarea.ubicacion?.nombre ?? null,
                            elemento: (0, elementoHierarchy_1.construirRutaElemento)(u.tarea.elemento) ?? null,
                            fechaInicio: u.tarea.fechaInicio,
                            fechaFin: u.tarea.fechaFin,
                            conjuntoId: u.tarea.conjuntoId,
                            conjuntoNombre: u.tarea.conjunto?.nombre ?? null,
                        }
                        : null,
                    observacion: u.observacion ?? null,
                    fuente: u.tarea?.borrador == true ? "BORRADOR" : "PUBLICADA",
                })),
                ...borradores
                    .filter((t) => getMaqIds(t.maquinariaPlanJson).includes(maquinariaId))
                    .map((t) => ({
                    id: -t.id,
                    fechaInicio: t.fechaInicio,
                    fechaFin: t.fechaFin,
                    tareaId: t.id,
                    tarea: {
                        id: t.id,
                        descripcion: t.descripcion,
                        estado: "BORRADOR",
                        tipo: "PREVENTIVA",
                        prioridad: 0,
                        ubicacion: null,
                        elemento: null,
                        fechaInicio: t.fechaInicio,
                        fechaFin: t.fechaFin,
                        conjuntoId: t.conjuntoId,
                        conjuntoNombre: t.conjunto?.nombre ?? null,
                    },
                    observacion: "Preventiva en borrador",
                    fuente: "BORRADOR",
                })),
                ...definicionReservas,
            ].sort((a, b) => a.fechaInicio.getTime() - b.fechaInicio.getTime()),
        };
    }
    async resumenEstado() {
        const maquinaria = await this.prisma.maquinaria.findUnique({
            where: { id: this.maquinariaId },
            select: { nombre: true, marca: true, estado: true },
        });
        if (!maquinaria)
            throw new Error("🛠️ Maquinaria no encontrada");
        const activa = await this.prisma.maquinariaConjunto.findFirst({
            where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
            include: { conjunto: { select: { nombre: true } } },
        });
        const estadoAsignacion = activa
            ? `Prestada a ${activa.conjunto?.nombre ?? activa.conjuntoId}`
            : "Disponible";
        return `🛠️ ${maquinaria.nombre} (${maquinaria.marca}) - ${maquinaria.estado} - ${estadoAsignacion}`;
    }
}
exports.MaquinariaService = MaquinariaService;
function pickReservasDefinicionMes(def, inicioMes, finMes) {
    const fechas = [];
    for (let d = new Date(inicioMes); d <= finMes; d = addDaysLocal(d, 1)) {
        if (coincideFrecuenciaDefinicionEnFecha(def, d)) {
            fechas.push(new Date(d));
        }
    }
    return fechas;
}
function coincideFrecuenciaDefinicionEnFecha(def, fecha) {
    switch (def.frecuencia) {
        case client_1.Frecuencia.DIARIA:
            return true;
        case client_1.Frecuencia.SEMANAL: {
            if (def.diaSemanaProgramado == null)
                return false;
            return fecha.getDay() === diaSemanaToJsValue(def.diaSemanaProgramado);
        }
        case client_1.Frecuencia.QUINCENAL: {
            const ancla = fechaAnclaDefinicion(def);
            return diferenciaDiasCalendario(ancla, fecha) % 14 === 0;
        }
        case client_1.Frecuencia.MENSUAL:
            return coincideFrecuenciaMensual(def, fecha, 1);
        case client_1.Frecuencia.BIMESTRAL:
            return coincideFrecuenciaExplicita(def, fecha);
        case client_1.Frecuencia.TRIMESTRAL:
            return coincideFrecuenciaExplicita(def, fecha);
        case client_1.Frecuencia.SEMESTRAL:
            return coincideFrecuenciaExplicita(def, fecha);
        case client_1.Frecuencia.ANUAL:
            return coincideFrecuenciaExplicita(def, fecha);
        default:
            return false;
    }
}
function coincideFrecuenciaExplicita(def, fecha) {
    const fechas = normalizarFechasProgramadas(def.fechasProgramadasJson);
    return fechas.some((item) => item.getMonth() === fecha.getMonth() && item.getDate() === fecha.getDate());
}
function diaSemanaToJsValue(dia) {
    switch (dia) {
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
        case client_1.DiaSemana.DOMINGO:
            return 0;
    }
}
function coincideFrecuenciaMensual(def, fecha, intervaloMeses) {
    const ancla = fechaAnclaDefinicion(def);
    if (mesesEntre(ancla, fecha) % intervaloMeses !== 0)
        return false;
    const diaObjetivo = Math.max(1, Math.min(31, Number(def.diaMesProgramado ?? ancla.getDate() ?? 1)));
    return fecha.getDate() === ajustarDiaMes(fecha.getFullYear(), fecha.getMonth(), diaObjetivo);
}
function fechaAnclaDefinicion(def) {
    const base = def.creadoEn instanceof Date ? def.creadoEn : new Date(def.creadoEn ?? Date.now());
    const diaObjetivo = Math.max(1, Math.min(31, Number(def.diaMesProgramado ?? base.getDate() ?? 1)));
    return new Date(base.getFullYear(), base.getMonth(), ajustarDiaMes(base.getFullYear(), base.getMonth(), diaObjetivo));
}
function ajustarDiaMes(anio, mesIndex, dia) {
    return Math.min(dia, new Date(anio, mesIndex + 1, 0).getDate());
}
function mesesEntre(a, b) {
    return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
}
function diferenciaDiasCalendario(a, b) {
    const utcA = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
    const utcB = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
    return Math.round((utcB - utcA) / 86400000);
}
function normalizarFechasProgramadas(value) {
    if (!Array.isArray(value))
        return [];
    return value
        .map((item) => {
        const raw = typeof item === "string" ? item : item?.toString();
        if (!raw)
            return null;
        const parsed = new Date(`${raw}T00:00:00`);
        return Number.isNaN(parsed.getTime()) ? null : parsed;
    })
        .filter((item) => item instanceof Date);
}
function startOfDayLocal(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}
function addDaysLocal(date, days) {
    const d = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
    d.setDate(d.getDate() + days);
    return d;
}
function isDeliveryPickupDay(date) {
    return DELIVERY_PICKUP_DOW.has(date.getDay() === 0 ? 7 : date.getDay());
}
/**
 * Devuelve el día logístico "anterior o igual" (para entrega).
 * Ej: Martes -> Lunes, Jueves -> Miércoles, Domingo -> Sábado.
 */
function prevDeliveryDayInclusive(fechaUso) {
    let d = startOfDayLocal(fechaUso);
    for (let guard = 0; guard < 8; guard++) {
        if (isDeliveryPickupDay(d))
            return d;
        d = addDaysLocal(d, -1);
    }
    return startOfDayLocal(fechaUso);
}
/**
 * Devuelve el día logístico "posterior o igual" (para recogida).
 * Ej: Martes -> Miércoles, Miércoles -> Miércoles, Jueves -> Sábado.
 */
function nextPickupDayInclusive(fechaUso) {
    let d = startOfDayLocal(fechaUso);
    for (let guard = 0; guard < 8; guard++) {
        if (isDeliveryPickupDay(d))
            return d;
        d = addDaysLocal(d, 1);
    }
    return startOfDayLocal(fechaUso);
}
/**
 * Ventana de préstamo logístico:
 * - inicio = 00:00 del día de entrega (prevDeliveryDayInclusive)
 * - finExclusivo = 00:00 del día siguiente a la recogida (nextPickupDayInclusive + 1)
 *
 * Así el intervalo es [inicio, finExclusivo) y es fácil de comparar en BD.
 */
function calcularVentanaPrestamoLogistico(fechaInicioUso, fechaFinUso) {
    const diaEntrega = prevDeliveryDayInclusive(fechaInicioUso);
    const diaRecogida = nextPickupDayInclusive(fechaFinUso);
    const inicioPrestamo = startOfDayLocal(diaEntrega);
    const finPrestamoExclusivo = addDaysLocal(diaRecogida, 1); // 00:00 día siguiente
    return { inicioPrestamo, finPrestamoExclusivo, diaEntrega, diaRecogida };
}
async function validarMaquinariaDisponibleEnVentana(params) {
    const { prisma, maquinariaIds, ventanaInicio, ventanaFinExclusivo, ignorarTareaIds = [], } = params;
    if (!maquinariaIds.length)
        return { ok: true };
    const usos = await prisma.usoMaquinaria.findMany({
        where: {
            maquinariaId: { in: maquinariaIds },
            // overlap: (usoInicio < ventanaFin) AND (usoFin > ventanaInicio)
            fechaInicio: { lt: ventanaFinExclusivo },
            OR: [
                { fechaFin: null }, // abierto => ocupa
                { fechaFin: { gt: ventanaInicio } },
            ],
            ...(ignorarTareaIds.length
                ? { NOT: { tareaId: { in: ignorarTareaIds } } }
                : {}),
        },
        select: {
            id: true,
            maquinariaId: true,
            tareaId: true,
            fechaInicio: true,
            fechaFin: true,
        },
    });
    if (!usos.length)
        return { ok: true };
    return {
        ok: false,
        conflictos: usos.map((u) => ({
            maquinariaId: u.maquinariaId,
            usoId: u.id,
            tareaId: u.tareaId,
            inicio: u.fechaInicio,
            fin: u.fechaFin,
        })),
    };
}
async function crearReservasMaquinariaParaTarea(params) {
    const { tx, tareaId, maquinariaIds, fechaInicioUso, fechaFinUso } = params;
    if (!maquinariaIds.length)
        return;
    const { inicioPrestamo, finPrestamoExclusivo, diaEntrega, diaRecogida } = calcularVentanaPrestamoLogistico(fechaInicioUso, fechaFinUso);
    const obs = params.observacion ??
        `Reserva logística: entrega ${diaEntrega.toISOString().slice(0, 10)} / recogida ${diaRecogida.toISOString().slice(0, 10)}`;
    // 1 registro por máquina
    for (const maqId of maquinariaIds) {
        await tx.usoMaquinaria.create({
            data: {
                tareaId,
                maquinariaId: maqId,
                fechaInicio: inicioPrestamo,
                fechaFin: finPrestamoExclusivo, // ✅ fin exclusivo (00:00 día siguiente a recogida)
                observacion: obs,
            },
        });
    }
}
