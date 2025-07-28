/*
  Warnings:

  - Added the required column `empresaId` to the `Operario` table without a default value. This is not possible if the table is not empty.

*/
-- AlterTable
ALTER TABLE "Operario" ADD COLUMN     "empresaId" TEXT NOT NULL;

-- AddForeignKey
ALTER TABLE "Operario" ADD CONSTRAINT "Operario_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;
