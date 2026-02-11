-- CreateEnum
CREATE TYPE "public"."PatronJornada" AS ENUM ('COMPLETA_ESTANDAR', 'MEDIO_LV4_S2', 'MEDIO_LX8_V6');

-- AlterTable
ALTER TABLE "public"."Usuario" ADD COLUMN     "activo" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "distribucionSemanal" JSONB,
ADD COLUMN     "factorJornada" DOUBLE PRECISION,
ADD COLUMN     "patronJornada" "public"."PatronJornada";

-- CreateTable
CREATE TABLE "public"."ConfiguracionLaboral" (
    "id" INTEGER NOT NULL DEFAULT 1,
    "horasSemanalesLegales" INTEGER NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ConfiguracionLaboral_pkey" PRIMARY KEY ("id")
);
