import {
  EstadoPedidoInterno,
  Prisma,
  Rol,
  TipoMovimientoInsumo,
  TipoPedidoApp,
  type PrismaClient,
} from "@prisma/client";
import { CambiarEstadoPedidoDTO, MapearPedidoItemDTO, SubirComprobantePagoDTO } from "../model/Commerce";
import {
  CommerceAccessService,
  commerceHttpError,
  type CommerceActor,
} from "./CommerceAccessService";
import { CommercePointsService } from "./CommercePointsService";
import {
  WooCommerceCatalogService,
  insumoDeclaradoCompleto,
  modoEfectivo,
  type WooInsumoConfig,
} from "./WooCommerceCatalogService";
import { buildEvidenciaFileName, uploadEvidenciaToDrive } from "../utils/drive_evidencias";
import { NotificacionService } from "./NotificacionService";
import { buildWooUrl, wooFetch } from "./wooFetch";
import crypto from "crypto";
import fs from "fs";
import { analizarComprobante } from "./ComprobanteOcrService";
import {
  resumenVerificacion,
  type VerificacionComprobante,
} from "../utils/comprobanteParser";

type TransactionClient = Prisma.TransactionClient;

// Estados personalizados de WooCommerce (plugin control-pagos-manuales).
// OCR = el comprobante coincide segun la lectura automatica, sin revisar;
// MANUAL = una persona lo reviso y confirmo (unico que cuenta como pagado).
export const ESTADO_WOO_PAGO_OCR = "pago-ocr";
export const ESTADO_WOO_PAGO_MANUAL = "pago-manual";
export const ESTADO_WOO_EN_PREPARACION = "en-preparacion";
export const ESTADO_WOO_EN_CAMINO = "en-camino";
export const ESTADO_WOO_RECIBIDO = "recibido";
export const ESTADO_WOO_ENTREGADO = "entregado";

// Woo -> app: estados que el equipo aplica desde wp-admin (Estado del pedido)
// y que mueven el pedido en la app. "Recibido" y "Entregado" NO estan a
// proposito: los confirma el cliente en la app (y "Recibido" suma al
// inventario del conjunto), asi que un cambio manual de esos en Woo se ignora.
// "processing"/"completed" siguen valiendo como pago confirmado por si se usan
// los estados nativos de Woo.
const ESTADO_APP_DESDE_WOO: Record<string, EstadoPedidoInterno> = {
  [ESTADO_WOO_PAGO_MANUAL]: EstadoPedidoInterno.PAGADO,
  processing: EstadoPedidoInterno.PAGADO,
  completed: EstadoPedidoInterno.PAGADO,
  [ESTADO_WOO_EN_PREPARACION]: EstadoPedidoInterno.PENDIENTE_ENVIO,
  [ESTADO_WOO_EN_CAMINO]: EstadoPedidoInterno.ENVIADO,
};

// Tramo del flujo que puede recorrer Woo, en orden. Solo se avanza: nunca se
// retrocede un pedido ni se reprocesa un aviso repetido.
const FLUJO_DESDE_WOO: EstadoPedidoInterno[] = [
  EstadoPedidoInterno.PENDIENTE_PAGO,
  EstadoPedidoInterno.PAGADO,
  EstadoPedidoInterno.PENDIENTE_ENVIO,
  EstadoPedidoInterno.ENVIADO,
];

// App -> Woo: estado que se refleja en wp-admin cuando el pedido cambia en la app.
const ESTADO_WOO_DESDE_APP: Partial<Record<EstadoPedidoInterno, string>> = {
  [EstadoPedidoInterno.PAGADO]: ESTADO_WOO_PAGO_MANUAL,
  [EstadoPedidoInterno.PENDIENTE_ENVIO]: ESTADO_WOO_EN_PREPARACION,
  [EstadoPedidoInterno.ENVIADO]: ESTADO_WOO_EN_CAMINO,
  [EstadoPedidoInterno.RECIBIDO]: ESTADO_WOO_RECIBIDO,
  [EstadoPedidoInterno.ENTREGADO]: ESTADO_WOO_ENTREGADO,
  [EstadoPedidoInterno.CANCELADO]: "cancelled",
};

// Subcarpeta de Drive (dentro de la carpeta de cada conjunto) donde quedan los
// comprobantes de pago.
export const CARPETA_DRIVE_COMPROBANTES = "comprobantes-pago";

// Roles internos de Control SAS: llevan el pedido por pago, preparacion y
// envio. Administrador (del conjunto) y residente son quienes compran: solo
// confirman lo que les llega.
const ROLES_INTERNOS = new Set<Rol>([Rol.gerente, Rol.jefe_operaciones]);

const TRANSICIONES: Record<EstadoPedidoInterno, EstadoPedidoInterno[]> = {
  BORRADOR: [EstadoPedidoInterno.PENDIENTE_PAGO, EstadoPedidoInterno.CANCELADO],
  PENDIENTE_PAGO: [EstadoPedidoInterno.PAGADO, EstadoPedidoInterno.CANCELADO],
  PAGADO: [EstadoPedidoInterno.PENDIENTE_ENVIO, EstadoPedidoInterno.CANCELADO],
  PENDIENTE_ENVIO: [EstadoPedidoInterno.ENVIADO, EstadoPedidoInterno.CANCELADO],
  ENVIADO: [EstadoPedidoInterno.RECIBIDO],
  RECIBIDO: [EstadoPedidoInterno.ENTREGADO],
  ENTREGADO: [],
  CANCELADO: [],
};

/**
 * TODO(pasarela-Mono): consultar el estado de pago en WooCommerce/Mono.la antes
 * de permitir PENDIENTE_PAGO -> PAGADO desde un flujo confiable del servidor.
 */
export async function verificarPagoEnWooCommerce(_pedidoId: number): Promise<boolean> {
  return false;
}

/**
 * TODO(pasarela-Mono): validar criptograficamente la firma y la antiguedad del
 * webhook antes de aceptar cualquier cambio de estado de pago.
 */
export async function validarWebhookWooCommerce(
  _payload: unknown,
  _signature: string,
): Promise<boolean> {
  return false;
}

type PedidoCompleto = Prisma.PedidoAppGetPayload<{
  include: {
    conjunto: { select: { nombre: true; empresaId: true } };
    items: { include: { insumo: { select: { id: true; nombre: true; unidad: true } } } };
    historialEstados: {
      include: { cambiadoPor: { select: { nombre: true } } };
    };
    consumosInventario: {
      include: {
        insumo: { select: { id: true; nombre: true; unidad: true } };
        inventario: {
          select: {
            insumos: { select: { insumoId: true; cantidad: true } };
          };
        };
      };
    };
  };
}>;

type PedidoRecepcion = Prisma.PedidoAppGetPayload<{
  include: {
    conjunto: { select: { nombre: true; empresaId: true } };
    items: { include: { insumo: true } };
  };
}>;

type MappedInsumo = { id: number; nombre: string; unidad: string; wooFactorConversion: Prisma.Decimal };

type ItemMapping = {
  item: PedidoRecepcion["items"][number];
  insumo: MappedInsumo | null;
  origen: "MANUAL" | "WOO_PRODUCT_ID" | "SKU" | "AUTO_WOO" | "SIN_MAPEO";
};

