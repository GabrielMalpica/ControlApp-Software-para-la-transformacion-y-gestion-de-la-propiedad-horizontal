ALTER TABLE "public"."EmpresaHerramientaStock"
ADD COLUMN "estado" "public"."EstadoHerramienta" NOT NULL DEFAULT 'OPERATIVA';

DROP INDEX "public"."EmpresaHerramientaStock_empresaId_herramientaId_key";

CREATE UNIQUE INDEX "EmpresaHerramientaStock_empresaId_herramientaId_estado_key"
ON "public"."EmpresaHerramientaStock"("empresaId", "herramientaId", "estado");

CREATE INDEX "EmpresaHerramientaStock_empresaId_estado_idx"
ON "public"."EmpresaHerramientaStock"("empresaId", "estado");
