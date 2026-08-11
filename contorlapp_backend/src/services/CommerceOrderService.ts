import {
  EstadoPedidoInterno,
  Prisma,
  Rol,
  TipoPedidoApp,
  type PrismaClient,
} from "@prisma/client";
import { z } from "zod";
import { CrearPedidoConjuntoDTO, CrearPedidoResidenteDTO } from "../model/Commerce";
import {
  type CommerceServiceConfig,
  WooCommerceCatalogService,
} from "./WooCommerceCatalogService";
import { cacheDelete } from "./RedisService";
import { buildWooUrl, getWooBaseUrl, wooFetch } from "./wooFetch";

type WooOrderResponse = {
  id: number;
  status?: string;
  total?: string;
  currency?: string;
  order_key?: string;
  checkout_url?: string;
};

type OrderItemsDTO = z.infer<typeof CrearPedidoResidenteDTO>["items"];

type ResolvedOrderItem = {
  productId: number;
  quantity: number;
  variationId?: number;
  name: string;
  sku: string;
  type: string;
  unitPrice: number;
  subtotal: number;
  service?: ResolvedServiceSelection;
};

type ServiceSelectionDTO = NonNullable<OrderItemsDTO[number]["service"]>;

type ResolvedAddon = {
  groupId: string;
  groupLabel: string;
  options: Array<{ id: number; label: string; price: number }>;
};

type ResolvedServiceSelection = {
  date: string;
  slot: string;
  slotLabel: string;
  payChoice: "deposit" | "full";
  depositPct: number;
  addons: ResolvedAddon[];
  addonsTotal: number;
  payNow: number;
  claimToken?: string;
};

