// src/services/AgendaMaquinariaService.ts
import type { PrismaClient } from "../generated/prisma";

type AgendaParams = {
  empresaNit: string;
  anio: number;
  mes: number; // 1..12
  tipo?: string;
};

type MaqSel = {
  id: number;
  nombre: string;
  tipo: any;
  marca: string;
  estado: any;
};

type UsoSel = {
  id: number;
  maquinariaId: number;
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

const DIAS_ENTREGA_RECOGIDA = new Set([1, 3, 6]); // Lun(1), Mie(3), Sab(6)

export class AgendaMaquinariaService {
  constructor(private prisma: PrismaClient) {}

  // =========================
  // Helpers base fecha
  // =========================
  private startOfDay(d: Date) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
  }
  private endOfDay(d: Date) {
    return new Date(
      d.getFullYear(),
      d.getMonth(),
      d.getDate(),
      23,
      59,
      59,
      999,
    );
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

  // =========================
  // Logística (L, X, S)
  // =========================
  private buscarDiaPermitidoAnterior(fecha: Date, diasPermitidos: Set<number>) {
    const d = this.dayOnly(fecha);
    d.setDate(d.getDate() - 1);
    for (let guard = 0; guard < 21; guard++) {
      if (diasPermitidos.has(d.getDay())) return d;
      d.setDate(d.getDate() - 1);
    }
    return this.dayOnly(fecha);
  }

  private buscarDiaPermitidoPosterior(
    fecha: Date,
    diasPermitidos: Set<number>,
  ) {
    const d = this.dayOnly(fecha);
    d.setDate(d.getDate() + 1); // 👈 estricto: empieza el día siguiente
    for (let guard = 0; guard < 21; guard++) {
      if (diasPermitidos.has(d.getDay())) return d;
      d.setDate(d.getDate() + 1);
    }
    return this.dayOnly(fecha);
  }

  private calcularRangoReserva(usoIni: Date, usoFin: Date) {
    const ini = +usoIni <= +usoFin ? usoIni : usoFin;
    const fin = +usoIni <= +usoFin ? usoFin : usoIni;

    const entregaDia = this.buscarDiaPermitidoAnterior(
      ini,
      DIAS_ENTREGA_RECOGIDA,
    );
    const recogidaDia = this.buscarDiaPermitidoPosterior(
      fin,
      DIAS_ENTREGA_RECOGIDA,
    );

    return {
      entregaDia,
      recogidaDia,
      iniReserva: this.startOfDay(entregaDia),
      finReserva: this.endOfDay(recogidaDia),
    };
  }

  // =========================
  // Días de uso (inclusive)
  // =========================
  private diasUso(usoIni: Date, usoFin: Date) {
    const a = this.dayOnly(usoIni).getTime();
    const b = this.dayOnly(usoFin).getTime();
    const diff = Math.round((b - a) / (1000 * 60 * 60 * 24));
    return Math.max(1, diff + 1);
  }

  // =========================
  // Semana tipo tu UI (por lunes)
  // Semana 1 empieza en el lunes anterior/al mismo del día 1 del mes
  // =========================
  private firstMondayOfGrid(anio: number, mes: number) {
    const first = new Date(anio, mes - 1, 1);
    // weekday: 1=Lun ... 7=Dom, pero en JS getDay(): 0=Dom..6=Sab
    // Queremos retroceder hasta lunes
    const dow = first.getDay(); // 0..6
    const back = (dow + 6) % 7; // Lun=>0, Mar=>1, ... Dom=>6
    const monday = new Date(first);
    monday.setDate(first.getDate() - back);
    return this.startOfDay(monday);
  }

  private weekIndexInMonth(anio: number, mes: number, date: Date) {
    const base = this.firstMondayOfGrid(anio, mes);
    const d = this.startOfDay(date);
    const diffDays = Math.floor((+d - +base) / (1000 * 60 * 60 * 24));
    return Math.floor(diffDays / 7) + 1; // 1..6 (a veces 5)
  }

  private weekRange(anio: number, mes: number, semana: number) {
    const base = this.firstMondayOfGrid(anio, mes);
    const start = new Date(base);
    start.setDate(base.getDate() + (semana - 1) * 7);
    const end = new Date(start);
    end.setDate(start.getDate() + 6); // domingo de esa semana (pero tú pintas L..S)
    return { start: this.startOfDay(start), end: this.endOfDay(end) };
  }

  // =========================
  // Grid L..S (6 columnas)
  // =========================
  private dayToCol(dow: number) {
    // JS getDay(): 0=Dom,1=Lun,...6=Sab
    // columnas: Lun(1)=0 ... Sab(6)=5
    if (dow === 0) return -1;
    return dow - 1;
  }

  private emptyGrid(): string[] {
    return ["", "", "", "", "", ""];
  }

  // Pinta E / A / P / R dentro de la semana visible
  private fillGridEAPR(params: {
    weekStart: Date; // startOfDay lunes de la semana
    weekEnd: Date; // endOfDay domingo de la semana
    entrega: Date;
    recogida: Date;
    usoIni: Date;
    usoFin: Date;
  }) {
    const { weekStart, weekEnd, entrega, recogida, usoIni, usoFin } = params;

    const grid = this.emptyGrid();

    const mark = (d: Date, letter: "E" | "R" | "A" | "P") => {
      if (+d < +weekStart || +d > +weekEnd) return;
      const col = this.dayToCol(d.getDay());
      if (col < 0 || col > 5) return; // domingo no se pinta
      // prioridad: E/R no se pisan
      if (
        (grid[col] === "E" || grid[col] === "R") &&
        (letter === "P" || letter === "A")
      )
        return;
      if (letter === "E" || letter === "R") {
        grid[col] = letter;
        return;
      }
      // A tiene prioridad sobre P
      if (letter === "A") grid[col] = "A";
      if (letter === "P" && grid[col] === "") grid[col] = "P";
    };

    const ent = this.dayOnly(entrega);
    const rec = this.dayOnly(recogida);
    const ini = this.dayOnly(usoIni);
    const fin = this.dayOnly(usoFin);

    // 1) E y R
    mark(ent, "E");
    mark(rec, "R");

    // 2) Actividad real (A) dentro de usoIni..usoFin
    {
      const cur = new Date(ini);
      while (+cur <= +fin) {
        mark(cur, "A");
        cur.setDate(cur.getDate() + 1);
      }
    }

    // 3) Estancia logística (P) entre entrega..recogida (incluye intermedios)
    {
      const cur = new Date(ent);
      while (+cur <= +rec) {
        // si no es A y no es E/R, queda P
        mark(cur, "P");
        cur.setDate(cur.getDate() + 1);
      }
    }

    return grid;
  }

  // =========================================================
  // ✅ AGENDA GLOBAL (CORRECTA)
  // =========================================================
  async agendaGlobalPorMaquina(params: AgendaParams) {
    const { empresaNit, anio, mes, tipo } = params;

    const iniMes = this.startOfMonth(anio, mes);
    const finMes = this.endOfMonth(anio, mes);

    const maquinas: MaqSel[] = await this.prisma.maquinaria.findMany({
      where: {
        empresaId: empresaNit,
        propietarioTipo: "EMPRESA",
        ...(tipo ? { tipo: tipo as any } : {}),
      },
      select: { id: true, nombre: true, tipo: true, marca: true, estado: true },
      orderBy: [{ tipo: "asc" }, { nombre: "asc" }],
    });

    if (!maquinas.length) return { ok: true, anio, mes, data: [] };

    const maqIds = maquinas.map((m) => m.id);

    // 1) Usos (préstamos/logística)
    const usos: UsoSel[] = await this.prisma.usoMaquinaria.findMany({
      where: {
        maquinariaId: { in: maqIds },
        fechaInicio: { lt: finMes },
        OR: [{ fechaFin: null }, { fechaFin: { gt: iniMes } }],
      },
      select: {
        id: true,
        maquinariaId: true,
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

    // 2) Batch: todas las tareas de todos los grupoPlanId presentes
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

    // 3) Agrupar por maquinaria
    const byMaq = new Map<number, UsoSel[]>();
    for (const u of usos) {
      const arr = byMaq.get(u.maquinariaId) ?? [];
      arr.push(u);
      byMaq.set(u.maquinariaId, arr);
    }

    const data = maquinas.map((m) => {
      const usosMaq = byMaq.get(m.id) ?? [];

      // 4) Agrupar por grupoPlanId (si no existe, por uso individual)
      const groups = new Map<string, UsoSel[]>();
      for (const u of usosMaq) {
        const key = u.tarea?.grupoPlanId ?? `__SINGLE__${u.id}`;
        const arr = groups.get(key) ?? [];
        arr.push(u);
        groups.set(key, arr);
      }

      // 5) items (✅ split por semanas ENTRE entrega y recogida)
      const items = Array.from(groups.entries()).flatMap(([groupKey, arr]) => {
        arr.sort((a, b) => {
          const ai = a.tarea?.fechaInicio ?? a.fechaInicio;
          const bi = b.tarea?.fechaInicio ?? b.fechaInicio;
          return +ai - +bi;
        });

        const u0 = arr[0];
        const gpKey = u0.tarea?.grupoPlanId ?? null;

        // ---- usoIni/usoFin para logística (min/max del GP si existe)
        let usoIni: Date;
        let usoFin: Date;

        if (gpKey && tareasPorGp.has(gpKey)) {
          const ts = tareasPorGp.get(gpKey)!;
          const inis = ts
            .map((t) => t.fechaInicio)
            .filter((d): d is Date => d instanceof Date && !isNaN(+d));
          const fins = ts
            .map((t) => t.fechaFin ?? t.fechaInicio)
            .filter((d): d is Date => d instanceof Date && !isNaN(+d));
          usoIni = new Date(Math.min(...inis.map((d) => +d)));
          usoFin = new Date(Math.max(...fins.map((d) => +d)));
        } else {
          const ini = u0.tarea?.fechaInicio ?? u0.fechaInicio;
          const fin = u0.tarea?.fechaFin ?? u0.fechaFin ?? ini;
          usoIni = ini;
          usoFin = fin;
        }

        // ---- grupo = días reales de trabajo (días únicos con tarea)
        let grupo = 1;
        if (gpKey && tareasPorGp.has(gpKey)) {
          const ts = tareasPorGp.get(gpKey)!;
          const diasUnicos = new Set(
            ts
              .map((t) => t.fechaInicio)
              .filter((d): d is Date => d instanceof Date && !isNaN(+d))
              .map((d) => this.isoDate(this.dayOnly(d))),
          ).size;

          grupo = Math.min(6, Math.max(1, diasUnicos));
        } else {
          grupo = 1;
        }

        // ---- logística
        const { entregaDia, recogidaDia } = this.calcularRangoReserva(
          usoIni,
          usoFin,
        );

        // ✅ split: semanas desde entrega hasta recogida
        const semanaIni = this.weekIndexInMonth(anio, mes, entregaDia);
        const semanaFin = this.weekIndexInMonth(anio, mes, recogidaDia);

        const out: any[] = [];
        for (let semana = semanaIni; semana <= semanaFin; semana++) {
          const { start: wStart, end: wEnd } = this.weekRange(
            anio,
            mes,
            semana,
          );

          const grid = this.fillGridEAPR({
            weekStart: wStart,
            weekEnd: wEnd,
            entrega: entregaDia,
            recogida: recogidaDia,
            usoIni,
            usoFin,
          });

          out.push({
            usoId: u0.id,
            tareaId: u0.tareaId,
            conjuntoId: u0.tarea?.conjuntoId ?? null,
            conjuntoNombre: u0.tarea?.conjunto?.nombre ?? null,
            descripcion: u0.tarea?.descripcion ?? null,
            entrega: this.isoDate(entregaDia),
            recogida: this.isoDate(recogidaDia),
            grupo,
            semana,
            grid,
          });
        }

        return out;
      });

      // 6) semanas[semana][grupo]
      const semanas: Record<number, Record<number, any[]>> = {};
      for (const it of items) {
        if (!semanas[it.semana]) {
          semanas[it.semana] = { 1: [], 2: [], 3: [], 4: [], 5: [], 6: [] };
        }
        semanas[it.semana][it.grupo].push(it);
      }

      return {
        maquinaria: m,
        semanas,
        resumen: { reservasMes: new Set(items.map(i => i.usoId)).size }
      };
    });

    return { ok: true, anio, mes, data };
  }
}
