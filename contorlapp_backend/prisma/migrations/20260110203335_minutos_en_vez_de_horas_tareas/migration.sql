/*
  Warnings:

  - You are about to drop the column `duracionHorasFija` on the `DefinicionTareaPreventiva` table. All the data in the column will be lost.
  - You are about to drop the column `duracionHoras` on the `Tarea` table. All the data in the column will be lost.
  - You are about to drop the column `tiempoEstimadoHoras` on the `Tarea` table. All the data in the column will be lost.
  - Added the required column `duracionMinutos` to the `Tarea` table without a default value. This is not possible if the table is not empty.

*/
-- AlterEnum
ALTER TYPE "public"."EstadoTarea" ADD VALUE 'PENDIENTE_REPROGRAMACION';

-- AlterTable
ALTER TABLE "public"."DefinicionTareaPreventiva" DROP COLUMN "duracionHorasFija",
ADD COLUMN     "diaMesProgramado" INTEGER,
ADD COLUMN     "diaSemanaProgramado" "public"."DiaSemana",
ADD COLUMN     "duracionMinutosFija" INTEGER,
ALTER COLUMN "prioridad" SET DEFAULT 2;

-- AlterTable
ALTER TABLE "public"."Tarea" DROP COLUMN "duracionHoras",
DROP COLUMN "tiempoEstimadoHoras",
ADD COLUMN     "duracionMinutos" INTEGER NOT NULL,
ADD COLUMN     "prioridad" INTEGER NOT NULL DEFAULT 2,
ADD COLUMN     "tiempoEstimadoMinutos" INTEGER;

-- CreateTable
CREATE TABLE "public"."Festivo" (
    "id" SERIAL NOT NULL,
    "fecha" TIMESTAMP(3) NOT NULL,
    "nombre" TEXT,
    "pais" TEXT NOT NULL DEFAULT 'CO',
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Festivo_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Festivo_fecha_key" ON "public"."Festivo"("fecha");
