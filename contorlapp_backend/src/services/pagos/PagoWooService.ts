import { CanalPago, OrigenVerificacionPago, type PagoCobro, type PrismaClient } from "@prisma/client";
import crypto from "crypto";
import { z } from "zod";
import { commerceHttpError } from "../CommerceAccessService";
import { buildWooUrl, wooFetch } from "../wooFetch";
import type { ConfirmadorPagoContexto, PagoService } from "./PagoService";

type TransactionClient = Parameters<Parameters<PrismaClient["$transaction"]>[0]>[0];

export const CrearCobroWooDTO = z.object({
  wooOrderId: z.coerce.string().regex(/^\d{1,12}$/, "La orden no es valida"),
  orderKey: z.string().trim().min(1).max(100),
});

type WooMeta = { key?: string; value?: unknown };

type WooOrderPago = {
  id: number;
  status: string;
  currency?: string;
  total?: string;
  order_key?: string;
  transaction_id?: string;
  meta_data?: WooMeta[];
  line_items?: Array<{ meta_data?: WooMeta[] }>;
};

// Estados de la orden en los que todavia tiene sentido cobrarla / marcarla
// pagada. Cualquier otro (cancelada, reembolsada, ya pagada por otra via) es
// un pago que necesita revision manual.
const ESTADOS_WOO_COBRABLES = new Set(["pending", "failed", "on-hold", "pago-ocr"]);

function meta(lista: WooMeta[] | undefined, clave: string) {
  return lista?.find((m) => m.key === clave)?.value;
}

/**
 * Cuanto se cobra de una orden de la tienda. Los servicios del plugin de
 * reservas (cl-servicios-reserva) dejan en cada item "Pago" = "Anticipo" o
 * "100%", y en la orden `_clsr_pay_choice` y `_clsr_pay_now` (lo que se paga
 * ahora, ya redondeado). Si la orden tiene servicios con anticipo se cobra
 * ese anticipo; si no -productos, o servicios al 100 %- el total. Ojo:
 * `_clsr_pay_choice` vale "deposit" por defecto tambien en ordenes de solo
 * productos, por eso se miran los items.
 */
export function montoACobrarWoo(orden: Pick<WooOrderPago, "total" | "meta_data" | "line_items">) {
  const total = Number(orden.total);
  const pagos = (orden.line_items ?? []).map((item) => meta(item.meta_data, "Pago")).filter(Boolean);
  const conAnticipo = pagos.includes("Anticipo") && !pagos.includes("100%");
  if (!conAnticipo || meta(orden.meta_data, "_clsr_pay_choice") !== "deposit") {
    return { monto: total, anticipo: false };
  }
  const anticipo = Number(meta(orden.meta_data, "_clsr_pay_now"));
  // Un anticipo que no tiene sentido (vacio, 0, mayor o igual al total) no se
  // cobra: se cobra el total, que es lo que el cliente ve en el pedido.
  if (!Number.isFinite(anticipo) || anticipo <= 0 || anticipo >= total) {
    return { monto: total, anticipo: false };
  }
  return { monto: Math.round(anticipo * 100) / 100, anticipo: true };
}

/** Contrato con el plugin controlapp-factus-pay (nunca expone campos internos). */
export function serializarCobroWoo(cobro: PagoCobro) {
  return {
    id: cobro.id,
    referenceCode: cobro.referenceCode,
    estado: cobro.estado,
    estadoProveedor: cobro.estadoProveedor,
    montoEsperado: Number(cobro.montoEsperado),
    moneda: cobro.moneda,
    qrBase64: cobro.qrBase64,
    // Llave Bre-B del QR: tambien se puede pagar copiandola, por el monto exacto.
    brebKey: cobro.brebKey,
    expiraLocalEn: cobro.expiraLocalEn,
    creadoEn: cobro.creadoEn,
    pagado: cobro.estado === "PAGADO",
  };
}

function mismaClave(a: string, b: string) {
  const ba = Buffer.from(a, "utf8");
  const bb = Buffer.from(b, "utf8");
  return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
}

