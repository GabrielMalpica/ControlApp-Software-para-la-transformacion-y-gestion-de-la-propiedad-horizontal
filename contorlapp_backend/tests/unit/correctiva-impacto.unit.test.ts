// Programar una correctiva (actividad especial) encima de la agenda publicada:
// - calcularImpactoCorrectiva: qué se reemplaza, qué lo impide y qué huecos
//   quedan, con uno o varios operarios.
// - POST /gerente/tareas/reemplazo/impacto (previsualización) y
//   POST /gerente/tareas/reemplazo: antes fallaban con "no liberan
//   completamente el horario" cuando la actividad pisaba varias tareas, varios
//   operarios o un borrador, y el límite semanal contaba las horas que se
//   reemplazaban.

const validarLimiteSemanalMock = jest.fn();
const obtenerIntervalosMock = jest.fn();

jest.mock('../../src/utils/operarioAvailability', () => ({
  ...jest.requireActual('../../src/utils/operarioAvailability'),
  validarOperariosDisponiblesEnFecha: jest.fn(async () => ({ ok: true, noDisponibles: [] })),
  validarLimiteSemanalOperarios: (...args: unknown[]) => validarLimiteSemanalMock(...args),
  obtenerIntervalosEfectivosProgramacion: (...args: unknown[]) => obtenerIntervalosMock(...args),
}));

const reservarRecursosMock = jest.fn();
jest.mock('../../src/services/ReservaRecursoService', () => ({
  ...jest.requireActual('../../src/services/ReservaRecursoService'),
  reservarRecursosDeTareaManual: (...args: unknown[]) => reservarRecursosMock(...args),
  aplicarCambioTareaEnRecursos: jest.fn(async () => undefined),
}));

jest.mock('../../src/services/AuditoriaService', () => ({
  AuditoriaService: jest.fn().mockImplementation(() => ({
    registrar: jest.fn(async () => undefined),
    registrarLote: jest.fn(async () => undefined),
    registrarEstricto: jest.fn(async () => undefined),
  })),
}));

jest.mock('../../src/services/NotificacionService', () => ({
  NotificacionService: jest.fn().mockImplementation(() => ({
    notificarAsignacionTareaOperarios: jest.fn(async () => undefined),
  })),
}));

jest.mock('../../src/db/prisma', () => ({ prisma: {} }));

import {
  buscarHuecoLibreDia,
  calcularImpactoCorrectiva,
  type TareaAgendaImpacto,
} from '../../src/utils/impactoCorrectiva';
import { GerenteService } from '../../src/services/GerenteServices';

// Miércoles 28 de octubre de 2026, hora local.
const h = (hora: number, minuto = 0) => new Date(2026, 9, 28, hora, minuto);

const PEDRO = { id: 'op-1', nombre: 'Pedro' };
const ANA = { id: 'op-2', nombre: 'Ana' };
const LUIS = { id: 'op-3', nombre: 'Luis' };

function tarea(
  id: number,
  inicio: Date,
  fin: Date,
  operarios: Array<{ id: string; nombre: string }>,
  extra: Partial<TareaAgendaImpacto> = {},
): TareaAgendaImpacto {
  return {
    id,
    descripcion: `Tarea ${id}`,
    tipo: 'PREVENTIVA',
    estado: 'ASIGNADA',
    prioridad: 2,
    fechaInicio: inicio,
    fechaFin: fin,
    operarios,
    ...extra,
  };
}

