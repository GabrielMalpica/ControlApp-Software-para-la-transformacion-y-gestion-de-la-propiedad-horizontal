const crearConjuntoMock = jest.fn();

jest.mock('../../src/db/prisma', () => ({ prisma: {} }));
jest.mock('../../src/services/GerenteServices', () => ({
  GerenteService: jest.fn().mockImplementation(() => ({
    crearConjunto: crearConjuntoMock,
  })),
}));

import { GerenteController } from '../../src/controller/GerenteController';

function makeRes() {
  const res: any = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  res.send = jest.fn().mockReturnValue(res);
  return res;
}

describe('Pruebas unitarias controlador gerente', () => {
  test('PU2 - Controlador de conjuntos: rechaza solicitudes incompletas', async () => {
    const controller = new GerenteController();
    const req: any = { body: { nombre: 'Sin nit' } };
    const res = makeRes();
    const next = jest.fn();

    crearConjuntoMock.mockRejectedValueOnce(new Error('Solicitud incompleta'));

    await controller.crearConjunto(req, res, next);

    expect(next).toHaveBeenCalledWith(expect.any(Error));
    expect(res.status).not.toHaveBeenCalledWith(201);
  });
});
