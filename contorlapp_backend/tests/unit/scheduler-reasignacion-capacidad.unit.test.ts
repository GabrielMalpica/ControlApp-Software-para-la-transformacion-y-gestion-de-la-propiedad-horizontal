import { DiaSemana, Frecuencia } from "@prisma/client";

// Misma neutralización de festivos que scheduler-necesidades.unit.test.ts.
jest.mock("../../src/utils/schedulerUtils", () => {
  const real = jest.requireActual("../../src/utils/schedulerUtils");
  return {
    ...real,
    getFestivosSet: jest.fn().mockResolvedValue(new Set<string>()),
  };
});

import { DefinicionTareaPreventivaService } from "../../src/services/DefinicionTareaPreventivaService";

const CONJUNTO = "C-CAP";

// Categorías (id = orden de programación)
const PISCINAS = 1;
const PODA = 2;
const JARDINERIA = 3;
const ASEO = 4;
const BASICO = 5;
const SALVAMENTO = 6;

const CATEGORIAS = [PISCINAS, PODA, JARDINERIA, ASEO, BASICO, SALVAMENTO].map((id) => ({
  id,
  ordenProgramacion: id,
  activa: true,
}));

type DefFake = {
  id: number;
  descripcion: string;
  operarioId: string;
  duracion: number;
  categoriaId: number | null;
  ordenEnCategoria?: number | null;
  prioridad?: number;
  /** Día del mes objetivo (MENSUAL). Por defecto 2 (lunes 2 de marzo de 2026). */
  diaMes?: number;
  diasParaCompletar?: number;
  /** Segundo operario => cuadrilla. */
  operarioExtraId?: string;
};

type PlazaFake = {
  id: number;
  orden: number;
  etiqueta: string;
  operarioId: string | null;
  perfilActivo?: boolean;
  /** Categorías que el perfil puede ejecutar (configuradas). */
  categorias: number[];
  /** Ventana LUNES de la plaza (horario especial). */
  lunes: [string, string];
};

