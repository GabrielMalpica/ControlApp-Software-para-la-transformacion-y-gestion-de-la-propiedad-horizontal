-- CreateEnum
CREATE TYPE "public"."RendimientoBaseTiempo" AS ENUM ('POR_HORA', 'POR_MINUTO', 'MIN_POR_UNIDAD');

-- AlterTable
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD COLUMN     "rendimientoTiempoBase" "public"."RendimientoBaseTiempo" DEFAULT 'POR_HORA',
ALTER COLUMN "rendimientoBase" SET DATA TYPE DECIMAL(65,30);
