import { Frecuencia, TipoTarea } from '@prisma/client';

import { intentarReemplazoPorPrioridadBaja } from '../../src/utils/schedulerUtils';
import { DefinicionTareaPreventivaService } from '../../src/services/DefinicionTareaPreventivaService';

describe('reemplazo automatico por prioridad', () => {
  test('PU-RP1 - acumula dos P3 cuando una sola no libera espacio suficiente', async () => {
    const fecha = new Date(2026, 2, 3);
    const at = (hora: number) => new Date(2026, 2, 3, hora);
    const tareas: any[] = [
      {
        id: 1,
        prioridad: 3,
        fechaInicio: at(8),
        fechaFin: at(9),
        borrador: true,
        estado: 'ASIGNADA',
        grupoPlanId: null,
        bloqueIndex: null,
        bloquesTotales: null,
        operarios: [{ id: 'op-1' }],
      },
      {
        id: 2,
        prioridad: 3,
        fechaInicio: at(9),
        fechaFin: at(10),
        borrador: true,
        estado: 'ASIGNADA',
        grupoPlanId: null,
        bloqueIndex: null,
        bloquesTotales: null,
        operarios: [{ id: 'op-1' }],
      },
      {
        id: 3,
        prioridad: 1,
        fechaInicio: at(10),
        fechaFin: at(12),
        borrador: true,
        estado: 'ASIGNADA',
        grupoPlanId: null,
        bloqueIndex: null,
        bloquesTotales: null,
        operarios: [{ id: 'op-1' }],
      },
    ];
    let secuencia = 3;

    const filtrar = (where: any) =>
      tareas.filter((tarea) => {
        if (where?.id?.notIn?.includes(tarea.id)) return false;
        if (where?.id?.in && !where.id.in.includes(tarea.id)) return false;
        if (where?.prioridad?.in && !where.prioridad.in.includes(tarea.prioridad)) {
          return false;
        }
        if (where?.borrador != null && tarea.borrador !== where.borrador) return false;
        if (where?.estado?.notIn?.includes(tarea.estado)) return false;
        if (
          where?.operarios?.some?.id?.in &&
          !tarea.operarios.some((op: any) =>
            where.operarios.some.id.in.includes(op.id),
          )
        ) {
          return false;
        }
        if (where?.fechaInicio?.lte && tarea.fechaInicio > where.fechaInicio.lte) {
          return false;
        }
        if (where?.fechaFin?.gte && tarea.fechaFin < where.fechaFin.gte) {
          return false;
        }
        return true;
      });

    const prisma: any = {
      tarea: {
        findMany: jest.fn(async ({ where }: any) => filtrar(where)),
        findUnique: jest.fn(async ({ where }: any) =>
          tareas.find((tarea) => tarea.id === where.id) ?? null,
        ),
        update: jest.fn(async ({ where, data }: any) => {
          const tarea = tareas.find((item) => item.id === where.id);
          Object.assign(tarea, data);
          return tarea;
        }),
        updateMany: jest.fn(async ({ where, data }: any) => {
          const afectadas = filtrar(where);
          for (const tarea of afectadas) Object.assign(tarea, data);
          return { count: afectadas.length };
        }),
        create: jest.fn(async ({ data }: any) => {
          const creada = {
            ...data,
            id: ++secuencia,
            operarios: [{ id: 'op-1' }],
          };
          tareas.push(creada);
          return creada;
        }),
      },
      $transaction: jest.fn(async (callback: any) => callback(prisma)),
    };

    const resultado = await intentarReemplazoPorPrioridadBaja({
      prisma,
      conjuntoId: '9001',
      fechaDia: fecha,
      startMin: 8 * 60,
      endMin: 12 * 60,
      bloqueos: [],
      durMin: 120,
      payload: {
        descripcion: 'Mantenimiento medio',
        tipo: TipoTarea.PREVENTIVA,
        frecuencia: Frecuencia.MENSUAL,
        definicionId: 77,
        prioridad: 2,
        supervisorId: null,
        ubicacionId: 1,
        elementoId: 2,
        conjuntoId: '9001',
        borrador: true,
        periodoAnio: 2026,
        periodoMes: 3,
        operariosIds: ['op-1'],
      },
      prioridadesCandidatas: [3],
      incluirBorradorEnAgenda: true,
      incluirPublicadasEnAgenda: true,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.reprogramadasIds).toEqual([1, 2]);
    expect(resultado.bloques).toEqual([{ i: 8 * 60, f: 10 * 60 }]);
    expect(tareas.find((tarea) => tarea.id === 1)?.estado).toBe(
      'PENDIENTE_REPROGRAMACION',
    );
    expect(tareas.find((tarea) => tarea.id === 2)?.estado).toBe(
      'PENDIENTE_REPROGRAMACION',
    );
    expect(prisma.tarea.create).toHaveBeenCalledTimes(1);
  });

  test('PU-RP2 - la tarea desplazada pasa a excluidas y se retira del borrador', async () => {
    const tarea = {
      id: 15,
      conjuntoId: '9001',
      periodoAnio: 2026,
      periodoMes: 3,
      definicionId: 55,
      descripcion: 'Limpieza de pasillo',
      frecuencia: Frecuencia.MENSUAL,
      diaSemanaProgramado: null,
      prioridad: 3,
      duracionMinutos: 60,
      fechaInicio: new Date(2026, 2, 3, 8),
      fechaFin: new Date(2026, 2, 3, 9),
      fechaInicioOriginal: null,
      ubicacionId: 1,
      ubicacion: { nombre: 'Torre A' },
      elementoId: 2,
      elemento: { nombre: 'Pasillo' },
      supervisorId: null,
      supervisor: null,
      operarios: [{ id: 'op-1', usuario: { nombre: 'Pedro' } }],
    };
    const prisma: any = {
      tarea: {
        findUnique: jest.fn().mockResolvedValue(tarea),
        delete: jest.fn().mockResolvedValue(tarea),
      },
      preventivaExcluidaBorrador: {
        create: jest.fn(async ({ data }: any) => ({ ...data, id: 90 })),
      },
      preventivaBorradorEvento: {
        create: jest.fn().mockResolvedValue({ id: 91 }),
      },
      auditoriaEvento: {
        create: jest.fn().mockResolvedValue({}),
      },
    };
    const service: any = new DefinicionTareaPreventivaService(prisma);

    await service.moverReemplazadasAExcluidas({
      tareaIds: [15],
      reemplazadaPorDefId: 77,
      reemplazadaPorDescripcion: 'Mantenimiento obligatorio',
    });

    expect(prisma.preventivaExcluidaBorrador.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          origenTareaId: 15,
          prioridad: 3,
          motivoTipo: 'REEMPLAZO_PRIORIDAD',
        }),
      }),
    );
    expect(prisma.tarea.delete).toHaveBeenCalledWith({ where: { id: 15 } });
  });
});