// El factor declarado EN WOOCOMMERCE al momento de comprar (item.wooFactorInventario)
// manda sobre el factor manual guardado en el Insumo -asi el catalogo de Woo
// es la fuente de verdad cuando el producto ya lo declara, y el mapeo manual
// en ControlApp sigue funcionando como respaldo para productos que no lo
// declaran (o que se compraron antes de que existiera este campo).
function effectiveFactor(item: { wooFactorInventario: Prisma.Decimal | null }, insumo: MappedInsumo) {
  if (item.wooFactorInventario != null) return Number(item.wooFactorInventario);
  return Number(insumo.wooFactorConversion ?? 1);
}

function marcarDuplicado(
  verificacion: VerificacionComprobante,
  pedidoId: number,
): VerificacionComprobante {
  return {
    ...verificacion,
    veredicto: "DUPLICADO",
    checks: [
      ...verificacion.checks.filter((check) => check.clave !== "duplicado"),
      {
        clave: "duplicado",
        ok: false,
        detalle: `La misma referencia ya se uso en el pedido #${pedidoId}`,
      },
    ],
  };
}

export class CommerceLifecycleService {
  private readonly access: CommerceAccessService;
  private readonly points: CommercePointsService;
  private readonly catalog: WooCommerceCatalogService;
  private readonly notificaciones: NotificacionService;

  constructor(private prisma: PrismaClient) {
    this.access = new CommerceAccessService(prisma);
    this.points = new CommercePointsService(prisma);
    this.catalog = new WooCommerceCatalogService();
    this.notificaciones = new NotificacionService(prisma);
  }

  private getAllowedTransitions(actor: CommerceActor, pedido: PedidoCompleto) {
    let possible = TRANSICIONES[pedido.estado];
    // Con comprobante ya enviado hay dinero real en juego: nadie -ni quien
    // compro, ni administracion- puede cancelar el pedido por su cuenta
    // desde aqui. Revertirlo a esa altura es un caso manual, no un boton.
    if (pedido.comprobanteUrl) {
      possible = possible.filter((estado) => estado !== EstadoPedidoInterno.CANCELADO);
    }
    if (ROLES_INTERNOS.has(actor.rol)) return possible;

    // Quien compra (administrador del conjunto o residente) no confirma pagos
    // ni mueve el pedido a preparacion/envio -eso es interno-. Solo cancela
    // mientras no ha pagado y confirma lo que le llega: "recibido" (que llego
    // completo; en pedidos de conjunto suma al inventario) y "entregado".
    const clienteAllowed: Partial<Record<EstadoPedidoInterno, EstadoPedidoInterno[]>> = {
      BORRADOR: [EstadoPedidoInterno.CANCELADO],
      PENDIENTE_PAGO: [EstadoPedidoInterno.CANCELADO],
      ENVIADO: [EstadoPedidoInterno.RECIBIDO],
      RECIBIDO: [EstadoPedidoInterno.ENTREGADO],
    };
    return possible.filter((estado) => clienteAllowed[pedido.estado]?.includes(estado));
  }

  private async loadPedido(pedidoId: number) {
    const pedido = await this.prisma.pedidoApp.findUnique({
      where: { id: pedidoId },
      include: {
        conjunto: { select: { nombre: true, empresaId: true } },
        items: {
          include: { insumo: { select: { id: true, nombre: true, unidad: true } } },
        },
        historialEstados: {
          include: { cambiadoPor: { select: { nombre: true } } },
          orderBy: { creadoEn: "asc" },
        },
        consumosInventario: {
          include: {
            insumo: { select: { id: true, nombre: true, unidad: true } },
            inventario: {
              select: { insumos: { select: { insumoId: true, cantidad: true } } },
            },
          },
          orderBy: { fecha: "asc" },
        },
      },
    });
    if (!pedido) throw commerceHttpError(404, "Pedido no encontrado");
    return pedido;
  }

  private serializePedido(actor: CommerceActor, pedido: PedidoCompleto) {
    return {
      id: pedido.id,
      tipo: pedido.tipo,
      estado: pedido.estado,
      estadoWoo: pedido.estadoWoo,
      wooOrderId: pedido.wooOrderId,
      usuarioId: pedido.usuarioId,
      conjuntoId: pedido.conjuntoId,
      conjuntoNombre: pedido.conjunto?.nombre ?? null,
      total: Number(pedido.total),
      moneda: pedido.moneda,
      pagarAhora: Number(pedido.pagarAhora),
      fechaServicio: pedido.fechaServicio,
      turnoServicio: pedido.turnoServicio,
      opcionPagoServicio: pedido.opcionPagoServicio,
      addonsServicio: pedido.addonsServicio,
      direccionEntrega: pedido.direccionEntrega,
      metodoPago: pedido.metodoPago,
      comprobanteUrl: pedido.comprobanteUrl,
      comprobanteSubidoEn: pedido.comprobanteSubidoEn,
      // La lectura automatica (OCR) es interna: solo la ve el equipo que revisa
      // pagos. Quien compra -el administrador del conjunto o el residente- no
      // debe saber si el sistema pudo leer su comprobante o no.
      verificacionComprobante: ROLES_INTERNOS.has(actor.rol)
        ? (pedido.comprobanteVerificacion ?? null)
        : null,
      whatsappPhone: String(
        process.env.WOO_WHATSAPP_PHONE ?? process.env.WHATSAPP_PHONE ?? "",
      ).replace(/\D/g, ""),
      creadoEn: pedido.creadoEn,
      actualizadoEn: pedido.actualizadoEn,
      entradaInventarioAplicada: pedido.entradaInventarioAplicada,
      entradaInventarioAplicadaEn: pedido.entradaInventarioAplicadaEn,
      puntosAplicados: pedido.puntosAplicados,
      puntosAplicadosEn: pedido.puntosAplicadosEn,
      descuentoPuntos: Number(pedido.descuentoPuntos),
      transicionesPermitidas: this.getAllowedTransitions(actor, pedido),
      items: pedido.items.map((item) => ({
        id: item.id,
        wooProductId: item.wooProductId,
        nombreProducto: item.nombreProducto,
        sku: item.sku,
        cantidad: Number(item.cantidad),
        cantidadRecibida: item.cantidadRecibida == null ? null : Number(item.cantidadRecibida),
        novedadRecepcion: item.novedadRecepcion ?? null,
        precioUnitario: Number(item.precioUnitario),
        subtotal: Number(item.subtotal),
        pagarAhora: Number(item.pagarAhora),
        fechaServicio: item.fechaServicio,
        turnoServicio: item.turnoServicio,
        opcionPagoServicio: item.opcionPagoServicio,
        addonsServicio: item.addonsServicio,
        insumo: item.insumo,
      })),
      historial: pedido.historialEstados.map((item) => ({
        id: item.id,
        estadoAnterior: item.estadoAnterior,
        estadoNuevo: item.estadoNuevo,
        cambiadoPor: item.cambiadoPor.nombre,
        cambiadoPorRol: item.cambiadoPorRol,
        motivo: item.motivo,
        creadoEn: item.creadoEn,
      })),
      entradasInventario: pedido.consumosInventario.map((consumo) => {
        const stock = consumo.inventario.insumos.find(
          (item) => item.insumoId === consumo.insumoId,
        );
        return {
          insumoId: consumo.insumoId,
          insumoNombre: consumo.insumo.nombre,
          unidad: consumo.insumo.unidad,
          cantidad: Number(consumo.cantidad),
          stockActual: Number(stock?.cantidad ?? 0),
          fecha: consumo.fecha,
        };
      }),
    };
  }

