/*
  Warnings:

  - You are about to drop the column `conjuntoId` on the `Maquinaria` table. All the data in the column will be lost.
  - You are about to drop the column `disponible` on the `Maquinaria` table. All the data in the column will be lost.
  - You are about to drop the column `fechaDevolucionEstimada` on the `Maquinaria` table. All the data in the column will be lost.
  - You are about to drop the column `fechaPrestamo` on the `Maquinaria` table. All the data in the column will be lost.
  - You are about to drop the column `aprobado` on the `SolicitudMaquinaria` table. All the data in the column will be lost.
  - A unique constraint covering the columns `[empresaId,nombre,unidad]` on the table `Insumo` will be added. If there are existing duplicate values, this will fail.
  - A unique constraint covering the columns `[maquinariaConjuntoId]` on the table `SolicitudMaquinaria` will be added. If there are existing duplicate values, this will fail.
  - Made the column `empresaId` on table `Insumo` required. This step will fail if there are existing NULL values in that column.
  - Added the required column `propietarioTipo` to the `Maquinaria` table without a default value. This is not possible if the table is not empty.

*/
-- CreateEnum
CREATE TYPE "public"."EstadoSolicitudMaquinaria" AS ENUM ('PENDIENTE', 'APROBADA', 'RECHAZADA', 'CANCELADA', 'DEVUELTA');

-- CreateEnum
CREATE TYPE "public"."TipoMovimientoInsumo" AS ENUM ('ENTRADA', 'SALIDA', 'AJUSTE');

-- CreateEnum
CREATE TYPE "public"."PropietarioMaquinaria" AS ENUM ('EMPRESA', 'CONJUNTO');

-- CreateEnum
CREATE TYPE "public"."TipoTenenciaMaquinaria" AS ENUM ('PROPIA', 'PRESTADA');

-- CreateEnum
CREATE TYPE "public"."EstadoAsignacionMaquinaria" AS ENUM ('ACTIVA', 'DEVUELTA', 'INACTIVA');

-- DropForeignKey
ALTER TABLE "public"."Insumo" DROP CONSTRAINT "Insumo_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "public"."Maquinaria" DROP CONSTRAINT "Maquinaria_conjuntoId_fkey";

-- AlterTable
ALTER TABLE "public"."ConsumoInsumo" ADD COLUMN     "tipo" "public"."TipoMovimientoInsumo" NOT NULL DEFAULT 'SALIDA',
ALTER COLUMN "cantidad" SET DATA TYPE DECIMAL(14,4);

-- AlterTable
ALTER TABLE "public"."Insumo" ALTER COLUMN "empresaId" SET NOT NULL;

-- AlterTable
ALTER TABLE "public"."InventarioInsumo" ALTER COLUMN "cantidad" SET DATA TYPE DECIMAL(14,4);

-- AlterTable
ALTER TABLE "public"."Maquinaria" DROP COLUMN "conjuntoId",
DROP COLUMN "disponible",
DROP COLUMN "fechaDevolucionEstimada",
DROP COLUMN "fechaPrestamo",
ADD COLUMN     "conjuntoPropietarioId" TEXT,
ADD COLUMN     "propietarioTipo" "public"."PropietarioMaquinaria" NOT NULL;

-- AlterTable
ALTER TABLE "public"."SolicitudInsumoItem" ALTER COLUMN "cantidad" SET DATA TYPE DECIMAL(14,4);

-- AlterTable
ALTER TABLE "public"."SolicitudMaquinaria" DROP COLUMN "aprobado",
ADD COLUMN     "estado" "public"."EstadoSolicitudMaquinaria" NOT NULL DEFAULT 'PENDIENTE',
ADD COLUMN     "maquinariaConjuntoId" INTEGER,
ADD COLUMN     "observacionRespuesta" TEXT;

