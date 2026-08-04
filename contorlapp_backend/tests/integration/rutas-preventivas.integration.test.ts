import express from 'express';
import request from 'supertest';

const descartarBorradorMesMock = jest.fn();
const eliminarMock = jest.fn();
const eliminarVariasMock = jest.fn();
const estadoBorradorMock = jest.fn();
const listarBorradorMock = jest.fn();

jest.mock('../../src/db/prisma', () => ({ prisma: {} }));

jest.mock('../../src/utils/auditoria', () => ({
  extraerActorAuditoriaConNombre: jest.fn().mockResolvedValue(undefined),
  extraerActorAuditoria: jest.fn(),
}));

jest.mock('../../src/services/DefinicionTareaPreventivaService', () => ({
  DefinicionTareaPreventivaService: jest.fn().mockImplementation(() => ({
    descartarBorradorMes: descartarBorradorMesMock,
    eliminar: eliminarMock,
    eliminarVarias: eliminarVariasMock,
    estadoBorrador: estadoBorradorMock,
    listarBorrador: listarBorradorMock,
  })),
}));

// El router exige sesión y rol gerente; aquí solo se prueba el enrutado.
jest.mock('../../src/middlewares/auth.middleware', () => ({
  authRequired: (_req: any, _res: any, next: any) => next(),
  authOptional: (_req: any, _res: any, next: any) => next(),
}));

jest.mock('../../src/middlewares/role.middleware', () => ({
  requireRoles: () => (_req: any, _res: any, next: any) => next(),
}));

import DefinicionPreventivaRoutes from '../../src/routes/DefinicionPreventiva';

function app(onError?: (err: any) => void) {
  const server = express();
  server.use(express.json());
  server.use('/definicion-preventiva', DefinicionPreventivaRoutes);
  // Sustituto del manejador central de `index.ts`, que es quien decide
  // que se le responde al cliente.
  server.use((err: any, _req: any, res: any, _next: any) => {
    onError?.(err);
    res.status(500).json({ ok: false, message: 'Error saneado' });
  });
  return server;
}

describe('Enrutado de preventivas', () => {
  beforeEach(() => {
    descartarBorradorMesMock.mockReset().mockResolvedValue({ ok: true, eliminadas: 3 });
    eliminarMock.mockReset().mockResolvedValue(undefined);
    eliminarVariasMock
      .mockReset()
      .mockResolvedValue({ ok: true, eliminadas: 2, noEncontradas: [] });
    estadoBorradorMock.mockReset().mockResolvedValue({ existe: false });
  });

  test('PI-R1 - DELETE .../preventivas/borrador descarta el borrador, no lo trata como un id', async () => {
    // Regresión: la ruta `/:id` estaba declarada antes y capturaba "borrador",
    // lo que reventaba con "ID inválido".
    const res = await request(app())
      .delete('/definicion-preventiva/conjuntos/9001/preventivas/borrador')
      .query({ anio: 2026, mes: 8 });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true, eliminadas: 3 });
    expect(descartarBorradorMesMock).toHaveBeenCalledWith(
      expect.objectContaining({ conjuntoId: '9001', anio: '2026', mes: '8' }),
    );
    expect(eliminarMock).not.toHaveBeenCalled();
  });

  test('PI-R2 - DELETE .../preventivas/:id sigue borrando una preventiva concreta', async () => {
    const res = await request(app()).delete(
      '/definicion-preventiva/conjuntos/9001/preventivas/42',
    );

    expect(res.status).toBe(204);
    expect(eliminarMock).toHaveBeenCalledWith('9001', 42);
    expect(descartarBorradorMesMock).not.toHaveBeenCalled();
  });

  test('PI-R3 - DELETE .../preventivas sin id hace el borrado en lote', async () => {
    const res = await request(app())
      .delete('/definicion-preventiva/conjuntos/9001/preventivas')
      .send({ ids: [1, 2] });

    expect(res.status).toBe(200);
    expect(eliminarVariasMock).toHaveBeenCalledWith('9001', { ids: [1, 2] });
    expect(eliminarMock).not.toHaveBeenCalled();
  });

  test('PI-R4 - GET .../preventivas/borrador/estado no colisiona con el listado del borrador', async () => {
    const res = await request(app())
      .get('/definicion-preventiva/conjuntos/9001/preventivas/borrador/estado')
      .query({ anio: 2026, mes: 8 });

    expect(res.status).toBe(200);
    expect(estadoBorradorMock).toHaveBeenCalled();
    expect(listarBorradorMock).not.toHaveBeenCalled();
  });

  test('PI-R5b - el asyncHandler delega en el manejador central en vez de responder él', async () => {
    // Regresión de seguridad: antes devolvía `err.message` en crudo, lo que
    // filtraba el volcado completo del ZodError y detalles internos.
    const zodLike: any = new Error(
      '[{"code":"invalid_type","message":"Invalid input: expected number, received null"}]',
    );
    zodLike.name = 'ZodError';
    descartarBorradorMesMock.mockRejectedValue(zodLike);

    const capturados: any[] = [];
    const res = await request(app((err) => capturados.push(err)))
      .delete('/definicion-preventiva/conjuntos/9001/preventivas/borrador')
      .query({ anio: 2026, mes: 8 });

    // El error llegó al manejador central...
    expect(capturados).toHaveLength(1);
    expect(capturados[0]).toBe(zodLike);
    // ...y el cliente nunca vio el volcado técnico.
    expect(JSON.stringify(res.body)).not.toMatch(/Invalid input|expected number/i);
    expect(res.body).toEqual({ ok: false, message: 'Error saneado' });
  });

  test('PI-R5 - un id no numérico no llega al servicio', async () => {
    const capturados: any[] = [];
    await request(app((err) => capturados.push(err))).delete(
      '/definicion-preventiva/conjuntos/9001/preventivas/no-es-un-id',
    );

    expect(capturados[0]?.message).toMatch(/ID inválido/i);
    expect(eliminarMock).not.toHaveBeenCalled();
  });
});
