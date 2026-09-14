import fs from 'fs';

import { EstadoTarea } from '@prisma/client';

jest.mock('../../src/utils/drive_evidencias', () => ({
  uploadEvidenciaToDrive: jest.fn().mockResolvedValue('https://drive.test/evidencia.jpg'),
  buildEvidenciaFileName: jest.fn().mockReturnValue('evidencia.jpg'),
}));

jest.mock('../../src/services/NotificacionService', () => ({
  NotificacionService: jest.fn().mockImplementation(() => ({
    notificarCierreTarea: jest.fn().mockResolvedValue(undefined),
  })),
}));

import { uploadEvidenciaToDrive } from '../../src/utils/drive_evidencias';
import { OperarioService } from '../../src/services/OperarioServices';

// La cola offline del operario reenvía el mismo cierre (mismo
// clienteCierreId) si nunca recibió confirmación del backend. Este cierre
// debe poder reintentarse sin re-subir evidencias ni reprocesar inventario.
describe('Idempotencia de cierre de tarea (cola offline del operario)', () => {
  const CLIENTE_CIERRE_ID = '11111111-1111-4111-8111-111111111111';

  function buildPrismaMock() {
    const tx: any = {
      inventario: { findUnique: jest.fn().mockResolvedValue({ id: 12 }) },
      inventarioInsumo: { findUnique: jest.fn() },
      consumoInsumo: { create: jest.fn() },
      usoMaquinaria: { updateMany: jest.fn().mockResolvedValue({ count: 0 }) },
      usoHerramienta: { updateMany: jest.fn().mockResolvedValue({ count: 0 }) },
      maquinariaConjunto: { updateMany: jest.fn().mockResolvedValue({ count: 0 }) },
      tarea: { update: jest.fn().mockResolvedValue({ id: 88 }) },
      cierreTareaIdempotencia: { create: jest.fn().mockResolvedValue({}) },
    };

    const prisma: any = {
      tarea: {
        findUnique: jest.fn().mockResolvedValue({
          id: 88,
          descripcion: 'Limpiar piscina',
          estado: EstadoTarea.EN_PROCESO,
          borrador: false,
          evidencias: [],
          conjuntoId: '9001',
          supervisorId: 'sup-1',
          operarios: [{ id: '77' }],
          conjunto: { nit: '9001', nombre: 'Conjunto Sol' },
        }),
      },
      usuario: { findUnique: jest.fn().mockResolvedValue({ nombre: 'Operario Test' }) },
      cierreTareaIdempotencia: { findUnique: jest.fn().mockResolvedValue(null) },
      $transaction: jest.fn(),
    };
    prisma.$transaction.mockImplementation((cb: any) => cb(tx));

    return { prisma, tx };
  }

  const archivo = {
    path: '/tmp/evidencia.jpg',
    originalname: 'evidencia.jpg',
    mimetype: 'image/jpeg',
  } as Express.Multer.File;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);
    jest.spyOn(fs, 'unlinkSync').mockImplementation(() => undefined);
  });

  test('primer envío: procesa el cierre y crea la marca de idempotencia dentro de la misma transacción', async () => {
    const { prisma, tx } = buildPrismaMock();
    const service = new OperarioService(prisma, 77);

    await service.cerrarTareaConEvidencias(
      88,
      { observaciones: 'Listo', insumosUsados: '[]', clienteCierreId: CLIENTE_CIERRE_ID },
      [archivo],
    );

    expect(uploadEvidenciaToDrive).toHaveBeenCalledTimes(1);
    expect(tx.tarea.update).toHaveBeenCalledTimes(1);
    expect(tx.cierreTareaIdempotencia.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          clienteCierreId: CLIENTE_CIERRE_ID,
          tareaId: 88,
          estadoResultante: EstadoTarea.APROBADA,
        }),
      }),
    );
  });

  test('reenvío con el mismo clienteCierreId: no vuelve a subir evidencias ni a tocar inventario', async () => {
    const { prisma, tx } = buildPrismaMock();
    prisma.cierreTareaIdempotencia.findUnique.mockResolvedValue({
      clienteCierreId: CLIENTE_CIERRE_ID,
      tareaId: 88,
      estadoResultante: EstadoTarea.APROBADA,
    });

    const service = new OperarioService(prisma, 77);
    await service.cerrarTareaConEvidencias(
      88,
      { observaciones: 'Listo', insumosUsados: '[]', clienteCierreId: CLIENTE_CIERRE_ID },
      [archivo],
    );

    expect(uploadEvidenciaToDrive).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(tx.tarea.update).not.toHaveBeenCalled();
    // El archivo temporal que multer ya escribió a disco para este reintento
    // se limpia igual, aunque no se reprocese nada.
    expect(fs.unlinkSync).toHaveBeenCalledWith(archivo.path);
  });

  test('sin clienteCierreId: se comporta como antes, sin marca de idempotencia', async () => {
    const { prisma, tx } = buildPrismaMock();
    const service = new OperarioService(prisma, 77);

    await service.cerrarTareaConEvidencias(
      88,
      { observaciones: 'Listo', insumosUsados: '[]' },
      [archivo],
    );

    expect(uploadEvidenciaToDrive).toHaveBeenCalledTimes(1);
    expect(tx.tarea.update).toHaveBeenCalledTimes(1);
    expect(tx.cierreTareaIdempotencia.create).not.toHaveBeenCalled();
  });
});
