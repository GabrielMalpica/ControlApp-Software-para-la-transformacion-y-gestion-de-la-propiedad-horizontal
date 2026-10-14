-- Webhook de Factus Pay: origen de cada verificacion, datos nuevos del
-- recaudo (vencimiento del QR, llave Bre-B, pagador recortado) y la bandeja
-- de entrada de los avisos. Ver docs/pagos-factus.md.

-- CreateEnum
CREATE TYPE "OrigenVerificacionPago" AS ENUM ('WEBHOOK', 'USUARIO', 'WORKER', 'CONCILIACION', 'ADMIN');

-- AlterTable
ALTER TABLE "PagoCobro"
    ADD COLUMN "clienteNotificadoEn" TIMESTAMP(3),
    ADD COLUMN "origenConfirmacion" "OrigenVerificacionPago",
    ADD COLUMN "ultimaVerificacionEn" TIMESTAMP(3),
    ADD COLUMN "ultimaVerificacionOrigen" "OrigenVerificacionPago",
    ADD COLUMN "webhookPrimeroEn" TIMESTAMP(3),
    ADD COLUMN "webhooksRecibidos" INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN "qrExpiraEn" TIMESTAMP(3),
    ADD COLUMN "brebKey" TEXT,
    ADD COLUMN "pagadorNombre" TEXT,
    ADD COLUMN "pagadorTipoDocumento" TEXT,
    ADD COLUMN "pagadorDocumentoUltimos4" TEXT;

-- Los cobros pagados antes de este cambio ya avisaron al cliente (el aviso
-- iba en la misma pasada): sin esto, un reintento de sincronizacion con Woo
-- volveria a notificarlos.
UPDATE "PagoCobro" SET "clienteNotificadoEn" = COALESCE("pagadoDetectadoEn", "actualizadoEn")
WHERE "estado" = 'PAGADO';

-- CreateTable
CREATE TABLE "PagoWebhookFactus" (
    "id" SERIAL NOT NULL,
    "recibidoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "referenceCode" TEXT,
    "cobroId" INTEGER,
    "bodySha256" TEXT NOT NULL,
    "payload" JSONB,
    "montoReportado" DECIMAL(14,2),
    "estadoReportado" TEXT,
    "ip" TEXT,
    "estado" TEXT NOT NULL DEFAULT 'RECIBIDO',
    "resultado" TEXT,
    "detalle" TEXT,
    "intentos" INTEGER NOT NULL DEFAULT 0,
    "lockedUntil" TIMESTAMP(3),
    "procesadoEn" TIMESTAMP(3),

    CONSTRAINT "PagoWebhookFactus_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PagoWebhookFactus_estado_recibidoEn_idx" ON "PagoWebhookFactus"("estado", "recibidoEn");

-- CreateIndex
CREATE INDEX "PagoWebhookFactus_referenceCode_idx" ON "PagoWebhookFactus"("referenceCode");

-- CreateIndex
CREATE INDEX "PagoWebhookFactus_cobroId_idx" ON "PagoWebhookFactus"("cobroId");

-- AddForeignKey
ALTER TABLE "PagoWebhookFactus" ADD CONSTRAINT "PagoWebhookFactus_cobroId_fkey" FOREIGN KEY ("cobroId") REFERENCES "PagoCobro"("id") ON DELETE SET NULL ON UPDATE CASCADE;
