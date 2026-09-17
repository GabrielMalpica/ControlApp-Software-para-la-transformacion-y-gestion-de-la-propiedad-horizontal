import { DiaSemana, Frecuencia } from "@prisma/client";

// Mismo patrón que scheduler-rescate.unit.test.ts: se neutraliza solo la
// consulta de festivos (va por SQL crudo), el resto de schedulerUtils real.
jest.mock("../../src/utils/schedulerUtils", () => {
  const real = jest.requireActual("../../src/utils/schedulerUtils");
  return {
    ...real,
    getFestivosSet: jest.fn().mockResolvedValue(new Set<string>()),
  };
});

import { DefinicionTareaPreventivaService } from "../../src/services/DefinicionTareaPreventivaService";

const CONJUNTO = "C-NEC";
const DIAS_LABORALES = [
  DiaSemana.LUNES,
  DiaSemana.MARTES,
  DiaSemana.MIERCOLES,
  DiaSemana.JUEVES,
  DiaSemana.VIERNES,
];

/**
 * Prisma falso equivalente al de scheduler-rescate.unit.test.ts, extendido
 * con `conjuntoNecesidadOperario` para poder probar el flujo completo de
 * generarBorradorMensual cuando la definición resuelve por necesidad/plaza
 * en vez de por operarios directos.
 */
