-- Permite crear insumos "personalizados" directamente en el inventario de un
-- conjunto, sin pasar por el catalogo de empresa (para productos que la
-- empresa no vende pero el cliente quiere controlar en la app y en tareas).
--
-- conjuntoId = "" (default) => insumo del catalogo de empresa (el de siempre).
-- conjuntoId = nit del conjunto => insumo personalizado, solo visible/usable
-- para ese conjunto. No se agrega FK porque "" no corresponde a un Conjunto
-- real; la validacion del nit se hace en la capa de servicio.
ALTER TABLE "public"."Insumo" ADD COLUMN "conjuntoId" TEXT NOT NULL DEFAULT '';

DROP INDEX IF EXISTS "public"."Insumo_empresaId_nombre_unidad_key";

CREATE UNIQUE INDEX "Insumo_empresaId_conjuntoId_nombre_unidad_key" ON "public"."Insumo"("empresaId", "conjuntoId", "nombre", "unidad");

CREATE INDEX "Insumo_empresaId_conjuntoId_idx" ON "public"."Insumo"("empresaId", "conjuntoId");