/**
 * Canal WOOCOMMERCE de los pagos: lo usa el plugin controlapp-factus-pay de la
 * tienda. El plugin NUNCA habla con Factus (un solo token activo por usuario,
 * ver docs/pagos-factus.md): le pide el cobro a este servicio, que relee la
 * orden en WooCommerce para no confiar en el monto que diga WordPress.
 */
export class PagoWooService {
  constructor(
    private prisma: PrismaClient,
    private pagos: Pick<
      PagoService,
      "crearCobro" | "verificarCobro" | "obtenerCobroPorReferencia" | "marcarHuerfano"
    >,
    private dominio: {
      confirmarPagoSistema(tx: TransactionClient, contexto: ConfirmadorPagoContexto): Promise<void>;
      notificarPagoConfirmado(cobro: PagoCobro): Promise<void>;
    },
  ) {}

  private async leerOrden(wooOrderId: string) {
    return wooFetch<WooOrderPago>(
      buildWooUrl("rest", `/orders/${wooOrderId}`, {
        _fields: "id,status,currency,total,order_key,transaction_id,meta_data,line_items",
      }),
      {},
      { requireAuth: true, timeoutMs: 8_000, failureMessage: "No pudimos consultar la orden en la tienda" },
    );
  }

  async crearCobro(payload: unknown) {
    const dto = CrearCobroWooDTO.parse(payload);
    const orden = await this.leerOrden(dto.wooOrderId);

    if (!orden.order_key || !mismaClave(orden.order_key, dto.orderKey)) {
      throw commerceHttpError(403, "La orden no coincide con la clave enviada");
    }
    if (!ESTADOS_WOO_COBRABLES.has(orden.status)) {
      throw commerceHttpError(409, "La orden ya no esta pendiente de pago");
    }
    if ((orden.currency ?? "COP") !== "COP") {
      throw commerceHttpError(422, "Solo se pueden cobrar ordenes en pesos colombianos (COP)");
    }
    const total = Number(orden.total);
    if (!Number.isFinite(total) || total <= 0) {
      throw commerceHttpError(422, "La orden no tiene un total valido para cobrar");
    }
    // Servicios con anticipo: se cobra el anticipo; lo demas, el total.
    const { monto } = montoACobrarWoo(orden);

    // Una orden creada desde la app tambien es una orden de Woo: se enlaza al
    // pedido para que el pago lo mueva a PAGADO y avise al cliente.
    const pedido = await this.prisma.pedidoApp.findUnique({
      where: { wooOrderId: dto.wooOrderId },
      select: { id: true, usuarioId: true, estado: true },
    });
    if (pedido && pedido.estado !== "PENDIENTE_PAGO") {
      throw commerceHttpError(409, "El pedido ya no esta pendiente de pago");
    }

    const cobro = await this.pagos.crearCobro({
      canal: CanalPago.WOOCOMMERCE,
      montoEsperado: monto,
      pedidoAppId: pedido?.id,
      wooOrderId: dto.wooOrderId,
      usuarioId: pedido?.usuarioId,
      referencePrefix: "WC",
    });
    return serializarCobroWoo(cobro);
  }

  private async cobroWoo(referenceCode: string) {
    const cobro = await this.pagos.obtenerCobroPorReferencia(referenceCode);
    // La tienda tambien consulta los cobros del saldo de un servicio.
    if (!cobro || (cobro.canal !== CanalPago.WOOCOMMERCE && cobro.canal !== CanalPago.SALDO_SERVICIO)) {
      throw commerceHttpError(404, "Cobro no encontrado");
    }
    return cobro;
  }

  async obtenerCobro(referenceCode: string) {
    return serializarCobroWoo(await this.cobroWoo(referenceCode));
  }

  async verificarCobro(referenceCode: string) {
    const cobro = await this.cobroWoo(referenceCode);
    return serializarCobroWoo(await this.pagos.verificarCobro(cobro.id, OrigenVerificacionPago.USUARIO));
  }

  /** Confirmador del canal (dentro de la transaccion del cobro): solo hay
   * algo que mover si la orden tambien es un pedido de la app. */
  async confirmarEnDominio(tx: TransactionClient, contexto: ConfirmadorPagoContexto): Promise<void> {
    if (!contexto.pedidoAppId) return;
    await this.dominio.confirmarPagoSistema(tx, contexto);
  }

