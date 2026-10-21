// Ids que llegan al crear o editar tareas y tope del listado de correctivas.
// - PATCH /gerente/tareas/:tareaId (y /tarea-correctiva/tareas/:id) aceptaba
//   ubicación, elemento, supervisor y operarios de otra empresa o conjunto.
// - POST /gerente/tareas (y /tareas/reemplazo) dejaba al administrador crear
//   tareas en conjuntos que no son suyos.
// - GET /tarea-correctiva/conjuntos/:nit/tareas no tenía tope de filas.

jest.mock('../../src/utils/operarioAvailability', () => ({
  ...jest.requireActual('../../src/utils/operarioAvailability'),
  validarIntervaloProgramacion: jest.fn(async () => ({ ok: true })),
  validarOperariosDisponiblesEnFecha: jest.fn(async () => ({ ok: true, noDisponibles: [] })),
  validarLimiteSemanalOperarios: jest.fn(async () => ({ ok: true, excedidos: [] })),
}));

jest.mock('../../src/services/ReservaRecursoService', () => ({
  ...jest.requireActual('../../src/services/ReservaRecursoService'),
  aplicarCambioTareaEnRecursos: jest.fn(async () => undefined),
  cancelarReservasDeTareas: jest.fn(async () => undefined),
}));

jest.mock('../../src/services/AuditoriaService', () => ({
  AuditoriaService: jest.fn().mockImplementation(() => ({
    registrar: jest.fn(async () => undefined),
    registrarEstricto: jest.fn(async () => undefined),
  })),
}));

jest.mock('../../src/services/NotificacionService', () => ({
  NotificacionService: jest.fn().mockImplementation(() => ({
    notificarAsignacionTareaOperarios: jest.fn(async () => undefined),
  })),
}));

// Dos empresas. En emp-1, c1 es de adm-1 y c2 de adm-2; c3 es de emp-2.
const CONJUNTOS = [
  { nit: 'c1', empresaId: 'emp-1', administradorId: 'adm-1' },
  { nit: 'c2', empresaId: 'emp-1', administradorId: 'adm-2' },
  { nit: 'c3', empresaId: 'emp-2', administradorId: 'adm-9' },
];
// ubicación → conjunto, elemento → ubicación
const UBICACIONES: Record<number, string> = { 10: 'c1', 11: 'c2', 12: 'c3' };
const ELEMENTOS: Record<number, number> = { 20: 10, 21: 11, 22: 12 };
const SUPERVISORES: Record<string, string> = { 'sup-1': 'emp-1', 'sup-2': 'emp-1', 'sup-x': 'emp-2' };
const OPERARIOS: Record<string, { empresaId: string; conjuntos: string[] }> = {
  'op-1': { empresaId: 'emp-1', conjuntos: ['c1'] },
  'op-2': { empresaId: 'emp-1', conjuntos: ['c2'] },
  'op-x': { empresaId: 'emp-2', conjuntos: ['c3'] },
};

type Fila = {
  id: number;
  descripcion: string;
  tipo: string;
  estado: string;
  borrador: boolean;
  prioridad: number;
  fechaInicio: Date;
  fechaFin: Date;
  duracionMinutos: number;
  ubicacionId: number;
  elementoId: number;
  observaciones: string | null;
  conjuntoId: string;
  supervisorId: string | null;
  conjunto: { nit: string; empresaId: string; administradorId: string };
  operarios: { id: string }[];
};

function fila(id: number, conjuntoId: string, extra: Partial<Fila> = {}): Fila {
  return {
    id,
    descripcion: `Tarea ${id}`,
    // Preventiva: GerenteService no aplica las reglas de agenda de correctivas.
    tipo: 'PREVENTIVA',
    estado: 'ASIGNADA',
    borrador: true,
    prioridad: 2,
    fechaInicio: new Date(Date.UTC(2026, 9, 21, 13)),
    fechaFin: new Date(Date.UTC(2026, 9, 21, 14)),
    duracionMinutos: 60,
    ubicacionId: 10,
    elementoId: 20,
    observaciones: null,
    conjuntoId,
    supervisorId: 'sup-1',
    conjunto: CONJUNTOS.find((c) => c.nit === conjuntoId)!,
    operarios: [{ id: 'op-1' }],
    ...extra,
  };
}

