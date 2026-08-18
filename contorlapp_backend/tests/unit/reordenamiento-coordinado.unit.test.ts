jest.mock('../../src/utils/schedulerUtils', () => {
  const real = jest.requireActual('../../src/utils/schedulerUtils');
  return {
    ...real,
    isFestivoDate: jest.fn().mockResolvedValue(false),
  };
});

jest.mock('../../src/utils/operarioAvailability', () => {
  const real = jest.requireActual('../../src/utils/operarioAvailability');
  return {
    ...real,
    validarIntervaloProgramacion: jest.fn().mockResolvedValue({ ok: true }),
    validarOperariosDisponiblesEnFecha: jest
      .fn()
      .mockResolvedValue({ ok: true, noDisponibles: [] }),
  };
});

import { DefinicionTareaPreventivaService } from '../../src/services/DefinicionTareaPreventivaService';

/** Filtro minimo que entiende las formas de `where` que usa el servicio de
 * reordenamiento: rango de fechaInicio/fechaFin, id.notIn y operarios.some.id.in. */
function coincideConWhere(tarea: any, where: any): boolean {
  if (!where) return true;
  if (where.id?.notIn && where.id.notIn.includes(tarea.id)) return false;
  const fi = where.fechaInicio;
  if (fi?.lt && !(tarea.fechaInicio < fi.lt)) return false;
  if (fi?.lte && !(tarea.fechaInicio <= fi.lte)) return false;
  if (fi?.gte && !(tarea.fechaInicio >= fi.gte)) return false;
  const ff = where.fechaFin;
  if (ff?.gt && !(tarea.fechaFin > ff.gt)) return false;
  if (ff?.gte && !(tarea.fechaFin >= ff.gte)) return false;
  if (ff?.lte && !(tarea.fechaFin <= ff.lte)) return false;
  const idsOperarios = where.operarios?.some?.id?.in;
  if (idsOperarios) {
    const tieneOperario = (tarea.operarios ?? []).some((o: any) =>
      idsOperarios.includes(o.id),
    );
    if (!tieneOperario) return false;
  }
  return true;
}

function construirPrisma(tareas: any[]) {
  let siguienteId = 9000;
  const excluidasCreadas: any[] = [];
  const eventos: any[] = [];
  const prisma: any = {
    tareas,
    excluidasCreadas,
    tarea: {
      findMany: jest.fn(async ({ where }: any = {}) =>
        tareas.filter((t) => coincideConWhere(t, where)),
      ),
      findFirst: jest.fn(async ({ where }: any = {}) =>
        tareas.find((t) => coincideConWhere(t, where)) ?? null,
      ),
      findUnique: jest.fn(async ({ where }: any) =>
        tareas.find((t) => t.id === where.id) ?? null,
      ),
      update: jest.fn(async ({ where, data }: any) => {
        const tarea = tareas.find((item) => item.id === where.id);
        Object.assign(tarea, data);
        return tarea;
      }),
      delete: jest.fn(async ({ where }: any) => {
        const index = tareas.findIndex((item) => item.id === where.id);
        const [eliminada] = index >= 0 ? tareas.splice(index, 1) : [null];
        return eliminada;
      }),
      create: jest.fn(async ({ data }: any) => {
        const creada = {
          ...data,
          id: ++siguienteId,
          operarios: data.operarios?.connect ?? data.operarios ?? [],
        };
        tareas.push(creada);
        return creada;
      }),
    },
    conjuntoHorario: {
      findFirst: jest.fn().mockResolvedValue({
        horaApertura: '08:00',
        horaCierre: '17:00',
        descansoInicio: '12:00',
        descansoFin: '13:00',
      }),
    },
    preventivaExcluidaBorrador: {
      create: jest.fn(async ({ data }: any) => {
        const creada = { ...data, id: ++siguienteId };
        excluidasCreadas.push(creada);
        return creada;
      }),
    },
    preventivaBorradorEvento: {
      create: jest.fn(async ({ data }: any) => {
        eventos.push(data);
        return { ...data, id: ++siguienteId };
      }),
    },
    auditoriaEvento: {
      create: jest.fn().mockResolvedValue({}),
    },
    $transaction: jest.fn(async (callback: any) => callback(prisma)),
  };
  return prisma;
}

