import { EstadoTarea } from '@prisma/client';

jest.mock('../../src/utils/drive_evidencias', () => ({
  uploadEvidenciaToDrive: jest
    .fn()
    .mockResolvedValue('https://drive.google.com/file/d/NUEVAxxxxxxxxxxxxxxxxxxxx1/view'),
  buildEvidenciaFileName: jest.fn().mockReturnValue('nueva.jpg'),
  eliminarEvidenciaDeDrive: jest.fn().mockResolvedValue(undefined),
  extraerDriveId: jest.requireActual('../../src/utils/drive_evidencias').extraerDriveId,
}));

const registrarEstrictoMock = jest.fn().mockResolvedValue(undefined);
jest.mock('../../src/services/AuditoriaService', () => ({
  AuditoriaService: jest.fn().mockImplementation(() => ({
    registrarEstricto: registrarEstrictoMock,
  })),
}));

import {
  eliminarEvidenciaDeDrive,
  uploadEvidenciaToDrive,
} from '../../src/utils/drive_evidencias';
import { TareaService } from '../../src/services/TareaServices';

const VIEJA = 'https://drive.google.com/file/d/VIEJAxxxxxxxxxxxxxxxxxxxx1/view';
const OTRA = 'https://drive.google.com/file/d/OTRAxxxxxxxxxxxxxxxxxxxxx2/view';
const NUEVA = 'https://drive.google.com/file/d/NUEVAxxxxxxxxxxxxxxxxxxxx1/view';

function buildPrisma(over: { evidencias?: string[]; estado?: EstadoTarea; otrasConLaMisma?: number } = {}) {
  const tx: any = {
    tarea: { update: jest.fn().mockResolvedValue({ id: 5, conjunto: { nombre: 'Demo' } }) },
  };
  const prisma: any = {
    tarea: {
      findFirst: jest.fn().mockResolvedValue({
        id: 5,
        estado: over.estado ?? EstadoTarea.APROBADA,
        evidencias: over.evidencias ?? [VIEJA, OTRA],
        insumosUsados: null,
        conjuntoId: '900',
        fechaFinalizarTarea: null,
        fechaFin: new Date(),
        conjunto: { nit: '900', nombre: 'Demo' },
      }),
      count: jest.fn().mockResolvedValue(over.otrasConLaMisma ?? 0),
    },
    $transaction: jest.fn((cb: any) => cb(tx)),
  };
  return { prisma, tx };
}

const actor = { id: 'ger-1', rol: 'gerente', nombre: 'Gerente' };
const archivo = { path: '/tmp/no-existe.jpg', originalname: 'n.jpg', mimetype: 'image/jpeg' } as Express.Multer.File;

describe('Corregir cierre: evidencias', () => {
  beforeEach(() => jest.clearAllMocks());

  test('reemplaza la evidencia: guarda la nueva y borra la quitada de Drive', async () => {
    const { prisma, tx } = buildPrisma();
    await TareaService.corregirCierre(
      prisma,
      5,
      { motivo: 'Subieron la foto equivocada', evidenciasEliminar: JSON.stringify([VIEJA]) },
      [archivo],
      'emp-1',
      actor,
    );

    expect(uploadEvidenciaToDrive).toHaveBeenCalledTimes(1);
    expect(tx.tarea.update.mock.calls[0][0].data.evidencias).toEqual([OTRA, NUEVA]);
    expect(eliminarEvidenciaDeDrive).toHaveBeenCalledTimes(1);
    expect(eliminarEvidenciaDeDrive).toHaveBeenCalledWith('VIEJAxxxxxxxxxxxxxxxxxxxx1');
  });

  test('solo agregar evidencias no borra nada de Drive', async () => {
    const { prisma } = buildPrisma();
    await TareaService.corregirCierre(prisma, 5, { motivo: 'Faltaba una foto' }, [archivo], 'emp-1', actor);
    expect(eliminarEvidenciaDeDrive).not.toHaveBeenCalled();
  });

  test('nunca borra de Drive un archivo que no era de la tarea', async () => {
    const { prisma } = buildPrisma();
    const ajena = 'https://drive.google.com/file/d/AJENAxxxxxxxxxxxxxxxxxxxx9/view';
    await TareaService.corregirCierre(
      prisma,
      5,
      { motivo: 'Intento malicioso', evidenciasEliminar: JSON.stringify([ajena]) },
      [],
      'emp-1',
      actor,
    );
    expect(eliminarEvidenciaDeDrive).not.toHaveBeenCalled();
  });

  test('conserva en Drive la evidencia que otra tarea sigue usando', async () => {
    const { prisma } = buildPrisma({ otrasConLaMisma: 1 });
    await TareaService.corregirCierre(
      prisma,
      5,
      { motivo: 'Quitar duplicada', evidenciasEliminar: JSON.stringify([VIEJA]) },
      [],
      'emp-1',
      actor,
    );
    expect(eliminarEvidenciaDeDrive).not.toHaveBeenCalled();
  });

  test('si Drive falla la tarea igual queda corregida', async () => {
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    (eliminarEvidenciaDeDrive as jest.Mock).mockRejectedValueOnce(new Error('403 sin permiso'));
    const { prisma, tx } = buildPrisma();
    await expect(
      TareaService.corregirCierre(
        prisma,
        5,
        { motivo: 'Quitar foto', evidenciasEliminar: JSON.stringify([VIEJA]) },
        [],
        'emp-1',
        actor,
      ),
    ).resolves.toBeDefined();
    expect(tx.tarea.update).toHaveBeenCalled();
  });

  test('no borra nada de Drive si la correccion falla antes de guardar', async () => {
    const { prisma } = buildPrisma({ estado: EstadoTarea.EN_PROCESO });
    await expect(
      TareaService.corregirCierre(
        prisma,
        5,
        { motivo: 'Quitar foto', evidenciasEliminar: JSON.stringify([VIEJA]) },
        [],
        'emp-1',
        actor,
      ),
    ).rejects.toThrow(/no se puede corregir/i);
    expect(eliminarEvidenciaDeDrive).not.toHaveBeenCalled();
  });
});