  async getPedido(userId: string, pedidoId: number) {
    const [actor, pedido] = await Promise.all([
      this.access.getActor(userId),
      this.loadPedido(pedidoId),
    ]);
    await this.access.assertPedidoAccess(actor, pedido);
    return this.serializePedido(actor, pedido);
  }

  /**
   * Sin pasarela de pago conectada: quien compro transfiere a mano (Nequi o
   * Bre-B, ver metodoPago) y sube aqui la captura/PDF como comprobante. No
   * marca el pedido como pagado por si sola -eso lo hace un administrador o
   * gerente revisando el comprobante y pasando el pedido a PAGADO (ver el
   * guard en transicionar), no una llamada automatica.
   */
  async subirComprobante(
    userId: string,
    pedidoId: number,
    file: { path: string; mimetype: string; originalname: string },
    payload: unknown,
  ) {
    const dto = SubirComprobantePagoDTO.parse(payload);
    const actor = await this.access.getActor(userId);
    const pedido = await this.loadPedido(pedidoId);
    await this.access.assertPedidoAccess(actor, pedido);

    if (pedido.estado !== EstadoPedidoInterno.PENDIENTE_PAGO) {
      throw commerceHttpError(
        409,
        "Solo se puede adjuntar comprobante mientras el pedido esta pendiente de pago",
      );
    }

    const fecha = new Date();
    const fileName = buildEvidenciaFileName({
      subidoPor: actor.nombre,
      rol: actor.rol,
      fecha,
      originalName: file.originalname,
    });
    // El archivo temporal se borra al terminar la subida; el analisis
    // automatico corre despues, asi que se conserva el contenido en memoria
    // (maximo 25 MB, ver uploadComprobante).
    let contenido: Buffer;
    let hashArchivo: string;
    let otroConMismoArchivo: { id: number } | null;
    let comprobanteUrl: string;
    try {
      contenido = await fs.promises.readFile(file.path);
      hashArchivo = crypto.createHash("sha256").update(contenido).digest("hex");
      otroConMismoArchivo = await this.prisma.pedidoApp.findFirst({
        where: { id: { not: pedidoId }, comprobanteHash: hashArchivo },
        select: { id: true },
      });
      comprobanteUrl = await uploadEvidenciaToDrive({
        filePath: file.path,
        fileName,
        mimeType: file.mimetype,
        // Todo pedido (RESIDENTE o CONJUNTO) queda asociado a un conjunto
        // -el propio o el de quien reside-, asi que siempre hay carpeta
        // destino.
        conjuntoNit: pedido.conjuntoId ?? "sin-conjunto",
        conjuntoNombre: pedido.conjunto?.nombre,
        fecha,
        // Carpeta propia dentro del conjunto (no la de evidencias de tareas)
        // para llevar la trazabilidad de los pagos.
        subcarpeta: CARPETA_DRIVE_COMPROBANTES,
      });
    } finally {
      await fs.promises.unlink(file.path).catch(() => undefined);
    }

    await this.prisma.pedidoApp.update({
      where: { id: pedidoId },
      data: {
        comprobanteUrl,
        comprobanteSubidoEn: fecha,
        comprobanteHash: hashArchivo,
        // Un comprobante nuevo invalida la lectura del anterior.
        comprobanteReferencia: null,
        comprobanteVerificacion: Prisma.DbNull,
        ...(dto.metodoPago ? { metodoPago: dto.metodoPago } : {}),
      },
    });

    const habiaCoincidido =
      (pedido.comprobanteVerificacion as { veredicto?: string } | null)?.veredicto === "COINCIDE";
    if (habiaCoincidido && pedido.wooOrderId) {
      await this.revertirWooConfirmadoOcr(pedido.wooOrderId);
    }

    // La lectura (OCR) tarda unos segundos: no se hace esperar a quien sube el
    // comprobante. Su resultado queda guardado para quien revise el pedido.
    void this.analizarYGuardarComprobante({
      pedidoId,
      hashArchivo,
      contenido,
      mimeType: file.mimetype,
      metodoPago: dto.metodoPago ?? pedido.metodoPago,
      montosEsperados: [
        Number(pedido.pagarAhora),
        Number(pedido.total),
        Number(pedido.total) - Number(pedido.descuentoPuntos ?? 0),
      ],
      creadoEn: pedido.creadoEn,
      wooOrderId: pedido.wooOrderId,
      duplicadoPorArchivo: otroConMismoArchivo?.id ?? null,
    });

    // Para que quien revise el pedido en wp-admin (WooCommerce) vea el
    // comprobante ahi mismo, sin tener que entrar a ControlApp primero.
    if (pedido.wooOrderId) {
      await this.pushWooOrderNote(
        pedido.wooOrderId,
        `Comprobante de pago (${dto.metodoPago ?? pedido.metodoPago ?? "manual"}) subido por ${actor.nombre}: ${comprobanteUrl}`,
      );
    }

    return this.getPedido(userId, pedidoId);
  }

  /**
   * Destinos (celular Nequi / llave Bre-B) del negocio, separados por comas en
   * COMPROBANTE_DESTINO_NEQUI y COMPROBANTE_DESTINO_BREB. Sin configurar, el
   * analisis simplemente no evalua el destinatario.
   */
  private destinosConfigurados(metodoPago: string | null): string[] {
    const lista = (valor: string | undefined) =>
      String(valor ?? "")
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
    const nequi = lista(process.env.COMPROBANTE_DESTINO_NEQUI);
    const breb = lista(process.env.COMPROBANTE_DESTINO_BREB);
    if (metodoPago === "nequi") return nequi;
    if (metodoPago === "bre_b") return breb;
    return [...nequi, ...breb];
  }

