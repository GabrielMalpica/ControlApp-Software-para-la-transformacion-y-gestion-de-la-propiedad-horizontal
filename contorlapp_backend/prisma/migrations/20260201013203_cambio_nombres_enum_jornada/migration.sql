/*
  Warnings:

  - The values [COMPLETA_ESTANDAR,MEDIO_LV4_S2,MEDIO_LX8_V6] on the enum `PatronJornada` will be removed. If these variants are still used in the database, this will fail.

*/
-- AlterEnum
BEGIN;
CREATE TYPE "public"."PatronJornada_new" AS ENUM ('MEDIO_SEMANA_SABADO', 'MEDIO_DIAS_INTERCALADOS');
ALTER TABLE "public"."Usuario" ALTER COLUMN "patronJornada" TYPE "public"."PatronJornada_new" USING ("patronJornada"::text::"public"."PatronJornada_new");
ALTER TYPE "public"."PatronJornada" RENAME TO "PatronJornada_old";
ALTER TYPE "public"."PatronJornada_new" RENAME TO "PatronJornada";
DROP TYPE "public"."PatronJornada_old";
COMMIT;
