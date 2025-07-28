/*
  Warnings:

  - The primary key for the `Conjunto` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `_OperarioConjuntos` table will be changed. If it partially fails, the table could be left without primary key constraint.

*/
-- DropForeignKey
ALTER TABLE "Inventario" DROP CONSTRAINT "Inventario_conjuntoId_fkey";

-- DropForeignKey
ALTER TABLE "Maquinaria" DROP CONSTRAINT "Maquinaria_conjuntoId_fkey";

-- DropForeignKey
ALTER TABLE "SolicitudInsumo" DROP CONSTRAINT "SolicitudInsumo_conjuntoId_fkey";

-- DropForeignKey
ALTER TABLE "SolicitudMaquinaria" DROP CONSTRAINT "SolicitudMaquinaria_conjuntoId_fkey";

-- DropForeignKey
ALTER TABLE "SolicitudTarea" DROP CONSTRAINT "SolicitudTarea_conjuntoId_fkey";

-- DropForeignKey
ALTER TABLE "Tarea" DROP CONSTRAINT "Tarea_conjuntoId_fkey";

-- DropForeignKey
ALTER TABLE "Ubicacion" DROP CONSTRAINT "Ubicacion_conjuntoId_fkey";

-- DropForeignKey
ALTER TABLE "_OperarioConjuntos" DROP CONSTRAINT "_OperarioConjuntos_A_fkey";

-- AlterTable
ALTER TABLE "Conjunto" DROP CONSTRAINT "Conjunto_pkey",
ALTER COLUMN "nit" SET DATA TYPE TEXT,
ADD CONSTRAINT "Conjunto_pkey" PRIMARY KEY ("nit");

-- AlterTable
ALTER TABLE "Inventario" ALTER COLUMN "conjuntoId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "Maquinaria" ALTER COLUMN "conjuntoId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "SolicitudInsumo" ALTER COLUMN "conjuntoId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "SolicitudMaquinaria" ALTER COLUMN "conjuntoId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "SolicitudTarea" ALTER COLUMN "conjuntoId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "Tarea" ALTER COLUMN "conjuntoId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "Ubicacion" ALTER COLUMN "conjuntoId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "_OperarioConjuntos" DROP CONSTRAINT "_OperarioConjuntos_AB_pkey",
ALTER COLUMN "A" SET DATA TYPE TEXT,
ADD CONSTRAINT "_OperarioConjuntos_AB_pkey" PRIMARY KEY ("A", "B");

-- AddForeignKey
ALTER TABLE "Tarea" ADD CONSTRAINT "Tarea_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Ubicacion" ADD CONSTRAINT "Ubicacion_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Inventario" ADD CONSTRAINT "Inventario_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Maquinaria" ADD CONSTRAINT "Maquinaria_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudTarea" ADD CONSTRAINT "SolicitudTarea_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudInsumo" ADD CONSTRAINT "SolicitudInsumo_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudMaquinaria" ADD CONSTRAINT "SolicitudMaquinaria_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_OperarioConjuntos" ADD CONSTRAINT "_OperarioConjuntos_A_fkey" FOREIGN KEY ("A") REFERENCES "Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;
