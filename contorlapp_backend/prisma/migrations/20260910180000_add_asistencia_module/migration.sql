-- CreateEnum
CREATE TYPE "OrigenRegistroAsistencia" AS ENUM ('QR', 'MANUAL');

-- CreateEnum
CREATE TYPE "TipoTurnoExtra" AS ENUM ('TURNO', 'NOVENA', 'OTRO');

-- CreateEnum
CREATE TYPE "EstadoTurnoExtra" AS ENUM ('PENDIENTE', 'PAGADO', 'CANCELADO');

-- AlterTable
ALTER TABLE "Conjunto" ADD COLUMN     "qrAsistenciaActualizado" TIMESTAMP(3),
ADD COLUMN     "qrAsistenciaToken" TEXT;

-- CreateTable
CREATE TABLE "ConceptoAsistencia" (
    "id" SERIAL NOT NULL,
    "empresaId" TEXT NOT NULL,
    "codigo" TEXT NOT NULL,
    "nombre" TEXT NOT NULL,
    "cuentaComoTrabajado" BOOLEAN NOT NULL DEFAULT false,
    "colorHex" TEXT NOT NULL DEFAULT '#9E9E9E',
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "orden" INTEGER NOT NULL DEFAULT 0,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ConceptoAsistencia_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RegistroAsistencia" (
    "id" SERIAL NOT NULL,
    "operarioId" TEXT NOT NULL,
    "conjuntoId" TEXT,
    "fecha" DATE NOT NULL,
    "conceptoId" INTEGER NOT NULL,
    "horaEntrada" TIMESTAMP(3),
    "horaSalida" TIMESTAMP(3),
    "origen" "OrigenRegistroAsistencia" NOT NULL DEFAULT 'MANUAL',
    "observacion" TEXT,
    "registradoPorId" TEXT,
    "actualizadoPorId" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RegistroAsistencia_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TurnoExtra" (
    "id" SERIAL NOT NULL,
    "empresaId" TEXT NOT NULL,
    "operarioId" TEXT NOT NULL,
    "conjuntoId" TEXT,
    "fecha" DATE NOT NULL,
    "tipo" "TipoTurnoExtra" NOT NULL DEFAULT 'TURNO',
    "esReemplazo" BOOLEAN NOT NULL DEFAULT false,
    "operarioReemplazadoId" TEXT,
    "reemplazadoNombreLibre" TEXT,
    "motivo" TEXT,
    "valorNegociado" DECIMAL(14,2),
    "turnosOrdinarios" INTEGER NOT NULL DEFAULT 0,
    "turnosDominicales" INTEGER NOT NULL DEFAULT 0,
    "estado" "EstadoTurnoExtra" NOT NULL DEFAULT 'PENDIENTE',
    "registradoPorId" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TurnoExtra_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ConceptoAsistencia_empresaId_activo_orden_idx" ON "ConceptoAsistencia"("empresaId", "activo", "orden");

-- CreateIndex
CREATE UNIQUE INDEX "ConceptoAsistencia_empresaId_codigo_key" ON "ConceptoAsistencia"("empresaId", "codigo");

-- CreateIndex
CREATE INDEX "RegistroAsistencia_conjuntoId_fecha_idx" ON "RegistroAsistencia"("conjuntoId", "fecha");

-- CreateIndex
CREATE INDEX "RegistroAsistencia_operarioId_fecha_idx" ON "RegistroAsistencia"("operarioId", "fecha");

-- CreateIndex
CREATE UNIQUE INDEX "RegistroAsistencia_operarioId_fecha_key" ON "RegistroAsistencia"("operarioId", "fecha");

-- CreateIndex
CREATE INDEX "TurnoExtra_empresaId_fecha_idx" ON "TurnoExtra"("empresaId", "fecha");

-- CreateIndex
CREATE INDEX "TurnoExtra_operarioId_fecha_idx" ON "TurnoExtra"("operarioId", "fecha");

-- CreateIndex
CREATE INDEX "TurnoExtra_conjuntoId_fecha_idx" ON "TurnoExtra"("conjuntoId", "fecha");

-- CreateIndex
CREATE UNIQUE INDEX "Conjunto_qrAsistenciaToken_key" ON "Conjunto"("qrAsistenciaToken");

-- AddForeignKey
ALTER TABLE "ConceptoAsistencia" ADD CONSTRAINT "ConceptoAsistencia_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RegistroAsistencia" ADD CONSTRAINT "RegistroAsistencia_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "Operario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RegistroAsistencia" ADD CONSTRAINT "RegistroAsistencia_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RegistroAsistencia" ADD CONSTRAINT "RegistroAsistencia_conceptoId_fkey" FOREIGN KEY ("conceptoId") REFERENCES "ConceptoAsistencia"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TurnoExtra" ADD CONSTRAINT "TurnoExtra_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TurnoExtra" ADD CONSTRAINT "TurnoExtra_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "Operario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TurnoExtra" ADD CONSTRAINT "TurnoExtra_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TurnoExtra" ADD CONSTRAINT "TurnoExtra_operarioReemplazadoId_fkey" FOREIGN KEY ("operarioReemplazadoId") REFERENCES "Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