let TAREAS: Fila[] = [];

// Solo las formas de `where` que arman los servicios para buscar la tarea.
function cumple(t: Fila, where: any): boolean {
  return Object.entries(where ?? {}).every(([campo, valor]: [string, any]) => {
    if (campo === 'AND') return (valor as any[]).every((w) => cumple(t, w));
    if (campo === 'conjunto') {
      return Object.entries(valor).every(([k, v]) => (t.conjunto as any)[k] === v);
    }
    if (campo === 'operarios') return t.operarios.some((o) => o.id === valor.some.id);
    return (t as any)[campo] === valor;
  });
}

const mockPrisma: any = {
  tarea: {
    // Con AND es la búsqueda por alcance; sin él, la de solapes (no hay).
    findFirst: jest.fn(async ({ where }: any) =>
      where?.AND ? (TAREAS.find((t) => cumple(t, where)) ?? null) : null,
    ),
    findMany: jest.fn(async ({ where }: any) => TAREAS.filter((t) => cumple(t, where))),
    create: jest.fn(async () => ({ id: 100 })),
    update: jest.fn(async ({ where, data }: any) => {
      const t = TAREAS.find((x) => x.id === where.id)!;
      if (typeof data.descripcion === 'string') t.descripcion = data.descripcion;
      return { ...t };
    }),
  },
  conjunto: {
    findFirst: jest.fn(async ({ where }: any) => {
      const c = CONJUNTOS.find(
        (x) =>
          x.nit === where.nit &&
          (where.empresaId === undefined || x.empresaId === where.empresaId) &&
          (where.administradorId === undefined || x.administradorId === where.administradorId),
      );
      if (!c) return null;
      const lugar = where.ubicaciones?.some;
      if (lugar) {
        const ubicacionOk = UBICACIONES[lugar.id] === c.nit;
        const elementoOk = ELEMENTOS[lugar.elementos.some.id] === lugar.id;
        if (!ubicacionOk || !elementoOk) return null;
      }
      return { nit: c.nit };
    }),
  },
  supervisor: {
    findFirst: jest.fn(async ({ where }: any) =>
      SUPERVISORES[where.id] === where.empresaId ? { id: where.id } : null,
    ),
  },
  operario: {
    count: jest.fn(
      async ({ where }: any) =>
        (where.id.in as string[]).filter((id) => {
          const op = OPERARIOS[id];
          if (!op || op.empresaId !== where.empresaId) return false;
          const nit = where.conjuntos?.some?.nit;
          return nit === undefined || op.conjuntos.includes(nit);
        }).length,
    ),
  },
  usuario: { findUnique: jest.fn(async () => ({ nombre: 'Usuario de prueba' })) },
  // isFestivoDate: ningún día es festivo.
  $queryRaw: jest.fn(async () => []),
  $transaction: jest.fn(async (cb: any) => cb(mockPrisma)),
};

jest.mock('../../src/db/prisma', () => ({ prisma: mockPrisma }));
jest.mock('../../src/middlewares/tenant.middleware', () => ({
  empresaIdAutenticada: jest.fn(async () => 'emp-1'),
}));

import {
  LIMITE_MAX_TAREAS,
  TareaService,
  type ActorConsultaTareas,
} from '../../src/services/TareaServices';
import { GerenteService } from '../../src/services/GerenteServices';
import { GerenteController } from '../../src/controller/GerenteController';
import { TareaCorrectivaController } from '../../src/controller/TareaCorrectivaController';

const admin1: ActorConsultaTareas = { id: 'adm-1', rol: 'administrador' };
const gerente: ActorConsultaTareas = { id: 'ger-1', rol: 'gerente' };
const sup1: ActorConsultaTareas = { id: 'sup-1', rol: 'supervisor' };

