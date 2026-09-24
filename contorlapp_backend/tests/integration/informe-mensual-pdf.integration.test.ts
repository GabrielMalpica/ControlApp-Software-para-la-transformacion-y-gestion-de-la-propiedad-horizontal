import express from 'express';
import fs from 'fs';
import os from 'os';
import path from 'path';
import request from 'supertest';

const conjuntoFindFirstMock = jest.fn();
let usuarioActual = 'usuario-1';

jest.mock('../../src/db/prisma', () => ({
  prisma: { conjunto: { findFirst: (...args: any[]) => conjuntoFindFirstMock(...args) } },
}));

jest.mock('../../src/middlewares/auth.middleware', () => ({
  authRequired: (req: any, _res: any, next: any) => {
    req.user = { sub: usuarioActual, rol: 'gerente', correo: 'x@x.com' };
    next();
  },
  authOptional: (_req: any, _res: any, next: any) => next(),
}));

jest.mock('../../src/middlewares/permission.middleware', () => ({
  requirePermission: () => (_req: any, _res: any, next: any) => next(),
}));

jest.mock('../../src/middlewares/tenant.middleware', () => ({
  empresaIdAutenticada: jest.fn().mockResolvedValue('empresa-1'),
}));

// La generacion real (Drive, sharp, PDF) se prueba en los unitarios: aqui solo
// interesa el contrato HTTP y que la respuesta no espere al PDF.
const ejecutarMock = jest.fn();
jest.mock('../../src/services/InformeMensualService', () => ({
  crearEjecutorInforme: jest.fn((params: any) => (ctx: any) => ejecutarMock(params, ctx)),
}));

import ReportesRoutes from '../../src/routes/Reportes';
import { informeMensualJobs } from '../../src/services/InformeMensualJobs';

function app() {
  const server = express();
  server.use(express.json());
  server.use('/reporte', ReportesRoutes);
  server.use((err: any, _req: any, res: any, _next: any) => {
    res.status(err?.status ?? 500).json({ message: err?.message ?? 'error' });
  });
  return server;
}

const body = {
  desde: '2026-09-01T05:00:00.000Z',
  hasta: '2026-10-01T04:59:59.000Z',
  conjuntoId: '900904193-8',
};

const esperar = (ms = 20) => new Promise((r) => setTimeout(r, ms));

describe('Informe mensual en PDF (HTTP)', () => {
  beforeEach(() => {
    usuarioActual = 'usuario-1';
    conjuntoFindFirstMock.mockReset().mockResolvedValue({ nit: '900904193-8' });
    ejecutarMock.mockReset().mockImplementation(async (_p: any, ctx: any) => {
      fs.writeFileSync(ctx.archivoDestino, '%PDF-1.4 demo');
      return { nombreArchivo: 'Informe_demo.pdf' };
    });
  });

  afterEach(async () => {
    await esperar(30);
  });

  test('IM-1 - responde 202 al instante y luego permite descargar el PDF', async () => {
    let liberar!: () => void;
    const bloqueo = new Promise<void>((r) => (liberar = r));
    ejecutarMock.mockImplementationOnce(async (_p: any, ctx: any) => {
      ctx.reportar(40, 'Preparando fotos');
      await bloqueo;
      fs.writeFileSync(ctx.archivoDestino, '%PDF-1.4 demo');
      return { nombreArchivo: 'Informe_demo.pdf' };
    });

    const inicio = await request(app()).post('/reporte/informe-mensual/pdf').send(body);
    expect(inicio.status).toBe(202);
    expect(['EN_COLA', 'GENERANDO']).toContain(inicio.body.estado);
    const jobId = inicio.body.jobId;

    await esperar();
    const enCurso = await request(app()).get(`/reporte/informe-mensual/pdf/${jobId}`);
    expect(enCurso.status).toBe(200);
    expect(enCurso.body).toMatchObject({ estado: 'GENERANDO', progreso: 40, mensaje: 'Preparando fotos' });

    // Todavia no esta listo: no se puede descargar.
    const antes = await request(app()).get(`/reporte/informe-mensual/pdf/${jobId}/archivo`);
    expect(antes.status).toBe(409);

    liberar();
    await esperar();
    const listo = await request(app()).get(`/reporte/informe-mensual/pdf/${jobId}`);
    expect(listo.body).toMatchObject({ estado: 'LISTO', progreso: 100, nombreArchivo: 'Informe_demo.pdf' });

    const pdf = await request(app()).get(`/reporte/informe-mensual/pdf/${jobId}/archivo`);
    expect(pdf.status).toBe(200);
    expect(pdf.headers['content-type']).toMatch(/application\/pdf/);
    expect(pdf.headers['content-disposition']).toContain('Informe_demo.pdf');
    expect(Buffer.from(pdf.body).toString()).toContain('%PDF-');

    expect(ejecutarMock.mock.calls[0][0]).toMatchObject({
      empresaId: 'empresa-1',
      conjuntoId: '900904193-8',
    });
  });

  test('IM-2 - otro usuario no puede ver ni descargar el informe', async () => {
    const inicio = await request(app()).post('/reporte/informe-mensual/pdf').send(body);
    await esperar();

    usuarioActual = 'usuario-2';
    const estado = await request(app()).get(`/reporte/informe-mensual/pdf/${inicio.body.jobId}`);
    expect(estado.status).toBe(404);
    const pdf = await request(app()).get(`/reporte/informe-mensual/pdf/${inicio.body.jobId}/archivo`);
    expect(pdf.status).toBe(404);
  });

  test('IM-3 - rechaza un conjunto que no es de la empresa', async () => {
    conjuntoFindFirstMock.mockResolvedValue(null);
    const res = await request(app()).post('/reporte/informe-mensual/pdf').send({ ...body, conjuntoId: 'ajeno' });
    expect(res.status).toBe(404);
    expect(ejecutarMock).not.toHaveBeenCalled();
  });

  test('IM-4 - valida el rango y el id del trabajo', async () => {
    const invertido = await request(app())
      .post('/reporte/informe-mensual/pdf')
      .send({ ...body, desde: body.hasta, hasta: body.desde });
    expect(invertido.status).toBeGreaterThanOrEqual(400);

    const enorme = await request(app())
      .post('/reporte/informe-mensual/pdf')
      .send({ ...body, desde: '2020-01-01T00:00:00Z', hasta: '2026-01-01T00:00:00Z' });
    expect(enorme.status).toBeGreaterThanOrEqual(400);

    const idRaro = await request(app()).get('/reporte/informe-mensual/pdf/no-es-uuid');
    expect(idRaro.status).toBeGreaterThanOrEqual(400);
    expect(ejecutarMock).not.toHaveBeenCalled();
  });

  test('IM-5 - un fallo al generar se informa sin detalles tecnicos', async () => {
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    ejecutarMock.mockRejectedValueOnce(new Error('ECONNRESET drive interno'));
    usuarioActual = 'usuario-3';
    const inicio = await request(app()).post('/reporte/informe-mensual/pdf').send(body);
    await esperar();
    const estado = await request(app()).get(`/reporte/informe-mensual/pdf/${inicio.body.jobId}`);
    expect(estado.body.estado).toBe('ERROR');
    expect(JSON.stringify(estado.body)).not.toMatch(/ECONNRESET|drive interno/);
  });

  afterAll(() => {
    informeMensualJobs.limpiar(Date.now() + 60 * 60 * 1000);
    fs.rmSync(path.join(os.tmpdir(), 'controlapp-informes'), { recursive: true, force: true });
  });
});