describe('calcularImpactoCorrectiva', () => {
  test('sin tareas a esa hora queda libre y no reemplaza nada', () => {
    const r = calcularImpactoCorrectiva({
      inicio: h(9),
      fin: h(10),
      prioridad: 2,
      operarios: [PEDRO],
      tareas: [tarea(1, h(8), h(9), [PEDRO]), tarea(2, h(10), h(11), [PEDRO])],
    });
    expect(r).toMatchObject({ libre: true, puedeProgramar: true, reemplazarIds: [], bloqueos: [] });
    expect(r.operarios).toEqual([
      expect.objectContaining({ operarioId: 'op-1', huecos: [], minutosHueco: 0 }),
    ]);
  });

  test('una actividad de 60 min sobre tres tareas de 30 min reemplaza las tres y muestra los huecos', () => {
    const r = calcularImpactoCorrectiva({
      inicio: h(9, 15),
      fin: h(10, 15),
      prioridad: 2,
      operarios: [PEDRO],
      tareas: [
        tarea(1, h(9), h(9, 30), [PEDRO]),
        tarea(2, h(9, 30), h(10), [PEDRO]),
        tarea(3, h(10), h(10, 30), [PEDRO]),
        tarea(4, h(10, 30), h(11), [PEDRO]),
      ],
    });
    expect(r.libre).toBe(false);
    expect(r.puedeProgramar).toBe(true);
    expect(r.reemplazarIds).toEqual([1, 2, 3]);
    const pedro = r.operarios[0];
    expect(pedro.minutosReemplazados).toBe(90);
    expect(pedro.huecos.map((x) => [x.fechaInicio.getHours(), x.fechaInicio.getMinutes(), x.minutos])).toEqual([
      [9, 0, 15],
      [10, 15, 15],
    ]);
    expect(pedro.huecoGrande).toBe(false);
  });

  test('con varios operarios reemplaza las tareas de todos y detalla cada uno', () => {
    const r = calcularImpactoCorrectiva({
      inicio: h(9),
      fin: h(10),
      prioridad: 1,
      operarios: [PEDRO, ANA],
      tareas: [
        tarea(1, h(9), h(9, 30), [PEDRO], { prioridad: 3 }),
        tarea(2, h(9, 30), h(10), [PEDRO], { prioridad: 1 }),
        tarea(3, h(8, 30), h(10, 30), [ANA]),
        tarea(4, h(9), h(10), [LUIS]), // de otra persona: no se toca
      ],
    });
    expect(r.reemplazarIds.sort()).toEqual([1, 2, 3]);
    expect(r.reemplazos.find((x) => x.tareaId === 1)?.tipoConfirmacion).toBe('AUTO');
    expect(r.reemplazos.find((x) => x.tareaId === 2)?.tipoConfirmacion).toBe('CONFIRM_DANGER');
    expect(r.reemplazos.find((x) => x.tareaId === 3)?.tipoConfirmacion).toBe('CONFIRM_WARN');
    expect(r.prioridadMasAltaReemplazada).toBe(1);
    expect(r.operarios.map((o) => o.operarioId)).toEqual(['op-1', 'op-2']);
    const ana = r.operarios[1];
    // La poda de Ana dura 2 h y la actividad cubre 1: le quedan 30 + 30 min.
    expect(ana.huecos.map((x) => x.minutos)).toEqual([30, 30]);
    expect(ana.minutosHueco).toBe(60);
  });

  test('una tarea compartida se cancela también para quien no está en la actividad (hueco grande)', () => {
    const r = calcularImpactoCorrectiva({
      inicio: h(9),
      fin: h(10),
      prioridad: 2,
      operarios: [PEDRO],
      tareas: [tarea(1, h(8, 30), h(10, 30), [PEDRO, LUIS])],
    });
    expect(r.reemplazarIds).toEqual([1]);
    const luis = r.operarios.find((o) => o.operarioId === 'op-3')!;
    expect(luis.enLaActividad).toBe(false);
    expect(luis.minutosHueco).toBe(120);
    expect(luis.huecoGrande).toBe(true);
    expect(r.hayHuecoGrande).toBe(true);
    expect(r.reemplazos[0].operarios).toEqual([
      { id: 'op-1', nombre: 'Pedro', enLaActividad: true },
      { id: 'op-3', nombre: 'Luis', enLaActividad: false },
    ]);
  });

  test('otra correctiva o una preventiva de prioridad más alta lo impiden, con el motivo', () => {
    const r = calcularImpactoCorrectiva({
      inicio: h(9),
      fin: h(10),
      prioridad: 2,
      operarios: [PEDRO, ANA],
      tareas: [
        tarea(1, h(9), h(10), [PEDRO], { tipo: 'CORRECTIVA', descripcion: 'Fuga' }),
        tarea(2, h(9), h(10), [ANA], { prioridad: 1, descripcion: 'Piscina' }),
      ],
    });
    expect(r.puedeProgramar).toBe(false);
    expect(r.reemplazarIds).toEqual([]);
    expect(r.bloqueos.map((b) => [b.tareaId, b.motivo])).toEqual([
      [1, 'NO_ES_PREVENTIVA'],
      [2, 'PRIORIDAD'],
    ]);
    expect(r.bloqueos[1].mensaje).toContain('P2, P3');
  });

  test('las tareas cerradas o canceladas no ocupan la agenda', () => {
    const r = calcularImpactoCorrectiva({
      inicio: h(9),
      fin: h(10),
      prioridad: 3,
      operarios: [PEDRO],
      tareas: [
        tarea(1, h(9), h(10), [PEDRO], { estado: 'COMPLETADA' }),
        tarea(2, h(9), h(10), [PEDRO], { estado: 'NO_COMPLETADA' }),
      ],
    });
    expect(r.libre).toBe(true);
  });

  test('las tareas repetidas en la entrada se cuentan una vez', () => {
    const t = tarea(1, h(9), h(10), [PEDRO]);
    const r = calcularImpactoCorrectiva({
      inicio: h(9),
      fin: h(10),
      prioridad: 2,
      operarios: [PEDRO],
      tareas: [t, { ...t }],
    });
    expect(r.reemplazarIds).toEqual([1]);
  });
});

