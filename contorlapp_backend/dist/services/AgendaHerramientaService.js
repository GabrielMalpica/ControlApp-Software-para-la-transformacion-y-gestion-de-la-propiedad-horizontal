"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AgendaHerramientaService = void 0;
class AgendaHerramientaService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    startOfDay(d) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
    }
    endOfDay(d) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
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
    startOfMonth(anio, mes) {
        return new Date(anio, mes - 1, 1, 0, 0, 0, 0);
    }
    endOfMonth(anio, mes) {
        return new Date(anio, mes, 0, 23, 59, 59, 999);
    }
    firstMondayOfGrid(anio, mes) {
        const first = new Date(anio, mes - 1, 1);
        const dow = first.getDay();
        const back = (dow + 6) % 7;
        const monday = new Date(first);
        monday.setDate(first.getDate() - back);
        return this.startOfDay(monday);
    }
    weekIndexInMonth(anio, mes, date) {
        const base = this.firstMondayOfGrid(anio, mes);
        const d = this.startOfDay(date);
        const diffDays = Math.floor((+d - +base) / (1000 * 60 * 60 * 24));
        return Math.floor(diffDays / 7) + 1;
    }
    weekRange(anio, mes, semana) {
        const base = this.firstMondayOfGrid(anio, mes);
        const start = new Date(base);
        start.setDate(base.getDate() + (semana - 1) * 7);
        const end = new Date(start);
        end.setDate(start.getDate() + 6);
        return { start: this.startOfDay(start), end: this.endOfDay(end) };
    }
    dayToCol(dow) {
        if (dow === 0)
            return -1;
        return dow - 1;
    }
    emptyGrid() {
        return ["", "", "", "", "", ""];
    }
    fillGridEAR(params) {
        const { weekStart, weekEnd, usoIni, usoFin } = params;
        const grid = this.emptyGrid();
        const mark = (d, letter) => {
            if (+d < +weekStart || +d > +weekEnd)
                return;
            const col = this.dayToCol(d.getDay());
            if (col < 0 || col > 5)
                return;
            if ((grid[col] === "E" || grid[col] === "R") && letter === "A")
                return;
            grid[col] = letter;
        };
        const ini = this.dayOnly(usoIni);
        const fin = this.dayOnly(usoFin);
        if (+ini === +fin) {
            mark(ini, "A");
            return grid;
        }
        mark(ini, "E");
        mark(fin, "R");
        const cur = new Date(ini);
        cur.setDate(cur.getDate() + 1);
        while (+cur < +fin) {
            mark(cur, "A");
            cur.setDate(cur.getDate() + 1);
        }
        return grid;
    }
    async agendaGlobalPorHerramienta(params) {
        const { empresaNit, anio, mes, categoria } = params;
        const iniMes = this.startOfMonth(anio, mes);
        const finMes = this.endOfMonth(anio, mes);
        const herramientas = await this.prisma.herramienta.findMany({
            where: {
                empresaId: empresaNit,
                ...(categoria ? { categoria: categoria } : {}),
            },
            select: {
                id: true,
                nombre: true,
                unidad: true,
                categoria: true,
                modoControl: true,
            },
            orderBy: [{ categoria: "asc" }, { nombre: "asc" }],
        });
        if (!herramientas.length)
            return { ok: true, anio, mes, data: [] };
        const ids = herramientas.map((h) => h.id);
        const usos = await this.prisma.usoHerramienta.findMany({
            where: {
                herramientaId: { in: ids },
                fechaInicio: { lt: finMes },
                OR: [{ fechaFin: null }, { fechaFin: { gt: iniMes } }],
            },
            select: {
                id: true,
                herramientaId: true,
                cantidad: true,
                origenStock: true,
                fechaInicio: true,
                fechaFin: true,
                tareaId: true,
                tarea: {
                    select: {
                        id: true,
                        grupoPlanId: true,
                        conjuntoId: true,
                        descripcion: true,
                        fechaInicio: true,
                        fechaFin: true,
                        conjunto: { select: { nombre: true } },
                    },
                },
            },
        });
        const gpIds = Array.from(new Set(usos
            .map((u) => u.tarea?.grupoPlanId)
            .filter((x) => typeof x === "string" && x.length > 0)));
        const tareasPorGp = new Map();
        if (gpIds.length) {
            const tareas = await this.prisma.tarea.findMany({
                where: { grupoPlanId: { in: gpIds } },
                select: { grupoPlanId: true, fechaInicio: true, fechaFin: true },
            });
            for (const t of tareas) {
                const key = t.grupoPlanId;
                const arr = tareasPorGp.get(key) ?? [];
                arr.push({ fechaInicio: t.fechaInicio, fechaFin: t.fechaFin });
                tareasPorGp.set(key, arr);
            }
        }
        const byHerr = new Map();
        for (const u of usos) {
            const arr = byHerr.get(u.herramientaId) ?? [];
            arr.push(u);
            byHerr.set(u.herramientaId, arr);
        }
        const data = herramientas.map((h) => {
            const usosHerr = byHerr.get(h.id) ?? [];
            const groups = new Map();
            for (const u of usosHerr) {
                const key = u.tarea?.grupoPlanId ?? `__SINGLE__${u.id}`;
                const arr = groups.get(key) ?? [];
                arr.push(u);
                groups.set(key, arr);
            }
            const items = Array.from(groups.values()).flatMap((arr) => {
                arr.sort((a, b) => {
                    const ai = a.tarea?.fechaInicio ?? a.fechaInicio;
                    const bi = b.tarea?.fechaInicio ?? b.fechaInicio;
                    return +ai - +bi;
                });
                const u0 = arr[0];
                const gpKey = u0.tarea?.grupoPlanId ?? null;
                let usoIni;
                let usoFin;
                if (gpKey && tareasPorGp.has(gpKey)) {
                    const ts = tareasPorGp.get(gpKey);
                    const inis = ts.map((t) => t.fechaInicio);
                    const fins = ts.map((t) => t.fechaFin ?? t.fechaInicio);
                    usoIni = new Date(Math.min(...inis.map((d) => +d)));
                    usoFin = new Date(Math.max(...fins.map((d) => +d)));
                }
                else {
                    const ini = u0.tarea?.fechaInicio ?? u0.fechaInicio;
                    const fin = u0.tarea?.fechaFin ?? u0.fechaFin ?? ini;
                    usoIni = ini;
                    usoFin = fin;
                }
                let grupo = 1;
                if (gpKey && tareasPorGp.has(gpKey)) {
                    const ts = tareasPorGp.get(gpKey);
                    const diasUnicos = new Set(ts.map((t) => this.isoDate(this.dayOnly(t.fechaInicio)))).size;
                    grupo = Math.min(6, Math.max(1, diasUnicos));
                }
                const semanaIni = this.weekIndexInMonth(anio, mes, usoIni);
                const semanaFin = this.weekIndexInMonth(anio, mes, usoFin);
                const cantidad = arr.reduce((acc, row) => acc + Number(row.cantidad ?? 0), 0);
                const out = [];
                for (let semana = semanaIni; semana <= semanaFin; semana++) {
                    const { start, end } = this.weekRange(anio, mes, semana);
                    out.push({
                        usoId: u0.id,
                        tareaId: u0.tareaId,
                        conjuntoId: u0.tarea?.conjuntoId ?? null,
                        conjuntoNombre: u0.tarea?.conjunto?.nombre ?? null,
                        descripcion: u0.tarea?.descripcion ?? null,
                        entrega: this.isoDate(this.dayOnly(usoIni)),
                        recogida: this.isoDate(this.dayOnly(usoFin)),
                        grupo,
                        semana,
                        cantidad,
                        origenStock: String(u0.origenStock ?? "CONJUNTO"),
                        grid: this.fillGridEAR({ weekStart: start, weekEnd: end, usoIni, usoFin }),
                    });
                }
                return out;
            });
            const semanas = {};
            for (const it of items) {
                if (!semanas[it.semana]) {
                    semanas[it.semana] = { 1: [], 2: [], 3: [], 4: [], 5: [], 6: [] };
                }
                semanas[it.semana][it.grupo].push(it);
            }
            return {
                herramienta: h,
                semanas,
                resumen: { reservasMes: new Set(items.map((i) => i.usoId)).size },
            };
        });
        return { ok: true, anio, mes, data };
    }
}
exports.AgendaHerramientaService = AgendaHerramientaService;
