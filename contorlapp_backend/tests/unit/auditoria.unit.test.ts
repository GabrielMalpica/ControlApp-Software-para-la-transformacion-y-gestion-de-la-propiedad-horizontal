import { AuditoriaService } from '../../src/services/AuditoriaService';
import {
  AccionAuditoria,
  EntidadAuditoria,
  ModuloAuditoria,
  OrigenAuditoria,
} from '../../src/model/Auditoria';

const ACTOR = { id: 'ger-1', rol: 'gerente', nombre: 'Ana Perez' };

function prismaAuditoria(rows: any[] = []) {
  return {
    creados: [] as any[],
    auditoriaEvento: {
      create: jest.fn(function (this: any, { data }: any) {
        return Promise.resolve(data);
      }),
      createMany: jest.fn().mockResolvedValue({ count: rows.length }),
      findMany: jest.fn().mockResolvedValue(rows),
    },
  } as any;
}

function evento(overrides: Record<string, any> = {}) {
  return {
    id: BigInt(1),
    modulo: ModuloAuditoria.TAREA,
    entidad: EntidadAuditoria.TAREA,
    entidadId: '55',
    accion: AccionAuditoria.CREAR,
    conjuntoId: '9001',
    actorId: 'ger-1',
    actorRol: 'gerente',
    actorNombre: 'Ana Perez',
    origen: OrigenAuditoria.USUARIO,
    descripcion: 'Se creo la tarea',
    metadataJson: null,
    periodoAnio: 2026,
    periodoMes: 3,
    creadoEn: new Date('2026-03-01T10:00:00'),
    ...overrides,
  };
}

describe('AuditoriaService', () => {
  test('PU-A1 - registra modulo, entidad, accion y actor', async () => {
    const prisma = prismaAuditoria();
    const service = new AuditoriaService(prisma);

    await service.registrar({
      modulo: ModuloAuditoria.CRONOGRAMA,
      entidad: EntidadAuditoria.CRONOGRAMA_PERIODO,
      entidadId: '9001-2026-3',
      accion: AccionAuditoria.PUBLICAR,
      conjuntoId: '9001',
      actor: ACTOR,
      descripcion: 'Se publico el cronograma',
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(prisma.auditoriaEvento.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        modulo: 'CRONOGRAMA',
        entidad: 'CronogramaPeriodo',
        entidadId: '9001-2026-3',
        accion: 'PUBLICAR',
        conjuntoId: '9001',
        actorId: 'ger-1',
        actorRol: 'gerente',
        actorNombre: 'Ana Perez',
        origen: 'USUARIO',
        periodoAnio: 2026,
        periodoMes: 3,
      }),
    });
  });

  test('PU-A2 - normaliza entidadId numerico a texto', async () => {
    const prisma = prismaAuditoria();
    await new AuditoriaService(prisma).registrar({
      modulo: ModuloAuditoria.TAREA,
      entidad: EntidadAuditoria.TAREA,
      entidadId: 55,
      accion: AccionAuditoria.CREAR,
    });

    expect(prisma.auditoriaEvento.create.mock.calls[0][0].data.entidadId).toBe('55');
  });

  test('PU-A3 - un fallo de auditoria no interrumpe la operacion de negocio', async () => {
    const prisma = prismaAuditoria();
    prisma.auditoriaEvento.create.mockRejectedValue(new Error('columna inexistente'));
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);

    await expect(
      new AuditoriaService(prisma).registrar({
        modulo: ModuloAuditoria.TAREA,
        entidad: EntidadAuditoria.TAREA,
        entidadId: 1,
        accion: AccionAuditoria.CREAR,
      }),
    ).resolves.toBeUndefined();

    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });

  test('PU-A4 - registrarLote no consulta la base si no hay eventos', async () => {
    const prisma = prismaAuditoria();
    await new AuditoriaService(prisma).registrarLote([]);
    expect(prisma.auditoriaEvento.createMany).not.toHaveBeenCalled();
  });

  test('PU-A5 - trazabilidadPorEntidad resume creador y ultima modificacion', async () => {
    const prisma = prismaAuditoria([
      evento({ id: BigInt(1), accion: AccionAuditoria.CREAR }),
      evento({
        id: BigInt(2),
        accion: AccionAuditoria.EDITAR,
        actorId: 'sup-1',
        actorNombre: 'Luis Gomez',
        actorRol: 'supervisor',
        descripcion: 'Se movio la tarea',
        creadoEn: new Date('2026-03-02T09:00:00'),
      }),
      evento({
        id: BigInt(3),
        accion: AccionAuditoria.REEMPLAZAR,
        actorId: 'ger-1',
        descripcion: 'Tarea desplazada',
        creadoEn: new Date('2026-03-03T09:00:00'),
      }),
      evento({ id: BigInt(4), entidadId: '56', accion: AccionAuditoria.CREAR }),
    ]);

    const out = await new AuditoriaService(prisma).trazabilidadPorEntidad({
      entidad: EntidadAuditoria.TAREA,
      entidadIds: ['55', '56'],
    });

    expect(out['55'].creadoPor).toEqual(ACTOR);
    expect(out['55'].creadoEn).toEqual(new Date('2026-03-01T10:00:00'));
    expect(out['55'].ultimaModificacion).toMatchObject({
      accion: 'REEMPLAZAR',
      descripcion: 'Tarea desplazada',
    });
    expect(out['55'].totalEventos).toBe(3);

    expect(out['56'].creadoPor).toEqual(ACTOR);
    expect(out['56'].ultimaModificacion).toBeNull();
  });

  test('PU-A6 - listar serializa el id BigInt a texto para poder viajar en JSON', async () => {
    const prisma = prismaAuditoria([evento({ id: BigInt(9007199254740993n) })]);

    const out = await new AuditoriaService(prisma).listar('9001', { limit: 10 });

    expect(out[0].id).toBe('9007199254740993');
    expect(() => JSON.stringify(out)).not.toThrow();
  });

  test('PU-A7 - informePeriodo agrupa por accion y por actor', async () => {
    const prisma = prismaAuditoria([
      evento({ id: BigInt(1), accion: AccionAuditoria.CREAR }),
      evento({ id: BigInt(2), accion: AccionAuditoria.CREAR }),
      evento({
        id: BigInt(3),
        accion: AccionAuditoria.PUBLICAR,
        actorId: 'sup-1',
        actorNombre: 'Luis Gomez',
        actorRol: 'supervisor',
      }),
    ]);

    const out = await new AuditoriaService(prisma).informePeriodo('9001', {
      anio: 2026,
      mes: 3,
    });

    expect(out.totalEventos).toBe(3);
    expect(out.porAccion).toEqual([
      { accion: 'CREAR', eventos: 2 },
      { accion: 'PUBLICAR', eventos: 1 },
    ]);
    expect(out.porActor).toEqual([
      expect.objectContaining({ actorId: 'ger-1', eventos: 2 }),
      expect.objectContaining({ actorId: 'sup-1', eventos: 1 }),
    ]);
  });
});
