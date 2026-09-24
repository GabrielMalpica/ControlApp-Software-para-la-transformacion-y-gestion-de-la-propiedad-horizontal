-- AlterTable
ALTER TABLE "PedidoApp" ADD COLUMN     "comprobanteHash" TEXT,
ADD COLUMN     "comprobanteReferencia" TEXT,
ADD COLUMN     "comprobanteVerificacion" JSONB;

-- CreateIndex
CREATE INDEX "PedidoApp_comprobanteReferencia_idx" ON "PedidoApp"("comprobanteReferencia");

-- CreateIndex
CREATE INDEX "PedidoApp_comprobanteHash_idx" ON "PedidoApp"("comprobanteHash");
