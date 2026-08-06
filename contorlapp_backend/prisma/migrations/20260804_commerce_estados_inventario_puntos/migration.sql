-- Fases 8-10: auditoria de estados, recepcion idempotente e incentivos.
-- La migracion es aditiva y conserva todos los pedidos/movimientos existentes.

ALTER TABLE "Insumo"
  ADD COLUMN "wooSku" TEXT,
  ADD COLUMN "wooProductId" INTEGER;

ALTER TABLE "PedidoApp"
  ADD COLUMN "entradaInventarioAplicada" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "entradaInventarioAplicadaEn" TIMESTAMP(3),
  ADD COLUMN "puntosAplicados" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "puntosAplicadosEn" TIMESTAMP(3),
  ADD COLUMN "descuentoPuntos" DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN "beneficioPuntosId" INTEGER;

ALTER TABLE "PedidoAppItem"
  ADD COLUMN "insumoId" INTEGER;

ALTER TABLE "ConsumoInsumo"
  ADD COLUMN "pedidoAppId" INTEGER;

ALTER TABLE "MovimientoPuntos"
  ADD COLUMN "beneficioId" INTEGER,
  ADD COLUMN "conjuntoId" TEXT;

CREATE TABLE "PedidoAppEstadoHistorico" (
  "id" SERIAL NOT NULL,
  "pedidoId" INTEGER NOT NULL,
  "estadoAnterior" "EstadoPedidoInterno",
  "estadoNuevo" "EstadoPedidoInterno" NOT NULL,
  "cambiadoPorId" TEXT NOT NULL,
  "cambiadoPorRol" TEXT NOT NULL,
  "motivo" TEXT,
  "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PedidoAppEstadoHistorico_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ConfigPuntosConjunto" (
  "id" SERIAL NOT NULL,
  "conjuntoId" TEXT NOT NULL,
  "activo" BOOLEAN NOT NULL DEFAULT false,
  "montoPorPuntoResidente" DECIMAL(14,2) NOT NULL DEFAULT 1000,
  "montoPorPuntoConjunto" DECIMAL(14,2) NOT NULL DEFAULT 1000,
  "minimoRedencionPuntos" INTEGER NOT NULL DEFAULT 100,
  "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "actualizadoEn" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ConfigPuntosConjunto_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "BeneficioPuntos" (
  "id" SERIAL NOT NULL,
  "configId" INTEGER NOT NULL,
  "nombre" TEXT NOT NULL,
  "descripcion" TEXT,
  "puntosCosto" INTEGER NOT NULL,
  "valorDescuento" DECIMAL(14,2) NOT NULL DEFAULT 0,
  "activo" BOOLEAN NOT NULL DEFAULT true,
  "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "actualizadoEn" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "BeneficioPuntos_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "Insumo_empresaId_wooSku_key"
  ON "Insumo"("empresaId", "wooSku");
CREATE UNIQUE INDEX "Insumo_empresaId_wooProductId_key"
  ON "Insumo"("empresaId", "wooProductId");
CREATE INDEX "PedidoAppItem_insumoId_idx" ON "PedidoAppItem"("insumoId");
CREATE UNIQUE INDEX "ConsumoInsumo_pedidoAppId_insumoId_tipo_key"
  ON "ConsumoInsumo"("pedidoAppId", "insumoId", "tipo");
CREATE INDEX "ConsumoInsumo_pedidoAppId_idx" ON "ConsumoInsumo"("pedidoAppId");
CREATE INDEX "PedidoAppEstadoHistorico_pedidoId_creadoEn_idx"
  ON "PedidoAppEstadoHistorico"("pedidoId", "creadoEn");
CREATE INDEX "PedidoAppEstadoHistorico_cambiadoPorId_idx"
  ON "PedidoAppEstadoHistorico"("cambiadoPorId");
CREATE UNIQUE INDEX "ConfigPuntosConjunto_conjuntoId_key"
  ON "ConfigPuntosConjunto"("conjuntoId");
CREATE INDEX "BeneficioPuntos_configId_activo_idx"
  ON "BeneficioPuntos"("configId", "activo");
CREATE INDEX "MovimientoPuntos_pedidoId_tipo_idx"
  ON "MovimientoPuntos"("pedidoId", "tipo");
CREATE INDEX "MovimientoPuntos_beneficioId_idx"
  ON "MovimientoPuntos"("beneficioId");
CREATE INDEX "MovimientoPuntos_usuarioId_conjuntoId_creadoEn_idx"
  ON "MovimientoPuntos"("usuarioId", "conjuntoId", "creadoEn");

ALTER TABLE "PedidoApp" ADD CONSTRAINT "PedidoApp_beneficioPuntosId_fkey"
  FOREIGN KEY ("beneficioPuntosId") REFERENCES "BeneficioPuntos"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "PedidoAppItem" ADD CONSTRAINT "PedidoAppItem_insumoId_fkey"
  FOREIGN KEY ("insumoId") REFERENCES "Insumo"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ConsumoInsumo" ADD CONSTRAINT "ConsumoInsumo_pedidoAppId_fkey"
  FOREIGN KEY ("pedidoAppId") REFERENCES "PedidoApp"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "PedidoAppEstadoHistorico" ADD CONSTRAINT "PedidoAppEstadoHistorico_pedidoId_fkey"
  FOREIGN KEY ("pedidoId") REFERENCES "PedidoApp"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PedidoAppEstadoHistorico" ADD CONSTRAINT "PedidoAppEstadoHistorico_cambiadoPorId_fkey"
  FOREIGN KEY ("cambiadoPorId") REFERENCES "Usuario"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ConfigPuntosConjunto" ADD CONSTRAINT "ConfigPuntosConjunto_conjuntoId_fkey"
  FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BeneficioPuntos" ADD CONSTRAINT "BeneficioPuntos_configId_fkey"
  FOREIGN KEY ("configId") REFERENCES "ConfigPuntosConjunto"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "MovimientoPuntos" ADD CONSTRAINT "MovimientoPuntos_beneficioId_fkey"
  FOREIGN KEY ("beneficioId") REFERENCES "BeneficioPuntos"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MovimientoPuntos" ADD CONSTRAINT "MovimientoPuntos_conjuntoId_fkey"
  FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit")
  ON DELETE SET NULL ON UPDATE CASCADE;

UPDATE "MovimientoPuntos" m
SET "conjuntoId" = p."conjuntoId"
FROM "PedidoApp" p
WHERE m."pedidoId" = p."id";

-- Todo conjunto existente recibe configuracion inactiva; debe habilitarse explicitamente.
INSERT INTO "ConfigPuntosConjunto" (
  "conjuntoId",
  "activo",
  "montoPorPuntoResidente",
  "montoPorPuntoConjunto",
  "minimoRedencionPuntos",
  "actualizadoEn"
)
SELECT "nit", false, 1000, 1000, 100, CURRENT_TIMESTAMP
FROM "Conjunto"
ON CONFLICT ("conjuntoId") DO NOTHING;

-- Registra un punto de partida auditable para pedidos creados antes de esta fase.
INSERT INTO "PedidoAppEstadoHistorico" (
  "pedidoId",
  "estadoAnterior",
  "estadoNuevo",
  "cambiadoPorId",
  "cambiadoPorRol",
  "motivo",
  "creadoEn"
)
SELECT p."id", NULL, p."estado", p."usuarioId", u."rol", 'Estado inicial migrado', p."creadoEn"
FROM "PedidoApp" p
JOIN "Usuario" u ON u."id" = p."usuarioId";
