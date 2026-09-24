import { z } from "zod";

const SeleccionServicioDTO = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "La fecha del servicio debe usar YYYY-MM-DD"),
  slot: z.string().trim().regex(/^[a-z0-9_-]+$/i, "El turno no es valido").optional(),
  payChoice: z.enum(["deposit", "full"]),
  addons: z.record(z.string().min(1), z.array(z.coerce.number().int().nonnegative()).max(30)),
});

export const PedidoCommerceItemDTO = z.object({
  productId: z.coerce.number().int().positive(),
  quantity: z.coerce.number().int().positive(),
  variationId: z.coerce.number().int().positive().optional(),
  service: SeleccionServicioDTO.optional(),
});

const IdempotencyKeyDTO = z
  .string()
  .trim()
  .min(8)
  .max(100)
  .regex(/^[A-Za-z0-9._:-]+$/, "La clave de idempotencia no es valida")
  .optional();

// Sin pasarela de pago conectada todavia: el comprador transfiere a mano y
// declara con que metodo va a pagar para que el checkout le muestre el QR
// correspondiente. El comprobante se sube despues, ya con el pedido creado
// (ver POST /commerce/pedidos/:id/comprobante).
export const MetodoPagoManualDTO = z.enum(["nequi", "bre_b"]);

export const CrearPedidoResidenteDTO = z.object({
  items: z.array(PedidoCommerceItemDTO).min(1, "Debes agregar al menos un producto al carrito"),
  direccionEntrega: z.string().trim().min(5, "Indica la direccion de entrega").max(300),
  metodoPago: MetodoPagoManualDTO,
  notas: z.string().trim().max(500).optional(),
  idempotencyKey: IdempotencyKeyDTO,
});

export const CrearPedidoConjuntoDTO = z.object({
  conjuntoId: z.string().trim().min(1, "Debes seleccionar un conjunto").optional(),
  items: z.array(PedidoCommerceItemDTO).min(1, "Debes agregar al menos un insumo al carrito"),
  direccionEntrega: z.string().trim().min(5, "Indica la direccion de entrega").max(300),
  metodoPago: MetodoPagoManualDTO,
  notas: z.string().trim().max(500).optional(),
  idempotencyKey: IdempotencyKeyDTO,
});

export const SubirComprobantePagoDTO = z.object({
  metodoPago: MetodoPagoManualDTO.optional(),
});

export const PedidoDetalleParamDTO = z.object({
  pedidoId: z.coerce.number().int().positive(),
});

export const PedidoItemParamDTO = PedidoDetalleParamDTO.extend({
  itemId: z.coerce.number().int().positive(),
});

export const CambiarEstadoPedidoDTO = z.object({
  estadoDestino: z.enum([
    "BORRADOR",
    "PENDIENTE_PAGO",
    "PAGADO",
    "PENDIENTE_ENVIO",
    "ENVIADO",
    "RECIBIDO",
    "ENTREGADO",
    "CANCELADO",
  ]),
  motivo: z.string().trim().max(500).optional(),
  // Solo al pasar un pedido de conjunto a RECIBIDO: lo que llego de cada
  // producto. Lo que no se reporte se da por recibido completo.
  recepcion: z
    .array(
      z.object({
        itemId: z.coerce.number().int().positive(),
        cantidadRecibida: z.coerce.number().min(0).max(1_000_000),
        nota: z.string().trim().max(300).optional(),
      }),
    )
    .max(200)
    .optional(),
});

export const MapearPedidoItemDTO = z.object({
  insumoId: z.coerce.number().int().positive(),
  // Cuantas unidades de inventario trae CADA unidad comprada en la tienda
  // (ej: insumo en litros, producto Woo es una garrafa de 3L => 3).
  factorConversion: z.coerce.number().positive().max(100000).optional(),
});

export const PuntosContextoDTO = z.object({
  conjuntoId: z.string().trim().min(1).optional(),
});

const BeneficioPuntosDTO = z.object({
  id: z.coerce.number().int().positive().optional(),
  nombre: z.string().trim().min(2).max(120),
  descripcion: z.string().trim().max(500).optional(),
  puntosCosto: z.coerce.number().int().positive(),
  valorDescuento: z.coerce.number().min(0),
  activo: z.boolean().default(true),
});

export const ConfigurarPuntosDTO = z.object({
  conjuntoId: z.string().trim().min(1),
  activo: z.boolean(),
  montoPorPuntoResidente: z.coerce.number().positive(),
  montoPorPuntoConjunto: z.coerce.number().positive(),
  minimoRedencionPuntos: z.coerce.number().int().nonnegative(),
  beneficios: z.array(BeneficioPuntosDTO).max(30),
});

export const RedimirBeneficioDTO = z.object({
  conjuntoId: z.string().trim().min(1).optional(),
  beneficioId: z.coerce.number().int().positive(),
});

export const AjustarPuntosDTO = z.object({
  conjuntoId: z.string().trim().min(1),
  usuarioId: z.string().trim().min(1),
  puntos: z.coerce.number().int().min(-100_000).max(100_000).refine((value) => value !== 0, {
    message: "El ajuste debe ser diferente de cero",
  }),
  descripcion: z.string().trim().min(5).max(500),
});