  private async analizarYGuardarComprobante(input: {
    pedidoId: number;
    hashArchivo: string;
    contenido: Buffer;
    mimeType: string;
    metodoPago: string | null;
    montosEsperados: number[];
    creadoEn: Date;
    wooOrderId: string | null;
    duplicadoPorArchivo: number | null;
  }) {
    try {
      let verificacion = await analizarComprobante({
        buffer: input.contenido,
        mimeType: input.mimeType,
        contexto: {
          metodoPago: input.metodoPago,
          montosEsperados: input.montosEsperados,
          creadoEn: input.creadoEn,
          destinosConfigurados: this.destinosConfigurados(input.metodoPago),
          duplicadoDe: input.duplicadoPorArchivo
            ? { pedidoId: input.duplicadoPorArchivo, motivo: "archivo" }
            : null,
        },
      });

      // La misma referencia en otro pedido es la señal mas fuerte de reuso.
      if (verificacion.referencia && verificacion.veredicto !== "DUPLICADO") {
        const otro = await this.prisma.pedidoApp.findFirst({
          where: {
            id: { not: input.pedidoId },
            comprobanteReferencia: verificacion.referencia,
          },
          select: { id: true },
        });
        if (otro) {
          verificacion = marcarDuplicado(verificacion, otro.id);
        }
      }

      // Si mientras tanto se subio otro comprobante, esta lectura ya no aplica.
      const guardado = await this.prisma.pedidoApp.updateMany({
        where: { id: input.pedidoId, comprobanteHash: input.hashArchivo },
        data: {
          comprobanteReferencia: verificacion.referencia,
          comprobanteVerificacion: verificacion as unknown as Prisma.InputJsonValue,
        },
      });

      if (guardado.count > 0 && input.wooOrderId) {
        await this.pushWooOrderNote(input.wooOrderId, resumenVerificacion(verificacion));
        if (verificacion.veredicto === "COINCIDE") {
          await this.marcarWooConfirmadoOcr(input.pedidoId, input.wooOrderId);
        }
      }
    } catch (error) {
      // Best-effort: el comprobante ya esta guardado y el revisor puede abrirlo.
      console.error("[comprobante] no se pudo guardar el analisis", {
        pedidoId: input.pedidoId,
        name: error instanceof Error ? error.name : "Error",
      });
    }
  }

  /** Nota interna (no visible al cliente) en el pedido de WooCommerce. */
  private async pushWooOrderNote(wooOrderId: string, note: string) {
    try {
      await wooFetch(
        buildWooUrl("rest", `/orders/${wooOrderId}/notes`),
        { method: "POST", body: JSON.stringify({ note, customer_note: false }) },
        { requireAuth: true, failureMessage: "No se pudo anotar el pedido en la tienda" },
      );
    } catch {
      // Best-effort: si Woo no responde, el comprobante ya quedo guardado en
      // ControlApp -no se bloquea al usuario por esto.
    }
  }

  /**
   * Busca en Woo (REST v3, en vivo) los datos de insumo declarados para este
   * item -el de la variacion si aplica, si no el del producto padre; ver
   * fallback en WooCommerceCatalogService.getProduct- y crea el Insumo de
   * catalogo automaticamente si al menos "unidad" esta declarada. Sin esto,
   * el primer pedido de un producto nuevo siempre exigia mapeo manual.
   */
  private async autoCrearInsumoDesdeWoo(
    client: TransactionClient | PrismaClient,
    empresaId: string,
    item: PedidoRecepcion["items"][number],
  ): Promise<MappedInsumo | null> {
    const wooId = item.wooVariationId ?? item.wooProductId;
    if (!item.wooProductId || !wooId) return null;
    let product;
    try {
      product = await this.catalog.getProduct(item.wooProductId);
    } catch {
      return null; // Tienda no disponible/no configurada: se sigue con mapeo manual.
    }
    const config: WooInsumoConfig = item.wooVariationId
      ? (product.variations.find((v) => v.id === item.wooVariationId)?.insumoConfig ?? product.insumoConfig)
      : product.insumoConfig;
    // No declarado (o incompleto: p. ej. "por empaque" sin contenido) en Woo:
    // sigue siendo mapeo manual, nunca se inventa el contenido.
    if (!insumoDeclaradoCompleto(config)) return null;
    const esEmpaque = modoEfectivo(config) === "empaque";
    const seleccion = { id: true, nombre: true, unidad: true, wooFactorConversion: true } as const;

    // Variaciones de un mismo producto que suman al MISMO insumo (Sanitabs de
    // 30, 60 y 120 pastillas): el insumo se llama como el producto -no como
    // cada variacion- y cada variacion aporta su factor al comprarse.
    const compartido = config.compartido && !esEmpaque && !!item.wooVariationId && !!product.name;
    const nombreInsumo = compartido ? product.name : item.nombreProducto;

    // Si el catalogo ya tiene un insumo con este mismo nombre y unidad pero sin
    // vincular a la tienda (se creo a mano o antes de declararlo en Woo), se
    // reutiliza -crear otro chocaria con la restriccion de unicidad y tumbaria
    // toda la vista previa-. Si ya esta vinculado a OTRO producto de Woo, no se
    // adivina: mapeo manual.
    const existente = await client.insumo.findFirst({
      where: { empresaId, conjuntoId: "", nombre: nombreInsumo, unidad: config.unidad! },
      select: { ...seleccion, wooProductId: true, wooSku: true },
    });
    if (existente) {
      if (compartido) {
        // Ya existe el insumo del producto: esta variacion suma al mismo. No
        // se toca su vinculo con la primera variacion que lo creo.
        const { wooProductId: _vinculo, wooSku: _sku, ...insumo } = existente;
        return insumo;
      }
      if (existente.wooProductId != null && existente.wooProductId !== wooId) return null;
      return client.insumo.update({
        where: { id: existente.id },
        data: {
          wooProductId: wooId,
          ...(existente.wooSku ? {} : { wooSku: item.sku?.trim() || null }),
        },
        select: seleccion,
      });
    }

    try {
      return await client.insumo.create({
        data: {
          nombre: nombreInsumo,
          unidad: config.unidad!,
          categoria: config.categoria ?? "OTROS",
          umbralBajo: config.umbralBajo,
          empresa: { connect: { nit: empresaId } },
          wooProductId: wooId,
          wooSku: item.sku?.trim() || null,
          // Compartido: el factor real es el de cada variacion (viaja en el
          // item al comprar); el del insumo es solo el respaldo, y aqui seria
          // el de la variacion que lo creo, asi que se deja en 1.
          wooFactorConversion: compartido ? 1 : (config.factorConversion ?? 1),
          // Por empaques: el inventario se cuenta en empaques ("tarro") y
          // muestra el total real (4 tarros de 1,8 L = 7,2 L).
          contenidoPorUnidad: esEmpaque ? config.contenido : null,
          unidadContenido: esEmpaque ? config.unidadContenido : null,
        },
        select: seleccion,
      });
    } catch (error) {
      // Carrera con otro proceso que creo el mismo insumo justo ahora: mapeo manual.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") return null;
      throw error;
    }
  }