function construirPrisma(opts: { defs: DefFake[]; plazas: PlazaFake[] }) {
  const tareasCreadas: any[] = [];
  const excluidasCreadas: any[] = [];
  const eventos: any[] = [];
  let secuencia = 1000;

  const nombrePorOperario = new Map<string, string>();
  for (const p of opts.plazas) if (p.operarioId) nombrePorOperario.set(p.operarioId, `Nombre ${p.operarioId}`);

  const defsFake = opts.defs.map((d) => ({
    id: d.id,
    conjuntoId: CONJUNTO,
    descripcion: d.descripcion,
    frecuencia: Frecuencia.MENSUAL,
    diaSemanaProgramado: null,
    diaMesProgramado: d.diaMes ?? 2,
    prioridad: d.prioridad ?? 2,
    duracionMinutosFija: d.duracion,
    diasParaCompletar: d.diasParaCompletar ?? 1,
    ubicacionId: 1,
    elementoId: 100 + d.id,
    supervisorId: null,
    insumosPlanJson: null,
    maquinariaPlanJson: null,
    herramientasPlanJson: null,
    creadoEn: new Date(2026, 0, 1),
    actualizadoEn: new Date(2026, 0, 1),
    categoriaId: d.categoriaId,
    ordenEnCategoria: d.ordenEnCategoria ?? null,
    operarios: [d.operarioId, ...(d.operarioExtraId ? [d.operarioExtraId] : [])].map((id) => ({
      id,
      usuario: { nombre: nombrePorOperario.get(id) ?? id },
    })),
    necesidades: [],
    supervisor: null,
    ubicacion: { nombre: "Ubicacion" },
    elemento: { id: 100 + d.id, nombre: `Elemento ${d.id}`, padre: null },
  }));

  const prisma: any = {
    tareasCreadas,
    excluidasCreadas,
    eventos,

    definicionTareaPreventiva: {
      findMany: jest.fn().mockResolvedValue(defsFake),
      findUnique: jest.fn().mockResolvedValue(null),
      findFirst: jest.fn(async ({ where }: any) => defsFake.find((d) => d.id === where?.id) ?? null),
    },

    conjuntoHorario: {
      findMany: jest.fn().mockResolvedValue(
        [DiaSemana.LUNES, DiaSemana.MARTES, DiaSemana.MIERCOLES, DiaSemana.JUEVES, DiaSemana.VIERNES].map(
          (dia) => ({ dia, horaApertura: "07:00", horaCierre: "15:00", descansoInicio: null, descansoFin: null }),
        ),
      ),
      findFirst: jest.fn().mockResolvedValue(null),
      findUnique: jest.fn().mockResolvedValue(null),
    },

    conjuntoNecesidadOperario: {
      findMany: jest.fn(async ({ where, select }: any) => {
        // Consulta del rescate por capacidades: plazas del conjunto con perfil.
        if (where?.conjuntoId && where?.operarioId == null) {
          return opts.plazas.map((p) => ({
            id: p.id,
            orden: p.orden,
            etiqueta: p.etiqueta,
            activo: true,
            operarioId: p.operarioId,
            perfil: {
              activo: p.perfilActivo ?? true,
              categorias: p.categorias.map((categoriaId) => ({ categoriaId })),
            },
            operario: p.operarioId
              ? { id: p.operarioId, usuario: { nombre: nombrePorOperario.get(p.operarioId) } }
              : null,
          }));
        }
        // Consulta de horarios efectivos por operario.
        const ids: string[] = where?.operarioId?.in ?? [];
        const diaFiltro = select?.horarios?.where?.dia;
        return opts.plazas
          .filter((p) => p.operarioId && ids.includes(p.operarioId))
          .map((p) => ({
            operarioId: p.operarioId,
            horarioEspecial: true,
            horarios:
              diaFiltro === DiaSemana.LUNES
                ? [{ horaApertura: p.lunes[0], horaCierre: p.lunes[1], descansoInicio: null, descansoFin: null }]
                : [],
            trabajaFestivos: false,
            festivoHoraApertura: null,
            festivoHoraCierre: null,
            festivoDescansoInicio: null,
            festivoDescansoFin: null,
            descansoCompensatorio: false,
            diasDescansoCompensatorio: 1,
          }));
      }),
    },

    categoriaTarea: {
      findMany: jest.fn(async ({ where }: any) => {
        const ids: number[] = where?.id?.in ?? [];
        return CATEGORIAS.filter((c) => ids.includes(c.id));
      }),
    },

    tarea: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      count: jest.fn().mockResolvedValue(0),
      findFirst: jest.fn().mockResolvedValue(null),
      findMany: jest.fn(async ({ where }: any) => {
        const desde: Date | undefined = where?.fechaFin?.gte ?? where?.fechaInicio?.gte;
        if (!desde) return tareasCreadas;
        const hasta: Date | undefined = where?.fechaInicio?.lte ?? where?.fechaFin?.lte;
        let lista = tareasCreadas.filter((t) => (!hasta || t.fechaInicio <= hasta) && t.fechaFin >= desde);
        // Filtro "misma tarea" (por definición o por descripción+ubicación+elemento).
        if (Array.isArray(where?.OR)) {
          lista = lista.filter((t) =>
            where.OR.some((c: any) =>
              c.definicionId != null
                ? t.definicionId === c.definicionId
                : String(t.descripcion).toLowerCase() === String(c.descripcion?.equals ?? "").toLowerCase() &&
                  t.ubicacionId === c.ubicacionId &&
                  t.elementoId === c.elementoId,
            ),
          );
        }
        // Filtro por operarios (carga del operario).
        const filtroId = where?.operarios?.some?.id;
        if (filtroId != null) {
          const opsIds: string[] = typeof filtroId === "string" ? [filtroId] : (filtroId.in ?? []);
          lista = lista.filter((t) => t.operarios.some((o: any) => opsIds.includes(o.id)));
        }
        return lista;
      }),
      create: jest.fn(async ({ data }: any) => {
        const creada = {
          ...data,
          operarios: data.operarios?.connect ?? [],
          necesidades: data.necesidades?.connect ?? [],
          id: ++secuencia,
        };
        tareasCreadas.push(creada);
        return creada;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const tarea = tareasCreadas.find((t) => t.id === where.id);
        if (tarea) Object.assign(tarea, data);
        return tarea;
      }),
      updateMany: jest.fn().mockResolvedValue({ count: 0 }),
    },

    preventivaExcluidaBorrador: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      create: jest.fn(async ({ data }: any) => {
        const creada = { estado: "PENDIENTE", metadataJson: null, ...data, id: ++secuencia };
        excluidasCreadas.push(creada);
        return creada;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const e = excluidasCreadas.find((x) => x.id === where.id);
        if (e) Object.assign(e, data);
        return e;
      }),
    },

    preventivaBorradorEvento: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      create: jest.fn(async ({ data }: any) => {
        eventos.push(data);
        return { ...data, id: ++secuencia };
      }),
    },

    operario: {
      findMany: jest.fn(async ({ where }: any) => {
        const ids: string[] = where?.id?.in ?? [];
        return ids.map((id) => ({ id, usuario: { jornadaLaboral: "COMPLETA", patronJornada: null } }));
      }),
      findUnique: jest.fn().mockResolvedValue({
        usuario: { jornadaLaboral: "COMPLETA", patronJornada: null },
        empresa: { limiteHorasSemana: 48 },
      }),
    },
    operarioDisponibilidadPeriodo: { findFirst: jest.fn().mockResolvedValue(null) },
    conjunto: {
      findUnique: jest.fn().mockResolvedValue({
        limiteHorasSemanaOverride: null,
        empresa: { limiteHorasSemana: 48 },
      }),
    },
    empresa: { findFirst: jest.fn().mockResolvedValue({ limiteHorasSemana: 48 }) },
    auditoriaEvento: {
      create: jest.fn().mockResolvedValue({}),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    $queryRaw: jest.fn().mockResolvedValue([]),
  };
  return prisma;
}