  /**
   * Pos-confirmacion: marca la orden pagada en WooCommerce (processing +
   * set_paid + transaction_id, lo que hace que Woo descuente stock y mande
   * sus correos). Si la orden ya no es cobrable -cancelada mientras el cliente
   * pagaba, por ejemplo- NO se toca: el cobro queda huerfano y se alerta.
   * Lanza si Woo no responde, para que PagoService lo reintente.
   *
   * Puede correr mas de una vez (reintento tras un fallo o una caida): si la
   * orden ya quedo pagada con ESTE cobro en un intento anterior, solo falta
   * el aviso al cliente -no es un huerfano-.
   */
  async posConfirmacion(cobro: PagoCobro): Promise<void> {
    if (!cobro.wooOrderId) return;
    const orden = await this.leerOrden(cobro.wooOrderId);
    if (orden.transaction_id === cobro.referenceCode && !ESTADOS_WOO_COBRABLES.has(orden.status)) {
      await this.dominio.notificarPagoConfirmado(cobro);
      return;
    }
    if (!ESTADOS_WOO_COBRABLES.has(orden.status)) {
      await this.pagos.marcarHuerfano(
        cobro.id,
        `Factus confirmo el pago (${cobro.referenceCode}) pero la orden #${cobro.wooOrderId} esta en estado "${orden.status}"`,
      );
      return;
    }

    await wooFetch(
      buildWooUrl("rest", `/orders/${cobro.wooOrderId}`),
      {
        method: "PUT",
        body: JSON.stringify({ status: "processing", set_paid: true, transaction_id: cobro.referenceCode }),
      },
      { requireAuth: true, timeoutMs: 8_000 },
    );
    // Un anticipo deja la orden pagada (como "Confirmado - manual" en el flujo
    // con comprobante); el saldo queda en la nota para quien preste el servicio.
    const pagado = Number(cobro.montoEsperado);
    const saldo = Math.round((Number(orden.total) - pagado) * 100) / 100;
    const detalle =
      saldo > 0
        ? ` Anticipo de $${pagado.toLocaleString("es-CO")}; saldo pendiente $${saldo.toLocaleString("es-CO")}.`
        : "";
    try {
      await wooFetch(
        buildWooUrl("rest", `/orders/${cobro.wooOrderId}/notes`),
        {
          method: "POST",
          body: JSON.stringify({
            note: `Pago confirmado automaticamente por Factus Pay (referencia ${cobro.referenceCode}).${detalle}`,
            customer_note: false,
          }),
        },
        { requireAuth: true, timeoutMs: 8_000 },
      );
    } catch {
      // La nota es informativa.
    }
    await this.dominio.notificarPagoConfirmado(cobro);
  }

  /**
   * Pos-fallo: Factus reporto el cobro como fallido/rechazado. Solo si la
   * orden sigue en un estado cobrable se refleja como "failed" en Woo -si ya
   * se pago por otra via o se cancelo, no tiene sentido tocarla-. Nunca lanza:
   * un cobro fallido no tiene dinero de por medio, no necesita reintentos.
   */
  async posFallo(cobro: PagoCobro): Promise<void> {
    if (!cobro.wooOrderId) return;
    try {
      const orden = await this.leerOrden(cobro.wooOrderId);
      if (!ESTADOS_WOO_COBRABLES.has(orden.status)) return;

      await wooFetch(
        buildWooUrl("rest", `/orders/${cobro.wooOrderId}`),
        { method: "PUT", body: JSON.stringify({ status: "failed" }) },
        { requireAuth: true, timeoutMs: 8_000 },
      );
      await wooFetch(
        buildWooUrl("rest", `/orders/${cobro.wooOrderId}/notes`),
        {
          method: "POST",
          body: JSON.stringify({
            note: `El pago con Factus Pay no se pudo confirmar (referencia ${cobro.referenceCode}).`,
            customer_note: false,
          }),
        },
        { requireAuth: true, timeoutMs: 8_000 },
      ).catch(() => undefined);
    } catch (error) {
      console.error("[pagos] no se pudo reflejar el pago fallido en Woo", {
        cobroId: cobro.id,
        name: error instanceof Error ? error.name : "Error",
      });
    }
  }
}