  private async resolveMappings(
    client: TransactionClient | PrismaClient,
    pedido: PedidoRecepcion,
    // true solo desde previewRecepcion (fuera de transaccion): permite crear
    // el insumo automaticamente si Woo lo declara, con una llamada HTTP a la
    // tienda. applyInventory (dentro de la transaccion de inventario) nunca
    // la activa, para no hacer I/O de red mientras hay una transaccion de
    // DB abierta -si algo quedo sin mapear ahi, se pide volver a la vista
    // previa primero (que ya lo habria creado).
    allowAutoCreate = false,
  ): Promise<ItemMapping[]> {
    const empresaId = pedido.conjunto?.empresaId;
    if (!empresaId) {
      return pedido.items.map((item) => ({ item, insumo: null, origen: "SIN_MAPEO" }));
    }

    const mappings: ItemMapping[] = [];
    for (const item of pedido.items) {
      if (item.insumo && item.insumo.empresaId === empresaId) {
        mappings.push({ item, insumo: item.insumo, origen: "MANUAL" });
        continue;
      }
      // Si el item es una variacion de un producto variable (ej. "Sanitabs
      // x60" vs "x120"), su identidad Woo real para efectos de mapeo/factor
      // de conversion es la variacion, no el producto padre -cada variacion
      // puede traer una cantidad distinta y por eso necesita su propio
      // insumo/factor. wooVariationId es un id unico en todo el sitio, igual
      // que wooProductId, asi que no hace falta un campo nuevo en Insumo.
      const wooId = item.wooVariationId ?? item.wooProductId;
      if (wooId) {
        const byProduct = await client.insumo.findFirst({
          where: { empresaId, wooProductId: wooId },
          select: { id: true, nombre: true, unidad: true, wooFactorConversion: true },
        });
        if (byProduct) {
          mappings.push({ item, insumo: byProduct, origen: "WOO_PRODUCT_ID" });
          continue;
        }
      }
      if (item.sku?.trim()) {
        const bySku = await client.insumo.findFirst({
          where: {
            empresaId,
            wooSku: { equals: item.sku.trim(), mode: "insensitive" },
          },
          select: { id: true, nombre: true, unidad: true, wooFactorConversion: true },
        });
        if (bySku) {
          mappings.push({ item, insumo: bySku, origen: "SKU" });
          continue;
        }
      }
      if (allowAutoCreate) {
        const creado = await this.autoCrearInsumoDesdeWoo(client, empresaId, item);
        if (creado) {
          mappings.push({ item, insumo: creado, origen: "AUTO_WOO" });
          continue;
        }
      }
      mappings.push({ item, insumo: null, origen: "SIN_MAPEO" });
    }
    return mappings;
  }

  private async loadPedidoRecepcion(client: TransactionClient | PrismaClient, pedidoId: number) {
    return client.pedidoApp.findUnique({
      where: { id: pedidoId },
      include: { conjunto: { select: { nombre: true, empresaId: true } }, items: { include: { insumo: true } } },
    });
  }

  async previewRecepcion(userId: string, pedidoId: number) {
    const actor = await this.access.getActor(userId);
    if (!this.access.esRolOperativo(actor)) {
      throw commerceHttpError(403, "Solo administracion u operaciones pueden recibir inventario");
    }
    const pedido = await this.loadPedidoRecepcion(this.prisma, pedidoId);
    if (!pedido || pedido.tipo !== TipoPedidoApp.CONJUNTO || !pedido.conjuntoId) {
      throw commerceHttpError(404, "Pedido operativo no encontrado");
    }
    await this.access.assertConjuntoAccess(actor, pedido.conjuntoId);

    const mappings = await this.resolveMappings(this.prisma, pedido, true);
    // Configurar o corregir insumos es del equipo de Control SAS: quien compra
    // ve el detalle fijo -viene de WooCommerce- y solo reporta lo que llego.
    const puedeMapear = ROLES_INTERNOS.has(actor.rol);
    const insumosDisponiblesRaw = pedido.conjunto?.empresaId
      ? await this.prisma.insumo.findMany({
          where: { empresaId: pedido.conjunto.empresaId },
          select: {
            id: true,
            nombre: true,
            unidad: true,
            wooSku: true,
            wooProductId: true,
            wooFactorConversion: true,
          },
          orderBy: { nombre: "asc" },
        })
      : [];
    const insumosDisponibles = insumosDisponiblesRaw.map((insumo) => ({
      ...insumo,
      wooFactorConversion: Number(insumo.wooFactorConversion),
    }));
    return {
      pedidoId,
      puedeAplicar:
        !pedido.entradaInventarioAplicada &&
        pedido.estado === EstadoPedidoInterno.ENVIADO &&
        mappings.every((mapping) => mapping.insumo !== null),
      yaAplicada: pedido.entradaInventarioAplicada,
      puedeMapear,
      mensaje: pedido.entradaInventarioAplicada
        ? "La entrada de este pedido ya fue aplicada"
        : mappings.some((mapping) => !mapping.insumo)
          ? puedeMapear
            ? "Mapea todos los productos antes de confirmar la recepcion"
            : "Hay productos de este pedido que aun no estan configurados como insumo. Avisa a Control SAS para que los configure y podras confirmar la recepcion."
          : "Revisa que llego todo. Solo lo que marques como recibido se suma al inventario del conjunto.",
      items: mappings.map((mapping) => {
        const factor = mapping.insumo ? effectiveFactor(mapping.item, mapping.insumo) : 1;
        return {
          itemId: mapping.item.id,
          producto: mapping.item.nombreProducto,
          sku: mapping.item.sku,
          cantidad: Number(mapping.item.cantidad),
          insumo: mapping.insumo
            ? { ...mapping.insumo, wooFactorConversion: factor }
            : null,
          // Cantidad que realmente entrara al inventario (cantidad comprada x
          // factor de conversion: el declarado en Woo al comprar, o si no
          // hay, el del mapeo manual del insumo).
          cantidadInventario: Number(mapping.item.cantidad) * factor,
          factorDesdeWoo: mapping.item.wooFactorInventario != null,
          origenMapeo: mapping.origen,
        };
      }),
      insumosDisponibles,
    };
  }

  async mapearItem(userId: string, pedidoId: number, itemId: number, payload: unknown) {
    const { insumoId, factorConversion } = MapearPedidoItemDTO.parse(payload);
    const actor = await this.access.getActor(userId);
    if (!ROLES_INTERNOS.has(actor.rol)) {
      throw commerceHttpError(403, "Solo el equipo de Control SAS puede configurar los insumos de un producto");
    }
    const initial = await this.loadPedidoRecepcion(this.prisma, pedidoId);
    if (!initial || initial.tipo !== TipoPedidoApp.CONJUNTO || !initial.conjuntoId) {
      throw commerceHttpError(404, "Pedido operativo no encontrado");
    }
    await this.access.assertConjuntoAccess(actor, initial.conjuntoId);

    await this.prisma.$transaction(async (tx) => {
      const pedido = await this.loadPedidoRecepcion(tx, pedidoId);
      if (!pedido || pedido.tipo !== TipoPedidoApp.CONJUNTO || !pedido.conjuntoId) {
        throw commerceHttpError(404, "Pedido operativo no encontrado");
      }
      if (pedido.entradaInventarioAplicada) {
        throw commerceHttpError(409, "El inventario de este pedido ya fue aplicado");
      }
      const item = pedido.items.find((value) => value.id === itemId);
      if (!item) throw commerceHttpError(404, "El item no pertenece al pedido");
      const empresaId = pedido.conjunto?.empresaId;
      if (!empresaId) {
        throw commerceHttpError(409, "El conjunto no tiene una empresa para resolver insumos");
      }
      const insumo = await tx.insumo.findFirst({ where: { id: insumoId, empresaId } });
      if (!insumo) throw commerceHttpError(404, "El insumo no pertenece a la empresa del conjunto");

      // Igual que en resolveMappings: si el item es una variacion, su
      // identidad Woo para el mapeo es la variacion, no el producto padre.
      const wooId = item.wooVariationId ?? item.wooProductId;
      const identifiers: Prisma.InsumoWhereInput[] = [
        ...(wooId ? [{ wooProductId: wooId }] : []),
        ...(item.sku?.trim() ? [{ wooSku: item.sku.trim() }] : []),
      ];
      const conflict = identifiers.length
        ? await tx.insumo.findFirst({
            where: {
              empresaId,
              id: { not: insumoId },
              OR: identifiers,
            },
            select: { nombre: true },
          })
        : null;
      if (conflict) {
        throw commerceHttpError(
          409,
          `El producto ya esta asociado al insumo ${conflict.nombre}. Corrige ese mapeo primero`,
        );
      }

      await tx.insumo.update({
        where: { id: insumoId },
        data: {
          ...(wooId && !insumo.wooProductId ? { wooProductId: wooId } : {}),
          ...(item.sku?.trim() && !insumo.wooSku ? { wooSku: item.sku.trim() } : {}),
          ...(factorConversion != null ? { wooFactorConversion: new Prisma.Decimal(factorConversion) } : {}),
        },
      });
      await tx.pedidoAppItem.update({ where: { id: itemId }, data: { insumoId } });
    });

    return this.previewRecepcion(userId, pedidoId);
  }