function gerenteSvc(actor?: ActorConsultaTareas) {
  return new GerenteService(mockPrisma, 'emp-1', actor);
}

function makeRes() {
  const res: any = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  res.send = jest.fn().mockReturnValue(res);
  return res;
}

const reqDe = (actor: ActorConsultaTareas, params: Record<string, string>, body: unknown, query = {}) =>
  ({ params, body, query, user: { sub: actor.id, rol: actor.rol, empresaId: 'emp-1' } }) as any;

/** Alta válida en c1 (ubicación 10, elemento 20, op-1, sup-1). */
function alta(extra: Record<string, unknown> = {}) {
  return {
    descripcion: 'Arreglar la reja',
    fechaInicio: '2026-10-21T13:00:00.000Z',
    duracionMinutos: 60,
    tipo: 'PREVENTIVA',
    conjuntoId: 'c1',
    ubicacionId: 10,
    elementoId: 20,
    supervisorId: 'sup-1',
    operariosIds: ['op-1'],
    ...extra,
  };
}

beforeEach(() => {
  TAREAS = [fila(1, 'c1'), fila(2, 'c2', { ubicacionId: 11, elementoId: 21, operarios: [{ id: 'op-2' }] })];
  jest.clearAllMocks();
});

describe('PATCH /gerente/tareas/:tareaId: ids de la tarea', () => {
  const editar = (payload: unknown, id = 1, actor: ActorConsultaTareas = gerente) =>
    gerenteSvc(actor).editarTarea(id, payload);

  test.each([
    ['ubicación de otra empresa', { ubicacionId: 12, elementoId: 22 }],
    ['ubicación de otro conjunto de la empresa', { ubicacionId: 11, elementoId: 21 }],
    ['elemento que no es de la ubicación', { elementoId: 21 }],
    ['supervisor de otra empresa', { supervisorId: 'sup-x' }],
    ['operario de otra empresa', { operariosIds: ['op-1', 'op-x'] }],
    ['operario de la empresa pero de otro conjunto', { operariosIds: ['op-2'] }],
    ['quitar el conjunto', { conjuntoId: null }],
  ])('rechaza %s con 404 y no guarda', async (_caso, payload) => {
    await expect(editar(payload)).rejects.toMatchObject({
      status: 404,
      message: 'Recurso no encontrado',
    });
    expect(mockPrisma.tarea.update).not.toHaveBeenCalled();
  });

  test('acepta ids de la tarea y reenviar los que ya tenía (como hace la app)', async () => {
    await expect(
      editar({
        descripcion: 'Con datos completos',
        conjuntoId: 'c1',
        ubicacionId: 10,
        elementoId: 20,
        supervisorId: 'sup-2',
        operariosIds: ['op-1'],
      }),
    ).resolves.toMatchObject({ ok: true, tarea: { descripcion: 'Con datos completos' } });
  });

  test('lo que no cambia no se revisa: una tarea con datos antiguos se sigue editando', async () => {
    // op-2 ya no es de c1, pero estaba asignado antes de esta edición.
    TAREAS[0].operarios = [{ id: 'op-2' }];
    await expect(
      editar({ descripcion: 'Solo el texto', ubicacionId: 10, elementoId: 20, operariosIds: ['op-2'] }),
    ).resolves.toMatchObject({ ok: true });
    expect(mockPrisma.conjunto.findFirst).not.toHaveBeenCalled();
    expect(mockPrisma.operario.count).not.toHaveBeenCalled();
  });

  test('al cambiar de conjunto, ubicación y operarios deben ser del nuevo', async () => {
    // Mantiene la ubicación y el operario de c1.
    await expect(editar({ conjuntoId: 'c2' })).rejects.toMatchObject({ status: 404 });
    await expect(
      editar({ conjuntoId: 'c2', ubicacionId: 11, elementoId: 21 }),
    ).rejects.toMatchObject({ status: 404 });
    await expect(
      editar({ conjuntoId: 'c2', ubicacionId: 11, elementoId: 21, operariosIds: ['op-2'] }),
    ).resolves.toMatchObject({ ok: true });
  });

  test('PATCH /tarea-correctiva/tareas/:id aplica la misma regla', async () => {
    const res = makeRes();
    const next = jest.fn();
    await new TareaCorrectivaController().editar(
      reqDe(gerente, { id: '1' }, { operariosIds: ['op-x'] }),
      res,
      next,
    );
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));
    expect(res.json).not.toHaveBeenCalled();
  });
});

