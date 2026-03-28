import { EstadoTarea, Prisma, TipoTarea } from '@prisma/client';

const notificarSolicitudInsumosCreadaMock = jest.fn();

jest.mock('../../src/utils/schedulerUtils', () => ({
  isFestivoDate: jest.fn().mockResolvedValue(false),
}));

jest.mock('../../src/utils/drive_evidencias', () => ({
  uploadEvidenciaToDrive: jest.fn().mockResolvedValue('https://drive.test/integracion.jpg'),
}));

jest.mock('../../src/services/NotificacionService', () => ({
  NotificacionService: jest.fn().mockImplementation(() => ({
    notificarCierreTarea: jest.fn().mockResolvedValue(undefined),
    notificarSolicitudInsumosCreada: notificarSolicitudInsumosCreadaMock,
  })),
}));

import { ReporteService } from '../../src/services/ReporteService';
import { SolicitudInsumoService } from '../../src/services/SolicitudInsumoServices';
import { SupervisorService } from '../../src/services/SupervisorServices';
import { TareaService } from '../../src/services/TareaServices';

describe('Pruebas de integración backend', () => {
  test('PI1 - Actividades + Evidencias: cerrar tarea adjunta evidencias', async () => {
    const prisma: any = {
      tarea: {
        findUnique: jest.fn().mockResolvedValue({
          id: 90,
          descripcion: 'Pulir pisos',
          estado: EstadoTarea.EN_PROCESO,
          evidencias: [],
          conjuntoId: 'C-1',
          supervisorId: 'sup-1',
          conjunto: { nit: 'C-1', nombre: 'Conjunto Uno' },
        }),
      },
      $transaction: jest.fn(),
    };
    const tx: any = {
      inventario: { findUnique: jest.fn().mockResolvedValue({ id: 4 }) },
      usoMaquinaria: { updateMany: jest.fn() },
      usoHerramienta: { updateMany: jest.fn() },
      maquinariaConjunto: { updateMany: jest.fn() },
      tarea: { update: jest.fn() },
    };
    prisma.$transaction.mockImplementation(async (cb: any) => cb(tx));

    const service = new SupervisorService(prisma, 'sup-1');
    await service.cerrarTareaConEvidencias(90, { insumosUsados: '[]' }, []);

    expect(tx.tarea.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ estado: EstadoTarea.PENDIENTE_APROBACION }),
      }),
    );
  });

  test('PI2 - Actividades + Inventario: tarea completada consume insumos', async () => {
    const prisma: any = {
      $transaction: jest.fn(),
      tarea: { update: jest.fn() },
    };
    prisma.$transaction.mockImplementation(async (cb: any) => cb());

    const inventory = { consumirInsumoPorId: jest.fn().mockResolvedValue(undefined) };
    const service = new TareaService(prisma, 91);

    await service.marcarComoCompletadaConInsumos(
      { insumosUsados: [{ insumoId: 1, cantidad: 2 }] },
      inventory,
    );

    expect(inventory.consumirInsumoPorId).toHaveBeenCalled();
    expect(prisma.tarea.update).toHaveBeenCalled();
  });

  test('PI3 - Inventario + Notificaciones: solicitud de insumos notifica al crear', async () => {
    const prisma: any = {
      conjunto: { findUnique: jest.fn().mockResolvedValue({ nit: 'C-1' }) },
      insumo: { findMany: jest.fn().mockResolvedValue([{ id: 1 }, { id: 2 }]) },
      solicitudInsumo: {
        create: jest.fn().mockResolvedValue({
          id: 15,
          conjuntoId: 'C-1',
          insumosSolicitados: [],
        }),
      },
    };

    const service = new SolicitudInsumoService(prisma);
    await service.crear({
      conjuntoId: 'C-1',
      empresaId: 'EMP-1',
      items: [
        { insumoId: 1, cantidad: 3 },
        { insumoId: 2, cantidad: 1 },
      ],
    }, 'actor-1');

    expect(notificarSolicitudInsumosCreadaMock).toHaveBeenCalledWith(
      expect.objectContaining({ solicitudId: 15, conjuntoId: 'C-1' }),
    );
  });

  test('PI4 - Actividades + Reportes: tareas reflejan métricas de cumplimiento', async () => {
    const prisma: any = {
      tarea: {
        groupBy: jest.fn().mockResolvedValue([
          { estado: EstadoTarea.APROBADA, _count: { _all: 3 } },
          { estado: EstadoTarea.NO_COMPLETADA, _count: { _all: 1 } },
        ]),
      },
    };

    const service = new ReporteService(prisma);
    const result = await service.kpis({
      desde: '2026-03-01T00:00:00.000Z',
      hasta: '2026-03-31T23:59:59.000Z',
      conjuntoId: 'C-1',
    });

    expect(result.kpi.cerradasOperativas).toBe(4);
    expect(result.kpi.tasaCierrePct).toBe(100);
  });

  test('PI5 - Conjuntos + Tareas: crea tarea vinculada correctamente al conjunto', async () => {
    const prisma: any = {
      tarea: {
        create: jest.fn().mockResolvedValue({
          id: 101,
          descripcion: 'Mantenimiento general',
          fechaInicio: new Date('2026-03-23T07:00:00.000Z'),
          fechaFin: new Date('2026-03-23T08:00:00.000Z'),
          duracionMinutos: 60,
          prioridad: 2,
          estado: EstadoTarea.ASIGNADA,
          evidencias: [],
          insumosUsados: null,
          observaciones: null,
          observacionesRechazo: null,
          tipo: TipoTarea.CORRECTIVA,
          frecuencia: null,
          conjuntoId: 'C-1',
          supervisorId: null,
          ubicacionId: 1,
          elementoId: 1,
        }),
      },
    };

    await TareaService.crearTareaCorrectiva(prisma, {
      descripcion: 'Mantenimiento general',
      fechaInicio: '2026-03-23T07:00:00.000Z',
      fechaFin: '2026-03-23T08:00:00.000Z',
      ubicacionId: 1,
      elementoId: 1,
      conjuntoId: 'C-1',
    });

    expect(prisma.tarea.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ conjunto: { connect: { nit: 'C-1' } } }),
      }),
    );
  });
});
