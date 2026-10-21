// Alcance por rol al MODIFICAR tareas: PATCH/DELETE /tarea/:id,
// POST /tarea/:id/corregir-cierre, PATCH/DELETE /gerente/tareas/:tareaId y
// PATCH /tarea-correctiva/tareas/:id. Antes filtraban solo por empresa: un
// supervisor con `tareas.crear` editaba o borraba tareas de otros
// supervisores. Ahora se usa la misma regla de lectura de GET /tarea.

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
  evidencias: string[];
  insumosUsados: unknown;
  fechaFinalizarTarea: Date | null;
  conjuntoId: string;
  supervisorId: string | null;
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
  supervisorId: string | null,
  extra: Partial<Fila> = {},
): Fila {
  return {
    id,
    descripcion: `Tarea ${id}`,
    // Preventiva: GerenteService no aplica las reglas de agenda de correctivas,
    // así la prueba se centra en el alcance.
    tipo: 'PREVENTIVA',
    estado: 'ASIGNADA',
    borrador: true,
    prioridad: 2,
    fechaInicio: new Date(Date.UTC(2026, 9, 20, 13)),
    fechaFin: new Date(Date.UTC(2026, 9, 20, 14)),
    duracionMinutos: 60,
    ubicacionId: 10,
    elementoId: 20,
    observaciones: null,
    evidencias: [],
    insumosUsados: null,
    fechaFinalizarTarea: null,
    conjuntoId: conjunto,
    supervisorId,
    conjunto: CONJUNTOS[conjunto],
    operarios: [{ id: 'op-1' }],
    ...extra,
  };
}

let TAREAS: Fila[] = [];

function datosIniciales(): Fila[] {
  return [
    fila(1, 'c1', 'sup-1'),
    fila(2, 'c1', 'sup-2'),
    fila(3, 'c2', 'sup-1'),
    fila(4, 'c3', 'sup-1'),
    fila(5, 'c1', null),
    fila(6, 'c1', 'sup-1', { estado: 'APROBADA', borrador: false }),
    fila(7, 'c2', 'sup-2', { estado: 'APROBADA', borrador: false }),
  ];
}

// Evalúa solo las formas de `where` que arman los servicios en estas rutas.
function cumple(t: Fila, where: any): boolean {
  return Object.entries(where ?? {}).every(([campo, valor]: [string, any]) => {
    if (campo === 'AND') return (valor as any[]).every((w) => cumple(t, w));
    if (campo === 'conjunto') {
      return Object.entries(valor).every(([k, v]) => (t.conjunto as any)[k] === v);
    }
    if (campo === 'operarios') return t.operarios.some((o) => o.id === valor.some.id);
    const actual = (t as any)[campo];
    if (actual instanceof Date) {
      return (!valor.gte || actual >= valor.gte) && (!valor.lte || actual <= valor.lte);
    }
    return actual === valor;
  });
}

function escalares(data: Record<string, unknown>) {
  return Object.fromEntries(
    Object.entries(data ?? {}).filter(
      ([, v]) => v !== undefined && (typeof v !== 'object' || v === null || v instanceof Date),
    ),
  );
}

const mockPrisma: any = {
  tarea: {
    findFirst: jest.fn(async (args: any) => TAREAS.find((t) => cumple(t, args.where)) ?? null),
    findMany: jest.fn(async (args: any) => TAREAS.filter((t) => cumple(t, args.where))),
    update: jest.fn(async ({ where, data }: any) => {
      const t = TAREAS.find((x) => x.id === where.id)!;
      Object.assign(t, escalares(data));
      return { ...t };
    }),
    delete: jest.fn(async ({ where }: any) => {
      TAREAS = TAREAS.filter((t) => t.id !== where.id);
      return { id: where.id };
    }),
    count: jest.fn(async () => 0),
  },
  conjunto: {
    findFirst: jest.fn(async ({ where }: any) => {
      const c = Object.values(CONJUNTOS).find(
        (x) =>
          x.nit === where.nit &&
          (where.empresaId === undefined || x.empresaId === where.empresaId) &&
          (where.administradorId === undefined || x.administradorId === where.administradorId),
      );
      return c ? { nit: c.nit } : null;
    }),
  },
  supervisor: { findFirst: jest.fn(async ({ where }: any) => ({ id: where.id })) },
  operario: { count: jest.fn(async ({ where }: any) => where.id.in.length) },
  usuario: { findUnique: jest.fn(async () => ({ nombre: 'Usuario de prueba' })) },
  maquinariaConjunto: { updateMany: jest.fn(async () => ({ count: 0 })) },
  usoMaquinaria: { deleteMany: jest.fn(async () => ({ count: 0 })) },
  usoHerramienta: { deleteMany: jest.fn(async () => ({ count: 0 })) },
  consumoInsumo: { deleteMany: jest.fn(async () => ({ count: 0 })) },
  $transaction: jest.fn(async (cb: any) => cb(mockPrisma)),
};