function construirPrisma(opts: {
  necesidades: Array<{
    id: number;
    operarioId: string | null;
    horarioEspecial: boolean;
    horarios: Array<{ dia: DiaSemana; horaApertura: string; horaCierre: string }>;
  }>;
  operarioTrabajaDomingo?: boolean;
  frecuencia: Frecuencia;
  diaMesProgramado?: number;
  diaSemanaProgramado?: DiaSemana;
  duracionMinutosFija: number;
  prioridad: number;
}) {
  const tareasCreadas: any[] = [];
  const excluidasCreadas: any[] = [];
  const eventos: any[] = [];
  let secuencia = 1000;

  const defBase = {
    id: 77,
    conjuntoId: CONJUNTO,
    descripcion: "Turno salvavidas",
    frecuencia: opts.frecuencia,
    diaSemanaProgramado: opts.diaSemanaProgramado ?? null,
    diaMesProgramado: opts.diaMesProgramado ?? null,
    prioridad: opts.prioridad,
    duracionMinutosFija: opts.duracionMinutosFija,
    diasParaCompletar: 1,
    ubicacionId: 1,
    elementoId: 2,
    supervisorId: null,
    insumosPlanJson: null,
    maquinariaPlanJson: null,
    herramientasPlanJson: null,
    creadoEn: new Date(2026, 0, 1),
    operarios: [], // Sin operarios directos: la definición SOLO tiene necesidades.
    necesidades: opts.necesidades.map((n) => ({
      id: n.id,
      operarioId: n.operarioId,
      operario: n.operarioId
        ? { id: n.operarioId, usuario: { nombre: "Carlos" } }
        : null,
    })),
    supervisor: null,
  };

  const prisma: any = {
    tareasCreadas,
    excluidasCreadas,
    eventos,

    definicionTareaPreventiva: {
      findMany: jest.fn().mockResolvedValue([defBase]),
      findUnique: jest.fn().mockResolvedValue(null),
      findFirst: jest.fn().mockResolvedValue(defBase),
    },

    conjuntoHorario: {
      // El conjunto SOLO tiene horario L-V: nunca hay fila para sábado/domingo.
      findMany: jest.fn().mockResolvedValue(
        DIAS_LABORALES.map((dia) => ({
          dia,
          horaApertura: "07:00",
          horaCierre: "16:00",
          descansoInicio: null,
          descansoFin: null,
        })),
      ),
      findFirst: jest.fn(async ({ where }: any) =>
        DIAS_LABORALES.includes(where.dia)
          ? { horaApertura: "07:00", horaCierre: "16:00", descansoInicio: null, descansoFin: null }
          : null,
      ),
      findUnique: jest.fn(async ({ where }: any) =>
        DIAS_LABORALES.includes(where.conjuntoId_dia.dia)
          ? { horaApertura: "07:00", horaCierre: "16:00", descansoInicio: null, descansoFin: null }
          : null,
      ),
    },

    conjuntoNecesidadOperario: {
      findMany: jest.fn(async ({ where, select }: any) => {
        const ids: string[] = where.operarioId?.in ?? [];
        const diaFiltro = select?.horarios?.where?.dia;
        return opts.necesidades
          .filter((n) => n.operarioId && ids.includes(n.operarioId))
          .map((n) => ({
            operarioId: n.operarioId,
            horarioEspecial: n.horarioEspecial,
            horarios: n.horarios
              .filter((h) => h.dia === diaFiltro)
              .map((h) => ({
                horaApertura: h.horaApertura,
                horaCierre: h.horaCierre,
                descansoInicio: null,
                descansoFin: null,
              })),
          }));
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
        const enRango = tareasCreadas.filter(
          (t) => (!hasta || t.fechaInicio <= hasta) && t.fechaFin >= desde,
        );
        return enRango.filter(
          (t: any) => !where?.prioridad?.in || where.prioridad.in.includes(t.prioridad),
        );
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
    },

    preventivaExcluidaBorrador: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      create: jest.fn(async ({ data }: any) => {
        const creada = { ...data, id: ++secuencia };
        excluidasCreadas.push(creada);
        return creada;
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
        return ids.map((id) => ({
          id,
          usuario: { jornadaLaboral: "COMPLETA", patronJornada: null },
        }));
      }),
      findUnique: jest.fn().mockResolvedValue({
        usuario: { jornadaLaboral: "COMPLETA", patronJornada: null },
        empresa: { limiteHorasSemana: 48 },
      }),
    },
    operarioDisponibilidadPeriodo: {
      findFirst: jest.fn().mockResolvedValue(
        opts.operarioTrabajaDomingo
          ? { trabajaDomingo: true, diaDescanso: DiaSemana.LUNES }
          : null,
      ),
    },
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

describe("generarBorradorMensual - necesidades operativas (plazas/cargos)", () => {
  test("una preventiva ligada a una plaza con horario especial se agenda un domingo aunque el conjunto no tenga horario ese día", async () => {
    // Salvavidas #1: SOLO domingo 08:00-17:00. El conjunto (L-V) no tiene
    // fila para domingo en absoluto.
    const prisma = construirPrisma({
      necesidades: [
        {
          id: 501,
          operarioId: "op-1",
          horarioEspecial: true,
          horarios: [{ dia: DiaSemana.DOMINGO, horaApertura: "08:00", horaCierre: "17:00" }],
        },
      ],
      // Sin periodo de disponibilidad (operarioTrabajaDomingo queda en
      // false/undefined): el horario especial de la plaza ya es suficiente,
      // no depende de un trabajaDomingo=true aparte.
      frecuencia: Frecuencia.MENSUAL,
      diaMesProgramado: 8, // 2026-03-08 es domingo.
      duracionMinutosFija: 120,
      prioridad: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(prisma.tareasCreadas).toHaveLength(1);

    const tarea = prisma.tareasCreadas[0];
    expect(tarea.fechaInicio.getDay()).toBe(0); // domingo
    expect(tarea.fechaInicio.getHours()).toBeGreaterThanOrEqual(8);
    expect(tarea.fechaFin.getHours()).toBeLessThanOrEqual(17);
    // Resuelto por la plaza, no por operarios directos (la definición no
    // tenía ninguno) -y el vínculo a la necesidad queda conectado.
    expect(tarea.operarios).toEqual([{ id: "op-1" }]);
    expect(tarea.necesidades).toEqual([{ id: 501 }]);
  });

  test("una plaza puede exceder el cierre del conjunto (Todero #2 hasta las 19:00 con el conjunto cerrando a las 16:00)", async () => {
    const prisma = construirPrisma({
      necesidades: [
        {
          id: 502,
          operarioId: "op-2",
          horarioEspecial: true,
          horarios: DIAS_LABORALES.map((dia) => ({
            dia,
            horaApertura: "17:00",
            horaCierre: "19:00",
          })),
        },
      ],
      frecuencia: Frecuencia.MENSUAL,
      diaMesProgramado: 2, // 2026-03-02 es lunes (día laboral del conjunto).
      duracionMinutosFija: 60,
      prioridad: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    const tarea = prisma.tareasCreadas[0];
    // 17:00-18:00: por fuera del cierre del conjunto (16:00), dentro de la
    // ventana extendida de la plaza (17:00-19:00).
    expect(tarea.fechaInicio.getHours()).toBe(17);
    expect(tarea.fechaFin.getHours()).toBe(18);
  });

  test("una necesidad vacante excluye la definición con motivo NECESIDAD_SIN_OPERARIO, sin agendar a medias", async () => {
    const prisma = construirPrisma({
      necesidades: [{ id: 503, operarioId: null, horarioEspecial: false, horarios: [] }],
      frecuencia: Frecuencia.MENSUAL,
      diaMesProgramado: 2,
      duracionMinutosFija: 60,
      prioridad: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(0);
    expect(prisma.tareasCreadas).toHaveLength(0);
    expect(prisma.excluidasCreadas).toHaveLength(1);
    expect(prisma.excluidasCreadas[0].motivoTipo).toBe("NECESIDAD_SIN_OPERARIO");
  });
});
