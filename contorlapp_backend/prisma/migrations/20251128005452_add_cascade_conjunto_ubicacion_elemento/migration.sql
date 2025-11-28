-- DropForeignKey
ALTER TABLE "public"."Elemento" DROP CONSTRAINT "Elemento_ubicacionId_fkey";

-- DropForeignKey
ALTER TABLE "public"."Ubicacion" DROP CONSTRAINT "Ubicacion_conjuntoId_fkey";

-- AddForeignKey
ALTER TABLE "public"."Ubicacion" ADD CONSTRAINT "Ubicacion_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Elemento" ADD CONSTRAINT "Elemento_ubicacionId_fkey" FOREIGN KEY ("ubicacionId") REFERENCES "public"."Ubicacion"("id") ON DELETE CASCADE ON UPDATE CASCADE;