jest.mock('../../src/db/prisma', () => ({ prisma: mockPrisma }));
jest.mock('../../src/middlewares/tenant.middleware', () => ({
  empresaIdAutenticada: jest.fn(async () => 'emp-1'),
}));

import { FiltroTareaDTO } from '../../src/model/Tarea';
import {
  TareaService,
  conSupervisorPorDefecto,
  type ActorConsultaTareas,
} from '../../src/services/TareaServices';
import { GerenteService } from '../../src/services/GerenteServices';
import { TareaController } from '../../src/controller/TareaController';
import { GerenteController } from '../../src/controller/GerenteController';
import { TareaCorrectivaController } from '../../src/controller/TareaCorrectivaController';

const sup1: ActorConsultaTareas = { id: 'sup-1', rol: 'supervisor' };
const admin1: ActorConsultaTareas = { id: 'adm-1', rol: 'administrador' };
const gerente: ActorConsultaTareas = { id: 'ger-1', rol: 'gerente' };
const jefe: ActorConsultaTareas = { id: 'jefe-1', rol: 'jefe_operaciones' };
const operario1: ActorConsultaTareas = { id: 'op-1', rol: 'operario' };

const NUEVA = { descripcion: 'Descripción corregida' };

function editar(id: number, actor: ActorConsultaTareas, payload: unknown = NUEVA) {
  return TareaService.editarTarea(mockPrisma, id, payload, 'emp-1', actor);
}

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

beforeEach(() => {
  TAREAS = datosIniciales();
  jest.clearAllMocks();
});

describe('PATCH /tarea/:id: alcance de modificación', () => {
  test('el supervisor que edita una tarea de otro supervisor recibe 404', async () => {
    await expect(editar(2, sup1)).rejects.toMatchObject({
      status: 404,
      message: 'Recurso no encontrado',
    });
    // Tampoco una sin supervisor: no la tiene a cargo.
    await expect(editar(5, sup1)).rejects.toMatchObject({ status: 404 });
    expect(mockPrisma.tarea.update).not.toHaveBeenCalled();
  });

  test('el supervisor edita una tarea que tiene a cargo', async () => {
    const tarea = await editar(1, sup1);
    expect(tarea.id).toBe(1);
    expect(tarea.descripcion).toBe('Descripción corregida');
    // Su alcance no depende del conjunto: también la de c2 que supervisa.
    expect((await editar(3, sup1)).id).toBe(3);
  });

  test('el administrador recibe 404 fuera de sus conjuntos y edita los suyos', async () => {
    await expect(editar(3, admin1)).rejects.toMatchObject({ status: 404 });
    // c3 tiene su administradorId pero es de otra empresa.
    await expect(editar(4, admin1)).rejects.toMatchObject({ status: 404 });
    expect((await editar(2, admin1)).id).toBe(2);
  });

  test('el administrador no puede mover su tarea a un conjunto ajeno', async () => {
    await expect(editar(1, admin1, { conjuntoId: 'c2' })).rejects.toMatchObject({ status: 404 });
    expect(mockPrisma.tarea.update).not.toHaveBeenCalled();
  });

  test('gerente y jefe de operaciones editan cualquier tarea de la empresa, nunca otra', async () => {
    expect((await editar(2, gerente)).id).toBe(2);
    expect((await editar(5, jefe)).id).toBe(5);
    await expect(editar(4, gerente)).rejects.toMatchObject({ status: 404 });
  });

  test('el operario no modifica tareas por estas rutas, ni las suyas: 403', async () => {
    await expect(editar(1, operario1)).rejects.toMatchObject({ status: 403 });
    expect(mockPrisma.tarea.findFirst).not.toHaveBeenCalled();
  });

  test('un rol sin regla de alcance no modifica tareas', async () => {
    await expect(editar(1, { id: 'r-1', rol: 'residente' })).rejects.toMatchObject({
      status: 403,
    });
  });
});

