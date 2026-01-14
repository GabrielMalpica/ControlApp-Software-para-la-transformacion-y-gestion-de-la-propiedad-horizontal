-- DropForeignKey
ALTER TABLE "public"."SolicitudInsumoItem" DROP CONSTRAINT "SolicitudInsumoItem_solicitudId_fkey";

-- AddForeignKey
ALTER TABLE "public"."SolicitudInsumoItem" ADD CONSTRAINT "SolicitudInsumoItem_solicitudId_fkey" FOREIGN KEY ("solicitudId") REFERENCES "public"."SolicitudInsumo"("id") ON DELETE CASCADE ON UPDATE CASCADE;
