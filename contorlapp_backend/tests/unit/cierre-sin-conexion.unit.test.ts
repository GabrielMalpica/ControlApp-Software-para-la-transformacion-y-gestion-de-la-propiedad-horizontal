// Cierres hechos sin señal en la app Android y enviados después: hora
// original (corregida si el reloj del celular estaba mal), rechazos con
// código para la app, carreras entre reintentos y marca de agua.
import fs from "fs";
import express from "express";
import request from "supertest";
import { EstadoTarea, Prisma } from "@prisma/client";

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));

jest.mock("../../src/utils/drive_evidencias", () => ({
  uploadEvidenciaToDrive: jest.fn().mockResolvedValue("https://drive.google.com/file/d/ID_DUPLICADO/view"),
  buildEvidenciaFileName: jest.fn().mockReturnValue("evidencia.jpg"),
  eliminarEvidenciaDeDrive: jest.fn().mockResolvedValue(undefined),
  extraerDriveId: jest.fn((url: string) => (url.includes("ID_DUPLICADO") ? "ID_DUPLICADO" : null)),
}));

jest.mock("../../src/services/NotificacionService", () => ({
  NotificacionService: jest.fn().mockImplementation(() => ({
    notificarCierreTarea: jest.fn().mockResolvedValue(undefined),
  })),
}));

import { eliminarEvidenciaDeDrive, uploadEvidenciaToDrive } from "../../src/utils/drive_evidencias";
import { OperarioService } from "../../src/services/OperarioServices";
import { crearDedupeCierrePorCabecera } from "../../src/middlewares/cierre-idempotencia.middleware";
import { desfaseRelojMs, resolverHora } from "../../src/utils/horaSinConexion";
import { lineasMarcaAgua, parsearCapturasEvidencias } from "../../src/utils/marca_agua_evidencia";

const CLIENTE_CIERRE_ID = "22222222-2222-4222-8222-222222222222";

/* ------------------------------ hora oficial ------------------------------ */

describe("hora de lo hecho sin señal", () => {
  const recibidoEn = new Date("2026-11-04T23:00:00.000Z");

  test("reloj bien puesto: vale la hora del celular", () => {
    const hora = new Date("2026-11-04T15:00:00.000Z");
    expect(resolverHora({ hora, recibidoEn })).toEqual({ hora, ajustada: false });
  });

  test("si la hora estimada (reloj monotónico) no cuadra, gana la estimada", () => {
    const r = resolverHora({
      hora: new Date("2026-11-04T08:00:00.000Z"), // alguien atrasó el reloj
      horaEstimada: new Date("2026-11-04T15:00:00.000Z"),
      recibidoEn,
    });
    expect(r).toMatchObject({ ajustada: true, motivo: "ESTIMADA" });
    expect(r.hora!.toISOString()).toBe("2026-11-04T15:00:00.000Z");
  });

  test("sin estimada, se corrige por el desfase medido al enviar", () => {
    const desfase = desfaseRelojMs("2026-11-04T22:00:00.000Z", recibidoEn); // celular 1 h atrasado
    expect(desfase).toBe(3_600_000);
    const r = resolverHora({ hora: new Date("2026-11-04T14:00:00.000Z"), desfaseMs: desfase, recibidoEn });
    expect(r).toMatchObject({ ajustada: true, motivo: "DESFASE" });
    expect(r.hora!.toISOString()).toBe("2026-11-04T15:00:00.000Z");
  });

  test("diferencias pequeñas no se corrigen y nunca queda en el futuro", () => {
    expect(
      resolverHora({ hora: new Date("2026-11-04T15:00:00.000Z"), desfaseMs: 60_000, recibidoEn }).ajustada,
    ).toBe(false);
    const futuro = resolverHora({ hora: new Date("2026-11-05T05:00:00.000Z"), recibidoEn });
    expect(futuro).toMatchObject({ ajustada: true, motivo: "FUTURO" });
    expect(futuro.hora!.getTime()).toBe(recibidoEn.getTime());
  });
});

/* ------------------------------ marca de agua ----------------------------- */