describe('DELETE /tarea/:id: alcance de modificación', () => {
  test('el supervisor no borra un borrador de otro supervisor', async () => {
    await expect(
      TareaService.eliminarTarea(mockPrisma, 2, 'emp-1', sup1),
    ).rejects.toMatchObject({ status: 404 });
    expect(mockPrisma.tarea.delete).not.toHaveBeenCalled();
  });

  test('el supervisor borra un borrador suyo', async () => {
    await expect(TareaService.eliminarTarea(mockPrisma, 1, 'emp-1', sup1)).resolves.toMatchObject({
      ok: true,
    });
    expect(mockPrisma.tarea.delete).toHaveBeenCalledWith({ where: { id: 1 } });
  });

  test('el administrador recibe 404 por un borrador de otro conjunto', async () => {
    await expect(
      TareaService.eliminarTarea(mockPrisma, 3, 'emp-1', admin1),
    ).rejects.toMatchObject({ status: 404 });
  });
});

describe('POST /tarea/:id/corregir-cierre: alcance de modificación', () => {
  const corregir = (id: number, actor: ActorConsultaTareas) =>
    TareaService.corregirCierre(
      mockPrisma,
      id,
      { motivo: 'Faltaba una foto' },
      [],
      'emp-1',
      actor,
    );

  test('el jefe de operaciones corrige el cierre de cualquier conjunto de la empresa', async () => {
    expect((await corregir(7, jefe)).id).toBe(7);
  });

  test('el administrador recibe 404 por una tarea de otro conjunto', async () => {
    await expect(corregir(7, admin1)).rejects.toMatchObject({ status: 404 });
  });

  test('un supervisor con el permiso solo corrige las que supervisa', async () => {
    await expect(corregir(7, sup1)).rejects.toMatchObject({ status: 404 });
    expect((await corregir(6, sup1)).id).toBe(6);
  });

  test('el operario nunca corrige cierres', async () => {
    await expect(corregir(6, operario1)).rejects.toMatchObject({ status: 403 });
  });
});

describe('PATCH/DELETE /gerente/tareas/:tareaId: alcance de modificación', () => {
  test('el supervisor recibe 404 por una tarea de otro supervisor', async () => {
    await expect(gerenteSvc(sup1).editarTarea(2, NUEVA)).rejects.toMatchObject({ status: 404 });
    expect(mockPrisma.tarea.update).not.toHaveBeenCalled();
  });

  test('el supervisor edita la suya', async () => {
    const out: any = await gerenteSvc(sup1).editarTarea(1, NUEVA);
    expect(out).toMatchObject({ ok: true, tarea: { id: 1, descripcion: 'Descripción corregida' } });
  });

  test('el administrador recibe 404 fuera de sus conjuntos y no mueve tareas a ellos', async () => {
    await expect(gerenteSvc(admin1).editarTarea(3, NUEVA)).rejects.toMatchObject({ status: 404 });
    await expect(
      gerenteSvc(admin1).editarTarea(1, { conjuntoId: 'c2' }),
    ).rejects.toMatchObject({ status: 404 });
  });

  test('el gerente edita cualquiera de la empresa, nunca de otra', async () => {
    await expect(gerenteSvc(gerente).editarTarea(5, NUEVA)).resolves.toMatchObject({ ok: true });
    await expect(gerenteSvc(gerente).editarTarea(4, NUEVA)).rejects.toMatchObject({ status: 404 });
  });

  test('eliminar: supervisor ajena 404, gerente OK', async () => {
    await expect(gerenteSvc(sup1).eliminarTarea(mockPrisma, 2)).rejects.toMatchObject({
      status: 404,
    });
    expect(mockPrisma.tarea.delete).not.toHaveBeenCalled();
    await expect(gerenteSvc(gerente).eliminarTarea(mockPrisma, 2)).resolves.toMatchObject({
      ok: true,
    });
  });

  test('sin actor (llamada interna del servicio) solo cuenta la empresa', async () => {
    await expect(gerenteSvc().eliminarTarea(mockPrisma, 2)).resolves.toMatchObject({ ok: true });
    await expect(gerenteSvc().eliminarTarea(mockPrisma, 4)).rejects.toMatchObject({ status: 404 });
  });
});

