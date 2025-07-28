/*
  Warnings:

  - Made the column `empresaId` on table `JefeOperaciones` required. This step will fail if there are existing NULL values in that column.
  - Added the required column `empresaId` to the `Supervisor` table without a default value. This is not possible if the table is not empty.

*/
-- DropForeignKey
ALTER TABLE "JefeOperaciones" DROP CONSTRAINT "JefeOperaciones_empresaId_fkey";

-- AlterTable
ALTER TABLE "JefeOperaciones" ALTER COLUMN "empresaId" SET NOT NULL;

-- AlterTable
ALTER TABLE "Supervisor" ADD COLUMN     "empresaId" TEXT NOT NULL;

-- AddForeignKey
ALTER TABLE "JefeOperaciones" ADD CONSTRAINT "JefeOperaciones_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Supervisor" ADD CONSTRAINT "Supervisor_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;