  private async applyInventory(
    tx: TransactionClient,
    pedido: PedidoRecepcion,
    registradoPorId: string,
    // Lo que llego de cada producto (itemId -> cantidad). Sin dato, se da por
    // recibido todo lo pedido.
    recibidas?: Map<number, { recibida: Prisma.Decimal }>,
  ) {
    if (pedido.entradaInventarioAplicada) return;
    if (!pedido.conjuntoId) throw commerceHttpError(409, "El pedido no tiene conjunto asociado");

    const mappings = await this.resolveMappings(tx, pedido);
    const missing = mappings.filter((mapping) => !mapping.insumo);
    if (missing.length) {
      throw commerceHttpError(
        409,
        `Falta mapear ${missing.map((mapping) => mapping.item.nombreProducto).join(", ")}`,
      );
    }

    const grouped = new Map<number, { cantidad: Prisma.Decimal; nombre: string }>();
    for (const mapping of mappings) {
      const insumo = mapping.insumo!;
      const current = grouped.get(insumo.id);
      // La cantidad comprada esta en "unidades de la tienda" (ej: garrafas);
      // se convierte a "unidades de inventario" (ej: litros) con el factor
      // definido en el mapeo, para no descuadrar el stock del conjunto.
      const cantidadRecibida = recibidas?.get(mapping.item.id)?.recibida ?? new Prisma.Decimal(mapping.item.cantidad);
      const cantidadInventario = new Prisma.Decimal(cantidadRecibida).times(
        effectiveFactor(mapping.item, insumo),
      );
      grouped.set(insumo.id, {
        nombre: insumo.nombre,
        cantidad: new Prisma.Decimal(current?.cantidad ?? 0).plus(cantidadInventario),
      });
    }

    // Lo que no llego (cantidad 0) no genera movimiento de inventario.
    for (const [insumoId, dato] of [...grouped]) {
      if (dato.cantidad.isZero()) grouped.delete(insumoId);
    }

    const claim = await tx.pedidoApp.updateMany({
      where: { id: pedido.id, entradaInventarioAplicada: false },
      data: { entradaInventarioAplicada: true, entradaInventarioAplicadaEn: new Date() },
    });
    if (claim.count === 0) return;

    const inventario = await tx.inventario.upsert({
      where: { conjuntoId: pedido.conjuntoId },
      create: { conjuntoId: pedido.conjuntoId },
      update: {},
    });
    for (const [insumoId, item] of grouped) {
      await tx.inventarioInsumo.upsert({
        where: { inventarioId_insumoId: { inventarioId: inventario.id, insumoId } },
        create: { inventarioId: inventario.id, insumoId, cantidad: item.cantidad },
        update: { cantidad: { increment: item.cantidad } },
      });
      await tx.consumoInsumo.upsert({
        where: {
          pedidoAppId_insumoId_tipo: {
            pedidoAppId: pedido.id,
            insumoId,
            tipo: TipoMovimientoInsumo.ENTRADA,
          },
        },
        create: {
          inventarioId: inventario.id,
          insumoId,
          pedidoAppId: pedido.id,
          tipo: TipoMovimientoInsumo.ENTRADA,
          cantidad: item.cantidad,
          fecha: new Date(),
          observacion: `Entrada por recepcion del pedido operativo #${pedido.id}`,
          registradoPorId,
        },
        update: {},
      });
    }
  }

  async transicionar(userId: string, pedidoId: number, payload: unknown) {
    const dto = CambiarEstadoPedidoDTO.parse(payload);
    const actor = await this.access.getActor(userId);
    const initial = await this.loadPedido(pedidoId);
    await this.access.assertPedidoAccess(actor, initial);

    if (initial.estado === dto.estadoDestino) {
      return this.serializePedido(actor, initial);
    }
    const allowed = this.getAllowedTransitions(actor, initial);
    if (!allowed.includes(dto.estadoDestino)) {
      throw commerceHttpError(
        409,
        `No puedes pasar el pedido de ${initial.estado} a ${dto.estadoDestino}`,
      );
    }

    // Sin pasarela conectada, "pagado" solo lo confirma una persona que ya
    // revisó el comprobante subido -nunca automatico ni sin evidencia.
    if (dto.estadoDestino === EstadoPedidoInterno.PAGADO && !initial.comprobanteUrl) {
      throw commerceHttpError(
        409,
        "Debes adjuntar el comprobante de pago antes de confirmar el pago",
      );
    }

    // Confirmar la recepcion cierra el pedido: pasa por "recibido" (se suma al
    // inventario y queda verificada la entrega) y termina "entregado", sin
    // pedirle al cliente un segundo paso. Los dos quedan en el historial.
    const pasos: EstadoPedidoInterno[] =
      dto.estadoDestino === EstadoPedidoInterno.RECIBIDO
        ? [EstadoPedidoInterno.RECIBIDO, EstadoPedidoInterno.ENTREGADO]
        : [dto.estadoDestino];
    const estadoFinal = pasos[pasos.length - 1];

    // Lo que llego de cada producto (solo al recibir un pedido de conjunto).
    const recepcion =
      dto.estadoDestino === EstadoPedidoInterno.RECIBIDO && initial.tipo === TipoPedidoApp.CONJUNTO
        ? this.normalizarRecepcion(initial.items, dto.recepcion)
        : null;

    await this.prisma.$transaction(async (tx) => {
      const pedido = await this.loadPedidoRecepcion(tx, pedidoId);
      if (!pedido) throw commerceHttpError(404, "Pedido no encontrado");
      if (pedido.estado !== initial.estado) {
        throw commerceHttpError(409, "El pedido cambio de estado. Actualiza el detalle e intenta de nuevo");
      }

      if (
        dto.estadoDestino === EstadoPedidoInterno.RECIBIDO &&
        pedido.tipo === TipoPedidoApp.CONJUNTO
      ) {
        await this.applyInventory(tx, pedido, userId, recepcion?.recibidas);
        // Queda registrado lo que llego de cada producto (y la nota, si hubo).
        for (const [itemId, dato] of recepcion?.recibidas ?? []) {
          await tx.pedidoAppItem.update({
            where: { id: itemId },
            data: { cantidadRecibida: dato.recibida, novedadRecepcion: dato.nota },
          });
        }
      }

      let anterior = initial.estado;
      for (const paso of pasos) {
        const updated = await tx.pedidoApp.updateMany({
          where: { id: pedidoId, estado: anterior },
          data: { estado: paso },
        });
        if (updated.count === 0) {
          throw commerceHttpError(409, "El pedido cambio de estado. Actualiza e intenta de nuevo");
        }
        await tx.pedidoAppEstadoHistorico.create({
          data: {
            pedidoId,
            estadoAnterior: anterior,
            estadoNuevo: paso,
            cambiadoPorId: actor.id,
            cambiadoPorRol: actor.rol,
            motivo:
              paso === dto.estadoDestino
                ? dto.motivo ||
                  (recepcion?.novedades.length
                    ? `Recepción con novedades: ${recepcion.novedades.join("; ")}`.slice(0, 480)
                    : null)
                : "Entregado automáticamente al confirmar la recepción",
          },
        });

        if (paso === EstadoPedidoInterno.ENTREGADO) {
          await this.points.applyAccumulation(tx, {
            id: pedido.id,
            usuarioId: pedido.usuarioId,
            conjuntoId: pedido.conjuntoId,
            tipo: pedido.tipo,
            estado: paso,
            total: pedido.total,
            puntosAplicados: pedido.puntosAplicados,
            // Solo cuenta como entrega verificada si antes se confirmo la recepcion.
            entregaVerificada: anterior === EstadoPedidoInterno.RECIBIDO,
          });
        }
        anterior = paso;
      }
    });

    await this.notificarAvance(initial.usuarioId, pedidoId, estadoFinal);
    if (recepcion?.novedades.length) {
      await this.reportarNovedadRecepcion(initial, actor.nombre, recepcion.novedades);
    }

    // Que wp-admin refleje el mismo estado que ve el cliente en la app (para
    // saber, desde WordPress, que el pedido ya llego y quedo entregado).
    if (initial.wooOrderId) {
      await this.reflejarEstadoEnWoo(initial.wooOrderId, estadoFinal);
      if (dto.estadoDestino === EstadoPedidoInterno.RECIBIDO && !recepcion?.novedades.length) {
        await this.pushWooOrderNote(
          initial.wooOrderId,
          `Recepción confirmada por ${actor.nombre}: el pedido llegó completo y quedó entregado.`,
        );
      }
    }

    return this.getPedido(userId, pedidoId);
  }

