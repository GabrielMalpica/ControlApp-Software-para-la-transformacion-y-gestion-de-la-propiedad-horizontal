import crypto from "crypto";
import fs from "fs";
import os from "os";
import path from "path";
import { EstadoPedidoInterno, Prisma, Rol } from "@prisma/client";

jest.mock("../../src/utils/drive_evidencias", () => ({
  buildEvidenciaFileName: jest.fn(() => "comprobante.png"),
  uploadEvidenciaToDrive: jest.fn(async () => "https://drive.google.com/file/d/abc/view"),
}));
jest.mock("../../src/services/wooFetch", () => ({
  wooFetch: jest.fn(),
  buildWooUrl: jest.fn((_ns: string, ruta: string) => `https://tienda.test${ruta}`),
}));
jest.mock("../../src/services/ComprobanteOcrService", () => ({
  analizarComprobante: jest.fn(),
}));

import { analizarComprobante } from "../../src/services/ComprobanteOcrService";
import { wooFetch } from "../../src/services/wooFetch";
import { CommerceLifecycleService } from "../../src/services/CommerceLifecycleService";
import type { VerificacionComprobante } from "../../src/utils/comprobanteParser";

const analizar = analizarComprobante as jest.MockedFunction<typeof analizarComprobante>;
const woo = wooFetch as jest.MockedFunction<typeof wooFetch>;

const CONTENIDO = Buffer.from("contenido-del-comprobante");
const HASH = crypto.createHash("sha256").update(CONTENIDO).digest("hex");

function verificacion(overrides: Partial<VerificacionComprobante> = {}): VerificacionComprobante {
  return {
    veredicto: "COINCIDE",
    metodoDetectado: "nequi",
    montoDetectado: 374500,
    montosEsperados: [374500],
    referencia: "M4839201",
    fechaDetectada: "2026-09-24T15:15:00.000Z",
    checks: [{ clave: "monto", ok: true, detalle: "El valor coincide con el pedido" }],
    motor: "ocr",
    analizadoEn: "2026-09-24T16:00:00.000Z",
    ...overrides,
  };
}

function pedido(overrides: Record<string, unknown> = {}) {
  return {
    id: 6,
    estado: EstadoPedidoInterno.PENDIENTE_PAGO,
    wooOrderId: "2395",
    metodoPago: "nequi",
    total: new Prisma.Decimal(374500),
    pagarAhora: new Prisma.Decimal(0),
    descuentoPuntos: new Prisma.Decimal(0),
    conjuntoId: "CJ-1",
    conjunto: { nombre: "Los Pinos", empresaId: "EMP-1" },
    creadoEn: new Date("2026-09-24T14:00:00Z"),
    ...overrides,
  };
}

async function esperarAnalisis() {
  // El analisis corre "en segundo plano" tras responder: se deja pasar tiempo
  // real (no solo ciclos) para que no dependa de que la maquina este cargada.
  for (let i = 0; i < 30; i++) await new Promise((r) => setTimeout(r, 3));
}

function crearServicio(opts: { pedido?: unknown; mismoArchivo?: unknown; mismaReferencia?: unknown } = {}) {
  const prisma = {
    pedidoApp: {
      findUnique: jest.fn().mockResolvedValue({ estado: EstadoPedidoInterno.PENDIENTE_PAGO }),
      update: jest.fn().mockResolvedValue({}),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      // 1a llamada: busqueda por hash del archivo; 2a: por referencia.
      findFirst: jest
        .fn()
        .mockResolvedValueOnce(opts.mismoArchivo ?? null)
        .mockResolvedValueOnce(opts.mismaReferencia ?? null),
    },
  };
  const service = new CommerceLifecycleService(prisma as never);
  (service as any).access = {
    getActor: jest.fn().mockResolvedValue({ id: "u1", nombre: "Ana", rol: Rol.administrador }),
    assertPedidoAccess: jest.fn().mockResolvedValue(undefined),
  };
  jest.spyOn(service as any, "loadPedido").mockResolvedValue(opts.pedido ?? pedido());
  jest.spyOn(service as any, "getPedido").mockResolvedValue({ id: 6 });
  const nota = jest.spyOn(service as any, "pushWooOrderNote").mockResolvedValue(undefined);
  return { service, prisma, nota };
}