describe('Controladores: el actor sale del token', () => {
  const reqDe = (actor: ActorConsultaTareas, params: Record<string, string>, body: unknown = NUEVA) =>
    ({ params, body, query: {}, user: { sub: actor.id, rol: actor.rol, empresaId: 'emp-1' } }) as any;

  test('PATCH /tarea/:id ajena para el supervisor responde 404', async () => {
    const res = makeRes();
    const next = jest.fn();
    await new TareaController().editarTarea(reqDe(sup1, { id: '2' }), res, next);
    expect(res.json).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));
  });

  test('DELETE /tarea/:id propia del supervisor responde 204', async () => {
    const res = makeRes();
    const next = jest.fn();
    await new TareaController().eliminarTarea(reqDe(sup1, { id: '1' }), res, next);
    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(204);
  });

  test('PATCH /gerente/tareas/:tareaId ajena para el supervisor responde 404', async () => {
    const res = makeRes();
    const next = jest.fn();
    await new GerenteController().editarTarea(reqDe(sup1, { tareaId: '2' }), res, next);
    expect(res.json).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));
  });

  test('DELETE /gerente/tareas/:tareaId del administrador en otro conjunto responde 404', async () => {
    const res = makeRes();
    const next = jest.fn();
    await new GerenteController().eliminarTarea(reqDe(admin1, { tareaId: '3' }), res, next);
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));
    expect(mockPrisma.tarea.delete).not.toHaveBeenCalled();
  });

  test('PATCH /tarea-correctiva/tareas/:id: ajena 404, propia OK', async () => {
    const controller = new TareaCorrectivaController();
    const next = jest.fn();
    await controller.editar(reqDe(sup1, { id: '2' }), makeRes(), next);
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));

    const res = makeRes();
    const next2 = jest.fn();
    await controller.editar(reqDe(sup1, { id: '1' }), res, next2);
    expect(next2).not.toHaveBeenCalled();
    expect(res.json.mock.calls[0][0]).toMatchObject({ ok: true, tarea: { id: 1 } });
  });

  test('GET /tarea-correctiva/conjuntos/:nit/tareas respeta el alcance de lectura', async () => {
    const res = makeRes();
    const next = jest.fn();
    const req = reqDe(sup1, { nit: 'c1' });
    req.query = { desde: '2026-10-01' };
    await new TareaCorrectivaController().listarPorConjunto(req, res, next);
    expect(next).not.toHaveBeenCalled();
    expect(res.json.mock.calls[0][0].map((t: any) => t.id)).toEqual([1, 6]);
  });
});

describe('Al crear, el supervisor queda a cargo si no elige supervisor', () => {
  test('sin supervisorId se asigna el supervisor que crea', () => {
    expect(conSupervisorPorDefecto(sup1, { descripcion: 'x' })).toEqual({
      descripcion: 'x',
      supervisorId: 'sup-1',
    });
    expect(conSupervisorPorDefecto(sup1, { supervisorId: '' })).toMatchObject({
      supervisorId: 'sup-1',
    });
  });

  test('respeta el supervisor elegido y no toca a otros roles', () => {
    expect(conSupervisorPorDefecto(sup1, { supervisorId: 'sup-2' })).toEqual({
      supervisorId: 'sup-2',
    });
    expect(conSupervisorPorDefecto(gerente, { descripcion: 'x' })).toEqual({ descripcion: 'x' });
    expect(conSupervisorPorDefecto(sup1, undefined)).toBeUndefined();
  });
});

describe('FiltroTareaDTO acepta los filtros que llegan por query', () => {
  test('convierte números y booleano desde texto', () => {
    expect(
      FiltroTareaDTO.parse({
        ubicacionId: '10',
        elementoId: '20',
        periodoAnio: '2026',
        periodoMes: '10',
        borrador: 'false',
      }),
    ).toMatchObject({
      ubicacionId: 10,
      elementoId: 20,
      periodoAnio: 2026,
      periodoMes: 10,
      borrador: false,
    });
    expect(FiltroTareaDTO.parse({ borrador: 'true' }).borrador).toBe(true);
    expect(FiltroTareaDTO.parse({ borrador: '1' }).borrador).toBe(true);
    expect(FiltroTareaDTO.parse({}).borrador).toBeUndefined();
  });

  test('sigue rechazando valores inválidos', () => {
    expect(() => FiltroTareaDTO.parse({ borrador: 'tal vez' })).toThrow();
    expect(() => FiltroTareaDTO.parse({ periodoMes: '13' })).toThrow();
    expect(() => FiltroTareaDTO.parse({ ubicacionId: 'abc' })).toThrow();
  });

  test('GET /tarea con filtros de texto filtra en lugar de responder 400', async () => {
    const res = makeRes();
    const next = jest.fn();
    const req: any = {
      query: { ubicacionId: '10', elementoId: '20', borrador: 'false' },
      user: { sub: 'ger-1', rol: 'gerente' },
    };
    await new TareaController().listarTareas(req, res, next);

    expect(next).not.toHaveBeenCalled();
    const where = mockPrisma.tarea.findMany.mock.calls[0][0].where.AND[1];
    expect(where).toMatchObject({ ubicacionId: 10, elementoId: 20, borrador: false });
    expect(res.json.mock.calls[0][0].map((t: any) => t.id).sort()).toEqual([6, 7]);
  });
});