-- CreateTable
CREATE TABLE "public"."MaquinariaConjunto" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "maquinariaId" INTEGER NOT NULL,
    "tipoTenencia" "public"."TipoTenenciaMaquinaria" NOT NULL,
    "estado" "public"."EstadoAsignacionMaquinaria" NOT NULL DEFAULT 'ACTIVA',
    "fechaInicio" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fechaFin" TIMESTAMP(3),
    "fechaDevolucionEstimada" TIMESTAMP(3),
    "operarioId" TEXT,

    CONSTRAINT "MaquinariaConjunto_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."UsoMaquinaria" (
    "id" SERIAL NOT NULL,
    "tareaId" INTEGER NOT NULL,
    "maquinariaId" INTEGER NOT NULL,
    "operarioId" TEXT,
    "fechaInicio" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fechaFin" TIMESTAMP(3),
    "observacion" TEXT,

    CONSTRAINT "UsoMaquinaria_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "MaquinariaConjunto_conjuntoId_estado_idx" ON "public"."MaquinariaConjunto"("conjuntoId", "estado");

-- CreateIndex
CREATE INDEX "MaquinariaConjunto_maquinariaId_estado_idx" ON "public"."MaquinariaConjunto"("maquinariaId", "estado");

-- CreateIndex
CREATE UNIQUE INDEX "MaquinariaConjunto_conjuntoId_maquinariaId_estado_key" ON "public"."MaquinariaConjunto"("conjuntoId", "maquinariaId", "estado");

-- CreateIndex
CREATE INDEX "UsoMaquinaria_tareaId_idx" ON "public"."UsoMaquinaria"("tareaId");

-- CreateIndex
CREATE INDEX "UsoMaquinaria_maquinariaId_idx" ON "public"."UsoMaquinaria"("maquinariaId");

-- CreateIndex
CREATE UNIQUE INDEX "Insumo_empresaId_nombre_unidad_key" ON "public"."Insumo"("empresaId", "nombre", "unidad");

-- CreateIndex
CREATE UNIQUE INDEX "SolicitudMaquinaria_maquinariaConjuntoId_key" ON "public"."SolicitudMaquinaria"("maquinariaConjuntoId");

-- CreateIndex
CREATE INDEX "SolicitudMaquinaria_conjuntoId_estado_idx" ON "public"."SolicitudMaquinaria"("conjuntoId", "estado");

-- CreateIndex
CREATE INDEX "SolicitudMaquinaria_maquinariaId_estado_idx" ON "public"."SolicitudMaquinaria"("maquinariaId", "estado");

-- AddForeignKey
ALTER TABLE "public"."Insumo" ADD CONSTRAINT "Insumo_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Maquinaria" ADD CONSTRAINT "Maquinaria_conjuntoPropietarioId_fkey" FOREIGN KEY ("conjuntoPropietarioId") REFERENCES "public"."Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MaquinariaConjunto" ADD CONSTRAINT "MaquinariaConjunto_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MaquinariaConjunto" ADD CONSTRAINT "MaquinariaConjunto_maquinariaId_fkey" FOREIGN KEY ("maquinariaId") REFERENCES "public"."Maquinaria"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MaquinariaConjunto" ADD CONSTRAINT "MaquinariaConjunto_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "public"."Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UsoMaquinaria" ADD CONSTRAINT "UsoMaquinaria_tareaId_fkey" FOREIGN KEY ("tareaId") REFERENCES "public"."Tarea"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UsoMaquinaria" ADD CONSTRAINT "UsoMaquinaria_maquinariaId_fkey" FOREIGN KEY ("maquinariaId") REFERENCES "public"."Maquinaria"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UsoMaquinaria" ADD CONSTRAINT "UsoMaquinaria_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "public"."Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."SolicitudMaquinaria" ADD CONSTRAINT "SolicitudMaquinaria_maquinariaConjuntoId_fkey" FOREIGN KEY ("maquinariaConjuntoId") REFERENCES "public"."MaquinariaConjunto"("id") ON DELETE SET NULL ON UPDATE CASCADE;
