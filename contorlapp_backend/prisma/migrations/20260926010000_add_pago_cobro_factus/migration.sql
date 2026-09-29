-- CreateEnum
CREATE TYPE "CanalPago" AS ENUM ('CONTROLAPP', 'WOOCOMMERCE');

-- CreateEnum
CREATE TYPE "EstadoCobro" AS ENUM ('CREADO', 'PENDIENTE', 'PAGADO', 'FALLIDO', 'VENCIDO', 'ABANDONADO', 'PAGADO_HUERFANO', 'PAGADO_DUPLICADO', 'DISCREPANCIA', 'ERROR');

-- CreateTable
CREATE TABLE "PagoCobro" (
    "id" SERIAL NOT NULL,
    "proveedor" TEXT NOT NULL DEFAULT 'factus',
    "referenceCode" TEXT NOT NULL,
    "canal" "CanalPago" NOT NULL,
    "pedidoAppId" INTEGER,
    "wooOrderId" TEXT,
    "usuarioId" TEXT,
    "montoEsperado" DECIMAL(14,2) NOT NULL,
    "montoProveedor" DECIMAL(14,2),
    "moneda" TEXT NOT NULL DEFAULT 'COP',
    "estado" "EstadoCobro" NOT NULL DEFAULT 'CREADO',
    "estadoProveedor" TEXT,
    "qrBase64" TEXT,
    "expiraLocalEn" TIMESTAMP(3),
    "proximaVerificacion" TIMESTAMP(3),
    "intentosVerificacion" INTEGER NOT NULL DEFAULT 0,
    "lockedUntil" TIMESTAMP(3),
    "pagadoDetectadoEn" TIMESTAMP(3),
    "pendienteSincronizarWoo" BOOLEAN NOT NULL DEFAULT false,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PagoCobro_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PagoEvento" (
    "id" SERIAL NOT NULL,
    "cobroId" INTEGER NOT NULL,
    "tipo" TEXT NOT NULL,
    "estadoAnterior" TEXT,
    "estadoNuevo" TEXT,
    "payload" JSONB,
    "actorId" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PagoEvento_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PagoCobro_referenceCode_key" ON "PagoCobro"("referenceCode");

-- CreateIndex
CREATE INDEX "PagoCobro_estado_proximaVerificacion_idx" ON "PagoCobro"("estado", "proximaVerificacion");

-- CreateIndex
CREATE INDEX "PagoCobro_pedidoAppId_idx" ON "PagoCobro"("pedidoAppId");

-- CreateIndex
CREATE INDEX "PagoCobro_wooOrderId_idx" ON "PagoCobro"("wooOrderId");

-- CreateIndex
CREATE INDEX "PagoEvento_cobroId_creadoEn_idx" ON "PagoEvento"("cobroId", "creadoEn");

-- AddForeignKey
ALTER TABLE "PagoCobro" ADD CONSTRAINT "PagoCobro_pedidoAppId_fkey" FOREIGN KEY ("pedidoAppId") REFERENCES "PedidoApp"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PagoEvento" ADD CONSTRAINT "PagoEvento_cobroId_fkey" FOREIGN KEY ("cobroId") REFERENCES "PagoCobro"("id") ON DELETE CASCADE ON UPDATE CASCADE;