describe('reordenamiento coordinado del borrador', () => {
  test('no mueve una tarea ajena solo porque comparte operario con una tarea reordenada', async () => {
    const fecha = new Date(2026, 2, 4);
    const tareas: any[] = [
      {
        id: 1,
        descripcion: 'Tarea operario uno',
        fechaInicio: new Date(2026, 2, 4, 8),
        fechaFin: new Date(2026, 2, 4, 9),
        duracionMinutos: 60,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 2,
        descripcion: 'Tarea compartida',
        fechaInicio: new Date(2026, 2, 4, 9),
        fechaFin: new Date(2026, 2, 4, 10),
        duracionMinutos: 60,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [
          { id: 'op-1', usuario: { nombre: 'Ana' } },
          { id: 'op-2', usuario: { nombre: 'Luis' } },
        ],
      },
      {
        id: 3,
        descripcion: 'Tarea operario dos, no solicitada',
        fechaInicio: new Date(2026, 2, 4, 10),
        fechaFin: new Date(2026, 2, 4, 11),
        duracionMinutos: 60,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-2', usuario: { nombre: 'Luis' } }],
      },
    ];
    const prisma = construirPrisma(tareas);
    const service = new DefinicionTareaPreventivaService(prisma);

    const resultado = await service.reordenarTareasBorradorDia({
      conjuntoId: '9001',
      fecha,
      tareaIds: [2, 1],
    });

    // Solo las dos tareas solicitadas se recalculan; la tarea 3 (operario
    // compartido con la 2, pero no solicitada) no se toca ni se valida.
    expect(resultado).toMatchObject({
      ok: true,
      reordenadas: 2,
      ajustadasPorDependencia: 0,
    });
    expect(tareas.find((tarea) => tarea.id === 2)?.fechaInicio.getHours()).toBe(8);
    expect(tareas.find((tarea) => tarea.id === 1)?.fechaInicio.getHours()).toBe(9);
    // La tarea no solicitada conserva exactamente su horario original.
    expect(tareas.find((tarea) => tarea.id === 3)?.fechaInicio.getHours()).toBe(10);
    expect(
      prisma.tarea.update.mock.calls.some(([args]: any[]) => args.where.id === 3),
    ).toBe(false);
  });

  test('cascada: reacomoda en el mismo dia una tarea ajena que bloquea el nuevo orden', async () => {
    const fecha = new Date(2026, 2, 4);
    const tareas: any[] = [
      {
        id: 10,
        descripcion: 'Tarea corta',
        fechaInicio: new Date(2026, 2, 4, 8, 0),
        fechaFin: new Date(2026, 2, 4, 8, 30),
        duracionMinutos: 30,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 11,
        descripcion: 'Tarea larga',
        fechaInicio: new Date(2026, 2, 4, 8, 30),
        fechaFin: new Date(2026, 2, 4, 10, 0),
        duracionMinutos: 90,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 20,
        descripcion: 'Tarea de equipo (bloqueadora)',
        fechaInicio: new Date(2026, 2, 4, 9, 0),
        fechaFin: new Date(2026, 2, 4, 9, 15),
        duracionMinutos: 15,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [
          { id: 'op-1', usuario: { nombre: 'Ana' } },
          { id: 'op-2', usuario: { nombre: 'Luis' } },
        ],
      },
    ];
    const prisma = construirPrisma(tareas);
    const service = new DefinicionTareaPreventivaService(prisma);

    // Pedir que la larga (11) vaya primero empuja su nuevo horario (8:00 a
    // 9:30) a chocar con la tarea de equipo (20, comparte op-1). El op-2 de
    // esa tarea de equipo tiene el resto del dia libre, asi que debe
    // reacomodarse sola, sin pedir confirmacion.
    const resultado = await service.reordenarTareasBorradorDia({
      conjuntoId: '9001',
      fecha,
      tareaIds: [11, 10],
    });

    expect(resultado).toMatchObject({ ok: true, requiereConfirmacion: false, aplicado: true });
    expect(resultado.cambiosCascada).toEqual([
      expect.objectContaining({ tareaId: 20, accion: 'MOVIDA' }),
    ]);

    expect(tareas.find((t) => t.id === 11)?.fechaInicio.getHours()).toBe(8);
    expect(tareas.find((t) => t.id === 10)?.fechaInicio.getHours()).toBe(9);
    expect(tareas.find((t) => t.id === 10)?.fechaInicio.getMinutes()).toBe(30);
    // La bloqueadora se corrio a las 9:30, justo cuando la larga libera op-1.
    const bloqueadora = tareas.find((t) => t.id === 20);
    expect(bloqueadora?.fechaInicio.getHours()).toBe(9);
    expect(bloqueadora?.fechaInicio.getMinutes()).toBe(30);
    expect(prisma.excluidasCreadas).toHaveLength(0);
  });

  test('cascada: si la bloqueadora no tiene hueco libre, pide confirmacion antes de excluirla', async () => {
    const fecha = new Date(2026, 2, 4);
    const tareas: any[] = [
      {
        id: 10,
        descripcion: 'Tarea corta',
        fechaInicio: new Date(2026, 2, 4, 8, 0),
        fechaFin: new Date(2026, 2, 4, 8, 30),
        duracionMinutos: 30,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 11,
        descripcion: 'Tarea larga',
        fechaInicio: new Date(2026, 2, 4, 8, 30),
        fechaFin: new Date(2026, 2, 4, 10, 0),
        duracionMinutos: 90,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 20,
        descripcion: 'Tarea de equipo (bloqueadora)',
        fechaInicio: new Date(2026, 2, 4, 9, 0),
        fechaFin: new Date(2026, 2, 4, 9, 15),
        duracionMinutos: 15,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        conjuntoId: '9001',
        ubicacionId: 1,
        elementoId: 1,
        prioridad: 2,
        frecuencia: null,
        periodoAnio: 2026,
        periodoMes: 3,
        operarios: [
          { id: 'op-1', usuario: { nombre: 'Ana' } },
          { id: 'op-2', usuario: { nombre: 'Luis' } },
        ],
      },
      {
        // Ocupa el resto del dia de op-2: ya no queda hueco para reacomodar
        // la bloqueadora (20) en ningun lado despues de las 9:15.
        id: 30,
        descripcion: 'Tarea que llena el dia de Luis',
        fechaInicio: new Date(2026, 2, 4, 9, 15),
        fechaFin: new Date(2026, 2, 4, 17, 0),
        duracionMinutos: 465,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-2', usuario: { nombre: 'Luis' } }],
      },
    ];
    const prisma = construirPrisma(tareas);
    const service = new DefinicionTareaPreventivaService(prisma);

    // Primera llamada: sin confirmar. Debe devolver la vista previa con la
    // exclusion pendiente y NO escribir nada en la base de datos.
    const preview = await service.reordenarTareasBorradorDia({
      conjuntoId: '9001',
      fecha,
      tareaIds: [11, 10],
    });

    expect(preview).toMatchObject({ ok: true, requiereConfirmacion: true, aplicado: false });
    expect(preview.cambiosCascada).toEqual([
      expect.objectContaining({ tareaId: 20, accion: 'EXCLUIDA' }),
    ]);
    expect(prisma.tarea.update).not.toHaveBeenCalled();
    expect(prisma.tarea.create).not.toHaveBeenCalled();
    expect(prisma.tarea.delete).not.toHaveBeenCalled();
    expect(prisma.excluidasCreadas).toHaveLength(0);
    // Nada cambio en los datos originales.
    expect(tareas.find((t) => t.id === 11)?.fechaInicio.getHours()).toBe(8);
    expect(tareas.find((t) => t.id === 11)?.fechaInicio.getMinutes()).toBe(30);

    // Segunda llamada: confirmando. Ahora si se aplica todo, incluida la
    // exclusion de la bloqueadora.
    const confirmado = await service.reordenarTareasBorradorDia({
      conjuntoId: '9001',
      fecha,
      tareaIds: [11, 10],
      confirmarExclusiones: true,
    } as any);

    expect(confirmado).toMatchObject({ ok: true, requiereConfirmacion: false, aplicado: true });
    expect(tareas.find((t) => t.id === 11)?.fechaInicio.getHours()).toBe(8);
    expect(tareas.find((t) => t.id === 10)?.fechaInicio.getHours()).toBe(9);
    expect(tareas.find((t) => t.id === 10)?.fechaInicio.getMinutes()).toBe(30);
    // La bloqueadora fue excluida: ya no esta entre las tareas y quedo
    // registrada como excluida.
    expect(tareas.some((t) => t.id === 20)).toBe(false);
    expect(prisma.excluidasCreadas).toHaveLength(1);
    expect(prisma.excluidasCreadas[0]).toMatchObject({
      origenTareaId: 20,
      motivoTipo: 'REORDEN_MANUAL_SIN_HUECO',
    });
  });

  test('cascada: si la bloqueadora es una division por almuerzo, el reordenamiento se rechaza sin tocar nada', async () => {
    const fecha = new Date(2026, 2, 4);
    const tareas: any[] = [
      {
        id: 10,
        descripcion: 'Tarea corta',
        fechaInicio: new Date(2026, 2, 4, 8, 0),
        fechaFin: new Date(2026, 2, 4, 8, 30),
        duracionMinutos: 30,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 11,
        descripcion: 'Tarea larga',
        fechaInicio: new Date(2026, 2, 4, 8, 30),
        fechaFin: new Date(2026, 2, 4, 10, 0),
        duracionMinutos: 90,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 20,
        descripcion: 'Division por almuerzo · antes (bloqueadora)',
        fechaInicio: new Date(2026, 2, 4, 9, 0),
        fechaFin: new Date(2026, 2, 4, 9, 15),
        duracionMinutos: 15,
        ocurrenciaPlanId: 'OC-9',
        grupoPlanId: 'GRP-9',
        bloqueIndex: 1,
        bloquesTotales: 2,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
    ];
    const prisma = construirPrisma(tareas);
    const service = new DefinicionTareaPreventivaService(prisma);

    await expect(
      service.reordenarTareasBorradorDia({
        conjuntoId: '9001',
        fecha,
        tareaIds: [11, 10],
      }),
    ).rejects.toThrow(/división por almuerzo/i);

    expect(prisma.tarea.update).not.toHaveBeenCalled();
    expect(prisma.tarea.create).not.toHaveBeenCalled();
    expect(prisma.tarea.delete).not.toHaveBeenCalled();
    expect(tareas.find((t) => t.id === 11)?.fechaInicio.getHours()).toBe(8);
  });

  test('si el reordenamiento obliga a partir una tarea por el almuerzo, los dos tramos quedan agrupados', async () => {
    const fecha = new Date(2026, 2, 4);
    const tareas: any[] = [
      {
        id: 1,
        descripcion: 'Tarea larga (3h)',
        fechaInicio: new Date(2026, 2, 4, 9),
        fechaFin: new Date(2026, 2, 4, 12),
        duracionMinutos: 180,
        ocurrenciaPlanId: 'OC-1',
        grupoPlanId: null,
        bloqueIndex: null,
        bloquesTotales: null,
        ubicacionId: 1,
        elementoId: 1,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 2,
        descripcion: 'Tarea corta (1h)',
        fechaInicio: new Date(2026, 2, 4, 13),
        fechaFin: new Date(2026, 2, 4, 14),
        duracionMinutos: 60,
        ocurrenciaPlanId: 'OC-2',
        grupoPlanId: null,
        bloqueIndex: null,
        bloquesTotales: null,
        ubicacionId: 1,
        elementoId: 1,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
    ];
    const prisma = construirPrisma(tareas);
    const service = new DefinicionTareaPreventivaService(prisma);

    // Pedir que la corta (2) vaya antes que la larga (1) obliga a la larga a
    // arrancar mas tarde de lo que cabe antes del almuerzo: debe partirse en
    // dos tramos (uno antes, otro justo despues del almuerzo) en vez de
    // fallar o dejar los dos tramos como tareas sueltas sin relacion.
    const resultado = await service.reordenarTareasBorradorDia({
      conjuntoId: '9001',
      fecha,
      tareaIds: [2, 1],
    });

    expect(resultado.ok).toBe(true);
    expect(resultado.divididas).toBe(1);

    const tarea2 = tareas.find((t) => t.descripcion === 'Tarea corta (1h)');
    expect(tarea2.fechaInicio.getHours()).toBe(9);

    const tramosLargos = tareas
      .filter((t) => t.descripcion === 'Tarea larga (3h)')
      .sort((a, b) => a.fechaInicio - b.fechaInicio);
    expect(tramosLargos).toHaveLength(2);

    // Los dos tramos comparten grupoPlanId y quedan indexados 1/2 de 2.
    const grupoPlanId = tramosLargos[0].grupoPlanId;
    expect(grupoPlanId).toBeTruthy();
    expect(tramosLargos[1].grupoPlanId).toBe(grupoPlanId);
    expect(tramosLargos[0]).toMatchObject({ bloqueIndex: 1, bloquesTotales: 2 });
    expect(tramosLargos[1]).toMatchObject({ bloqueIndex: 2, bloquesTotales: 2 });

    // Un tramo termina justo al empezar el almuerzo y el otro arranca justo
    // al terminarlo.
    expect(tramosLargos[0].fechaInicio.getHours()).toBe(10);
    expect(tramosLargos[0].fechaFin.getHours()).toBe(12);
    expect(tramosLargos[1].fechaInicio.getHours()).toBe(13);
    expect(tramosLargos[1].fechaFin.getHours()).toBe(14);
  });

  test('omite los bloques de una division por almuerzo pero sigue reordenando el resto del dia a su alrededor', async () => {
    const fecha = new Date(2026, 2, 4);
    // El frontend suele enviar la vista completa del dia (aqui filtrada por
    // el mismo operario), no solo las dos tareas que el usuario movio. La
    // division por almuerzo (20/21) queda en medio de esa vista pero no debe
    // reflotarse: sus dos tramos deben conservar exactamente su horario.
    const tareas: any[] = [
      {
        id: 30,
        descripcion: 'Tarea suelta A',
        fechaInicio: new Date(2026, 2, 4, 8),
        fechaFin: new Date(2026, 2, 4, 9),
        duracionMinutos: 60,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 20,
        descripcion: 'Division por almuerzo · antes',
        fechaInicio: new Date(2026, 2, 4, 9),
        fechaFin: new Date(2026, 2, 4, 10),
        duracionMinutos: 60,
        ocurrenciaPlanId: 'OC-1',
        grupoPlanId: 'GRP-1',
        bloqueIndex: 1,
        bloquesTotales: 2,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 31,
        descripcion: 'Tarea suelta B',
        fechaInicio: new Date(2026, 2, 4, 11),
        fechaFin: new Date(2026, 2, 4, 12),
        duracionMinutos: 60,
        ocurrenciaPlanId: null,
        grupoPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 21,
        descripcion: 'Division por almuerzo · despues',
        fechaInicio: new Date(2026, 2, 4, 13),
        fechaFin: new Date(2026, 2, 4, 14),
        duracionMinutos: 60,
        ocurrenciaPlanId: 'OC-1',
        grupoPlanId: 'GRP-1',
        bloqueIndex: 2,
        bloquesTotales: 2,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
    ];
    const prisma = construirPrisma(tareas);
    const service = new DefinicionTareaPreventivaService(prisma);

    // Vista completa del dia con la tarea suelta B (31) arrastrada delante
    // de la tarea suelta A (30); la division (20) va incluida tal cual la
    // manda el frontend pero no cambio de posicion relativa.
    const resultado = await service.reordenarTareasBorradorDia({
      conjuntoId: '9001',
      fecha,
      tareaIds: [20, 31, 30],
    });

    expect(resultado).toMatchObject({ ok: true, omitidasPorDivisionAlmuerzo: 1 });
    // Las dos tareas sueltas se intercambian alrededor de la division.
    expect(tareas.find((tarea) => tarea.id === 31)?.fechaInicio.getHours()).toBe(8);
    expect(tareas.find((tarea) => tarea.id === 30)?.fechaInicio.getHours()).toBe(11);
    // Los dos tramos de la division conservan su horario exacto: no se
    // tocaron ni se recrearon.
    expect(tareas.find((tarea) => tarea.id === 20)?.fechaInicio.getHours()).toBe(9);
    expect(tareas.find((tarea) => tarea.id === 21)?.fechaInicio.getHours()).toBe(13);
    expect(
      prisma.tarea.update.mock.calls.some(([args]: any[]) => args.where.id === 20),
    ).toBe(false);
    expect(
      prisma.tarea.update.mock.calls.some(([args]: any[]) => args.where.id === 21),
    ).toBe(false);
  });
});
