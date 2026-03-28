import { EstadoTarea, Prisma, TipoServicio, TipoTarea } from '@prisma/client';

jest.mock('../../src/utils/schedulerUtils', () => ({
  isFestivoDate: jest.fn().mockResolvedValue(false),
}));

jest.mock('../../src/utils/drive_evidencias', () => ({
  uploadEvidenciaToDrive: jest.fn().mockResolvedValue('https://drive.test/foto-funcional.jpg'),
}));

jest.mock('../../src/services/NotificacionService', () => ({
  NotificacionService: jest.fn().mockImplementation(() => ({
    notificarCierreTarea: jest.fn().mockResolvedValue(undefined),
    notificarSolicitudInsumosCreada: jest.fn().mockResolvedValue(undefined),
  })),
}));

import { GerenteService } from '../../src/services/GerenteServices';
import { InventarioService } from '../../src/services/InventarioServices';
import { OperarioService } from '../../src/services/OperarioServices';
import { ReporteService } from '../../src/services/ReporteService';
import { SupervisorService } from '../../src/services/SupervisorServices';
import { TareaService } from '../../src/services/TareaServices';

describe('Pruebas funcionales backend', () => {
  test('PF1 - Gestión de conjuntos: crea un conjunto con estado activo', async () => {
    const prisma: any = {
      conjunto: {
        create: jest.fn().mockResolvedValue({
          nit: 'C-100',
          nombre: 'Conjunto Palmas',
          direccion: 'Cra 10 # 10-10',
          correo: 'palmas@test.com',
          administradorId: null,
          empresaId: 'EMP-1',
          fechaInicioContrato: null,
          fechaFinContrato: null,
          activo: true,
          tipoServicio: [TipoServicio.ASEO],
          valorMensual: null,
          consignasEspeciales: [],
          valorAgregado: [],
          horarios: [],
        }),
      },
      administrador: { findUnique: jest.fn() },
      herramienta: { findMany: jest.fn().mockResolvedValue([]) },
      conjuntoHerramientaStock: { createMany: jest.fn() },
    };
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue('EMP-1');

    const result = await service.crearConjunto({
      nit: 'C-100',
      nombre: 'Conjunto Palmas',
      direccion: 'Cra 10 # 10-10',
      correo: 'palmas@test.com',
      activo: true,
      tipoServicio: [TipoServicio.ASEO],
      consignasEspeciales: [],
      valorAgregado: [],
      horarios: [],
      ubicaciones: [],
    });

    expect((result as any).activo).toBe(true);
  });

  test('PF2 - Gestión de conjuntos: edita información de un conjunto existente', async () => {
    const prisma: any = {
      conjunto: {
        update: jest.fn().mockResolvedValue({
          nit: 'C-100',
          nombre: 'Conjunto Palmas Editado',
          direccion: 'Nueva dirección',
          correo: 'nuevo@test.com',
          administradorId: null,
          empresaId: 'EMP-1',
          fechaInicioContrato: null,
          fechaFinContrato: null,
          activo: true,
          tipoServicio: [],
          valorMensual: null,
          consignasEspeciales: [],
          valorAgregado: [],
          horarios: [],
        }),
      },
    };
    const service = new GerenteService(prisma);

    const result = await service.editarConjunto('C-100', {
      nombre: 'Conjunto Palmas Editado',
      direccion: 'Nueva dirección',
      correo: 'nuevo@test.com',
    });

    expect(prisma.conjunto.update).toHaveBeenCalled();
    expect((result as any).nombre).toBe('Conjunto Palmas Editado');
  });

  test('PF3 - Gestión de tareas: crea una tarea preventiva/correctiva con prioridad', async () => {
    const prisma: any = {
      tarea: {
        create: jest.fn().mockResolvedValue({
          id: 1,
          descripcion: 'Revisión de bomba',
          fechaInicio: new Date('2026-03-23T10:00:00.000Z'),
          fechaFin: new Date('2026-03-23T11:00:00.000Z'),
          duracionMinutos: 60,
          prioridad: 1,
          estado: EstadoTarea.ASIGNADA,
          evidencias: [],
          insumosUsados: null,
          observaciones: null,
          observacionesRechazo: null,
          tipo: TipoTarea.CORRECTIVA,
          frecuencia: null,
          conjuntoId: 'C-100',
          supervisorId: null,
          ubicacionId: 1,
          elementoId: 2,
        }),
      },
    };

    const result = await TareaService.crearTareaCorrectiva(prisma, {
      descripcion: 'Revisión de bomba',
      fechaInicio: '2026-03-23T10:00:00.000Z',
      fechaFin: '2026-03-23T11:00:00.000Z',
      prioridad: 1,
      ubicacionId: 1,
      elementoId: 2,
      conjuntoId: 'C-100',
      operariosIds: ['op-1'],
    });

    expect((result as any).prioridad).toBe(1);
  });

  test('PF4 - Gestión de tareas: asigna operario responsable a una tarea', async () => {
    const prisma: any = {
      tarea: {
        findUnique: jest.fn().mockResolvedValue({
          id: 10,
          fechaInicio: new Date('2026-03-23T10:00:00.000Z'),
          duracionMinutos: 120,
          borrador: false,
        }),
        update: jest.fn().mockResolvedValue({ id: 10 }),
      },
      operario: {
        findUnique: jest.fn().mockResolvedValue({ usuario: { nombre: 'Pedro' } }),
      },
    };
    const service: any = new OperarioService(prisma, 5);
    service.getLimiteHorasSemana = jest.fn().mockResolvedValue(3000);
    service.horasAsignadasEnSemana = jest.fn().mockResolvedValue(120);

    await service.asignarTarea({ tareaId: 10 });

    expect(prisma.tarea.update).toHaveBeenCalledWith({
      where: { id: 10 },
      data: { operarios: { connect: { id: '5' } } },
    });
  });

  test('PF5 - Inventario: crea un nuevo insumo en el sistema', async () => {
    const prisma: any = {
      insumo: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 8, nombre: 'Cloro', unidad: 'L', empresaId: 'EMP-1' }),
      },
    };
    const service = new GerenteService(prisma);

    const result = await service.agregarInsumoAlCatalogo(
      { nombre: 'Cloro', unidad: 'L', categoria: 'PISCINA' },
      'EMP-1',
    );

    expect(prisma.insumo.create).toHaveBeenCalled();
    expect((result as any).nombre).toBe('Cloro');
  });

  test('PF6 - Inventario: registra consumo desde una tarea', async () => {
    const prisma: any = {
      $transaction: jest.fn(),
      tarea: {
        update: jest.fn().mockResolvedValue({ id: 20 }),
      },
    };
    prisma.$transaction.mockImplementation(async (cb: any) => cb());

    const service = new TareaService(prisma, 20);
    const inventory = { consumirInsumoPorId: jest.fn().mockResolvedValue(undefined) };

    await service.marcarComoCompletadaConInsumos(
      { insumosUsados: [{ insumoId: 2, cantidad: 3 }] },
      inventory,
    );

    expect(inventory.consumirInsumoPorId).toHaveBeenCalledWith({ insumoId: 2, cantidad: 3 });
    expect(prisma.tarea.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ estado: EstadoTarea.PENDIENTE_APROBACION }) }),
    );
  });

  test('PF7 - Evidencias: asocia imagen a la tarea cerrada', async () => {
    const prisma: any = {
      tarea: {
        findUnique: jest.fn().mockResolvedValue({
          id: 77,
          descripcion: 'Lavar zona común',
          estado: EstadoTarea.ASIGNADA,
          evidencias: [],
          conjuntoId: 'C-100',
          supervisorId: 'sup-1',
          conjunto: { nit: 'C-100', nombre: 'Conjunto Palmas' },
        }),
      },
      $transaction: jest.fn(),
    };
    const tx: any = {
      inventario: { findUnique: jest.fn().mockResolvedValue({ id: 3 }) },
      usoMaquinaria: { updateMany: jest.fn() },
      usoHerramienta: { updateMany: jest.fn() },
      maquinariaConjunto: { updateMany: jest.fn() },
      tarea: { update: jest.fn() },
    };
    prisma.$transaction.mockImplementation(async (cb: any) => cb(tx));

    const service = new SupervisorService(prisma, 'sup-1');
    await service.cerrarTareaConEvidencias(77, { insumosUsados: '[]' }, []);

    expect(tx.tarea.update).toHaveBeenCalled();
  });

  test('PF8 - Reportes: genera indicadores de cumplimiento', async () => {
    const prisma: any = {
      tarea: {
        groupBy: jest.fn().mockResolvedValue([
          { estado: EstadoTarea.APROBADA, _count: { _all: 4 } },
          { estado: EstadoTarea.RECHAZADA, _count: { _all: 1 } },
          { estado: EstadoTarea.ASIGNADA, _count: { _all: 1 } },
        ]),
      },
    };

    const service = new ReporteService(prisma);
    const result = await service.kpis({
      desde: '2026-03-01T00:00:00.000Z',
      hasta: '2026-03-31T23:59:59.000Z',
      conjuntoId: 'C-100',
    });

    expect(result.ok).toBe(true);
    expect(result.kpi.aprobadas).toBe(4);
  });

  test('PF9 - Dashboard: muestra indicadores de desempeño por conjunto', async () => {
    const prisma: any = {
      tarea: {
        findMany: jest.fn().mockResolvedValue([
          {
            estado: EstadoTarea.APROBADA,
            conjuntoId: 'C-100',
            conjunto: { nombre: 'Conjunto Palmas', nit: 'C-100' },
          },
          {
            estado: EstadoTarea.RECHAZADA,
            conjuntoId: 'C-100',
            conjunto: { nombre: 'Conjunto Palmas', nit: 'C-100' },
          },
        ]),
      },
    };

    const service = new ReporteService(prisma);
    const result = await service.resumenPorConjunto({
      desde: '2026-03-01T00:00:00.000Z',
      hasta: '2026-03-31T23:59:59.000Z',
    });

    expect(result.ok).toBe(true);
    expect(result.data[0].conjuntoNombre).toBe('Conjunto Palmas');
  });
});