describe('PATCH /tarea/:id: ids de la tarea', () => {
  const editar = (payload: unknown) =>
    TareaService.editarTarea(mockPrisma, 1, payload, 'emp-1', gerente);

  test('rechaza ubicación, supervisor u operario de otra empresa con 404', async () => {
    await expect(editar({ ubicacionId: 12, elementoId: 22 })).rejects.toMatchObject({ status: 404 });
    await expect(editar({ supervisorId: 'sup-x' })).rejects.toMatchObject({ status: 404 });
    await expect(editar({ operariosIds: ['op-x'] })).rejects.toMatchObject({ status: 404 });
    expect(mockPrisma.tarea.update).not.toHaveBeenCalled();
  });
});

describe('POST /gerente/tareas: alcance al crear', () => {
  test('el administrador recibe 404 en un conjunto que no es suyo, antes de mirar la agenda', async () => {
    await expect(
      gerenteSvc(admin1).asignarTarea(
        alta({ conjuntoId: 'c2', ubicacionId: 11, elementoId: 21, operariosIds: ['op-2'] }),
      ),
    ).rejects.toMatchObject({ status: 404, message: 'Recurso no encontrado' });
    // c3 tampoco: es de otra empresa.
    await expect(
      gerenteSvc(admin1).asignarTarea(
        alta({ conjuntoId: 'c3', ubicacionId: 12, elementoId: 22, operariosIds: ['op-x'] }),
      ),
    ).rejects.toMatchObject({ status: 404 });
    expect(mockPrisma.$queryRaw).not.toHaveBeenCalled();
    expect(mockPrisma.tarea.create).not.toHaveBeenCalled();
  });

  test('el administrador crea en sus conjuntos', async () => {
    await expect(gerenteSvc(admin1).asignarTarea(alta())).resolves.toMatchObject({
      ok: true,
      tareaId: 100,
    });
    expect(mockPrisma.tarea.create).toHaveBeenCalledTimes(1);
  });

  test('gerente y supervisor crean en cualquier conjunto de la empresa', async () => {
    const enC2 = alta({ conjuntoId: 'c2', ubicacionId: 11, elementoId: 21, operariosIds: ['op-2'] });
    await expect(gerenteSvc(gerente).asignarTarea(enC2)).resolves.toMatchObject({ ok: true });
    await expect(gerenteSvc(sup1).asignarTarea(enC2)).resolves.toMatchObject({ ok: true });
  });

  test.each([
    ['conjunto de otra empresa', { conjuntoId: 'c3', ubicacionId: 12, elementoId: 22, operariosIds: [] }],
    ['sin conjunto', { conjuntoId: null }],
    ['ubicación de otro conjunto', { ubicacionId: 11, elementoId: 21 }],
    ['supervisor de otra empresa', { supervisorId: 'sup-x' }],
    ['operario de otra empresa', { operariosIds: ['op-x'] }],
    ['operario de otro conjunto', { operariosIds: ['op-2'] }],
  ])('rechaza %s con 404 aunque sea el gerente', async (_caso, extra) => {
    await expect(gerenteSvc(gerente).asignarTarea(alta(extra))).rejects.toMatchObject({
      status: 404,
    });
    expect(mockPrisma.tarea.create).not.toHaveBeenCalled();
  });

  test('una llamada interna sin empresa (el cronograma) no se revisa aquí', async () => {
    await expect(new GerenteService(mockPrisma).asignarTarea(alta())).resolves.toMatchObject({
      ok: true,
    });
    expect(mockPrisma.conjunto.findFirst).not.toHaveBeenCalled();
  });

  test('el controlador toma el actor del token: administrador en conjunto ajeno → 404', async () => {
    const res = makeRes();
    const next = jest.fn();
    // Correctiva P2: entra por las reglas de reemplazo, que también lo exigen.
    await new GerenteController().asignarTarea(
      reqDe(admin1, {}, alta({
        tipo: 'CORRECTIVA',
        conjuntoId: 'c2',
        ubicacionId: 11,
        elementoId: 21,
        operariosIds: ['op-2'],
      })),
      res,
      next,
    );
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));
    expect(res.json).not.toHaveBeenCalled();
    expect(mockPrisma.tarea.create).not.toHaveBeenCalled();
  });

  test('el controlador deja crear al administrador en su conjunto', async () => {
    const res = makeRes();
    const next = jest.fn();
    await new GerenteController().asignarTarea(
      reqDe(admin1, {}, alta({ tipo: 'CORRECTIVA' })),
      res,
      next,
    );
    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(201);
    expect(res.json.mock.calls[0][0]).toMatchObject({ ok: true, tareaId: 100 });
  });

  test('POST /gerente/tareas/reemplazo: administrador en conjunto ajeno → 404', async () => {
    const res = makeRes();
    await new GerenteController().asignarTareaConReemplazo(
      reqDe(admin1, {}, {
        tarea: alta({
          tipo: 'CORRECTIVA',
          conjuntoId: 'c2',
          ubicacionId: 11,
          elementoId: 21,
          operariosIds: ['op-2'],
        }),
        reemplazarIds: [2],
      }),
      res,
    );
    expect(res.status).toHaveBeenCalledWith(404);
    expect(res.json).toHaveBeenCalledWith({ ok: false, message: 'Recurso no encontrado' });
    expect(mockPrisma.tarea.create).not.toHaveBeenCalled();
  });

  test('POST /tarea-correctiva/conjuntos/:nit/tareas: el servicio también lo exige', async () => {
    const next = jest.fn();
    await new TareaCorrectivaController().crear(
      reqDe(admin1, { nit: 'c2' }, alta({ ubicacionId: 11, elementoId: 21, operariosIds: ['op-2'] })),
      makeRes(),
      next,
    );
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));
    expect(mockPrisma.tarea.create).not.toHaveBeenCalled();
  });
});

