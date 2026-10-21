// Alcance por rol de GET /tarea y GET /tarea/:id: antes filtraban solo por
// empresa y un operario podía leer (y bajar de una vez) cualquier tarea.

type Fila = {
  id: number;
  fechaInicio: Date;
  conjuntoId: string;
  supervisorId: string | null;
  borrador: boolean;
  estado: string;
  conjunto: { nit: string; nombre: string; empresaId: string; administradorId: string | null };
  operarios: { id: string }[];
};

const CONJUNTOS = {
  c1: { nit: 'c1', nombre: 'Conjunto Uno', empresaId: 'emp-1', administradorId: 'adm-1' },
  c2: { nit: 'c2', nombre: 'Conjunto Dos', empresaId: 'emp-1', administradorId: 'adm-2' },
  c3: { nit: 'c3', nombre: 'Otra empresa', empresaId: 'emp-2', administradorId: 'adm-1' },
};

function fila(
  id: number,
  conjunto: keyof typeof CONJUNTOS,
  operarios: string[],
  supervisorId: string | null,
  extra: Partial<Fila> = {},
): Fila {
  return {
    id,
    fechaInicio: new Date(Date.UTC(2026, 9, id)),
    conjuntoId: conjunto,
    supervisorId,
    borrador: false,
    estado: 'ASIGNADA',
    conjunto: CONJUNTOS[conjunto],
    operarios: operarios.map((o) => ({ id: o })),
    ...extra,
  };
}

const TAREAS: Fila[] = [
  fila(1, 'c1', ['op-1'], 'sup-1'),
  fila(2, 'c2', ['op-2'], 'sup-2'),
  fila(3, 'c1', ['op-1', 'op-2'], 'sup-2'),
  fila(4, 'c1', ['op-1'], 'sup-1', { borrador: true }),
  fila(5, 'c3', ['op-1'], 'sup-1'),
  fila(6, 'c2', ['op-1'], null, { estado: 'APROBADA' }),
];

// Evalúa solo las formas de `where` que arma TareaService para /tarea.
function cumple(t: Fila, where: any): boolean {
  return Object.entries(where ?? {}).every(([campo, valor]: [string, any]) => {
    if (campo === 'AND') return (valor as any[]).every((w) => cumple(t, w));
    if (campo === 'conjunto') {
      return Object.entries(valor).every(([k, v]) => (t.conjunto as any)[k] === v);
    }
    if (campo === 'operarios') return t.operarios.some((o) => o.id === valor.some.id);
    if (campo === 'fechaInicio') {
      return (
        (!valor.gte || t.fechaInicio >= valor.gte) && (!valor.lte || t.fechaInicio <= valor.lte)
      );
    }
    return (t as any)[campo] === valor;
  });
}

function filtrar(args: any): Fila[] {
  return TAREAS.filter((t) => cumple(t, args.where)).sort(
    (a, b) => b.fechaInicio.getTime() - a.fechaInicio.getTime() || b.id - a.id,
  );
}

const mockPrisma: any = {
  tarea: {
    findMany: jest.fn(async (args: any) => filtrar(args).slice(0, args.take ?? Infinity)),
    findFirst: jest.fn(async (args: any) => filtrar(args)[0] ?? null),
  },
};

jest.mock('../../src/db/prisma', () => ({ prisma: mockPrisma }));
jest.mock('../../src/middlewares/tenant.middleware', () => ({
  empresaIdAutenticada: jest.fn(async () => 'emp-1'),
}));

import { TareaController } from '../../src/controller/TareaController';
import {
  LIMITE_MAX_TAREAS,
  TareaService,
  type ActorConsultaTareas,
} from '../../src/services/TareaServices';

const operario1: ActorConsultaTareas = { id: 'op-1', rol: 'operario' };
const admin1: ActorConsultaTareas = { id: 'adm-1', rol: 'administrador' };
const supervisor2: ActorConsultaTareas = { id: 'sup-2', rol: 'supervisor' };
const gerente: ActorConsultaTareas = { id: 'ger-1', rol: 'gerente' };
const jefe: ActorConsultaTareas = { id: 'jefe-1', rol: 'jefe_operaciones' };

async function ids(actor: ActorConsultaTareas, filtro: unknown = {}) {
  const lista = await TareaService.listarTareas(mockPrisma, filtro, 'emp-1', actor);
  return lista.map((t) => t.id);
}

