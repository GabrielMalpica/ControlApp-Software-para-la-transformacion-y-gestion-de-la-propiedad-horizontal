-- Baseline idempotente del esquema de comercio y residentes.
-- Estas tablas/enums solo se habian creado con `prisma db push` y no tenian
-- migracion propia, por lo que una BD montada con `prisma migrate deploy`
-- (como la de produccion) nunca las tuvo. Debe ejecutarse ANTES de
-- 20260804_commerce_estados_inventario_puntos, que asume que ya existen.
--
-- Es idempotente (IF NOT EXISTS / DO blocks) para que tambien aplique sobre
-- bases creadas con db push donde estos objetos ya existen.

-- 1) ENUMS
DO $$
BEGIN
  CREATE TYPE "TipoPedidoApp" AS ENUM ('CONJUNTO', 'RESIDENTE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "EstadoPedidoInterno" AS ENUM (
    'BORRADOR', 'PENDIENTE_PAGO', 'PAGADO', 'PENDIENTE_ENVIO',
    'ENVIADO', 'RECIBIDO', 'ENTREGADO', 'CANCELADO'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "TipoMovimientoPuntos" AS ENUM ('ACUMULACION', 'REDENCION', 'AJUSTE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "TipoUnidadResidencial" AS ENUM ('APARTAMENTO', 'CASA', 'OFICINA', 'LOCAL');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 2) TABLAS BASE

CREATE TABLE IF NOT EXISTS "Residente" (
    "id" TEXT NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "tipoUnidad" "TipoUnidadResidencial" NOT NULL,
    "sector" TEXT,
    "unidad" TEXT NOT NULL,
    "telefonoContacto" TEXT,
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Residente_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "PedidoApp" (
    "id" SERIAL NOT NULL,
    "tipo" "TipoPedidoApp" NOT NULL,
    "estado" "EstadoPedidoInterno" NOT NULL DEFAULT 'BORRADOR',
    "estadoWoo" TEXT,
    "wooOrderId" TEXT,
    "usuarioId" TEXT NOT NULL,
    "conjuntoId" TEXT,
    "residenteId" TEXT,
    "total" DECIMAL(14,2) NOT NULL,
    "moneda" TEXT NOT NULL DEFAULT 'COP',
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "PedidoApp_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "PedidoAppItem" (
    "id" SERIAL NOT NULL,
    "pedidoId" INTEGER NOT NULL,
    "wooProductId" INTEGER,
    "wooVariationId" INTEGER,
    "nombreProducto" TEXT NOT NULL,
    "sku" TEXT,
    "cantidad" DECIMAL(14,4) NOT NULL,
    "precioUnitario" DECIMAL(14,2) NOT NULL,
    "subtotal" DECIMAL(14,2) NOT NULL,
    CONSTRAINT "PedidoAppItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "MovimientoPuntos" (
    "id" SERIAL NOT NULL,
    "usuarioId" TEXT NOT NULL,
    "pedidoId" INTEGER,
    "tipo" "TipoMovimientoPuntos" NOT NULL,
    "puntos" INTEGER NOT NULL,
    "descripcion" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "MovimientoPuntos_pkey" PRIMARY KEY ("id")
);

-- 3) INDEXES

CREATE INDEX IF NOT EXISTS "Residente_conjuntoId_idx" ON "Residente"("conjuntoId");
CREATE INDEX IF NOT EXISTS "Residente_conjuntoId_activo_idx" ON "Residente"("conjuntoId", "activo");

CREATE UNIQUE INDEX IF NOT EXISTS "PedidoApp_wooOrderId_key" ON "PedidoApp"("wooOrderId");
CREATE INDEX IF NOT EXISTS "PedidoApp_usuarioId_idx" ON "PedidoApp"("usuarioId");
CREATE INDEX IF NOT EXISTS "PedidoApp_usuarioId_estado_idx" ON "PedidoApp"("usuarioId", "estado");
CREATE INDEX IF NOT EXISTS "PedidoApp_conjuntoId_estado_idx" ON "PedidoApp"("conjuntoId", "estado");
CREATE INDEX IF NOT EXISTS "PedidoApp_wooOrderId_idx" ON "PedidoApp"("wooOrderId");

CREATE INDEX IF NOT EXISTS "PedidoAppItem_pedidoId_idx" ON "PedidoAppItem"("pedidoId");

CREATE INDEX IF NOT EXISTS "MovimientoPuntos_usuarioId_idx" ON "MovimientoPuntos"("usuarioId");
CREATE INDEX IF NOT EXISTS "MovimientoPuntos_usuarioId_creadoEn_idx" ON "MovimientoPuntos"("usuarioId", "creadoEn");

-- 4) FOREIGN KEYS (idempotentes)

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Residente_usuario_fkey') THEN
    ALTER TABLE "Residente" ADD CONSTRAINT "Residente_usuario_fkey"
      FOREIGN KEY ("id") REFERENCES "Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Residente_conjunto_fkey') THEN
    ALTER TABLE "Residente" ADD CONSTRAINT "Residente_conjunto_fkey"
      FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PedidoApp_usuario_fkey') THEN
    ALTER TABLE "PedidoApp" ADD CONSTRAINT "PedidoApp_usuario_fkey"
      FOREIGN KEY ("usuarioId") REFERENCES "Usuario"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PedidoApp_conjunto_fkey') THEN
    ALTER TABLE "PedidoApp" ADD CONSTRAINT "PedidoApp_conjunto_fkey"
      FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PedidoApp_residente_fkey') THEN
    ALTER TABLE "PedidoApp" ADD CONSTRAINT "PedidoApp_residente_fkey"
      FOREIGN KEY ("residenteId") REFERENCES "Residente"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PedidoAppItem_pedido_fkey') THEN
    ALTER TABLE "PedidoAppItem" ADD CONSTRAINT "PedidoAppItem_pedido_fkey"
      FOREIGN KEY ("pedidoId") REFERENCES "PedidoApp"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'MovimientoPuntos_usuario_fkey') THEN
    ALTER TABLE "MovimientoPuntos" ADD CONSTRAINT "MovimientoPuntos_usuario_fkey"
      FOREIGN KEY ("usuarioId") REFERENCES "Usuario"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'MovimientoPuntos_pedido_fkey') THEN
    ALTER TABLE "MovimientoPuntos" ADD CONSTRAINT "MovimientoPuntos_pedido_fkey"
      FOREIGN KEY ("pedidoId") REFERENCES "PedidoApp"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;
