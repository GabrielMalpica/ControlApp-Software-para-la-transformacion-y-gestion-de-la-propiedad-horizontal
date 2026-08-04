import { z } from "zod";

export const CrearPedidoResidenteDTO = z.object({
  items: z
    .array(
      z.object({
        productId: z.coerce.number().int().positive(),
        quantity: z.coerce.number().positive(),
        variationId: z.coerce.number().int().positive().optional(),
      }),
    )
    .min(1, "Debes agregar al menos un producto al carrito"),
  notas: z.string().trim().max(500).optional(),
});

export const PedidoDetalleParamDTO = z.object({
  pedidoId: z.coerce.number().int().positive(),
});
