-- Saldo de servicios pagados con anticipo: lo que falta se cobra al terminar
-- el servicio (canal SALDO_SERVICIO) y bloquea nuevos pedidos mientras este
-- pendiente. Ver docs/saldos-servicio.md.

-- CreateEnum
CREATE TYPE "EstadoSaldoServicio" AS ENUM ('PENDIENTE', 'PAGADO', 'PAGADO_POR_FUERA');

-- AlterEnum
ALTER TYPE "CanalPago" ADD VALUE 'SALDO_SERVICIO';

-- AlterTable
ALTER TABLE "PagoCobro" ADD COLUMN     "saldoServicioId" INTEGER;

-- CreateTable
CREATE TABLE "SaldoServicio" (
    "id" SERIAL NOT NULL,
    "wooOrderId" TEXT NOT NULL,
    "pedidoAppId" INTEGER,
    "usuarioId" TEXT,
    "clienteNombre" TEXT NOT NULL,
    "clienteCorreo" TEXT,
    "clienteTelefono" TEXT,
    "clienteDireccion" TEXT,
    "servicios" TEXT NOT NULL,
    "totalOrden" DECIMAL(14,2) NOT NULL,
    "pagadoAntes" DECIMAL(14,2) NOT NULL,
    "montoSaldo" DECIMAL(14,2) NOT NULL,
    "estado" "EstadoSaldoServicio" NOT NULL DEFAULT 'PENDIENTE',
    "servicioTerminadoEn" TIMESTAMP(3) NOT NULL,
    "pagadoEn" TIMESTAMP(3),
    "cobroPagoId" INTEGER,
    "resueltoPorId" TEXT,
    "resueltoPorNombre" TEXT,
    "resolucionMotivo" TEXT,
    "clienteAvisadoEn" TIMESTAMP(3),
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SaldoServicio_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SaldoServicioIncidencia" (
    "id" SERIAL NOT NULL,
    "saldoServicioId" INTEGER NOT NULL,
    "wooOrderId" TEXT NOT NULL,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SaldoServicioIncidencia_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SaldoServicio_wooOrderId_key" ON "SaldoServicio"("wooOrderId");

-- CreateIndex
CREATE INDEX "SaldoServicio_estado_usuarioId_idx" ON "SaldoServicio"("estado", "usuarioId");

-- CreateIndex
CREATE INDEX "SaldoServicio_estado_clienteCorreo_idx" ON "SaldoServicio"("estado", "clienteCorreo");

-- CreateIndex
CREATE INDEX "SaldoServicio_estado_clienteTelefono_idx" ON "SaldoServicio"("estado", "clienteTelefono");

-- CreateIndex
CREATE INDEX "SaldoServicio_pedidoAppId_idx" ON "SaldoServicio"("pedidoAppId");

-- CreateIndex
CREATE UNIQUE INDEX "SaldoServicioIncidencia_saldoServicioId_wooOrderId_key" ON "SaldoServicioIncidencia"("saldoServicioId", "wooOrderId");

-- CreateIndex
CREATE INDEX "PagoCobro_saldoServicioId_idx" ON "PagoCobro"("saldoServicioId");

-- AddForeignKey
ALTER TABLE "PagoCobro" ADD CONSTRAINT "PagoCobro_saldoServicioId_fkey" FOREIGN KEY ("saldoServicioId") REFERENCES "SaldoServicio"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SaldoServicioIncidencia" ADD CONSTRAINT "SaldoServicioIncidencia_saldoServicioId_fkey" FOREIGN KEY ("saldoServicioId") REFERENCES "SaldoServicio"("id") ON DELETE CASCADE ON UPDATE CASCADE;

