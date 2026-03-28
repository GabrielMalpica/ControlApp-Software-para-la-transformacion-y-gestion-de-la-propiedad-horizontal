import type { PrismaClient } from "@prisma/client";

type AgendaParams = {
  empresaNit: string;
  anio: number;
  mes: number;
  categoria?: string;
};

type HerrSel = {
  id: number;
  nombre: string;
  unidad: string;
  categoria: unknown;
  modoControl: unknown;
};

type UsoSel = {
  id: number;
  herramientaId: number;
  cantidad: unknown;
  origenStock: unknown;
  fechaInicio: Date;
  fechaFin: Date | null;
  tareaId: number | null;
  tarea: null | {
    id: number;
    grupoPlanId: string | null;
    conjuntoId: string | null;
    descripcion: string | null;
    fechaInicio: Date | null;
    fechaFin: Date | null;
    conjunto?: { nombre: string | null } | null;
  };
};

export class AgendaHerramientaService {
  constructor(private prisma: PrismaClient) {}

  private startOfDay(d: Date) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
  }

  private endOfDay(d: Date) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
  }

  private dayOnly(d: Date) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  }

  private isoDate(d: Date) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  }

  private startOfMonth(anio: number, mes: number) {
    return new Date(anio, mes - 1, 1, 0, 0, 0, 0);
  }

  private endOfMonth(anio: number, mes: number) {
    return new Date(anio, mes, 0, 23, 59, 59, 999);
  }

  private firstMondayOfGrid(anio: number, mes: number) {
    const first = new Date(anio, mes - 1, 1);
    const dow = first.getDay();
    const back = (dow + 6) % 7;
    const monday = new Date(first);
    monday.setDate(first.getDate() - back);
    return this.startOfDay(monday);
  }

  private weekIndexInMonth(anio: number, mes: number, date: Date) {
    const base = this.firstMondayOfGrid(anio, mes);
    const d = this.startOfDay(date);
    const diffDays = Math.floor((+d - +base) / (1000 * 60 * 60 * 24));
    return Math.floor(diffDays / 7) + 1;
  }

  private weekRange(anio: number, mes: number, semana: number) {
    const base = this.firstMondayOfGrid(anio, mes);
    const start = new Date(base);
    start.setDate(base.getDate() + (semana - 1) * 7);
    const end = new Date(start);
    end.setDate(start.getDate() + 6);
    return { start: this.startOfDay(start), end: this.endOfDay(end) };
  }

  private dayToCol(dow: number) {
    if (dow === 0) return -1;
    return dow - 1;
  }

  private emptyGrid(): string[] {
    return ["", "", "", "", "", ""];
  }

  private fillGridEAR(params: {
    weekStart: Date;
    weekEnd: Date;
    usoIni: Date;
    usoFin: Date;
  }) {
    const { weekStart, weekEnd, usoIni, usoFin } = params;
    const grid = this.emptyGrid();

    const mark = (d: Date, letter: "E" | "R" | "A") => {
      if (+d < +weekStart || +d > +weekEnd) return;
      const col = this.dayToCol(d.getDay());
      if (col < 0 || col > 5) return;
      if ((grid[col] === "E" || grid[col] === "R") && letter === "A") return;
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

  async agendaGlobalPorHerramienta(params: AgendaParams) {
    const { empresaNit, anio, mes, categoria } = params;
    const iniMes = this.startOfMonth(anio, mes);
    const finMes = this.endOfMonth(anio, mes);

    const herramientas: HerrSel[] = await this.prisma.herramienta.findMany({
      where: {
        empresaId: empresaNit,
        ...(categoria ? { categoria: categoria as any } : {}),
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

    if (!herramientas.length) return { ok: true, anio, mes, data: [] };

    const ids = herramientas.map((h) => h.id);
    const usos: UsoSel[] = await (this.prisma.usoHerramienta as any).findMany({
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

    const gpIds = Array.from(
      new Set(
        usos
          .map((u) => u.tarea?.grupoPlanId)
          .filter((x): x is string => typeof x === "string" && x.length > 0),
      ),
    );

    type GPTaskLite = { fechaInicio: Date; fechaFin: Date | null };
    const tareasPorGp = new Map<string, GPTaskLite[]>();

    if (gpIds.length) {
      const tareas = await this.prisma.tarea.findMany({
        where: { grupoPlanId: { in: gpIds } },
        select: { grupoPlanId: true, fechaInicio: true, fechaFin: true },
      });

      for (const t of tareas) {
        const key = t.grupoPlanId!;
        const arr = tareasPorGp.get(key) ?? [];
        arr.push({ fechaInicio: t.fechaInicio, fechaFin: t.fechaFin });
        tareasPorGp.set(key, arr);
      }
    }

    const byHerr = new Map<number, UsoSel[]>();
    for (const u of usos) {
      const arr = byHerr.get(u.herramientaId) ?? [];
      arr.push(u);
      byHerr.set(u.herramientaId, arr);
    }

    const data = herramientas.map((h) => {
      const usosHerr = byHerr.get(h.id) ?? [];
      const groups = new Map<string, UsoSel[]>();

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

        let usoIni: Date;
        let usoFin: Date;

        if (gpKey && tareasPorGp.has(gpKey)) {
          const ts = tareasPorGp.get(gpKey)!;
          const inis = ts.map((t) => t.fechaInicio);
          const fins = ts.map((t) => t.fechaFin ?? t.fechaInicio);
          usoIni = new Date(Math.min(...inis.map((d) => +d)));
          usoFin = new Date(Math.max(...fins.map((d) => +d)));
        } else {
          const ini = u0.tarea?.fechaInicio ?? u0.fechaInicio;
          const fin = u0.tarea?.fechaFin ?? u0.fechaFin ?? ini;
          usoIni = ini;
          usoFin = fin;
        }

        let grupo = 1;
        if (gpKey && tareasPorGp.has(gpKey)) {
          const ts = tareasPorGp.get(gpKey)!;
          const diasUnicos = new Set(ts.map((t) => this.isoDate(this.dayOnly(t.fechaInicio)))).size;
          grupo = Math.min(6, Math.max(1, diasUnicos));
        }

        const semanaIni = this.weekIndexInMonth(anio, mes, usoIni);
        const semanaFin = this.weekIndexInMonth(anio, mes, usoFin);
        const cantidad = arr.reduce((acc, row) => acc + Number(row.cantidad ?? 0), 0);

        const out: any[] = [];
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

      const semanas: Record<number, Record<number, any[]>> = {};
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
