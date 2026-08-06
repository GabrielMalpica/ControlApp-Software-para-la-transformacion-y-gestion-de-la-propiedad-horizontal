ALTER TABLE "PedidoApp"
  ADD COLUMN "pagarAhora" DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN "fechaServicio" DATE,
  ADD COLUMN "turnoServicio" TEXT,
  ADD COLUMN "opcionPagoServicio" TEXT,
  ADD COLUMN "addonsServicio" JSONB,
  ADD COLUMN "idempotencyKey" TEXT;

ALTER TABLE "PedidoAppItem"
  ADD COLUMN "pagarAhora" DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN "fechaServicio" DATE,
  ADD COLUMN "turnoServicio" TEXT,
  ADD COLUMN "opcionPagoServicio" TEXT,
  ADD COLUMN "addonsServicio" JSONB;

CREATE UNIQUE INDEX "PedidoApp_idempotencyKey_key" ON "PedidoApp"("idempotencyKey");
