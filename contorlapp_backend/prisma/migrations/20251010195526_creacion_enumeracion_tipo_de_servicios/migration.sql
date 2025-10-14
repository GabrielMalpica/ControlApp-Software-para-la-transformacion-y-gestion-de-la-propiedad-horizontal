-- CreateEnum
CREATE TYPE "public"."TipoServicio" AS ENUM ('JARDINERÍA', 'PISCINA', 'ASEO', 'MANTENIMIENTOS_LOCATIVOS', 'SALVAMENTO_ACUATICO');

-- CreateEnum
CREATE TYPE "public"."DiaSemana" AS ENUM ('LUNES', 'MARTES', 'MIERCOLES', 'JUEVES', 'VIERNES', 'SABADO', 'DOMINGO');

-- AlterTable
ALTER TABLE "public"."Conjunto" ADD COLUMN     "activo" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "consignasEspeciales" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "fechaFinContrato" TIMESTAMP(3),
ADD COLUMN     "fechaInicioContrato" TIMESTAMP(3),
ADD COLUMN     "tipoServicio" "public"."TipoServicio"[],
ADD COLUMN     "valorAgregado" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "valorMensual" DECIMAL(14,2);

-- CreateTable
CREATE TABLE "public"."ConjuntoHorario" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "dia" "public"."DiaSemana" NOT NULL,
    "horaApertura" TEXT NOT NULL,
    "horaCierre" TEXT NOT NULL,

    CONSTRAINT "ConjuntoHorario_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ConjuntoHorario_conjuntoId_dia_key" ON "public"."ConjuntoHorario"("conjuntoId", "dia");

-- AddForeignKey
ALTER TABLE "public"."ConjuntoHorario" ADD CONSTRAINT "ConjuntoHorario_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;
