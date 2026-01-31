-- AlterTable
ALTER TABLE "public"."Tarea" ADD COLUMN     "fechaFinOriginal" TIMESTAMP(3),
ADD COLUMN     "fechaInicioOriginal" TIMESTAMP(3),
ADD COLUMN     "reprogramada" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "reprogramadaEn" TIMESTAMP(3),
ADD COLUMN     "reprogramadaMotivo" TEXT,
ADD COLUMN     "reprogramadaPorTareaId" INTEGER;