function makeRes() {
  const res: any = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

describe('GET /tarea: alcance por rol', () => {
  test('el operario solo ve las tareas publicadas donde está asignado', async () => {
    // 4 es borrador, 5 es de otra empresa, 2 es de otro operario.
    expect(await ids(operario1)).toEqual([6, 3, 1]);
  });

  test('el filtro operarioId no amplía lo que ve el operario', async () => {
    expect(await ids(operario1, { operarioId: 'op-2' })).toEqual([3]);
  });

  test('el administrador solo ve las tareas de sus conjuntos', async () => {
    expect(await ids(admin1)).toEqual([4, 3, 1]);
    // Pedir un conjunto ajeno no devuelve nada.
    expect(await ids(admin1, { conjuntoId: 'c2' })).toEqual([]);
  });

  test('el supervisor ve las tareas que tiene a cargo', async () => {
    expect(await ids(supervisor2)).toEqual([3, 2]);
  });

  test('gerente y jefe de operaciones ven toda la empresa, nunca otra', async () => {
    expect(await ids(gerente)).toEqual([6, 4, 3, 2, 1]);
    expect(await ids(jefe)).toEqual([6, 4, 3, 2, 1]);
  });

  test('un rol sin regla de alcance no lee tareas', async () => {
    await expect(
      TareaService.listarTareas(mockPrisma, {}, 'emp-1', { id: 'r-1', rol: 'residente' }),
    ).rejects.toMatchObject({ status: 403 });
    expect(mockPrisma.tarea.findMany).not.toHaveBeenCalled();
  });
});

describe('GET /tarea: tope de resultados', () => {
  test('sin limite usa el tope máximo con orden estable', async () => {
    await ids(gerente);
    const args = mockPrisma.tarea.findMany.mock.calls[0][0];
    expect(args.take).toBe(LIMITE_MAX_TAREAS);
    expect(args.orderBy).toEqual([{ fechaInicio: 'desc' }, { id: 'desc' }]);
  });

  test('respeta un limite menor (viene como texto en la query)', async () => {
    expect(await ids(gerente, { limite: '2' })).toEqual([6, 4]);
    expect(mockPrisma.tarea.findMany.mock.calls[0][0].take).toBe(2);
  });

  test('rechaza un limite por encima del tope', async () => {
    await expect(ids(gerente, { limite: String(LIMITE_MAX_TAREAS + 1) })).rejects.toMatchObject({
      name: 'ZodError',
    });
    expect(mockPrisma.tarea.findMany).not.toHaveBeenCalled();
  });
});

describe('GET /tarea/:id: alcance por rol', () => {
  test('el operario lee una tarea suya', async () => {
    const tarea = await TareaService.obtenerTarea(mockPrisma, 1, 'emp-1', operario1);
    expect(tarea.id).toBe(1);
    expect(tarea.conjuntoNombre).toBe('Conjunto Uno');
  });

  test('el operario que pide una tarea ajena recibe 404', async () => {
    await expect(
      TareaService.obtenerTarea(mockPrisma, 2, 'emp-1', operario1),
    ).rejects.toMatchObject({ status: 404, message: 'Recurso no encontrado' });
  });

  test('el operario no lee borradores aunque esté asignado', async () => {
    await expect(
      TareaService.obtenerTarea(mockPrisma, 4, 'emp-1', operario1),
    ).rejects.toMatchObject({ status: 404 });
  });

  test('el administrador recibe 404 por una tarea de otro conjunto', async () => {
    await expect(TareaService.obtenerTarea(mockPrisma, 2, 'emp-1', admin1)).rejects.toMatchObject({
      status: 404,
    });
    // Ni siquiera su propio conjunto si es de otra empresa.
    await expect(TareaService.obtenerTarea(mockPrisma, 5, 'emp-1', admin1)).rejects.toMatchObject({
      status: 404,
    });
  });

  test('el gerente lee cualquier tarea de la empresa', async () => {
    const tarea = await TareaService.obtenerTarea(mockPrisma, 2, 'emp-1', gerente);
    expect(tarea.id).toBe(2);
  });
});

describe('TareaController toma el actor del token', () => {
  test('GET /tarea/:id ajena para el operario responde 404', async () => {
    const controller = new TareaController();
    const req: any = { params: { id: '2' }, user: { sub: 'op-1', rol: 'operario' } };
    const res = makeRes();
    const next = jest.fn();

    await controller.obtenerTarea(req, res, next);

    expect(res.json).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));
  });

  test('GET /tarea del operario devuelve solo sus tareas', async () => {
    const controller = new TareaController();
    const req: any = { query: {}, user: { sub: 'op-1', rol: 'operario' } };
    const res = makeRes();
    const next = jest.fn();

    await controller.listarTareas(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.json.mock.calls[0][0].map((t: any) => t.id)).toEqual([6, 3, 1]);
  });
});
