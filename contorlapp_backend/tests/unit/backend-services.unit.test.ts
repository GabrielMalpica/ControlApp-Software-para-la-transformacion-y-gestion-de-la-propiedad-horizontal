import fs from 'fs';

import { EstadoTarea, Prisma, TipoServicio, TipoTarea } from '@prisma/client';

jest.mock('../../src/utils/schedulerUtils', () => ({
  isFestivoDate: jest.fn().mockResolvedValue(false),
}));

jest.mock('../../src/utils/drive_evidencias', () => ({
  uploadEvidenciaToDrive: jest.fn().mockResolvedValue('https://drive.test/evidencia.jpg'),
}));

jest.mock('../../src/services/NotificacionService', () => ({
  NotificacionService: jest.fn().mockImplementation(() => ({
    notificarCierreTarea: jest.fn().mockResolvedValue(undefined),
  })),
}));

import { GerenteService } from '../../src/services/GerenteServices';
import { InventarioService } from '../../src/services/InventarioServices';
import { SupervisorService } from '../../src/services/SupervisorServices';
import { TareaService } from '../../src/services/TareaServices';

describe('Pruebas unitarias backend', () => {
  beforeEach(() => {
    jest.restoreAllMocks();
  });

  test('PU1 - Servicio de conjuntos: crea un conjunto con metadatos requeridos', async () => {
    const prisma: any = {
      administrador: { findUnique: jest.fn().mockResolvedValue({ id: 'admin-1' }) },
      conjunto: {
        create: jest.fn().mockResolvedValue({
          nit: '9001',
          nombre: 'Conjunto Central',
          direccion: 'Calle 1 # 2-3',
          correo: 'admin@conjunto.com',
          administradorId: 'admin-1',
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
      herramienta: { findMany: jest.fn().mockResolvedValue([{ id: 10 }, { id: 11 }]) },
      conjuntoHerramientaStock: { createMany: jest.fn().mockResolvedValue({ count: 2 }) },
    };

    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue('EMP-1');

    const result = await service.crearConjunto({
      nit: '9001',
      nombre: 'Conjunto Central',
      direccion: 'Calle 1 # 2-3',
      correo: 'admin@conjunto.com',
      administradorId: 'admin-1',
      activo: true,
      tipoServicio: [TipoServicio.ASEO],
      consignasEspeciales: [],
      valorAgregado: [],
      horarios: [],
      ubicaciones: [],
    });

    expect(prisma.conjunto.create).toHaveBeenCalled();
    expect(prisma.conjuntoHerramientaStock.createMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.arrayContaining([
          expect.objectContaining({ conjuntoId: '9001', herramientaId: 10, cantidad: 0 }),
        ]),
      }),
    );
    expect((result as any).nit).toBe('9001');
  });

  test('PU3 - Servicio de tareas: registra una tarea en un conjunto', async () => {
    const prisma: any = {
      tarea: {
        create: jest.fn().mockResolvedValue({
          id: 55,
          descripcion: 'Lubricar puerta principal',
          fechaInicio: new Date('2026-03-23T08:00:00.000Z'),
          fechaFin: new Date('2026-03-23T09:00:00.000Z'),
          duracionMinutos: 60,
          prioridad: 2,
          estado: EstadoTarea.ASIGNADA,
          evidencias: [],
          insumosUsados: null,
          observaciones: null,
          observacionesRechazo: null,
          tipo: TipoTarea.CORRECTIVA,
          frecuencia: null,
          conjuntoId: '9001',
          supervisorId: 'sup-1',
          ubicacionId: 1,
          elementoId: 2,
        }),
      },
    };

    const result = await TareaService.crearTareaCorrectiva(prisma, {
      descripcion: 'Lubricar puerta principal',
      fechaInicio: '2026-03-23T08:00:00.000Z',
      fechaFin: '2026-03-23T09:00:00.000Z',
      prioridad: 2,
      tipo: TipoTarea.CORRECTIVA,
      ubicacionId: 1,
      elementoId: 2,
      conjuntoId: '9001',
      supervisorId: 'sup-1',
      operariosIds: ['op-1'],
    });

    expect(prisma.tarea.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          descripcion: 'Lubricar puerta principal',
          conjunto: { connect: { nit: '9001' } },
          operarios: { connect: [{ id: 'op-1' }] },
        }),
      }),
    );
    expect((result as any).id).toBe(55);
  });

  test('PU4 - Servicio de inventario: registra un nuevo insumo', async () => {
    const prisma: any = {
      inventarioInsumo: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 1, inventarioId: 99, insumoId: 7, cantidad: 3 }),
      },
    };

    const service = new InventarioService(prisma, 99);
    const result = await service.agregarInsumo({ insumoId: 7, cantidad: 3 });

    expect(prisma.inventarioInsumo.create).toHaveBeenCalledWith({
      data: { inventarioId: 99, insumoId: 7, cantidad: 3 },
    });
    expect((result as any).cantidad).toBe(3);
  });

  test('PU5 - Servicio de inventario: registra consumo de insumo', async () => {
    const prisma: any = {
      $transaction: jest.fn(),
    };
    const tx: any = {
      inventarioInsumo: {
        findUnique: jest.fn().mockResolvedValue({
          id: 33,
          cantidad: new Prisma.Decimal(10),
          insumo: { nombre: 'Cloro' },
        }),
        update: jest.fn().mockResolvedValue({ id: 33, inventarioId: 50, insumoId: 4, cantidad: new Prisma.Decimal(6) }),
      },
      consumoInsumo: {
        create: jest.fn().mockResolvedValue({ id: 1 }),
      },
    };
    prisma.$transaction.mockImplementation(async (cb: any) => cb(tx));

    const service = new InventarioService(prisma, 50);
    const result = await service.consumirStock({
      conjuntoId: '9001',
      insumoId: 4,
      cantidad: 4,
      observacion: 'Consumo de prueba',
    });

    expect(tx.inventarioInsumo.update).toHaveBeenCalled();
    expect(tx.consumoInsumo.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ insumoId: 4, observacion: 'Consumo de prueba' }),
      }),
    );
    expect((result as any).cantidad).toBe(6);
  });

  test('PU6 - Servicio de evidencias: guarda evidencia asociada a una tarea', async () => {
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);
    jest.spyOn(fs, 'unlinkSync').mockImplementation(() => undefined);

    const prisma: any = {
      tarea: {
        findUnique: jest.fn().mockResolvedValue({
          id: 88,
          descripcion: 'Limpiar piscina',
          estado: EstadoTarea.EN_PROCESO,
          evidencias: ['https://previa.test/1.jpg'],
          conjuntoId: '9001',
          supervisorId: 'sup-1',
          conjunto: { nit: '9001', nombre: 'Conjunto Sol' },
        }),
      },
      $transaction: jest.fn(),
    };
    const tx: any = {
      inventario: { findUnique: jest.fn().mockResolvedValue({ id: 12 }) },
      inventarioInsumo: { findUnique: jest.fn() },
      consumoInsumo: { create: jest.fn() },
      usoMaquinaria: { updateMany: jest.fn().mockResolvedValue({ count: 0 }) },
      usoHerramienta: { updateMany: jest.fn().mockResolvedValue({ count: 0 }) },
      maquinariaConjunto: { updateMany: jest.fn().mockResolvedValue({ count: 0 }) },
      tarea: { update: jest.fn().mockResolvedValue({ id: 88 }) },
    };
    prisma.$transaction.mockImplementation(async (cb: any) => cb(tx));

    const service = new SupervisorService(prisma, 'sup-1');
    await service.cerrarTareaConEvidencias(
      88,
      { observaciones: 'Actividad finalizada', insumosUsados: '[]' },
      [
        {
          path: '/tmp/evidencia.jpg',
          originalname: 'evidencia.jpg',
          mimetype: 'image/jpeg',
        } as Express.Multer.File,
      ],
    );

    expect(tx.tarea.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 88 },
        data: expect.objectContaining({
          evidencias: [
            'https://previa.test/1.jpg',
            'https://drive.test/evidencia.jpg',
          ],
          estado: EstadoTarea.PENDIENTE_APROBACION,
        }),
      }),
    );
  });
});