function makeHttpError(status: number, message: string) {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export function roundUpServicePayNow(amount: number, multiple = 1000) {
  const safeMultiple = Math.max(1, Math.trunc(multiple));
  return Math.ceil(Math.max(0, amount) / safeMultiple) * safeMultiple;
}

function parseYmd(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (
    date.getUTCFullYear() !== Number(match[1]) ||
    date.getUTCMonth() !== Number(match[2]) - 1 ||
    date.getUTCDate() !== Number(match[3])
  ) {
    return null;
  }
  return date;
}

function todayInBogota() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const part = (type: string) => parts.find((item) => item.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}`;
}

export function validateAndPriceServiceSelection(
  config: CommerceServiceConfig,
  selection: ServiceSelectionDTO,
  basePrice: number,
  quantity: number,
  todayYmd = todayInBogota(),
) {
  const date = parseYmd(selection.date);
  const today = parseYmd(todayYmd);
  if (!date || !today) throw makeHttpError(400, "La fecha del servicio no es valida");
  const minDate = new Date(today.getTime());
  minDate.setUTCDate(minDate.getUTCDate() + config.minDays);
  if (date < minDate) {
    throw makeHttpError(400, `El servicio requiere al menos ${config.minDays} dia(s) de anticipacion`);
  }
  const weekday = date.getUTCDay() === 0 ? 7 : date.getUTCDay();
  if (!config.daysAllowed.includes(weekday)) {
    throw makeHttpError(400, "El servicio no esta disponible el dia de la semana seleccionado");
  }

  const slots =
    config.slots.length > 0
      ? config.slots
      : [{ id: "full", label: "Día completo", capacity: config.maxPerDay }];
  const slotId = selection.slot ?? (slots.length === 1 ? slots[0].id : "");
  const slot = slots.find((item) => item.id === slotId);
  if (!slot) throw makeHttpError(400, "Debes seleccionar un turno valido para el servicio");
  if (quantity > slot.capacity) {
    throw makeHttpError(409, "La cantidad solicitada supera la capacidad del turno");
  }
  if (selection.payChoice === "full" && !config.allowFull) {
    throw makeHttpError(400, "Este servicio no permite pagar el 100% desde la app");
  }

  const configuredIds = new Set(config.addons.map((addon) => addon.id));
  for (const requestedId of Object.keys(selection.addons)) {
    if (!configuredIds.has(requestedId)) {
      throw makeHttpError(400, "La seleccion contiene un grupo de adicionales no valido");
    }
  }

  const resolvedAddons: ResolvedAddon[] = [];
  let addonsTotal = 0;
  for (const addon of config.addons) {
    const selectedIds = [...new Set(selection.addons[addon.id] ?? [])];
    if (addon.required && selectedIds.length === 0) {
      throw makeHttpError(400, `Debes seleccionar una opcion en ${addon.label}`);
    }
    if (addon.type === "radio" && selectedIds.length > 1) {
      throw makeHttpError(400, `Solo puedes seleccionar una opcion en ${addon.label}`);
    }
    const options = selectedIds.map((id) => {
      const option = addon.group.find((candidate) => candidate.id === id);
      if (!option) throw makeHttpError(400, `Una opcion de ${addon.label} no es valida`);
      addonsTotal += option.price;
      return option;
    });
    if (options.length > 0) {
      resolvedAddons.push({ groupId: addon.id, groupLabel: addon.label, options });
    }
  }

  const unitPrice = basePrice + addonsTotal;
  const serviceTotal = unitPrice * quantity;
  const rawPayNow =
    selection.payChoice === "full"
      ? serviceTotal
      : (serviceTotal * config.depositPct) / 100;
  return {
    unitPrice,
    service: {
      date: selection.date,
      slot: slot.id,
      slotLabel: slot.label,
      payChoice: selection.payChoice,
      depositPct: config.depositPct,
      addons: resolvedAddons,
      addonsTotal,
      payNow: roundUpServicePayNow(rawPayNow),
    } satisfies ResolvedServiceSelection,
  };
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
    return getWooBaseUrl();
  }

  private async wooRequest<T>(path: string, init?: RequestInit) {
    return wooFetch<T>(buildWooUrl("rest", path), init, {
      requireAuth: true,
      failureMessage: "La tienda no pudo crear el pedido en este momento. Intenta nuevamente",
    });
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

  private async getConjuntoActor(userId: string) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: {
        id: true,
        nombre: true,
        correo: true,
        rol: true,
        gerente: { select: { empresaId: true } },
        jefeOperaciones: { select: { empresaId: true } },
      },
    });

    if (!usuario) throw makeHttpError(404, "Usuario no encontrado");

    const rol = String(usuario.rol).trim().toLowerCase();
    if (
      rol !== Rol.administrador &&
      rol !== Rol.gerente &&
      rol !== Rol.jefe_operaciones
    ) {
      throw makeHttpError(
        403,
        "Tu rol no tiene acceso a los pedidos operativos de conjuntos",
      );
    }

    return { ...usuario, rol: rol as Rol };
  }

  private async resolveConjuntoForCreate(userId: string, conjuntoId?: string) {
    const usuario = await this.getConjuntoActor(userId);
    const requestedId = conjuntoId?.trim() || undefined;

    if (usuario.rol === Rol.administrador) {
      const conjunto = await this.prisma.conjunto.findFirst({
        where: {
          administradorId: userId,
          activo: true,
          ...(requestedId ? { nit: requestedId } : {}),
        },
        select: { nit: true, nombre: true, correo: true },
        orderBy: { nombre: "asc" },
      });

      if (!conjunto) {
        throw makeHttpError(
          403,
          "No tienes un conjunto activo asignado para realizar esta compra",
        );
      }

      return { usuario, conjunto };
    }

    if (!requestedId) {
      throw makeHttpError(400, "Debes seleccionar el conjunto que realizara la compra");
    }

    const empresaId =
      usuario.rol === Rol.gerente
        ? usuario.gerente?.empresaId
        : usuario.jefeOperaciones?.empresaId;
    if (!empresaId) {
      throw makeHttpError(403, "Tu usuario no tiene una empresa asociada");
    }

    const conjunto = await this.prisma.conjunto.findFirst({
      where: { nit: requestedId, empresaId, activo: true },
      select: { nit: true, nombre: true, correo: true },
    });
    if (!conjunto) {
      throw makeHttpError(
        403,
        "El conjunto seleccionado no pertenece a tu empresa o no esta activo",
      );
    }

    return { usuario, conjunto };
  }

  private async getAuthorizedConjuntoIds(userId: string) {
    const usuario = await this.getConjuntoActor(userId);

    if (usuario.rol === Rol.administrador) {
      const conjuntos = await this.prisma.conjunto.findMany({
        where: { administradorId: userId },
        select: { nit: true },
      });
      return conjuntos.map((conjunto) => conjunto.nit);
    }

    const empresaId =
      usuario.rol === Rol.gerente
        ? usuario.gerente?.empresaId
        : usuario.jefeOperaciones?.empresaId;
    if (!empresaId) {
      throw makeHttpError(403, "Tu usuario no tiene una empresa asociada");
    }

    const conjuntos = await this.prisma.conjunto.findMany({
      where: { empresaId },
      select: { nit: true },
    });
    return conjuntos.map((conjunto) => conjunto.nit);
  }

  private async resolveOrderItems(
    items: OrderItemsDTO,
    options: { conjuntoOrder?: boolean } = {},
  ) {
    const resolved: ResolvedOrderItem[] = [];

    for (const item of items) {
      const product = await this.catalogService.getProduct(item.productId);
      if (!product.purchasable) {
        throw makeHttpError(400, `El producto ${product.name} no esta disponible para compra`);
      }
      if (
        options.conjuntoOrder === true &&
        !product.audience.paraConjunto
      ) {
        throw makeHttpError(
          400,
          `${product.name} no es un insumo habilitado para compras del conjunto`,
        );
      }
      if (product.service?.enabled && !item.service) {
        throw makeHttpError(400, `Debes configurar fecha, turno, pago y adicionales para ${product.name}`);
      }
      if (!product.service?.enabled && item.service) {
        throw makeHttpError(400, `${product.name} no admite configuracion de servicio`);
      }
      if (product.type != "simple" && !item.variationId) {
        throw makeHttpError(
          400,
          `El producto ${product.name} requiere seleccion de variacion. Este soporte se activa en el siguiente ajuste de checkout`,
        );
      }

      const pricedService = item.service
        ? validateAndPriceServiceSelection(
            product.service!,
            item.service,
            product.price.current,
            item.quantity,
          )
        : null;
      const unitPrice = pricedService?.unitPrice ?? product.price.current;

      resolved.push({
        productId: item.productId,
        quantity: item.quantity,
        variationId: item.variationId,
        name: product.name,
        sku: product.sku,
        type: product.type,
        unitPrice,
        subtotal: unitPrice * item.quantity,
        service: pricedService?.service,
      });
    }

    for (const item of resolved) {
      if (!item.service) continue;
      const availability = await this.catalogService.getServiceAvailability(
        item.productId,
        item.service.date,
        item.service.slot,
      );
      if (!availability.available || availability.remaining < item.quantity) {
        throw makeHttpError(409, `${item.name} ya no tiene cupos en la fecha y turno seleccionados`);
      }
      const claim = await this.catalogService.claimServiceAvailability(item.productId, {
        date: item.service.date,
        slot: item.service.slot,
        quantity: item.quantity,
      });
      item.service.claimToken = claim.token;
    }

    return resolved;
  }

  private getServiceSummary(items: ResolvedOrderItem[]) {
    const first = items.find((item) => item.service)?.service;
    const total = items.reduce((sum, item) => sum + item.subtotal, 0);
    if (!first) {
      return {
        first: undefined,
        pagarAhora: 0,
        addons: undefined,
        claimTokens: [] as string[],
      };
    }
    const rawPayNow =
      first.payChoice === "full" ? total : (total * first.depositPct) / 100;
    return {
      first,
      pagarAhora: roundUpServicePayNow(rawPayNow),
      addons: items
        .filter((item) => item.service)
        .map((item) => ({ productId: item.productId, addons: item.service!.addons })),
      claimTokens: items
        .map((item) => item.service?.claimToken)
        .filter((token): token is string => Boolean(token)),
    };
  }

  private buildWooLineItem(item: ResolvedOrderItem) {
    const metaData: Array<{ key: string; value: string }> = [];
    if (item.service) {
      metaData.push(
        { key: "Fecha del servicio", value: item.service.date },
        { key: "Turno", value: item.service.slotLabel },
        { key: "Pago", value: item.service.payChoice === "full" ? "100%" : "Anticipo" },
        { key: "_clsr_slot_id", value: item.service.slot },
      );
      if (item.service.claimToken) {
        metaData.push({ key: "_clsr_claim_token", value: item.service.claimToken });
      }
      for (const addon of item.service.addons) {
        metaData.push({
          key: addon.groupLabel,
          value: addon.options.map((option) => option.label).join(", "),
        });
      }
    }

    return {
      product_id: item.productId,
      quantity: item.quantity,
      ...(item.variationId ? { variation_id: item.variationId } : {}),
      subtotal: item.subtotal.toFixed(2),
      total: item.subtotal.toFixed(2),
      ...(metaData.length > 0 ? { meta_data: metaData } : {}),
    };
  }

  private buildServiceOrderMeta(items: ResolvedOrderItem[]) {
    const serviceSummary = this.getServiceSummary(items);
    if (!serviceSummary.first) return [];
    return [
      { key: "_clsr_date", value: serviceSummary.first.date },
      { key: "_clsr_slot", value: serviceSummary.first.slot },
      { key: "_clsr_pay_choice", value: serviceSummary.first.payChoice },
      { key: "_clsr_pay_now", value: serviceSummary.pagarAhora },
      { key: "_clsr_claim_token", value: serviceSummary.claimTokens[0] ?? "" },
      { key: "_clsr_claim_tokens", value: JSON.stringify(serviceSummary.claimTokens) },
    ];
  }

  private buildPedidoItem(item: ResolvedOrderItem) {
    return {
      wooProductId: item.productId,
      wooVariationId: item.variationId ?? null,
      nombreProducto: item.name,
      sku: item.sku || null,
      cantidad: new Prisma.Decimal(item.quantity),
      precioUnitario: new Prisma.Decimal(item.unitPrice),
      subtotal: new Prisma.Decimal(item.subtotal),
      pagarAhora: new Prisma.Decimal(item.service?.payNow ?? 0),
      fechaServicio: item.service ? new Date(`${item.service.date}T00:00:00.000Z`) : null,
      turnoServicio: item.service?.slotLabel ?? null,
      opcionPagoServicio: item.service?.payChoice ?? null,
      addonsServicio: item.service?.addons ?? Prisma.JsonNull,
    };
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

  private async invalidateServiceAvailability(items: ResolvedOrderItem[]) {
    const keys = new Set<string>();
    for (const item of items) {
      if (!item.service) continue;
      const prefix = `commerce:disponibilidad:v1:${item.productId}:${item.service.date}`;
      keys.add(`${prefix}:${item.service.slot}`);
      keys.add(`${prefix}:todos`);
    }
    await cacheDelete(...keys);
  }

  private serializeOrder(
    pedido: {
      id: number;
      wooOrderId: string | null;
      estado: EstadoPedidoInterno;
      estadoWoo: string | null;
      total: Prisma.Decimal;
      moneda: string;
      pagarAhora: Prisma.Decimal;
      fechaServicio: Date | null;
      turnoServicio: string | null;
      opcionPagoServicio: string | null;
      addonsServicio: Prisma.JsonValue | null;
      conjuntoId: string | null;
      creadoEn: Date;
      actualizadoEn: Date;
      conjunto?: { nombre: string } | null;
      items: Array<{
        id: number;
        nombreProducto: string;
        sku: string | null;
        cantidad: Prisma.Decimal;
        precioUnitario: Prisma.Decimal;
        subtotal: Prisma.Decimal;
        pagarAhora: Prisma.Decimal;
        fechaServicio: Date | null;
        turnoServicio: string | null;
        opcionPagoServicio: string | null;
        addonsServicio: Prisma.JsonValue | null;
      }>;
    },
  ) {
    return {
      id: pedido.id,
      wooOrderId: pedido.wooOrderId,
      estado: pedido.estado,
      estadoWoo: pedido.estadoWoo,
      total: Number(pedido.total),
      moneda: pedido.moneda,
      pagarAhora: Number(pedido.pagarAhora),
      fechaServicio: pedido.fechaServicio,
      turnoServicio: pedido.turnoServicio,
      opcionPagoServicio: pedido.opcionPagoServicio,
      addonsServicio: pedido.addonsServicio,
      whatsappPhone: String(
        process.env.WOO_WHATSAPP_PHONE ?? process.env.WHATSAPP_PHONE ?? "",
      ).replace(/\D/g, ""),
      conjuntoId: pedido.conjuntoId,
      conjuntoNombre: pedido.conjunto?.nombre ?? null,
      creadoEn: pedido.creadoEn,
      actualizadoEn: pedido.actualizadoEn,
      cantidadItems: pedido.items.length,
      items: pedido.items.map((item) => ({
        id: item.id,
        nombreProducto: item.nombreProducto,
        sku: item.sku,
        cantidad: Number(item.cantidad),
        precioUnitario: Number(item.precioUnitario),
        subtotal: Number(item.subtotal),
        pagarAhora: Number(item.pagarAhora),
        fechaServicio: item.fechaServicio,
        turnoServicio: item.turnoServicio,
        opcionPagoServicio: item.opcionPagoServicio,
        addonsServicio: item.addonsServicio,
      })),
    };
  }

  private async findIdempotentOrder(
    userId: string,
    tipo: TipoPedidoApp,
    idempotencyKey?: string,
  ) {
    if (!idempotencyKey) return null;
    const pedido = await this.prisma.pedidoApp.findUnique({
      where: { idempotencyKey },
      include: {
        conjunto: { select: { nombre: true } },
        items: true,
      },
    });
    if (!pedido) return null;
    if (pedido.usuarioId !== userId || pedido.tipo !== tipo) {
      throw makeHttpError(409, "La clave de idempotencia ya fue utilizada en otro pedido");
    }
    return {
      ...this.serializeOrder(pedido),
      pagoUrl: `${this.baseUrl}/mi-cuenta/orders/`,
      idempotentReplay: true,
    };
  }

  async createResidentOrder(userId: string, payload: unknown) {
    const dto = CrearPedidoResidenteDTO.parse(payload);
    const usuario = await this.getResidentContext(userId);
    const existing = await this.findIdempotentOrder(
      userId,
      TipoPedidoApp.RESIDENTE,
      dto.idempotencyKey,
    );
    if (existing) return existing;
    const orderItems = await this.resolveOrderItems(dto.items);
    const total = orderItems.reduce((sum, item) => sum + item.subtotal, 0);
    const serviceSummary = this.getServiceSummary(orderItems);
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
        line_items: orderItems.map((item) => this.buildWooLineItem(item)),
        meta_data: [
          { key: "controlapp_tipo_pedido", value: "RESIDENTE" },
          { key: "controlapp_residente_id", value: usuario.residente!.id },
          { key: "controlapp_conjunto_id", value: usuario.residente!.conjuntoId },
          ...(dto.idempotencyKey
            ? [{ key: "controlapp_idempotency_key", value: dto.idempotencyKey }]
            : []),
          ...this.buildServiceOrderMeta(orderItems),
        ],
      }),
    });

    const estadoInicial = toOrderStatus(wooOrder.status);
    const pedido = await this.prisma.pedidoApp.create({
      data: {
        tipo: TipoPedidoApp.RESIDENTE,
        estado: estadoInicial,
        estadoWoo: wooOrder.status ?? "pending",
        wooOrderId: String(wooOrder.id),
        usuarioId: usuario.id,
        conjuntoId: usuario.residente!.conjuntoId,
        residenteId: usuario.residente!.id,
        total: new Prisma.Decimal(total),
        pagarAhora: new Prisma.Decimal(serviceSummary.pagarAhora),
        fechaServicio: serviceSummary.first
          ? new Date(`${serviceSummary.first.date}T00:00:00.000Z`)
          : null,
        turnoServicio: serviceSummary.first?.slotLabel ?? null,
        opcionPagoServicio: serviceSummary.first?.payChoice ?? null,
        addonsServicio: serviceSummary.addons ?? Prisma.JsonNull,
        idempotencyKey: dto.idempotencyKey ?? null,
        moneda: wooOrder.currency ?? "COP",
        items: {
          create: orderItems.map((item) => this.buildPedidoItem(item)),
        },
        historialEstados: {
          create: {
            estadoAnterior: null,
            estadoNuevo: estadoInicial,
            cambiadoPorId: usuario.id,
            cambiadoPorRol: Rol.residente,
            motivo: "Pedido creado desde la app",
          },
        },
      },
      include: {
        items: true,
      },
    });
    await this.invalidateServiceAvailability(orderItems);

    return {
      id: pedido.id,
      wooOrderId: pedido.wooOrderId,
      estado: pedido.estado,
      estadoWoo: pedido.estadoWoo,
      total: Number(pedido.total),
      moneda: pedido.moneda,
      pagarAhora: Number(pedido.pagarAhora),
      fechaServicio: pedido.fechaServicio,
      turnoServicio: pedido.turnoServicio,
      opcionPagoServicio: pedido.opcionPagoServicio,
      addonsServicio: pedido.addonsServicio,
      whatsappPhone: String(
        process.env.WOO_WHATSAPP_PHONE ?? process.env.WHATSAPP_PHONE ?? "",
      ).replace(/\D/g, ""),
      pagoUrl: this.buildPayUrl(wooOrder),
      creadoEn: pedido.creadoEn,
      items: pedido.items.map((item) => ({
        id: item.id,
        nombreProducto: item.nombreProducto,
        cantidad: Number(item.cantidad),
        precioUnitario: Number(item.precioUnitario),
        subtotal: Number(item.subtotal),
        pagarAhora: Number(item.pagarAhora),
        fechaServicio: item.fechaServicio,
        turnoServicio: item.turnoServicio,
        opcionPagoServicio: item.opcionPagoServicio,
        addonsServicio: item.addonsServicio,
      })),
    };
  }

  async createConjuntoOrder(userId: string, payload: unknown) {
    const dto = CrearPedidoConjuntoDTO.parse(payload);
    const { usuario, conjunto } = await this.resolveConjuntoForCreate(
      userId,
      dto.conjuntoId,
    );
    const existing = await this.findIdempotentOrder(
      userId,
      TipoPedidoApp.CONJUNTO,
      dto.idempotencyKey,
    );
    if (existing) return existing;
    const orderItems = await this.resolveOrderItems(dto.items, { conjuntoOrder: true });
    const total = orderItems.reduce((sum, item) => sum + item.subtotal, 0);
    const serviceSummary = this.getServiceSummary(orderItems);
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
          company: conjunto.nombre,
          email: conjunto.correo || usuario.correo,
        },
        line_items: orderItems.map((item) => this.buildWooLineItem(item)),
        meta_data: [
          { key: "controlapp_tipo_pedido", value: "CONJUNTO" },
          { key: "controlapp_conjunto_id", value: conjunto.nit },
          ...(dto.idempotencyKey
            ? [{ key: "controlapp_idempotency_key", value: dto.idempotencyKey }]
            : []),
          ...this.buildServiceOrderMeta(orderItems),
        ],
      }),
    });

    const estadoInicial = toOrderStatus(wooOrder.status);
    const pedido = await this.prisma.pedidoApp.create({
      data: {
        tipo: TipoPedidoApp.CONJUNTO,
        estado: estadoInicial,
        estadoWoo: wooOrder.status ?? "pending",
        wooOrderId: String(wooOrder.id),
        usuarioId: usuario.id,
        conjuntoId: conjunto.nit,
        residenteId: null,
        total: new Prisma.Decimal(total),
        pagarAhora: new Prisma.Decimal(serviceSummary.pagarAhora),
        fechaServicio: serviceSummary.first
          ? new Date(`${serviceSummary.first.date}T00:00:00.000Z`)
          : null,
        turnoServicio: serviceSummary.first?.slotLabel ?? null,
        opcionPagoServicio: serviceSummary.first?.payChoice ?? null,
        addonsServicio: serviceSummary.addons ?? Prisma.JsonNull,
        idempotencyKey: dto.idempotencyKey ?? null,
        moneda: wooOrder.currency ?? "COP",
        items: {
          create: orderItems.map((item) => this.buildPedidoItem(item)),
        },
        historialEstados: {
          create: {
            estadoAnterior: null,
            estadoNuevo: estadoInicial,
            cambiadoPorId: usuario.id,
            cambiadoPorRol: usuario.rol,
            motivo: "Pedido operativo creado desde la app",
          },
        },
      },
      include: {
        conjunto: { select: { nombre: true } },
        items: true,
      },
    });
    await this.invalidateServiceAvailability(orderItems);

    return {
      ...this.serializeOrder(pedido),
      pagoUrl: this.buildPayUrl(wooOrder),
    };
  }

  async listConjuntoOrders(userId: string) {
    const conjuntoIds = await this.getAuthorizedConjuntoIds(userId);
    if (conjuntoIds.length === 0) return [];

    const pedidos = await this.prisma.pedidoApp.findMany({
      where: {
        tipo: TipoPedidoApp.CONJUNTO,
        conjuntoId: { in: conjuntoIds },
      },
      include: {
        conjunto: { select: { nombre: true } },
        items: true,
      },
      orderBy: { creadoEn: "desc" },
    });

    return pedidos.map((pedido) => this.serializeOrder(pedido));
  }

  async getConjuntoOrder(userId: string, pedidoId: number) {
    const conjuntoIds = await this.getAuthorizedConjuntoIds(userId);
    const pedido = await this.prisma.pedidoApp.findFirst({
      where: {
        id: pedidoId,
        tipo: TipoPedidoApp.CONJUNTO,
        conjuntoId: { in: conjuntoIds },
      },
      include: {
        conjunto: { select: { nombre: true } },
        items: true,
      },
    });

    if (!pedido) throw makeHttpError(404, "Pedido de conjunto no encontrado");
    return this.serializeOrder(pedido);
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

    return pedidos.map((pedido) => this.serializeOrder(pedido));
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

    return this.serializeOrder(pedido);
  }
}
