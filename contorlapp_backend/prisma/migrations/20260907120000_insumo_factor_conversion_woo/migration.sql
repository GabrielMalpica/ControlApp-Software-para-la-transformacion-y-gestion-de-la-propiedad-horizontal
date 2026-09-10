-- Factor de conversion entre "unidad de compra" en WooCommerce y "unidad de
-- inventario" del insumo (Insumo.unidad). Por defecto 1 (sin conversion), lo
-- que preserva el comportamiento actual para todo insumo ya mapeado.
-- Ej: insumo medido en litros, la tienda vende una garrafa de 3L =>
-- wooFactorConversion = 3. Recibir 2 garrafas suma 6 L, no 2, al inventario.
ALTER TABLE "Insumo" ADD COLUMN "wooFactorConversion" DECIMAL(12,4) NOT NULL DEFAULT 1;