describe('buscarHuecoLibreDia', () => {
  const ventanas = [
    { i: 7 * 60, f: 12 * 60 },
    { i: 13 * 60, f: 16 * 60 },
  ];

  test('el primer hueco desde la hora pedida donde cabe completa', () => {
    expect(
      buscarHuecoLibreDia({
        ventanas,
        ocupados: [
          { i: 7 * 60, f: 9 * 60 },
          { i: 9 * 60 + 30, f: 11 * 60 },
        ],
        duracionMin: 60,
        desdeMin: 8 * 60,
      }),
    ).toBe(11 * 60);
  });

  test('no cruza el almuerzo y busca en la tarde', () => {
    expect(
      buscarHuecoLibreDia({ ventanas, ocupados: [{ i: 7 * 60, f: 11 * 60 + 30 }], duracionMin: 60, desdeMin: 7 * 60 }),
    ).toBe(13 * 60);
  });

  test('si no hay después de la hora pedida, busca más temprano', () => {
    expect(
      buscarHuecoLibreDia({ ventanas, ocupados: [{ i: 13 * 60, f: 16 * 60 }], duracionMin: 60, desdeMin: 14 * 60 }),
    ).toBe(7 * 60);
  });

  test('sin espacio en el día no sugiere nada', () => {
    expect(
      buscarHuecoLibreDia({ ventanas, ocupados: [{ i: 7 * 60, f: 16 * 60 }], duracionMin: 30, desdeMin: 7 * 60 }),
    ).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Servicio con una base en memoria (solo las consultas que hace este flujo).

type Fila = {
  id: number;
  descripcion: string;
  tipo: string;
  estado: string;
  prioridad: number;
  borrador: boolean;
  conjuntoId: string;
  fechaInicio: Date;
  fechaFin: Date;
  duracionMinutos: number;
  fechaInicioOriginal: Date | null;
  fechaFinOriginal: Date | null;
  operarios: Array<{ id: string; usuario: { nombre: string } }>;
};

let TAREAS: Fila[] = [];
const NOMBRES: Record<string, string> = { 'op-1': 'Pedro', 'op-2': 'Ana', 'op-3': 'Luis' };

function fila(
  id: number,
  inicio: Date,
  fin: Date,
  operarios: string[],
  extra: Partial<Fila> = {},
): Fila {
  return {
    id,
    descripcion: `Tarea ${id}`,
    tipo: 'PREVENTIVA',
    estado: 'ASIGNADA',
    prioridad: 2,
    borrador: false,
    conjuntoId: 'c1',
    fechaInicio: inicio,
    fechaFin: fin,
    duracionMinutos: Math.round((fin.getTime() - inicio.getTime()) / 60000),
    fechaInicioOriginal: null,
    fechaFinOriginal: null,
    operarios: operarios.map((id) => ({ id, usuario: { nombre: NOMBRES[id] } })),
    ...extra,
  };
}

function cumpleCampo(valor: any, condicion: any): boolean {
  if (condicion && typeof condicion === 'object' && !(condicion instanceof Date)) {
    if ('in' in condicion) return condicion.in.includes(valor);
    if ('notIn' in condicion) return !condicion.notIn.includes(valor);
    if ('lt' in condicion) return valor < condicion.lt;
    if ('gt' in condicion) return valor > condicion.gt;
    if ('not' in condicion) return valor !== condicion.not;
  }
  return valor === condicion;
}

function cumple(t: Fila, where: any): boolean {
  return Object.entries(where ?? {}).every(([campo, cond]: [string, any]) => {
    if (campo === 'AND') return (cond as any[]).every((w) => cumple(t, w));
    if (campo === 'operarios') return t.operarios.some((o) => cond.some.id.in.includes(o.id));
    if (campo === 'fechaInicio' || campo === 'fechaFin') {
      const v = (t as any)[campo].getTime();
      if (cond.lt) return v < cond.lt.getTime();
      if (cond.gt) return v > cond.gt.getTime();
    }
    return cumpleCampo((t as any)[campo], cond);
  });
}

const creadas: any[] = [];
const prismaMock: any = {
  tarea: {
    findMany: jest.fn(async ({ where }: any) => TAREAS.filter((t) => cumple(t, where))),
    findFirst: jest.fn(async ({ where }: any) => TAREAS.find((t) => cumple(t, where)) ?? null),
    create: jest.fn(async ({ data }: any) => {
      creadas.push(data);
      return { id: 900 + creadas.length };
    }),
    update: jest.fn(async ({ where, data }: any) => {
      const t = TAREAS.find((x) => x.id === where.id)!;
      const { operarios, ubicacion, elemento, conjunto, supervisor, ...resto } = data;
      Object.assign(t, resto);
      if (operarios?.set) {
        t.operarios = operarios.set.map((o: { id: string }) => ({
          id: o.id,
          usuario: { nombre: NOMBRES[o.id] },
        }));
      }
      return t;
    }),
    updateMany: jest.fn(async () => ({ count: 0 })),
  },
  conjunto: { findUnique: jest.fn(async () => ({ empresaId: 'emp-1' })) },
  operario: {
    findMany: jest.fn(async ({ where }: any) =>
      (where.id.in as string[]).map((id) => ({ id, usuario: { nombre: NOMBRES[id] } })),
    ),
  },
  // isFestivoDate: ningún día es festivo.
  $queryRaw: jest.fn(async () => []),
  $transaction: jest.fn(async (cb: any) => cb(prismaMock)),
};

const svc = () => new GerenteService(prismaMock);

function correctiva(extra: Record<string, unknown> = {}) {
  return {
    descripcion: 'Reparar bomba',
    tipo: 'CORRECTIVA',
    prioridad: 2,
    fechaInicio: h(9).toISOString(),
    fechaFin: h(10).toISOString(),
    duracionMinutos: 60,
    conjuntoId: 'c1',
    ubicacionId: 10,
    elementoId: 20,
    operariosIds: ['op-1'],
    ...extra,
  };
}

beforeEach(() => {
  TAREAS = [];
  creadas.length = 0;
  jest.clearAllMocks();
  validarLimiteSemanalMock.mockResolvedValue({ ok: true, excedidos: [], detalle: [] });
  reservarRecursosMock.mockResolvedValue({ reservas: 0, necesidades: 0 });
  obtenerIntervalosMock.mockResolvedValue({
    dia: 'MIERCOLES',
    horario: null,
    intervalosConjunto: [
      { i: 7 * 60, f: 12 * 60 },
      { i: 13 * 60, f: 16 * 60 },
    ],
    intervalosEfectivos: [
      { i: 7 * 60, f: 12 * 60 },
      { i: 13 * 60, f: 16 * 60 },
    ],
    operariosSinConfiguracion: [],
    operariosEnDescanso: [],
  });
});

describe('previsualizarImpactoCorrectiva', () => {
  test('lista las tareas de todos los operarios a reemplazar, ignora borradores y sugiere hueco libre', async () => {
    TAREAS = [
      fila(1, h(9), h(9, 30), ['op-1'], { prioridad: 3 }),
      fila(2, h(9, 30), h(10), ['op-1']),
      fila(3, h(8, 30), h(10, 30), ['op-2']),
      fila(4, h(9), h(10), ['op-1'], { borrador: true }), // borrador: no ocupa
      fila(5, h(10), h(11), ['op-1']),
    ];
    const r = await svc().previsualizarImpactoCorrectiva({
      tarea: correctiva({ operariosIds: ['op-1', 'op-2'] }),
    });
    expect(r.ok).toBe(true);
    expect(r.puedeProgramar).toBe(true);
    expect(r.reemplazarIds.sort()).toEqual([1, 2, 3]);
    expect(r.operarios.map((o: any) => o.nombre)).toEqual(['Pedro', 'Ana']);
    // El límite semanal ya no cuenta las horas que se liberan.
    expect(validarLimiteSemanalMock).toHaveBeenCalledWith(
      expect.objectContaining({ excluirTareaIds: expect.arrayContaining([1, 2, 3]) }),
    );
    // Libre para los dos: Pedro termina a las 11 y Ana a las 10:30.
    expect(r.sugerencia.fechaInicio.getHours()).toBe(11);
  });

  test('el límite semanal bloquea con el nombre del operario y sus horas', async () => {
    validarLimiteSemanalMock.mockResolvedValue({
      ok: false,
      excedidos: ['op-1'],
      detalle: [{ operarioId: 'op-1', capacidadMinutos: 42 * 60, usadosMinutos: 41 * 60 + 30 }],
    });
    const r = await svc().previsualizarImpactoCorrectiva({ tarea: correctiva() });
    expect(r.puedeProgramar).toBe(false);
    expect(r.bloqueosGenerales).toEqual([
      expect.objectContaining({
        codigo: 'LIMITE_SEMANAL_SUPERADO',
        mensaje: expect.stringContaining('Pedro ya tiene 41 h 30 min de 42 h'),
      }),
    ]);
  });

  test('una máquina ocupada se avisa antes de confirmar (la reserva se prueba y se deshace)', async () => {
    TAREAS = [fila(1, h(9), h(10), ['op-1'])];
    reservarRecursosMock.mockRejectedValue({
      status: 409,
      reason: 'RECURSO_OCUPADO',
      message: 'GUA-01 ya está reservada para "Corte de prado" de 09:00 a 10:00.',
    });
    const svcConEmpresa = new GerenteService(prismaMock, 'emp-1');
    jest.spyOn(svcConEmpresa as any, 'exigirAltaDeTareaEnAlcance').mockResolvedValue(undefined);
    jest.spyOn(svcConEmpresa as any, 'resolverEmpresaNit').mockResolvedValue('emp-1');

    const r = await svcConEmpresa.previsualizarImpactoCorrectiva({
      tarea: correctiva({ maquinariaIds: [7] }),
    });
    expect(r.puedeProgramar).toBe(false);
    expect(r.bloqueosGenerales).toEqual([
      { codigo: 'RECURSO_OCUPADO', mensaje: expect.stringContaining('GUA-01') },
    ]);
    // La prueba cancela primero la preventiva a reemplazar (libera su reserva).
    expect(prismaMock.tarea.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: { in: [1] }, conjuntoId: 'c1' } }),
    );
    // Con la reserva libre, la prueba se deshace y no bloquea.
    reservarRecursosMock.mockResolvedValue({ reservas: 1, necesidades: 1 });
    const libre = await svcConEmpresa.previsualizarImpactoCorrectiva({
      tarea: correctiva({ maquinariaIds: [7] }),
    });
    expect(libre.puedeProgramar).toBe(true);
    expect(libre.bloqueosGenerales).toEqual([]);
  });

  test('fuera de la jornada es un aviso, no un bloqueo', async () => {
    const r = await svc().previsualizarImpactoCorrectiva({
      tarea: correctiva({ fechaInicio: h(17).toISOString(), fechaFin: h(18).toISOString() }),
    });
    expect(r.libre).toBe(true);
    expect(r.puedeProgramar).toBe(true);
    expect(r.avisos.map((a: any) => a.codigo)).toEqual(['FUERA_HORARIO_CONJUNTO']);
  });
});

describe('POST /gerente/tareas/reemplazo con varias tareas y operarios', () => {
  test('reemplaza todas las tareas que ocupaban el horario aunque un borrador coincida', async () => {
    TAREAS = [
      fila(1, h(9), h(9, 30), ['op-1']),
      fila(2, h(9, 30), h(10), ['op-1']),
      fila(3, h(8, 30), h(10, 30), ['op-2']),
      fila(4, h(9), h(10), ['op-2'], { borrador: true }),
    ];
    const r = await svc().asignarTareaConReemplazoV2({
      tarea: correctiva({ operariosIds: ['op-1', 'op-2'] }),
      reemplazarIds: [1, 2, 3],
      accionReemplazadas: 'CANCELAR',
    });
    expect(r).toMatchObject({ ok: true, canceladasIds: [1, 2, 3] });
    expect(TAREAS.filter((t) => [1, 2, 3].includes(t.id)).map((t) => t.estado)).toEqual([
      'NO_COMPLETADA',
      'NO_COMPLETADA',
      'NO_COMPLETADA',
    ]);
    expect(TAREAS.find((t) => t.id === 4)?.estado).toBe('ASIGNADA');
    expect(validarLimiteSemanalMock).toHaveBeenCalledWith(
      expect.objectContaining({ excluirTareaIds: [1, 2, 3] }),
    );
  });

  test('si falta una tarea por reemplazar dice cuál y no crea nada', async () => {
    TAREAS = [fila(1, h(9), h(9, 30), ['op-1']), fila(2, h(9, 30), h(10), ['op-1'], { descripcion: 'Vidrios' })];
    const r = await svc().asignarTareaConReemplazoV2({
      tarea: correctiva(),
      reemplazarIds: [1],
      accionReemplazadas: 'CANCELAR',
    });
    expect(r).toMatchObject({
      ok: false,
      reason: 'REEMPLAZOS_NO_LIBERAN_ESPACIO',
      conflictosRestantes: [expect.objectContaining({ id: 2 })],
    });
    expect(r.message).toContain('Vidrios');
    expect(creadas).toHaveLength(0);
  });

  test('un motivo muy corto responde en español', async () => {
    const r = await svc().asignarTareaConReemplazoV2({
      tarea: correctiva(),
      reemplazarIds: [1],
      motivoReemplazo: 'ok',
    });
    expect(r).toMatchObject({ ok: false, message: 'El motivo del reemplazo debe tener al menos 3 caracteres.' });
  });
});

describe('editar una especial ya programada', () => {
  const especial = () =>
    fila(50, h(9), h(10), ['op-1', 'op-2'], { tipo: 'CORRECTIVA', descripcion: 'Reparar bomba' });

  test('alargarla revisa solo las otras tareas y al guardar reemplaza las que ahora pisa', async () => {
    TAREAS = [
      especial(),
      fila(51, h(10), h(10, 30), ['op-1'], { prioridad: 3 }),
      fila(52, h(10, 30), h(11), ['op-1'], { descripcion: 'Vidrios' }),
      fila(53, h(10), h(11), ['op-3']),
    ];
    const r = await svc().previsualizarImpactoCorrectiva({
      tareaId: 50,
      tarea: correctiva({
        fechaFin: h(11).toISOString(),
        duracionMinutos: 120,
        operariosIds: ['op-1', 'op-2'],
      }),
    });
    expect(r.reemplazarIds.sort()).toEqual([51, 52]);
    expect(r.bloqueos).toEqual([]);
    expect(validarLimiteSemanalMock).toHaveBeenCalledWith(
      expect.objectContaining({ excluirTareaIds: expect.arrayContaining([50, 51, 52]) }),
    );

    // Sin decir qué se reemplaza, la edición explica con qué choca.
    const sin = await svc().editarTarea(50, {
      fechaInicio: h(9).toISOString(),
      fechaFin: h(11).toISOString(),
      duracionMinutos: 120,
    });
    expect(sin).toMatchObject({ ok: false, reason: 'HAY_SOLAPE_CON_TAREAS_EXISTENTES' });
    expect(sin.message).toContain('Tarea 51');

    const ok = await svc().editarTarea(50, {
      fechaInicio: h(9).toISOString(),
      fechaFin: h(11).toISOString(),
      duracionMinutos: 120,
      reemplazarIds: r.reemplazarIds,
      motivoReemplazo: 'Se demoró la reparación',
    });
    expect(ok).toMatchObject({ ok: true, reemplazadasIds: [51, 52] });
    const t = (id: number) => TAREAS.find((x) => x.id === id)!;
    expect([t(51).estado, t(52).estado]).toEqual(['NO_COMPLETADA', 'NO_COMPLETADA']);
    expect((t(52) as any).reprogramadaPorTareaId).toBe(50);
    expect((t(52) as any).reprogramadaMotivo).toContain('Se demoró la reparación');
    expect(t(50).duracionMinutos).toBe(120);
    expect(t(53).estado).toBe('ASIGNADA');
  });

  test('quitarle un operario se guarda sin más', async () => {
    TAREAS = [especial(), fila(51, h(9), h(10), ['op-3'])];
    const r = await svc().editarTarea(50, { operariosIds: ['op-1'] });
    expect(r.ok).toBe(true);
    expect(TAREAS[0].operarios.map((o) => o.id)).toEqual(['op-1']);
  });

  test('no reemplaza una preventiva de prioridad más alta aunque llegue la id', async () => {
    TAREAS = [especial(), fila(51, h(10), h(11), ['op-1'], { prioridad: 1 })];
    const r = await svc().editarTarea(50, {
      fechaFin: h(11).toISOString(),
      duracionMinutos: 120,
      reemplazarIds: [51],
    });
    expect(r).toMatchObject({ ok: false, reason: 'REEMPLAZO_NO_VALIDO' });
    expect(TAREAS[1].estado).toBe('ASIGNADA');
  });
});
