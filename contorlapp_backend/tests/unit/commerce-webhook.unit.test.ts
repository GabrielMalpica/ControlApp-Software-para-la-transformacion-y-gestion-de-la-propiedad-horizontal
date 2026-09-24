import crypto from "crypto";
import express from "express";
import request from "supertest";
import { EstadoPedidoInterno } from "@prisma/client";

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));
jest.mock("../../src/services/wooFetch", () => ({
  wooFetch: jest.fn(),
  buildWooUrl: jest.fn((_ns: string, ruta: string) => `https://tienda.test${ruta}`),
}));

import { CommerceWebhookController } from "../../src/controller/CommerceWebhookController";
import { CommerceLifecycleService } from "../../src/services/CommerceLifecycleService";
import { wooFetch } from "../../src/services/wooFetch";

const E = EstadoPedidoInterno;
const SECRET = "secreto-de-prueba";

function firmar(cuerpo: string, secret = SECRET) {
  return crypto.createHmac("sha256", secret).update(cuerpo).digest("base64");
}

// Misma configuracion que src/index.ts: se conserva el cuerpo crudo para poder
// verificar la firma HMAC de WooCommerce.
function crearApp() {
  const app = express();
  app.use(
    express.json({
      verify: (req, _res, buf) => {
        (req as any).rawBody = buf;
      },
    }),
  );
  const controller = new CommerceWebhookController();
  app.post("/commerce/webhooks/woocommerce", controller.ordenActualizada);
  return app;
}

describe("webhook de WooCommerce (POST /commerce/webhooks/woocommerce)", () => {
  const aplicar = jest.spyOn(CommerceLifecycleService.prototype, "aplicarEstadoDesdeWoo");
  const original = process.env.WOOCOMMERCE_WEBHOOK_SECRET;

  beforeEach(() => {
    process.env.WOOCOMMERCE_WEBHOOK_SECRET = SECRET;
    aplicar.mockReset();
    aplicar.mockResolvedValue(undefined);
  });

  afterAll(() => {
    aplicar.mockRestore();
    if (original === undefined) delete process.env.WOOCOMMERCE_WEBHOOK_SECRET;
    else process.env.WOOCOMMERCE_WEBHOOK_SECRET = original;
  });

  const enviar = (app: express.Express, cuerpo: object, firma?: string) => {
    const texto = JSON.stringify(cuerpo);
    return request(app)
      .post("/commerce/webhooks/woocommerce")
      .set("Content-Type", "application/json")
      .set("X-WC-Webhook-Signature", firma ?? firmar(texto))
      .send(texto);
  };

  test.each([
    "pago-manual",
    "en-preparacion",
    "en-camino",
    "recibido",
    "entregado",
    "pago-ocr",
    "processing",
    "completed",
    "pending",
    "cancelled",
  ])("estado %s con firma valida se entrega al servicio, que decide que hacer", async (status) => {
    const res = await enviar(crearApp(), { id: 2395, status });
    expect(res.status).toBe(200);
    expect(aplicar).toHaveBeenCalledWith("2395", status);
  });

  test("firma invalida -> 401 y no toca ningun pedido", async () => {
    const res = await enviar(crearApp(), { id: 2395, status: "en-camino" }, firmar("otro cuerpo"));
    expect(res.status).toBe(401);
    expect(aplicar).not.toHaveBeenCalled();
  });

  test("firmado con otro secreto -> 401", async () => {
    const texto = JSON.stringify({ id: 2395, status: "en-camino" });
    const res = await enviar(crearApp(), JSON.parse(texto), firmar(texto, "otro-secreto"));
    expect(res.status).toBe(401);
    expect(aplicar).not.toHaveBeenCalled();
  });

  test("sin firma en un JSON -> 401", async () => {
    const res = await request(crearApp())
      .post("/commerce/webhooks/woocommerce")
      .send({ id: 2395, status: "en-camino" });
    expect(res.status).toBe(401);
    expect(aplicar).not.toHaveBeenCalled();
  });

  test("modificar el cuerpo despues de firmar invalida la firma", async () => {
    const firmado = JSON.stringify({ id: 2395, status: "pending" });
    const res = await enviar(crearApp(), { id: 2395, status: "en-camino" }, firmar(firmado));
    expect(res.status).toBe(401);
    expect(aplicar).not.toHaveBeenCalled();
  });

  test("sin secreto configurado -> 503 (nunca se confia en payloads sin verificar)", async () => {
    delete process.env.WOOCOMMERCE_WEBHOOK_SECRET;
    const res = await enviar(crearApp(), { id: 2395, status: "en-camino" });
    expect(res.status).toBe(503);
    expect(aplicar).not.toHaveBeenCalled();
  });

  test("ping de WooCommerce al guardar el webhook (form-urlencoded, sin firma) -> 200", async () => {
    const res = await request(crearApp())
      .post("/commerce/webhooks/woocommerce")
      .type("form")
      .send("webhook_id=2");
    expect(res.status).toBe(200);
    expect(aplicar).not.toHaveBeenCalled();
  });

  test("el ping responde 200 aunque el secreto no este configurado todavia", async () => {
    delete process.env.WOOCOMMERCE_WEBHOOK_SECRET;
    const res = await request(crearApp())
      .post("/commerce/webhooks/woocommerce")
      .type("form")
      .send("webhook_id=2");
    expect(res.status).toBe(200);
  });

  test("un JSON sin firma NO se trata como ping", async () => {
    const res = await request(crearApp())
      .post("/commerce/webhooks/woocommerce")
      .set("Content-Type", "application/json")
      .send(JSON.stringify({ webhook_id: 2 }));
    expect(res.status).toBe(401);
  });

  test("payload firmado sin id de pedido -> 200 sin procesar", async () => {
    const res = await enviar(crearApp(), { status: "en-camino" });
    expect(res.status).toBe(200);
    expect(aplicar).not.toHaveBeenCalled();
  });

  test("si el servicio falla responde error (WooCommerce reintenta la entrega)", async () => {
    aplicar.mockRejectedValue(new Error("db caida"));
    const app = crearApp();
    app.use(((err, _req, res, _next) => {
      res.status(500).json({ message: err.message });
    }) as express.ErrorRequestHandler);
    const res = await enviar(app, { id: 2395, status: "en-camino" });
    expect(res.status).toBe(500);
  });
});

