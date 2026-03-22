CREATE TYPE "public"."CategoriaHerramienta" AS ENUM ('LIMPIEZA', 'JARDINERIA', 'PISCINA', 'OTROS');
CREATE TYPE "public"."OrigenHerramientaStock" AS ENUM ('EMPRESA', 'CONJUNTO');
ALTER TABLE "public"."Herramienta"
ADD COLUMN "categoria" "public"."CategoriaHerramienta" NOT NULL DEFAULT 'OTROS';
ALTER TABLE "public"."UsoHerramienta"
ADD COLUMN "origenStock" "public"."OrigenHerramientaStock" NOT NULL DEFAULT 'CONJUNTO';
CREATE TABLE "public"."EmpresaHerramientaStock" (
    "id" SERIAL NOT NULL,
    "empresaId" TEXT NOT NULL,
    "herramientaId" INTEGER NOT NULL,
    "cantidad" DECIMAL(14,4) NOT NULL,
    "actualizadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "EmpresaHerramientaStock_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "EmpresaHerramientaStock_empresaId_idx"
ON "public"."EmpresaHerramientaStock"("empresaId");
CREATE UNIQUE INDEX "EmpresaHerramientaStock_empresaId_herramientaId_key"
ON "public"."EmpresaHerramientaStock"("empresaId", "herramientaId");
ALTER TABLE "public"."EmpresaHerramientaStock"
ADD CONSTRAINT "EmpresaHerramientaStock_empresaId_fkey"
FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit")
ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "public"."EmpresaHerramientaStock"
ADD CONSTRAINT "EmpresaHerramientaStock_herramientaId_fkey"
FOREIGN KEY ("herramientaId") REFERENCES "public"."Herramienta"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
INSERT INTO "public"."EmpresaHerramientaStock" ("empresaId", "herramientaId", "cantidad")
SELECT h."empresaId", h."id", 0
FROM "public"."Herramienta" h
ON CONFLICT ("empresaId", "herramientaId") DO NOTHING;