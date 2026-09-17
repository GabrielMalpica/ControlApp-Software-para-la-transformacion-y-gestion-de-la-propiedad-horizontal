/*
  Warnings:

  - You are about to drop the column `rol` on the `ConjuntoNecesidadOperario` table. All the data in the column will be lost.

*/
-- AlterEnum
ALTER TYPE "TipoFuncion" ADD VALUE 'JARDINERO';

-- AlterTable
ALTER TABLE "ConjuntoNecesidadOperario" DROP COLUMN "rol",
ADD COLUMN     "roles" "TipoFuncion"[];