describe("CommerceLifecycleService.aplicarEstadoDesdeWoo", () => {
  const woo = wooFetch as jest.MockedFunction<typeof wooFetch>;

  function crearServicio(pedido: unknown, opciones: { falla?: EstadoPedidoInterno } = {}) {
    // El claim atomico solo prospera si el pedido sigue en el estado esperado.
    let estadoActual = (pedido as { estado?: EstadoPedidoInterno } | null)?.estado;
    const tx = {
      pedidoApp: {
        updateMany: jest.fn(async ({ where, data }: any) => {
          if (opciones.falla === data.estado || where.estado !== estadoActual) return { count: 0 };
          estadoActual = data.estado;
          return { count: 1 };
        }),
      },
      pedidoAppEstadoHistorico: { create: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      pedidoApp: {
        findUnique: jest.fn().mockResolvedValue(pedido),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      $transaction: jest.fn(async (fn: (t: typeof tx) => unknown) => fn(tx)),
    };
    const service = new CommerceLifecycleService(prisma as never);
    const crearParaUsuarios = jest.fn().mockResolvedValue(undefined);
    (service as any).notificaciones = { crearParaUsuarios };
    return { service, prisma, tx, crearParaUsuarios };
  }

  const pedido = (estado: EstadoPedidoInterno, estadoWoo = "pending") => ({
    id: 6,
    estado,
    usuarioId: "34319305",
    estadoWoo,
  });

  const historial = (tx: any) =>
    tx.pedidoAppEstadoHistorico.create.mock.calls.map(([{ data }]: any) => [
      data.estadoAnterior,
      data.estadoNuevo,
    ]);

  const tipos = (crearParaUsuarios: jest.Mock) =>
    crearParaUsuarios.mock.calls.map(([datos]) => datos.tipo);

  beforeEach(() => woo.mockReset());

  describe("pago", () => {
    test("Confirmado - manual: PAGADO, historial atribuido a WooCommerce y aviso al cliente", async () => {
      const { service, tx, crearParaUsuarios } = crearServicio(pedido(E.PENDIENTE_PAGO));

      await service.aplicarEstadoDesdeWoo("2395", "pago-manual");

      expect(tx.pedidoApp.updateMany).toHaveBeenCalledWith({
        where: { id: 6, estado: E.PENDIENTE_PAGO },
        data: { estado: E.PAGADO, estadoWoo: "pago-manual" },
      });
      expect(tx.pedidoAppEstadoHistorico.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          pedidoId: 6,
          estadoAnterior: E.PENDIENTE_PAGO,
          estadoNuevo: E.PAGADO,
          cambiadoPorRol: "woocommerce",
          motivo: expect.stringContaining("Confirmado - manual"),
        }),
      });
      expect(crearParaUsuarios).toHaveBeenCalledWith(
        expect.objectContaining({
          usuarioIds: ["34319305"],
          tipo: "pedido_pagado",
          referenciaTipo: "PedidoApp",
          referenciaId: 6,
        }),
      );
    });

    test.each(["processing", "completed"])("%s (estado nativo de Woo) tambien confirma el pago", async (status) => {
      const { service, tx } = crearServicio(pedido(E.PENDIENTE_PAGO));
      await service.aplicarEstadoDesdeWoo("2395", status);
      expect(historial(tx)).toEqual([[E.PENDIENTE_PAGO, E.PAGADO]]);
    });

    test("Confirmado - OCR NO confirma el pago: solo se registra el estado de Woo", async () => {
      const { service, prisma, tx, crearParaUsuarios } = crearServicio(pedido(E.PENDIENTE_PAGO));

      await service.aplicarEstadoDesdeWoo("2395", "pago-ocr");

      expect(prisma.$transaction).not.toHaveBeenCalled();
      expect(crearParaUsuarios).not.toHaveBeenCalled();
      expect(tx.pedidoAppEstadoHistorico.create).not.toHaveBeenCalled();
      expect(prisma.pedidoApp.updateMany).toHaveBeenCalledWith({
        where: { wooOrderId: "2395", estadoWoo: { not: "pago-ocr" } },
        data: { estadoWoo: "pago-ocr" },
      });
    });
  });

  describe("preparacion y envio desde wp-admin", () => {
    test("En preparación: PAGADO -> PENDIENTE_ENVIO y le llega la notificacion", async () => {
      const { service, tx, crearParaUsuarios } = crearServicio(pedido(E.PAGADO, "pago-manual"));

      await service.aplicarEstadoDesdeWoo("2395", "en-preparacion");

      expect(historial(tx)).toEqual([[E.PAGADO, E.PENDIENTE_ENVIO]]);
      expect(tx.pedidoApp.updateMany).toHaveBeenCalledWith({
        where: { id: 6, estado: E.PAGADO },
        data: { estado: E.PENDIENTE_ENVIO, estadoWoo: "en-preparacion" },
      });
      expect(crearParaUsuarios).toHaveBeenCalledWith(
        expect.objectContaining({
          tipo: "pedido_preparacion",
          titulo: "Estamos preparando tu pedido",
          referenciaId: 6,
        }),
      );
    });

    test("En camino: PENDIENTE_ENVIO -> ENVIADO, notifica y le pide confirmar la recepcion", async () => {
      const { service, tx, crearParaUsuarios } = crearServicio(pedido(E.PENDIENTE_ENVIO, "en-preparacion"));

      await service.aplicarEstadoDesdeWoo("2395", "en-camino");

      expect(historial(tx)).toEqual([[E.PENDIENTE_ENVIO, E.ENVIADO]]);
      expect(crearParaUsuarios).toHaveBeenCalledWith(
        expect.objectContaining({
          tipo: "pedido_enviado",
          mensaje: expect.stringContaining("confirma que lo recibiste completo"),
        }),
      );
    });

    test("si el equipo salta pasos, se aplican los intermedios en orden con su historial y su aviso", async () => {
      const { service, tx, crearParaUsuarios } = crearServicio(pedido(E.PENDIENTE_PAGO));

      await service.aplicarEstadoDesdeWoo("2395", "en-camino");

      expect(historial(tx)).toEqual([
        [E.PENDIENTE_PAGO, E.PAGADO],
        [E.PAGADO, E.PENDIENTE_ENVIO],
        [E.PENDIENTE_ENVIO, E.ENVIADO],
      ]);
      expect(tipos(crearParaUsuarios)).toEqual(["pedido_pagado", "pedido_preparacion", "pedido_enviado"]);
      // Solo el paso final guarda el estado de Woo.
      const datos = tx.pedidoApp.updateMany.mock.calls.map(([arg]: any) => arg.data);
      expect(datos[0]).toEqual({ estado: E.PAGADO });
      expect(datos[2]).toEqual({ estado: E.ENVIADO, estadoWoo: "en-camino" });
    });

    test("el paso de pago intermedio deja claro que se dio por confirmado al avanzar", async () => {
      const { service, tx } = crearServicio(pedido(E.PENDIENTE_PAGO));
      await service.aplicarEstadoDesdeWoo("2395", "en-preparacion");
      const primero = tx.pedidoAppEstadoHistorico.create.mock.calls[0][0].data;
      expect(primero.motivo).toContain("al avanzar el pedido");
    });
  });

  describe("solo avanza: idempotencia y proteccion del cliente", () => {
    test("reintento del webhook con el pedido ya en ese estado no hace nada", async () => {
      const { service, prisma, crearParaUsuarios } = crearServicio(pedido(E.ENVIADO, "en-camino"));

      await service.aplicarEstadoDesdeWoo("2395", "en-camino");

      expect(prisma.$transaction).not.toHaveBeenCalled();
      expect(crearParaUsuarios).not.toHaveBeenCalled();
      expect(prisma.pedidoApp.updateMany).not.toHaveBeenCalled();
    });

    test.each([
      [E.ENVIADO, "en-preparacion"],
      [E.ENVIADO, "pago-manual"],
      [E.PENDIENTE_ENVIO, "pago-manual"],
      [E.RECIBIDO, "en-camino"],
      [E.ENTREGADO, "en-camino"],
      [E.CANCELADO, "en-camino"],
    ])("un pedido en %s NO retrocede cuando Woo dice %s", async (estado, status) => {
      const { service, prisma, crearParaUsuarios } = crearServicio(pedido(estado));

      await service.aplicarEstadoDesdeWoo("2395", status);

      expect(prisma.$transaction).not.toHaveBeenCalled();
      expect(crearParaUsuarios).not.toHaveBeenCalled();
    });

    test.each(["recibido", "entregado"])(
      "'%s' puesto a mano en Woo NO mueve el pedido: lo confirma el cliente en la app",
      async (status) => {
        const { service, prisma, crearParaUsuarios } = crearServicio(pedido(E.ENVIADO, "en-camino"));

        await service.aplicarEstadoDesdeWoo("2395", status);

        expect(prisma.$transaction).not.toHaveBeenCalled();
        expect(crearParaUsuarios).not.toHaveBeenCalled();
      },
    );

    test("dos entregas simultaneas: la que pierde la carrera no duplica historial ni avisos", async () => {
      // El pedido ya no esta en el estado que leyo esta entrega.
      const { service, tx, crearParaUsuarios } = crearServicio(pedido(E.PAGADO), { falla: E.PENDIENTE_ENVIO });

      await service.aplicarEstadoDesdeWoo("2395", "en-preparacion");

      expect(tx.pedidoAppEstadoHistorico.create).not.toHaveBeenCalled();
      expect(crearParaUsuarios).not.toHaveBeenCalled();
    });

    test("si un paso intermedio pierde la carrera, no aplica los siguientes", async () => {
      const { service, tx, crearParaUsuarios } = crearServicio(pedido(E.PENDIENTE_PAGO), { falla: E.PENDIENTE_ENVIO });

      await service.aplicarEstadoDesdeWoo("2395", "en-camino");

      expect(historial(tx)).toEqual([[E.PENDIENTE_PAGO, E.PAGADO]]);
      expect(tipos(crearParaUsuarios)).toEqual(["pedido_pagado"]);
    });

    test("estados ajenos (cancelled, pending, on-hold) solo se registran", async () => {
      for (const status of ["cancelled", "pending", "on-hold", "refunded"]) {
        const { service, prisma } = crearServicio(pedido(E.PAGADO, "pago-manual"));
        await service.aplicarEstadoDesdeWoo("2395", status);
        expect(prisma.$transaction).not.toHaveBeenCalled();
        expect(prisma.pedidoApp.updateMany).toHaveBeenCalledWith({
          where: { wooOrderId: "2395", estadoWoo: { not: status } },
          data: { estadoWoo: status },
        });
      }
    });

    test("pedido que no existe en esta base (otro ambiente) se ignora sin error", async () => {
      const { service, prisma } = crearServicio(null);
      await expect(service.aplicarEstadoDesdeWoo("9999", "en-camino")).resolves.toBeUndefined();
      expect(prisma.$transaction).not.toHaveBeenCalled();
      expect(prisma.pedidoApp.updateMany).not.toHaveBeenCalled();
    });

    test("nunca escribe de vuelta a WooCommerce (evita bucles con el eco del webhook)", async () => {
      const { service } = crearServicio(pedido(E.PAGADO, "pago-manual"));
      await service.aplicarEstadoDesdeWoo("2395", "en-preparacion");
      expect(woo).not.toHaveBeenCalled();
    });
  });
});