async function generar(opts: { defs: DefFake[]; plazas: PlazaFake[] }) {
  const prisma = construirPrisma(opts);
  const service = new DefinicionTareaPreventivaService(prisma);
  const { creadas, novedades } = await service.generarBorradorMensual({
    conjuntoId: CONJUNTO,
    periodoAnio: 2026,
    periodoMes: 3,
  });
  return { prisma, creadas, novedades };
}

const fechaClave = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const hhmm = (d: Date) =>
  `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
const tareasDe = (prisma: any, operarioId: string) =>
  prisma.tareasCreadas.filter((t: any) => t.operarios.some((o: any) => o.id === operarioId));
const tareaPorDesc = (prisma: any, descripcion: string) =>
  prisma.tareasCreadas.find((t: any) => t.descripcion === descripcion);
const excluidaPorDesc = (prisma: any, descripcion: string) =>
  prisma.excluidasCreadas.find((e: any) => e.descripcion === descripcion && e.estado === "PENDIENTE");

/**
 * Conjunto X con dos plazas (marzo de 2026; lunes: 2, 9, 16, 23 y 30):
 *  - Todero (op-T): solo LUNES 07:00-09:00 (120 min por lunes). 5 tareas de
 *    120 min llenan sus 5 lunes.
 *  - Todero-Salvavidas (op-S): solo LUNES 07:00-11:00 (240 min por lunes);
 *    habilitado para Poda, Jardinería, Mant. básico y Salvamento (no Piscinas).
 */
const TODERO: PlazaFake = {
  id: 1,
  orden: 1,
  etiqueta: "Todero #1",
  operarioId: "op-T",
  categorias: [PISCINAS, PODA, JARDINERIA, ASEO, BASICO],
  lunes: ["07:00", "09:00"],
};
const TODERO_SALVAVIDAS: PlazaFake = {
  id: 2,
  orden: 2,
  etiqueta: "Todero-Salvavidas #1",
  operarioId: "op-S",
  categorias: [PODA, JARDINERIA, BASICO, SALVAMENTO],
  lunes: ["07:00", "11:00"],
};

// Las que llenan el mes del Todero: duran 120 y por eso se procesan primero.
const RELLENO_TODERO: DefFake[] = [1, 2, 3, 4, 5].map((n) => ({
  id: n,
  descripcion: `Relleno aseo ${n}`,
  operarioId: "op-T",
  duracion: 120,
  categoriaId: ASEO,
}));

describe("generarBorradorMensual - reasignación por capacidades", () => {
  test("CASO OBLIGATORIO: el Todero lleno deriva Poda A, Jardinería B y Mantenimiento C al Todero-Salvavidas; solo quedan excluidas las que realmente no caben o no tienen perfil", async () => {
    const { prisma, novedades } = await generar({
      plazas: [TODERO, TODERO_SALVAVIDAS],
      defs: [
        ...RELLENO_TODERO,
        // Pendientes del Todero (60 min c/u, ids altos => van después)
        { id: 10, descripcion: "Poda A", operarioId: "op-T", duracion: 60, categoriaId: PODA, ordenEnCategoria: 1 },
        { id: 11, descripcion: "Poda B", operarioId: "op-T", duracion: 60, categoriaId: PODA, ordenEnCategoria: 2 },
        { id: 12, descripcion: "Jardineria B", operarioId: "op-T", duracion: 60, categoriaId: JARDINERIA },
        { id: 13, descripcion: "Mantenimiento C", operarioId: "op-T", duracion: 60, categoriaId: BASICO },
        // No caben en ninguna ventana de 4 h => exclusión real
        { id: 14, descripcion: "Poda gigante", operarioId: "op-T", duracion: 300, categoriaId: PODA },
        // El Todero-Salvavidas NO tiene Piscinas => exclusión real
        { id: 15, descripcion: "Piscina extra", operarioId: "op-T", duracion: 60, categoriaId: PISCINAS },
        // Tarea propia del Todero-Salvavidas: ocupa capacidad parcial el lunes 2
        { id: 20, descripcion: "Turno salvamento", operarioId: "op-S", duracion: 120, categoriaId: SALVAMENTO },
      ],
    });

    // 1) Reasignadas al Todero-Salvavidas (op-S), nunca al Todero.
    for (const desc of ["Poda A", "Poda B", "Jardineria B", "Mantenimiento C"]) {
      const t = tareaPorDesc(prisma, desc);
      expect(t).toBeDefined();
      expect(t.operarios).toEqual([{ id: "op-S" }]);
      expect(t.necesidades).toEqual([{ id: 2 }]);
      expect(t.reasignadaAutomaticamente).toBe(true);
      expect(t.necesidadPrevistaId).toBe(1);
    }

    // 2) Exclusiones reales: sin recurso compatible o sin espacio.
    expect(excluidaPorDesc(prisma, "Poda gigante")).toBeDefined();
    expect(excluidaPorDesc(prisma, "Piscina extra")).toBeDefined();
    for (const desc of ["Poda A", "Poda B", "Jardineria B", "Mantenimiento C"]) {
      expect(excluidaPorDesc(prisma, desc)).toBeUndefined();
    }
    // Las excluidas rescatadas quedan AGENDADAS con la trazabilidad.
    const rescatada = prisma.excluidasCreadas.find((e: any) => e.descripcion === "Poda A");
    expect(rescatada.estado).toBe("AGENDADA");
    expect(rescatada.metadataJson.reasignacionAutomatica).toMatchObject({
      desdeNecesidadId: 1,
      haciaNecesidadId: 2,
      haciaOperarioId: "op-S",
    });

    // 3) Las tareas del Todero no cambiaron y nadie le asignó nada de más.
    const delTodero = tareasDe(prisma, "op-T").filter((t: any) => !t.reasignadaAutomaticamente);
    expect(delTodero).toHaveLength(5);
    expect(tareasDe(prisma, "op-T")).toHaveLength(5);

    // 4) Novedades: reasignaciones sí, y sin "sin hueco" para lo rescatado.
    const reasignaciones = novedades.filter((n: any) => n.tipo === "REASIGNADA_POR_CAPACIDAD");
    expect(reasignaciones).toHaveLength(4);
    expect(novedades.some((n: any) => n.tipo === "SIN_CANDIDATAS" && n.descripcion === "Poda A")).toBe(false);
    expect(novedades.some((n: any) => n.tipo === "SIN_CANDIDATAS" && n.descripcion === "Poda gigante")).toBe(true);

    // 5) Orden del día del Todero-Salvavidas: categoría y luego orden interno
    //    (Poda A -> Poda B -> ... -> Salvamento), todo el lunes 2 por cercanía.
    const lunes2 = tareasDe(prisma, "op-S")
      .filter((t: any) => fechaClave(t.fechaInicio) === "2026-03-02")
      .sort((a: any, b: any) => +a.fechaInicio - +b.fechaInicio);
    expect(lunes2.map((t: any) => t.descripcion)).toEqual(["Poda A", "Poda B", "Turno salvamento"]);
    expect(hhmm(lunes2[0].fechaInicio)).toBe("07:00");
    expect(hhmm(lunes2[1].fechaInicio)).toBe("08:00");
    expect(hhmm(lunes2[2].fechaInicio)).toBe("09:00");
  });

  test("ningún operario queda con tareas solapadas ni fuera de su ventana", async () => {
    const { prisma } = await generar({
      plazas: [TODERO, TODERO_SALVAVIDAS],
      defs: [
        ...RELLENO_TODERO,
        { id: 10, descripcion: "Poda A", operarioId: "op-T", duracion: 60, categoriaId: PODA, ordenEnCategoria: 1 },
        { id: 11, descripcion: "Poda B", operarioId: "op-T", duracion: 60, categoriaId: PODA, ordenEnCategoria: 2 },
        { id: 12, descripcion: "Jardineria B", operarioId: "op-T", duracion: 60, categoriaId: JARDINERIA },
        { id: 20, descripcion: "Turno salvamento", operarioId: "op-S", duracion: 120, categoriaId: SALVAMENTO },
      ],
    });
    for (const op of ["op-T", "op-S"]) {
      const lista = tareasDe(prisma, op).sort((a: any, b: any) => +a.fechaInicio - +b.fechaInicio);
      for (let i = 1; i < lista.length; i++) {
        expect(+lista[i].fechaInicio).toBeGreaterThanOrEqual(+lista[i - 1].fechaFin);
      }
      const fin = op === "op-T" ? "09:00" : "11:00";
      for (const t of lista) {
        expect(t.fechaInicio.getDay()).toBe(1); // solo lunes
        expect(hhmm(t.fechaInicio) >= "07:00").toBe(true);
        expect(hhmm(t.fechaFin) <= fin).toBe(true);
      }
    }
  });

  test("capacidad parcial: lo que no cabe en el lunes objetivo se ubica en el lunes siguiente con espacio", async () => {
    const { prisma } = await generar({
      plazas: [TODERO, TODERO_SALVAVIDAS],
      defs: [
        ...RELLENO_TODERO,
        // 120 (salvamento) + 4 x 60 = 360 min > 240 del lunes 2
        { id: 10, descripcion: "Poda A", operarioId: "op-T", duracion: 60, categoriaId: PODA, ordenEnCategoria: 1 },
        { id: 11, descripcion: "Poda B", operarioId: "op-T", duracion: 60, categoriaId: PODA, ordenEnCategoria: 2 },
        { id: 12, descripcion: "Jardineria B", operarioId: "op-T", duracion: 60, categoriaId: JARDINERIA },
        { id: 13, descripcion: "Mantenimiento C", operarioId: "op-T", duracion: 60, categoriaId: BASICO },
        { id: 20, descripcion: "Turno salvamento", operarioId: "op-S", duracion: 120, categoriaId: SALVAMENTO },
      ],
    });
    const fechas = ["Poda A", "Poda B", "Jardineria B", "Mantenimiento C"].map((d) =>
      fechaClave(tareaPorDesc(prisma, d).fechaInicio),
    );
    expect(fechas.filter((f) => f === "2026-03-02")).toHaveLength(2); // caben 2 el lunes objetivo
    expect(fechas.filter((f) => f === "2026-03-09")).toHaveLength(2); // el resto, el lunes siguiente
    expect(prisma.excluidasCreadas.filter((e: any) => e.estado === "PENDIENTE")).toHaveLength(0);
  });

  test("un perfil inactivo, una plaza vacante o un perfil sin la categoría nunca reciben la tarea", async () => {
    const base = [
      ...RELLENO_TODERO,
      { id: 10, descripcion: "Poda A", operarioId: "op-T", duracion: 60, categoriaId: PODA } as DefFake,
    ];
    for (const alternativa of [
      { ...TODERO_SALVAVIDAS, perfilActivo: false },
      { ...TODERO_SALVAVIDAS, operarioId: null },
      { ...TODERO_SALVAVIDAS, categorias: [JARDINERIA, BASICO, SALVAMENTO] },
      { ...TODERO_SALVAVIDAS, categorias: [] },
    ] as PlazaFake[]) {
      const { prisma } = await generar({ plazas: [TODERO, alternativa], defs: base });
      expect(tareaPorDesc(prisma, "Poda A")).toBeUndefined();
      expect(excluidaPorDesc(prisma, "Poda A")).toBeDefined();
      expect(prisma.tareasCreadas.some((t: any) => t.reasignadaAutomaticamente)).toBe(false);
    }
  });

  test("dos perfiles compatibles: toma el que deja la tarea más cerca de su fecha y, a igual cercanía, el menos cargado", async () => {
    const otro: PlazaFake = {
      id: 3,
      orden: 3,
      etiqueta: "Todero #2",
      operarioId: "op-U",
      categorias: [PODA],
      lunes: ["07:00", "11:00"],
    };
    // op-S ya tiene 120 min el lunes 2; op-U está libre => igual cercanía (lunes 2), gana op-U.
    const { prisma } = await generar({
      plazas: [TODERO, TODERO_SALVAVIDAS, otro],
      defs: [
        ...RELLENO_TODERO,
        { id: 10, descripcion: "Poda A", operarioId: "op-T", duracion: 60, categoriaId: PODA },
        { id: 20, descripcion: "Turno salvamento", operarioId: "op-S", duracion: 120, categoriaId: SALVAMENTO },
      ],
    });
    expect(tareaPorDesc(prisma, "Poda A").operarios).toEqual([{ id: "op-U" }]);
  });

  test("las cuadrillas, las tareas de varios días y las definiciones sin categoría no se reasignan", async () => {
    const { prisma } = await generar({
      plazas: [TODERO, TODERO_SALVAVIDAS],
      defs: [
        ...RELLENO_TODERO,
        { id: 10, descripcion: "Cuadrilla", operarioId: "op-T", operarioExtraId: "op-S", duracion: 600, categoriaId: PODA },
        { id: 11, descripcion: "Multidia", operarioId: "op-T", duracion: 60, categoriaId: PODA, diasParaCompletar: 2 },
        { id: 12, descripcion: "Sin categoria", operarioId: "op-T", duracion: 60, categoriaId: null },
      ],
    });
    expect(prisma.tareasCreadas.some((t: any) => t.reasignadaAutomaticamente)).toBe(false);
    expect(prisma.tareasCreadas.some((t: any) => t.descripcion === "Sin categoria")).toBe(false);
  });

  test("sin capacidades configuradas el generador se comporta como antes (nada se reasigna)", async () => {
    const { prisma } = await generar({
      plazas: [TODERO, { ...TODERO_SALVAVIDAS, categorias: [] }],
      defs: [
        ...RELLENO_TODERO,
        { id: 10, descripcion: "Poda A", operarioId: "op-T", duracion: 60, categoriaId: PODA },
      ],
    });
    // TODERO sí tiene capacidades pero no hay alternativa => excluida real
    expect(excluidaPorDesc(prisma, "Poda A")).toBeDefined();
  });

  test("regenerar es determinista: dos corridas idénticas producen el mismo cronograma", async () => {
    const opts = {
      plazas: [TODERO, TODERO_SALVAVIDAS],
      defs: [
        ...RELLENO_TODERO,
        { id: 10, descripcion: "Poda A", operarioId: "op-T", duracion: 60, categoriaId: PODA, ordenEnCategoria: 1 },
        { id: 11, descripcion: "Poda B", operarioId: "op-T", duracion: 60, categoriaId: PODA, ordenEnCategoria: 2 },
        { id: 12, descripcion: "Jardineria B", operarioId: "op-T", duracion: 60, categoriaId: JARDINERIA },
        { id: 13, descripcion: "Mantenimiento C", operarioId: "op-T", duracion: 60, categoriaId: BASICO },
        { id: 20, descripcion: "Turno salvamento", operarioId: "op-S", duracion: 120, categoriaId: SALVAMENTO },
      ],
    } as { defs: DefFake[]; plazas: PlazaFake[] };
    const resumen = (prisma: any) =>
      prisma.tareasCreadas
        .map((t: any) => `${t.descripcion}|${t.operarios.map((o: any) => o.id).join(",")}|${t.fechaInicio.toISOString()}|${t.fechaFin.toISOString()}`)
        .sort();
    const a = await generar(opts);
    const b = await generar(opts);
    expect(resumen(a.prisma)).toEqual(resumen(b.prisma));
    expect(a.prisma.excluidasCreadas.map((e: any) => `${e.descripcion}|${e.estado}`).sort()).toEqual(
      b.prisma.excluidasCreadas.map((e: any) => `${e.descripcion}|${e.estado}`).sort(),
    );
  });

  test("la prioridad de selección sigue mandando: P1 entra antes que P3 y la categoría no cambia qué entra", async () => {
    // Solo hay espacio para 5 de 120 min en el Todero (5 lunes de 120).
    const defs: DefFake[] = [
      // P3 con categoría "primera" (Piscinas): NO debe desplazar a las P1.
      { id: 1, descripcion: "P3 piscinas", operarioId: "op-T", duracion: 120, categoriaId: PISCINAS, prioridad: 3 },
      ...[2, 3, 4, 5, 6].map((id) => ({
        id,
        descripcion: `P1 aseo ${id}`,
        operarioId: "op-T",
        duracion: 120,
        categoriaId: ASEO,
        prioridad: 1,
      })),
    ];
    const { prisma } = await generar({ plazas: [TODERO], defs });
    const programadas = prisma.tareasCreadas.map((t: any) => t.descripcion);
    expect(programadas.filter((d: string) => d.startsWith("P1"))).toHaveLength(5);
    expect(programadas).not.toContain("P3 piscinas");
  });
});