describe('GET /tarea-correctiva/conjuntos/:nit/tareas: tope de filas', () => {
  const listar = (query: Record<string, string>) =>
    TareaService.listarTareasDeConjuntoPorRango(mockPrisma, 'c1', query, 'emp-1', gerente);

  test(`sin límite trae como mucho ${LIMITE_MAX_TAREAS}`, async () => {
    expect(LIMITE_MAX_TAREAS).toBe(500);
    await listar({});
    expect(mockPrisma.tarea.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ take: 500, orderBy: [{ fechaInicio: 'asc' }, { id: 'asc' }] }),
    );
  });

  test('acepta un límite menor y rechaza uno mayor que el tope', async () => {
    await listar({ limite: '20' });
    expect(mockPrisma.tarea.findMany.mock.calls[0][0].take).toBe(20);
    await expect(listar({ limite: '501' })).rejects.toThrow();
    await expect(listar({ limite: '0' })).rejects.toThrow();
  });

  test('el controlador pasa la query y responde 400 si el límite se pasa del tope', async () => {
    const res = makeRes();
    const next = jest.fn();
    await new TareaCorrectivaController().listarPorConjunto(
      reqDe(gerente, { nit: 'c1' }, undefined, { limite: '1000' }),
      res,
      next,
    );
    expect(res.json).not.toHaveBeenCalled();
    expect(next.mock.calls[0][0].name).toBe('ZodError');

    const res2 = makeRes();
    await new TareaCorrectivaController().listarPorConjunto(
      reqDe(gerente, { nit: 'c1' }, undefined, {}),
      res2,
      jest.fn(),
    );
    expect(res2.json.mock.calls[0][0].map((t: any) => t.id)).toEqual([1]);
    expect(mockPrisma.tarea.findMany.mock.calls.at(-1)[0].take).toBe(500);
  });
});