describe("marca de agua de un cierre sin señal", () => {
  const subidaEn = new Date("2026-11-04T23:00:00.000Z");

  test("la hora de la foto va primero y luego 'Enviada … (sin señal)'", () => {
    const lineas = lineasMarcaAgua({
      captura: { tomadaEn: new Date("2026-11-04T15:00:00.000Z"), latitud: null, longitud: null },
      subidaEn,
      conjunto: { nombre: "Conjunto Sol" },
      sinConexion: true,
    });
    expect(lineas[0]).toBe("4 nov 2026 10:00:00 a. m.");
    expect(lineas[1]).toBe("Enviada 4 nov 2026 6:00:00 p. m. (sin señal)");
  });

  test("sin la marca de sin señal se conserva el texto de siempre", () => {
    const lineas = lineasMarcaAgua({
      captura: { tomadaEn: new Date("2026-11-04T15:00:00.000Z"), latitud: null, longitud: null },
      subidaEn,
      conjunto: { nombre: "Conjunto Sol" },
    });
    expect(lineas[1]).toBe("Subida 4 nov 2026 6:00:00 p. m.");
  });

  test("la hora estimada de la foto corrige un reloj mal puesto", () => {
    const [captura] = parsearCapturasEvidencias(
      JSON.stringify([
        {
          tomadaEn: "2026-11-04T08:00:00.000Z",
          tomadaEnEstimada: "2026-11-04T15:00:00.000Z",
          latitud: 4.7,
          longitud: -74.05,
        },
      ]),
      1,
      subidaEn,
    );
    expect(captura?.tomadaEn?.toISOString()).toBe("2026-11-04T15:00:00.000Z");
    expect(captura?.horaAjustada).toBe(true);
  });

  test("una foto con hora en el futuro sigue sin hora (no se inventa)", () => {
    const [captura] = parsearCapturasEvidencias(
      JSON.stringify([{ tomadaEn: "2026-11-06T08:00:00.000Z" }]),
      1,
      subidaEn,
    );
    expect(captura).toBeNull();
  });
});

/* ---------------------------------- cierre --------------------------------- */

function tareaBase(parcial: Record<string, unknown> = {}) {
  return {
    id: 88,
    descripcion: "Limpiar piscina",
    estado: EstadoTarea.EN_PROCESO,
    borrador: false,
    evidencias: [],
    conjuntoId: "9001",
    supervisorId: "sup-1",
    fechaFinalizarTarea: null,
    finalizadaPorId: null,
    operarios: [{ id: "77" }],
    conjunto: { nit: "9001", nombre: "Conjunto Sol" },
    ...parcial,
  };
}

function prismaMock(tarea: Record<string, unknown> | null = tareaBase()) {
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
    tarea: { findUnique: jest.fn().mockResolvedValue(tarea) },
    usuario: { findUnique: jest.fn().mockResolvedValue({ nombre: "Gerente Uno" }) },
    cierreTareaIdempotencia: { findUnique: jest.fn().mockResolvedValue(null) },
    $transaction: jest.fn((cb: any) => cb(tx)),
  };
  return { prisma, tx };
}

const archivo = {
  path: "/tmp/evidencia.jpg",
  originalname: "evidencia.jpg",
  mimetype: "image/jpeg",
} as Express.Multer.File;

