import {
  EstadoPedidoInterno,
  Prisma,
  Rol,
  TipoPedidoApp,
  type PrismaClient,
} from "@prisma/client";
import { z } from "zod";
import { CrearPedidoResidenteDTO } from "../model/Commerce";
import { WooCommerceCatalogService } from "./WooCommerceCatalogService";

type WooOrderResponse = {
  id: number;
  status?: string;
  total?: string;
  currency?: string;
  order_key?: string;
  checkout_url?: string;
};

function makeHttpError(status: number, message: string) {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function splitName(nombre: string) {
  const clean = nombre.trim().replace(/\s+/g, " ");
  const parts = clean.split(" ");
  if (parts.length <= 1) return { firstName: clean, lastName: "" };
  return {
    firstName: parts.slice(0, -1).join(" "),
    lastName: parts.slice(-1).join(" "),
  };
}

function toOrderStatus(status: string | null | undefined) {
  const value = String(status ?? "").trim().toLowerCase();
  switch (value) {
    case "pending":
      return EstadoPedidoInterno.PENDIENTE_PAGO;
    case "processing":
    case "on-hold":
      return EstadoPedidoInterno.PAGADO;
    case "completed":
      return EstadoPedidoInterno.ENTREGADO;
    case "cancelled":
    case "failed":
      return EstadoPedidoInterno.CANCELADO;
    default:
      return EstadoPedidoInterno.BORRADOR;
  }
}

export class CommerceOrderService {
  private readonly catalogService: WooCommerceCatalogService;

  constructor(private prisma: PrismaClient) {
    this.catalogService = new WooCommerceCatalogService();
  }

  private get baseUrl() {
    const base =
      process.env.WOOCOMMERCE_BASE_URL?.trim() || process.env.ECOMMERCE_BASE_URL?.trim() || "";
    if (!base) {
      throw makeHttpError(500, "Falta WOOCOMMERCE_BASE_URL para gestionar pedidos del ecommerce");
    }
    return base.endsWith("/") ? base.slice(0, -1) : base;
  }

  private get consumerKey() {
    return process.env.WOOCOMMERCE_CONSUMER_KEY?.trim() || "";
  }

  private get consumerSecret() {
    return process.env.WOOCOMMERCE_CONSUMER_SECRET?.trim() || "";
  }

  private ensureWooWriteConfigured() {
    if (!this.consumerKey || !this.consumerSecret) {
      throw makeHttpError(
        503,
        "Faltan WOOCOMMERCE_CONSUMER_KEY y WOOCOMMERCE_CONSUMER_SECRET para crear pedidos en WooCommerce",
      );
    }
  }

  private wooRestUrl(path: string) {
    const url = new URL(`${this.baseUrl}/wp-json/wc/v3${path}`);
    url.searchParams.set("consumer_key", this.consumerKey);
    url.searchParams.set("consumer_secret", this.consumerSecret);
    return url.toString();
  }

  private async wooRequest<T>(path: string, init?: RequestInit) {
    this.ensureWooWriteConfigured();
    const response = await fetch(this.wooRestUrl(path), {
      ...init,
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    });

    if (!response.ok) {
      const text = await response.text();
      throw makeHttpError(
        502,
        `WooCommerce rechazo la operacion (${response.status}). ${text || "No se pudo crear el pedido"}`,
      );
    }

    return response.json() as Promise<T>;
  }

  private async getResidentContext(userId: string) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: {
        id: true,
        nombre: true,
        correo: true,
        rol: true,
        residente: {
          select: {
            id: true,
            conjuntoId: true,
            conjunto: { select: { nit: true, nombre: true } },
          },
        },
      },
    });

    if (!usuario) throw makeHttpError(404, "Usuario no encontrado");
    if (String(usuario.rol).trim().toLowerCase() !== Rol.residente) {
      throw makeHttpError(403, "Solo los residentes pueden crear pedidos personales desde este flujo");
    }
    if (!usuario.residente) {
      throw makeHttpError(403, "El usuario no tiene un residente asociado");
    }

    return usuario;
  }

  private async resolveOrderItems(items: z.infer<typeof CrearPedidoResidenteDTO>["items"]) {
    const resolved = [] as Array<{
      productId: number;
      quantity: number;
      variationId?: number;
      name: string;
      sku: string;
      type: string;
      unitPrice: number;
      subtotal: number;
    }>;

    for (const item of items) {
      const product = await this.catalogService.getProduct(item.productId);
      if (!product.purchasable) {
        throw makeHttpError(400, `El producto ${product.name} no esta disponible para compra`);
      }
      if (product.type != "simple" && !item.variationId) {
        throw makeHttpError(
          400,
          `El producto ${product.name} requiere seleccion de variacion. Este soporte se activa en el siguiente ajuste de checkout`,
        );
      }

      resolved.push({
        productId: item.productId,
        quantity: item.quantity,
        variationId: item.variationId,
        name: product.name,
        sku: product.sku,
        type: product.type,
        unitPrice: product.price.current,
        subtotal: product.price.current * item.quantity,
      });
    }

    return resolved;
  }

  private buildPayUrl(order: WooOrderResponse) {
    if (order.checkout_url && String(order.checkout_url).trim() !== "") {
      return String(order.checkout_url).trim();
    }
    if (order.id && order.order_key) {
      return `${this.baseUrl}/checkout/order-pay/${order.id}/?pay_for_order=true&key=${order.order_key}`;
    }
    return `${this.baseUrl}/mi-cuenta/orders/`;
  }

  async createResidentOrder(userId: string, payload: unknown) {
    const dto = CrearPedidoResidenteDTO.parse(payload);
    const usuario = await this.getResidentContext(userId);
    const orderItems = await this.resolveOrderItems(dto.items);
    const total = orderItems.reduce((sum, item) => sum + item.subtotal, 0);
    const { firstName, lastName } = splitName(usuario.nombre);

    const wooOrder = await this.wooRequest<WooOrderResponse>("/orders", {
      method: "POST",
      body: JSON.stringify({
        payment_method: "bacs",
        payment_method_title: "Pago desde app ControlApp",
        set_paid: false,
        status: "pending",
        customer_note: dto.notas?.trim() || undefined,
        billing: {
          first_name: firstName,
          last_name: lastName,
          email: usuario.correo,
        },
        line_items: orderItems.map((item) => ({
          product_id: item.productId,
          quantity: item.quantity,
          ...(item.variationId ? { variation_id: item.variationId } : {}),
        })),
        meta_data: [
          { key: "controlapp_tipo_pedido", value: "RESIDENTE" },
          { key: "controlapp_residente_id", value: usuario.residente!.id },
          { key: "controlapp_conjunto_id", value: usuario.residente!.conjuntoId },
        ],
      }),
    });

    const pedido = await this.prisma.pedidoApp.create({
      data: {
        tipo: TipoPedidoApp.RESIDENTE,
        estado: toOrderStatus(wooOrder.status),
        estadoWoo: wooOrder.status ?? "pending",
        wooOrderId: String(wooOrder.id),
        usuarioId: usuario.id,
        conjuntoId: usuario.residente!.conjuntoId,
        residenteId: usuario.residente!.id,
        total: new Prisma.Decimal(total),
        moneda: wooOrder.currency ?? "COP",
        items: {
          create: orderItems.map((item) => ({
            wooProductId: item.productId,
            wooVariationId: item.variationId ?? null,
            nombreProducto: item.name,
            sku: item.sku || null,
            cantidad: new Prisma.Decimal(item.quantity),
            precioUnitario: new Prisma.Decimal(item.unitPrice),
            subtotal: new Prisma.Decimal(item.subtotal),
          })),
        },
      },
      include: {
        items: true,
      },
    });

    return {
      id: pedido.id,
      wooOrderId: pedido.wooOrderId,
      estado: pedido.estado,
      estadoWoo: pedido.estadoWoo,
      total: Number(pedido.total),
      moneda: pedido.moneda,
      pagoUrl: this.buildPayUrl(wooOrder),
      creadoEn: pedido.creadoEn,
      items: pedido.items.map((item) => ({
        id: item.id,
        nombreProducto: item.nombreProducto,
        cantidad: Number(item.cantidad),
        precioUnitario: Number(item.precioUnitario),
        subtotal: Number(item.subtotal),
      })),
    };
  }

  async listResidentOrders(userId: string) {
    await this.getResidentContext(userId);
    const pedidos = await this.prisma.pedidoApp.findMany({
      where: {
        usuarioId: userId,
        tipo: TipoPedidoApp.RESIDENTE,
      },
      include: {
        items: true,
      },
      orderBy: { creadoEn: "desc" },
    });

    return pedidos.map((pedido) => ({
      id: pedido.id,
      wooOrderId: pedido.wooOrderId,
      estado: pedido.estado,
      estadoWoo: pedido.estadoWoo,
      total: Number(pedido.total),
      moneda: pedido.moneda,
      creadoEn: pedido.creadoEn,
      cantidadItems: pedido.items.length,
      items: pedido.items.map((item) => ({
        id: item.id,
        nombreProducto: item.nombreProducto,
        cantidad: Number(item.cantidad),
        subtotal: Number(item.subtotal),
      })),
    }));
  }

  async getResidentOrder(userId: string, pedidoId: number) {
    await this.getResidentContext(userId);
    const pedido = await this.prisma.pedidoApp.findFirst({
      where: {
        id: pedidoId,
        usuarioId: userId,
        tipo: TipoPedidoApp.RESIDENTE,
      },
      include: {
        items: true,
      },
    });

    if (!pedido) throw makeHttpError(404, "Pedido no encontrado");

    return {
      id: pedido.id,
      wooOrderId: pedido.wooOrderId,
      estado: pedido.estado,
      estadoWoo: pedido.estadoWoo,
      total: Number(pedido.total),
      moneda: pedido.moneda,
      creadoEn: pedido.creadoEn,
      actualizadoEn: pedido.actualizadoEn,
      items: pedido.items.map((item) => ({
        id: item.id,
        nombreProducto: item.nombreProducto,
        sku: item.sku,
        cantidad: Number(item.cantidad),
        precioUnitario: Number(item.precioUnitario),
        subtotal: Number(item.subtotal),
      })),
    };
  }
}
