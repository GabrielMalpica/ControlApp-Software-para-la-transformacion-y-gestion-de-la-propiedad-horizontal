-- AlterTable
ALTER TABLE "PedidoApp" ADD COLUMN     "comprobanteSubidoEn" TIMESTAMP(3),
ADD COLUMN     "comprobanteUrl" TEXT,
ADD COLUMN     "direccionEntrega" TEXT,
ADD COLUMN     "metodoPago" TEXT;