describe("cierre del operario enviado desde la cola sin señal", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(fs, "existsSync").mockReturnValue(true);
    jest.spyOn(fs, "unlinkSync").mockImplementation(() => undefined);
  });

  test("guarda la hora corregida y deja constancia de que llegó sin señal", async () => {
    const { prisma, tx } = prismaMock();
    const service = new OperarioService(prisma, 77);
    const ahora = Date.now();
    const out = await service.cerrarTareaConEvidencias(
      88,
      {
        observaciones: "Listo",
        clienteCierreId: CLIENTE_CIERRE_ID,
        fechaFinalizarTarea: new Date(ahora - 8 * 3_600_000).toISOString(), // reloj atrasado
        horaEstimada: new Date(ahora - 5 * 3_600_000).toISOString(),
        horaDispositivoEnvio: new Date(ahora - 3 * 3_600_000).toISOString(),
        sinConexion: "true",
      },
      [],
    );
    expect(out).toEqual({ duplicado: false });
    const data = tx.tarea.update.mock.calls[0][0].data;
    expect(Math.abs(data.fechaFinalizarTarea.getTime() - (ahora - 5 * 3_600_000))).toBeLessThan(1_000);
    expect(tx.cierreTareaIdempotencia.create.mock.calls[0][0].data).toMatchObject({
      operarioId: "77",
      sinConexion: true,
      horaAjustada: true,
    });
  });

  test("fecha de cierre ilegible → 400 con código", async () => {
    const { prisma } = prismaMock();
    await expect(
      new OperarioService(prisma, 77).cerrarTareaConEvidencias(
        88,
        { fechaFinalizarTarea: "no-es-fecha" },
        [archivo],
      ),
    ).rejects.toMatchObject({ status: 400, code: "FECHA_CIERRE_INVALIDA" });
    expect(fs.unlinkSync).toHaveBeenCalledWith(archivo.path);
  });

  test("tarea eliminada → 404 TAREA_ELIMINADA (y borra los temporales)", async () => {
    const { prisma } = prismaMock(null);
    await expect(
      new OperarioService(prisma, 77).cerrarTareaConEvidencias(88, {}, [archivo]),
    ).rejects.toMatchObject({ status: 404, code: "TAREA_ELIMINADA" });
    expect(fs.unlinkSync).toHaveBeenCalledWith(archivo.path);
  });

  test("se la pasaron a otro operario → 409 TAREA_REASIGNADA", async () => {
    const { prisma } = prismaMock(tareaBase({ operarios: [{ id: "99" }] }));
    await expect(
      new OperarioService(prisma, 77).cerrarTareaConEvidencias(88, {}, []),
    ).rejects.toMatchObject({ status: 409, code: "TAREA_REASIGNADA" });
  });

  test("ya la cerró el gerente → 409 TAREA_YA_CERRADA con quién", async () => {
    const { prisma } = prismaMock(
      tareaBase({
        estado: EstadoTarea.APROBADA,
        finalizadaPorId: "g-1",
        fechaFinalizarTarea: new Date("2026-11-04T14:00:00.000Z"),
      }),
    );
    const promesa = new OperarioService(prisma, 77).cerrarTareaConEvidencias(88, {}, []);
    await expect(promesa).rejects.toMatchObject({ status: 409, code: "TAREA_YA_CERRADA" });
    await expect(promesa).rejects.toThrow(/por Gerente Uno/);
  });

  test("reenvío con el mismo id para otra tarea → 409", async () => {
    const { prisma } = prismaMock();
    prisma.cierreTareaIdempotencia.findUnique.mockResolvedValue({ tareaId: 5 });
    await expect(
      new OperarioService(prisma, 77).cerrarTareaConEvidencias(
        88,
        { clienteCierreId: CLIENTE_CIERRE_ID },
        [archivo],
      ),
    ).rejects.toMatchObject({ status: 409, code: "CIERRE_ID_REUTILIZADO" });
  });

  test("dos copias a la vez: la segunda responde duplicado y borra sus fotos de Drive", async () => {
    const { prisma } = prismaMock();
    prisma.$transaction.mockRejectedValue(
      new Prisma.PrismaClientKnownRequestError("Unique constraint failed", {
        code: "P2002",
        clientVersion: "test",
        meta: { modelName: "CierreTareaIdempotencia", target: ["clienteCierreId"] },
      }),
    );
    const out = await new OperarioService(prisma, 77).cerrarTareaConEvidencias(
      88,
      { observaciones: "Listo", clienteCierreId: CLIENTE_CIERRE_ID },
      [archivo],
    );
    expect(out).toEqual({ duplicado: true });
    expect(uploadEvidenciaToDrive).toHaveBeenCalledTimes(1);
    expect(eliminarEvidenciaDeDrive).toHaveBeenCalledWith("ID_DUPLICADO");
  });

  test("la app consulta si un cierre ya entró, solo los suyos", async () => {
    const { prisma } = prismaMock();
    prisma.cierreTareaIdempotencia.findUnique.mockResolvedValue({
      tareaId: 88,
      estadoResultante: EstadoTarea.APROBADA,
      creadoEn: new Date(),
      operarioId: "77",
    });
    await expect(new OperarioService(prisma, 77).estadoCierreCliente(CLIENTE_CIERRE_ID)).resolves.toMatchObject({
      procesado: true,
      tareaId: 88,
    });
    await expect(new OperarioService(prisma, 12).estadoCierreCliente(CLIENTE_CIERRE_ID)).resolves.toEqual({
      procesado: false,
    });
  });
});

/* ------------------------ cabecera antes de las fotos ----------------------- */

describe("X-Cliente-Cierre-Id antes de recibir las fotos", () => {
  function app(buscar: (id: string) => Promise<{ tareaId: number } | null>) {
    const siguiente = jest.fn((_req: express.Request, res: express.Response) => {
      res.json({ ok: true, procesado: "normal" });
    });
    const a = express();
    a.post("/tareas/:tareaId/cerrar", crearDedupeCierrePorCabecera(buscar), siguiente);
    return { a, siguiente };
  }

  test("si ya entró, confirma sin pasar al cierre", async () => {
    const { a, siguiente } = app(async () => ({ tareaId: 88 }));
    const res = await request(a)
      .post("/tareas/88/cerrar")
      .set("X-Cliente-Cierre-Id", CLIENTE_CIERRE_ID)
      .attach("files", Buffer.from("foto"), "foto.jpg");
    expect(res.body).toEqual({ ok: true, duplicado: true });
    expect(siguiente).not.toHaveBeenCalled();
  });

  test("si no ha entrado o es de otra tarea, sigue el camino normal", async () => {
    for (const fila of [null, { tareaId: 5 }]) {
      const { a, siguiente } = app(async () => fila);
      const res = await request(a).post("/tareas/88/cerrar").set("X-Cliente-Cierre-Id", CLIENTE_CIERRE_ID);
      expect(res.body.procesado).toBe("normal");
      expect(siguiente).toHaveBeenCalled();
    }
  });
});