  /** Guarda el estado que tiene el pedido en Woo, sin cambiar el estado del pedido en la app. */
  async registrarEstadoWoo(wooOrderId: string, wooStatus: string) {
    await this.prisma.pedidoApp.updateMany({
      where: { wooOrderId, estadoWoo: { not: wooStatus } },
      data: { estadoWoo: wooStatus },
    });
  }

  private async estadoWooActual(wooOrderId: string): Promise<string | null> {
    const order = await wooFetch<{ status?: string }>(
      buildWooUrl("rest", `/orders/${wooOrderId}`, { _fields: "status" }),
      {},
      { requireAuth: true, timeoutMs: 5_000 },
    );
    return order.status ?? null;
  }

  private async cambiarEstadoWoo(wooOrderId: string, status: string) {
    await wooFetch(
      buildWooUrl("rest", `/orders/${wooOrderId}`),
      { method: "PUT", body: JSON.stringify({ status }) },
      { requireAuth: true, timeoutMs: 8_000 },
    );
  }

  /**
   * "Confirmado - OCR" en WooCommerce: solo si el pedido sigue esperando pago
   * en ambos lados (nunca pisa un pedido que alguien ya confirmo o cancelo).
   * Best-effort: si la tienda no tiene el plugin de estados, Woo rechaza el
   * estado y simplemente queda la nota con el resultado.
   */
  private async marcarWooConfirmadoOcr(pedidoId: number, wooOrderId: string) {
    try {
      const pedido = await this.prisma.pedidoApp.findUnique({
        where: { id: pedidoId },
        select: { estado: true },
      });
      if (pedido?.estado !== EstadoPedidoInterno.PENDIENTE_PAGO) return;

      const actual = await this.estadoWooActual(wooOrderId);
      if (actual !== "pending" && actual !== "on-hold") return;

      await this.cambiarEstadoWoo(wooOrderId, ESTADO_WOO_PAGO_OCR);
    } catch {
      // Best-effort.
    }
  }

  /**
   * Si el comprobante anterior habia dejado el pedido en "Confirmado - OCR" y
   * llega uno nuevo, esa lectura ya no vale: vuelve a "Pago pendiente" hasta
   * que se analice el nuevo.
   */
  private async revertirWooConfirmadoOcr(wooOrderId: string) {
    try {
      const actual = await this.estadoWooActual(wooOrderId);
      if (actual === ESTADO_WOO_PAGO_OCR) await this.cambiarEstadoWoo(wooOrderId, "pending");
    } catch {
      // Best-effort.
    }
  }

  /**
   * Lo que el cliente reporta al confirmar la recepcion. Todo producto que no
   * se reporte se da por recibido completo; nunca puede llegar mas de lo
   * pedido. Devuelve lo recibido por producto y el resumen de novedades
   * (lo que llego incompleto o no llego).
   */
  private normalizarRecepcion(
    items: Array<{ id: number; cantidad: Prisma.Decimal; nombreProducto: string }>,
    reportes: Array<{ itemId: number; cantidadRecibida: number; nota?: string }> | undefined,
  ) {
    const porItem = new Map((reportes ?? []).map((reporte) => [reporte.itemId, reporte]));
    for (const itemId of porItem.keys()) {
      if (!items.some((item) => item.id === itemId)) {
        throw commerceHttpError(400, "Uno de los productos reportados no pertenece a este pedido");
      }
    }

    const recibidas = new Map<number, { recibida: Prisma.Decimal; nota: string | null }>();
    const novedades: string[] = [];
    for (const item of items) {
      const reporte = porItem.get(item.id);
      const pedida = new Prisma.Decimal(item.cantidad);
      const recibida = reporte ? new Prisma.Decimal(reporte.cantidadRecibida) : pedida;
      if (recibida.gt(pedida)) {
        throw commerceHttpError(400, `No puedes recibir mas de lo pedido de ${item.nombreProducto}`);
      }
      const nota = reporte?.nota?.trim() || null;
      recibidas.set(item.id, { recibida, nota });
      if (recibida.lt(pedida)) {
        novedades.push(
          `${item.nombreProducto}: llegaron ${recibida.toString()} de ${pedida.toString()}${nota ? ` (${nota})` : ""}`,
        );
      }
    }
    return { recibidas, novedades };
  }

