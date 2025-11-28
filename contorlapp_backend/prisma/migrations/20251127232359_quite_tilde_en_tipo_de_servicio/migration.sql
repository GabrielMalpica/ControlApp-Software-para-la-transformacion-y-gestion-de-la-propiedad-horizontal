/*
  Warnings:

  - The values [JARDINERÍA] on the enum `TipoServicio` will be removed. If these variants are still used in the database, this will fail.

*/
-- AlterEnum
BEGIN;
CREATE TYPE "public"."TipoServicio_new" AS ENUM ('JARDINERIA', 'PISCINA', 'ASEO', 'MANTENIMIENTOS_LOCATIVOS', 'SALVAMENTO_ACUATICO');
ALTER TABLE "public"."Conjunto" ALTER COLUMN "tipoServicio" TYPE "public"."TipoServicio_new"[] USING ("tipoServicio"::text::"public"."TipoServicio_new"[]);
ALTER TABLE "public"."Rendimiento" ALTER COLUMN "tipoServicio" TYPE "public"."TipoServicio_new" USING ("tipoServicio"::text::"public"."TipoServicio_new");
ALTER TYPE "public"."TipoServicio" RENAME TO "TipoServicio_old";
ALTER TYPE "public"."TipoServicio_new" RENAME TO "TipoServicio";
DROP TYPE "public"."TipoServicio_old";
COMMIT;