let archivoTemporal: string;
async function subir(service: CommerceLifecycleService) {
  archivoTemporal = path.join(os.tmpdir(), `test_comprobante_${Date.now()}_${Math.random()}.png`);
  await fs.promises.writeFile(archivoTemporal, CONTENIDO);
  return service.subirComprobante(
    "u1",
    6,
    { path: archivoTemporal, mimetype: "image/png", originalname: "captura.png" },
    { metodoPago: "nequi" },
  );
}

describe("subirComprobante + verificacion automatica", () => {
  beforeEach(() => {
    analizar.mockReset();
    analizar.mockResolvedValue(verificacion());
    woo.mockReset();
    woo.mockResolvedValue({ status: "pending" });
  });

  test("guarda hash, limpia la lectura anterior y responde sin esperar al OCR", async () => {
    const { service, prisma } = crearServicio();
    let terminarOcr!: (v: VerificacionComprobante) => void;
    analizar.mockReturnValue(new Promise((resolve) => (terminarOcr = resolve)));

    await expect(subir(service)).resolves.toEqual({ id: 6 });

    expect(prisma.pedidoApp.update).toHaveBeenCalledWith({
      where: { id: 6 },
      data: expect.objectContaining({
        comprobanteUrl: "https://drive.google.com/file/d/abc/view",
        comprobanteHash: HASH,
        comprobanteReferencia: null,
        comprobanteVerificacion: Prisma.DbNull,
      }),
    });
    // La subida ya termino aunque el OCR sigue corriendo.
    expect(prisma.pedidoApp.updateMany).not.toHaveBeenCalled();

    terminarOcr(verificacion());
    await esperarAnalisis();
    expect(prisma.pedidoApp.updateMany).toHaveBeenCalled();
  });

  test("sube el comprobante a la carpeta comprobantes-pago del conjunto (no a evidencias)", async () => {
    const { uploadEvidenciaToDrive } = jest.requireMock("../../src/utils/drive_evidencias");
    const { service } = crearServicio();
    await subir(service);

    expect(uploadEvidenciaToDrive).toHaveBeenCalledWith(
      expect.objectContaining({
        conjuntoNit: "CJ-1",
        conjuntoNombre: "Los Pinos",
        subcarpeta: "comprobantes-pago",
      }),
    );
  });

  test("borra el archivo temporal", async () => {
    const { service } = crearServicio();
    await subir(service);
    await expect(fs.promises.access(archivoTemporal)).rejects.toThrow();
  });

  test("pasa al OCR el contenido, el metodo y los montos esperados del pedido", async () => {
    const { service } = crearServicio({
      pedido: pedido({
        total: new Prisma.Decimal(400000),
        descuentoPuntos: new Prisma.Decimal(25500),
      }),
    });
    await subir(service);
    await esperarAnalisis();

    const entrada = analizar.mock.calls[0][0];
    expect(entrada.buffer.equals(CONTENIDO)).toBe(true);
    expect(entrada.mimeType).toBe("image/png");
    expect(entrada.contexto.metodoPago).toBe("nequi");
    expect(entrada.contexto.montosEsperados).toEqual(expect.arrayContaining([400000, 374500]));
  });

  test("guarda el resultado solo si sigue siendo el mismo comprobante (por hash)", async () => {
    const { service, prisma } = crearServicio();
    await subir(service);
    await esperarAnalisis();

    expect(prisma.pedidoApp.updateMany).toHaveBeenCalledWith({
      where: { id: 6, comprobanteHash: HASH },
      data: {
        comprobanteReferencia: "M4839201",
        comprobanteVerificacion: expect.objectContaining({ veredicto: "COINCIDE" }),
      },
    });
  });

  test("anota el resultado en el pedido de WooCommerce para quien revisa en wp-admin", async () => {
    const { service, nota } = crearServicio();
    await subir(service);
    await esperarAnalisis();

    expect(nota).toHaveBeenCalledWith("2395", expect.stringContaining("Comprobante de pago"));
    expect(nota).toHaveBeenCalledWith(
      "2395",
      expect.stringContaining("Verificacion automatica del comprobante: COINCIDE"),
    );
  });

  test("el mismo archivo ya subido en otro pedido se pasa al analisis como duplicado", async () => {
    const { service } = crearServicio({ mismoArchivo: { id: 3 } });
    await subir(service);
    await esperarAnalisis();

    expect(analizar.mock.calls[0][0].contexto.duplicadoDe).toEqual({
      pedidoId: 3,
      motivo: "archivo",
    });
  });

  test("la misma referencia en otro pedido marca DUPLICADO aunque el archivo sea distinto", async () => {
    const { service, prisma } = crearServicio({ mismaReferencia: { id: 4 } });
    await subir(service);
    await esperarAnalisis();

    const guardado = prisma.pedidoApp.updateMany.mock.calls[0][0].data.comprobanteVerificacion;
    expect(guardado.veredicto).toBe("DUPLICADO");
    expect(guardado.checks.find((c: any) => c.clave === "duplicado").detalle).toContain("#4");
  });

  test("si se subio otro comprobante mientras tanto, no anota una lectura obsoleta", async () => {
    const { service, prisma, nota } = crearServicio();
    prisma.pedidoApp.updateMany.mockResolvedValue({ count: 0 });
    await subir(service);
    await esperarAnalisis();

    // Solo la nota de la subida; la del analisis no se envia.
    expect(nota).toHaveBeenCalledTimes(1);
  });

  test("un fallo al guardar el analisis no rompe la subida", async () => {
    const { service, prisma } = crearServicio();
    prisma.pedidoApp.updateMany.mockRejectedValue(new Error("db caida"));
    const errores = jest.spyOn(console, "error").mockImplementation(() => undefined);

    await expect(subir(service)).resolves.toEqual({ id: 6 });
    await esperarAnalisis();

    expect(errores).toHaveBeenCalled();
    errores.mockRestore();
  });

  test("solo se acepta comprobante mientras el pedido esta pendiente de pago", async () => {
    const { service, prisma } = crearServicio({
      pedido: pedido({ estado: EstadoPedidoInterno.PAGADO }),
    });
    archivoTemporal = path.join(os.tmpdir(), `test_comprobante_${Date.now()}.png`);
    await fs.promises.writeFile(archivoTemporal, CONTENIDO);

    await expect(
      service.subirComprobante(
        "u1",
        6,
        { path: archivoTemporal, mimetype: "image/png", originalname: "x.png" },
        {},
      ),
    ).rejects.toMatchObject({ status: 409 });
    expect(prisma.pedidoApp.update).not.toHaveBeenCalled();
    await fs.promises.unlink(archivoTemporal).catch(() => undefined);
  });
});

