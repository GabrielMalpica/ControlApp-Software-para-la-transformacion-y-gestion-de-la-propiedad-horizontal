-- CreateEnum
CREATE TYPE "public"."CategoriaHerramienta" AS ENUM ('LIMPIEZA', 'JARDINERIA', 'PISCINA', 'OTROS');
-- CreateEnum
CREATE TYPE "public"."OrigenHerramientaStock" AS ENUM ('EMPRESA', 'CONJUNTO');
-- AlterTable
ALTER TABLE "public"."Herramienta"
ADD COLUMN "categoria" "public"."CategoriaHerramienta" NOT NULL DEFAULT 'OTROS';
-- AlterTable
ALTER TABLE "public"."UsoHerramienta"
ADD COLUMN "origenStock" "public"."OrigenHerramientaStock" NOT NULL DEFAULT 'CONJUNTO';
-- CreateTable
CREATE TABLE "public"."EmpresaHerramientaStock" (
    "id" SERIAL NOT NULL,
    "empresaId" TEXT NOT NULL,
    "herramientaId" INTEGER NOT NULL,
    "cantidad" DECIMAL(14,4) NOT NULL,
    "actualizadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "EmpresaHerramientaStock_pkey" PRIMARY KEY ("id")
);
-- CreateIndex
CREATE INDEX "EmpresaHerramientaStock_empresaId_idx"
ON "public"."EmpresaHerramientaStock"("empresaId");
-- CreateIndex
CREATE UNIQUE INDEX "EmpresaHerramientaStock_empresaId_herramientaId_key"
ON "public"."EmpresaHerramientaStock"("empresaId", "herramientaId");
-- AddForeignKey
ALTER TABLE "public"."EmpresaHerramientaStock"
ADD CONSTRAINT "EmpresaHerramientaStock_empresaId_fkey"
FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit")
ON DELETE CASCADE ON UPDATE CASCADE;
-- AddForeignKey
ALTER TABLE "public"."EmpresaHerramientaStock"
ADD CONSTRAINT "EmpresaHerramientaStock_herramientaId_fkey"
FOREIGN KEY ("herramientaId") REFERENCES "public"."Herramienta"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
-- Seed existing tools with company stock rows in 0
INSERT INTO "public"."EmpresaHerramientaStock" ("empresaId", "herramientaId", "cantidad")
SELECT h."empresaId", h."id", 0
FROM "public"."Herramienta" h
ON CONFLICT ("empresaId", "herramientaId") DO NOTHING;