  /**
   * Avisa al equipo de Control SAS (gerentes y jefes de operaciones de la
   * empresa del conjunto) que algo no llego completo, y lo deja anotado en el
   * pedido de WooCommerce. Best-effort: la recepcion ya quedo registrada.
   */
  private async reportarNovedadRecepcion(
    pedido: { id: number; wooOrderId: string | null; conjunto: { nombre: string; empresaId: string | null } | null },
    reportadoPor: string,
    novedades: string[],
  ) {
    try {
      const empresaId = pedido.conjunto?.empresaId;
      if (empresaId) {
        const [gerentes, jefes] = await Promise.all([
          this.prisma.gerente.findMany({ where: { empresaId }, select: { id: true } }),
          this.prisma.jefeOperaciones.findMany({ where: { empresaId }, select: { id: true } }),
        ]);
        await this.notificaciones.crearParaUsuarios({
          usuarioIds: [...gerentes, ...jefes].map((persona) => persona.id),
          tipo: "pedido_novedad_recepcion",
          titulo: `Novedad en la recepción del pedido #${pedido.id}`,
          mensaje: `${pedido.conjunto?.nombre ?? "Un conjunto"} reportó que no llegó completo: ${novedades.join("; ")}`.slice(0, 480),
          referenciaTipo: "PedidoApp",
          referenciaId: pedido.id,
        });
      }
      if (pedido.wooOrderId) {
        await this.pushWooOrderNote(
          pedido.wooOrderId,
          `Recepción con novedades reportada por ${reportadoPor}: ${novedades.join("; ")}`,
        );
      }
    } catch (error) {
      console.error("[recepcion] no se pudo avisar la novedad", {
        pedidoId: pedido.id,
        name: error instanceof Error ? error.name : "Error",
      });
    }
  }

  /**
   * Aviso al cliente (campanita) cuando el pedido avanza. Lo comparten los
   * cambios hechos en la app y los que llegan por el webhook de WooCommerce,
   * para que el cliente siempre reciba lo mismo sin importar donde se cambio.
   */
  private async notificarAvance(usuarioId: string, pedidoId: number, estado: EstadoPedidoInterno) {
    const aviso: Partial<Record<EstadoPedidoInterno, { tipo: string; titulo: string; mensaje: string }>> = {
      [EstadoPedidoInterno.PAGADO]: {
        tipo: "pedido_pagado",
        titulo: "Tu pago fue confirmado",
        mensaje: `El pedido #${pedidoId} ya quedó marcado como pagado.`,
      },
      [EstadoPedidoInterno.PENDIENTE_ENVIO]: {
        tipo: "pedido_preparacion",
        titulo: "Estamos preparando tu pedido",
        mensaje: `El pedido #${pedidoId} ya está en preparación.`,
      },
      [EstadoPedidoInterno.ENVIADO]: {
        tipo: "pedido_enviado",
        titulo: "Tu pedido va en camino",
        mensaje: `El pedido #${pedidoId} va en camino. Cuando llegue, confirma que lo recibiste completo.`,
      },
    };
    const datos = aviso[estado];
    if (!datos) return;
    await this.notificaciones.crearParaUsuarios({
      usuarioIds: [usuarioId],
      ...datos,
      referenciaTipo: "PedidoApp",
      referenciaId: pedidoId,
    });
  }

  /** Best-effort: si Woo no responde o no tiene el plugin de estados, el pedido en la app ya cambio. */
  private async reflejarEstadoEnWoo(wooOrderId: string, estado: EstadoPedidoInterno) {
    const estadoWoo = ESTADO_WOO_DESDE_APP[estado];
    if (!estadoWoo) return;
    try {
      await this.cambiarEstadoWoo(wooOrderId, estadoWoo);
    } catch {
      // Best-effort.
    }
  }

  /**
   * Aplica en la app el estado que el equipo puso en WooCommerce (webhook).
   *
   * Solo avanza -nunca retrocede ni repite-, por lo que es idempotente ante
   * los reintentos de entrega del webhook y ante el "eco" del propio backend
   * cuando el cambio nacio en la app (ver reflejarEstadoEnWoo). Si el equipo
   * salta pasos (p. ej. de pago pendiente directo a "En camino") se aplican
   * los intermedios en orden, cada uno con su historial y su aviso.
   *
   * Contraparte del guard de transicionar(): esta via SI puede confirmar el
   * pago sin comprobante en ControlApp, porque quien cambia el estado en
   * wp-admin ya verifico el pago (en el banco, en Woo, etc.).
   *
   * "Recibido" y "Entregado" nunca se aplican desde aqui: los confirma el
   * cliente en la app. Cualquier otro estado solo se guarda en estadoWoo.
   */
  async aplicarEstadoDesdeWoo(wooOrderId: string, wooStatus: string) {
    const pedido = await this.prisma.pedidoApp.findUnique({
      where: { wooOrderId },
      select: { id: true, estado: true, usuarioId: true, estadoWoo: true },
    });
    // Puede ser un pedido de otro ambiente o que no nacio en la app.
    if (!pedido) return;

    const destino = ESTADO_APP_DESDE_WOO[wooStatus];
    const actual = FLUJO_DESDE_WOO.indexOf(pedido.estado);
    const meta = destino ? FLUJO_DESDE_WOO.indexOf(destino) : -1;

    if (!destino || actual < 0 || meta <= actual) {
      if (pedido.estadoWoo !== wooStatus) await this.registrarEstadoWoo(wooOrderId, wooStatus);
      return;
    }

    const motivoDe = (paso: EstadoPedidoInterno) => {
      if (paso === EstadoPedidoInterno.PAGADO) {
        return wooStatus === ESTADO_WOO_PAGO_MANUAL
          ? "Pago revisado y confirmado manualmente en WooCommerce (Confirmado - manual)"
          : paso === destino
            ? "Pago confirmado desde WooCommerce (webhook de la tienda)"
            : "Pago dado por confirmado al avanzar el pedido en WooCommerce";
      }
      if (paso === EstadoPedidoInterno.PENDIENTE_ENVIO) {
        return "Pedido pasado a En preparación en WooCommerce";
      }
      return "Pedido marcado En camino en WooCommerce";
    };

    const pasos = FLUJO_DESDE_WOO.slice(actual + 1, meta + 1);
    const aplicados = await this.prisma.$transaction(async (tx) => {
      const hechos: EstadoPedidoInterno[] = [];
      let anterior = pedido.estado;
      for (const paso of pasos) {
        // Claim atomico: si otra entrega del webhook (o alguien en la app) ya
        // movio el pedido, se corta aqui sin duplicar historial ni avisos.
        const claim = await tx.pedidoApp.updateMany({
          where: { id: pedido.id, estado: anterior },
          data: { estado: paso, ...(paso === destino ? { estadoWoo: wooStatus } : {}) },
        });
        if (claim.count === 0) break;
        await tx.pedidoAppEstadoHistorico.create({
          data: {
            pedidoId: pedido.id,
            estadoAnterior: anterior,
            estadoNuevo: paso,
            // Sin actor humano en un webhook; se referencia al dueño del
            // pedido y se deja explicito en cambiadoPorRol/motivo que fue
            // WooCommerce, no la propia persona, quien lo cambio.
            cambiadoPorId: pedido.usuarioId,
            cambiadoPorRol: "woocommerce",
            motivo: motivoDe(paso),
          },
        });
        hechos.push(paso);
        anterior = paso;
      }
      return hechos;
    });

    for (const paso of aplicados) {
      await this.notificarAvance(pedido.usuarioId, pedido.id, paso);
    }
  }
}