describe("visibilidad de la lectura automatica", () => {
  const conVerificacion = pedido({
    comprobanteUrl: "https://drive.google.com/file/d/abc/view",
    comprobanteSubidoEn: new Date(),
    comprobanteVerificacion: verificacion({ veredicto: "REVISAR" }),
    pagarAhora: new Prisma.Decimal(0),
    items: [],
    historialEstados: [],
    consumosInventario: [],
  });

  test.each([
    [Rol.gerente, "REVISAR"],
    [Rol.jefe_operaciones, "REVISAR"],
    [Rol.administrador, null],
    [Rol.residente, null],
    [Rol.supervisor, null],
    [Rol.operario, null],
  ])("rol %s ve: %s", (rol, esperado) => {
    const service = new CommerceLifecycleService({} as never);
    const actor = { id: "u", nombre: "X", rol, empresaId: null, residente: null };
    const serializado = (service as any).serializePedido(actor, conVerificacion);
    expect(serializado.verificacionComprobante?.veredicto ?? null).toBe(esperado);
  });
});

describe('estado "Confirmado - OCR" en WooCommerce', () => {
  beforeEach(() => {
    analizar.mockReset();
    woo.mockReset();
  });

  const cambiosDeEstadoEnWoo = () =>
    woo.mock.calls
      .filter(([, init]) => (init as RequestInit | undefined)?.method === "PUT")
      .map(([url, init]) => ({ url, body: JSON.parse(String((init as RequestInit).body)) }));

  test("comprobante que COINCIDE deja el pedido en pago-ocr (pendiente de revision humana)", async () => {
    analizar.mockResolvedValue(verificacion({ veredicto: "COINCIDE" }));
    woo.mockResolvedValue({ status: "pending" });
    const { service } = crearServicio();

    await subir(service);
    await esperarAnalisis();

    expect(cambiosDeEstadoEnWoo()).toEqual([
      { url: "https://tienda.test/orders/2395", body: { status: "pago-ocr" } },
    ]);
  });

  test("nunca marca 'Confirmado - manual': eso solo lo hace una persona", async () => {
    analizar.mockResolvedValue(verificacion({ veredicto: "COINCIDE" }));
    woo.mockResolvedValue({ status: "pending" });
    const { service } = crearServicio();

    await subir(service);
    await esperarAnalisis();

    expect(cambiosDeEstadoEnWoo().every((c) => c.body.status !== "pago-manual")).toBe(true);
  });

  test.each(["REVISAR", "DUPLICADO", "ILEGIBLE"] as const)(
    "veredicto %s no cambia el estado en WooCommerce",
    async (veredicto) => {
      analizar.mockResolvedValue(verificacion({ veredicto }));
      woo.mockResolvedValue({ status: "pending" });
      const { service } = crearServicio();

      await subir(service);
      await esperarAnalisis();

      expect(cambiosDeEstadoEnWoo()).toEqual([]);
    },
  );

  test.each(["processing", "completed", "cancelled", "pago-manual"])(
    "no pisa un pedido que en Woo ya esta en %s",
    async (estadoWoo) => {
      analizar.mockResolvedValue(verificacion({ veredicto: "COINCIDE" }));
      woo.mockResolvedValue({ status: estadoWoo });
      const { service } = crearServicio();

      await subir(service);
      await esperarAnalisis();

      expect(cambiosDeEstadoEnWoo()).toEqual([]);
    },
  );

  test("no cambia Woo si en la app el pedido ya no esta pendiente de pago", async () => {
    analizar.mockResolvedValue(verificacion({ veredicto: "COINCIDE" }));
    woo.mockResolvedValue({ status: "pending" });
    const { service, prisma } = crearServicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({ estado: EstadoPedidoInterno.PAGADO });

    await subir(service);
    await esperarAnalisis();

    expect(cambiosDeEstadoEnWoo()).toEqual([]);
  });

  test("si la tienda no tiene el plugin de estados (Woo rechaza) la subida y la nota siguen bien", async () => {
    analizar.mockResolvedValue(verificacion({ veredicto: "COINCIDE" }));
    woo.mockImplementation((async (_url: string, init?: RequestInit) => {
      if (init?.method === "PUT") throw new Error("invalid status");
      return { status: "pending" };
    }) as never);
    const { service, nota } = crearServicio();

    await expect(subir(service)).resolves.toEqual({ id: 6 });
    await esperarAnalisis();

    expect(nota).toHaveBeenCalledWith("2395", expect.stringContaining("COINCIDE"));
  });

  test("un comprobante nuevo revierte pago-ocr a pending mientras se vuelve a analizar", async () => {
    analizar.mockResolvedValue(verificacion({ veredicto: "REVISAR" }));
    woo.mockResolvedValue({ status: "pago-ocr" });
    const { service } = crearServicio({
      pedido: pedido({ comprobanteVerificacion: verificacion({ veredicto: "COINCIDE" }) }),
    });

    await subir(service);
    await esperarAnalisis();

    expect(cambiosDeEstadoEnWoo()).toEqual([
      { url: "https://tienda.test/orders/2395", body: { status: "pending" } },
    ]);
  });

  test("no revierte si el comprobante anterior no habia coincidido", async () => {
    analizar.mockResolvedValue(verificacion({ veredicto: "REVISAR" }));
    woo.mockResolvedValue({ status: "pending" });
    const { service } = crearServicio({
      pedido: pedido({ comprobanteVerificacion: verificacion({ veredicto: "REVISAR" }) }),
    });

    await subir(service);
    await esperarAnalisis();

    expect(woo).not.toHaveBeenCalled();
  });
});

describe("la lectura automatica no se filtra a quien compra", () => {
  test.each([Rol.administrador, Rol.residente])(
    "%s no recibe ningun rastro del analisis, ni siquiera cuando no se pudo leer",
    (rol) => {
      const service = new CommerceLifecycleService({} as never);
      const actor = { id: "u", nombre: "X", rol, empresaId: null, residente: null };
      const pedidoIlegible = pedido({
        comprobanteUrl: "https://drive.google.com/file/d/abc/view",
        comprobanteSubidoEn: new Date(),
        comprobanteReferencia: "M4839201",
        comprobanteVerificacion: verificacion({ veredicto: "ILEGIBLE" }),
        items: [],
        historialEstados: [],
        consumosInventario: [],
      });

      const json = JSON.stringify((service as any).serializePedido(actor, pedidoIlegible));

      expect(json).not.toContain("ILEGIBLE");
      expect(json).not.toContain("verificacionComprobante\":{");
      expect((service as any).serializePedido(actor, pedidoIlegible).verificacionComprobante).toBeNull();
    },
  );
});

