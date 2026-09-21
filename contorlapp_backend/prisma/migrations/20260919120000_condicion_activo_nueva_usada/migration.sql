-- CreateEnum
CREATE TYPE "public"."CondicionActivo" AS ENUM ('NUEVA', 'USADA');

-- AlterTable
ALTER TABLE "public"."Maquinaria" ADD COLUMN "condicion" "public"."CondicionActivo";

-- AlterTable
ALTER TABLE "public"."HerramientaItem" ADD COLUMN "condicion" "public"."CondicionActivo";
