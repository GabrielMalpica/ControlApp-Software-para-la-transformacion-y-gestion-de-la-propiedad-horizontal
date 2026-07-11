-- AlterTable
ALTER TABLE "public"."PlanEsperanzaConfig"
ALTER COLUMN "intervaloMeses" SET DEFAULT 3;

-- AlterTable
ALTER TABLE "public"."DiagnosticoArea"
ADD COLUMN "checklist" JSONB;
