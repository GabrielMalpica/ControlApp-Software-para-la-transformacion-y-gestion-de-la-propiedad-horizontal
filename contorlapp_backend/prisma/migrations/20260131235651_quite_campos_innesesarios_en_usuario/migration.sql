/*
  Warnings:

  - You are about to drop the column `distribucionSemanal` on the `Usuario` table. All the data in the column will be lost.
  - You are about to drop the column `factorJornada` on the `Usuario` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "public"."Usuario" DROP COLUMN "distribucionSemanal",
DROP COLUMN "factorJornada";
