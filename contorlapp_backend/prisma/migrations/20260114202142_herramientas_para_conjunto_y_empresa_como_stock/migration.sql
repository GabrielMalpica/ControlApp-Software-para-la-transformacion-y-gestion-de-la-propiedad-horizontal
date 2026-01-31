-- CreateEnum
CREATE TYPE "public"."EstadoUsoHerramienta" AS ENUM ('RESERVADA', 'EN_USO', 'DEVUELTA', 'CONSUMIDA', 'CANCELADA');

-- CreateEnum
CREATE TYPE "public"."ModoControlHerramienta" AS ENUM ('PRESTAMO', 'CONSUMO', 'VIDA_CORTA');

-- CreateEnum
CREATE TYPE "public"."EstadoHerramienta" AS ENUM ('OPERATIVA', 'DANADA', 'PERDIDA', 'BAJA');

-- AlterEnum
ALTER TYPE "public"."EstadoAsignacionMaquinaria" ADD VALUE 'RESERVADA';

-- AlterTable
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD COLUMN     "herramientasPlanJson" JSONB;

-- AlterTable
ALTER TABLE "public"."MaquinariaConjunto" ADD COLUMN     "tareaId" INTEGER;

-- AlterTable
ALTER TABLE "public"."Tarea" ADD COLUMN     "herramientasPlanJson" JSONB;

-- CreateTable
CREATE TABLE "public"."Herramienta" (
    "id" SERIAL NOT NULL,
    "nombre" TEXT NOT NULL,
    "unidad" TEXT NOT NULL DEFAULT 'UNIDAD',
    "modoControl" "public"."ModoControlHerramienta" NOT NULL DEFAULT 'PRESTAMO',
    "vidaUtilDias" INTEGER,
    "umbralBajo" INTEGER,
    "empresaId" TEXT NOT NULL,

    CONSTRAINT "Herramienta_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ConjuntoHerramientaStock" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "herramientaId" INTEGER NOT NULL,
    "cantidad" DECIMAL(14,4) NOT NULL,
    "estado" "public"."EstadoHerramienta" NOT NULL DEFAULT 'OPERATIVA',
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ConjuntoHerramientaStock_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."UsoHerramienta" (
    "id" SERIAL NOT NULL,
    "tareaId" INTEGER NOT NULL,
    "herramientaId" INTEGER NOT NULL,
    "cantidad" DECIMAL(14,4) NOT NULL DEFAULT 1,
    "estado" "public"."EstadoUsoHerramienta" NOT NULL DEFAULT 'RESERVADA',
    "operarioId" TEXT,
    "fechaInicio" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fechaFin" TIMESTAMP(3),
    "observacion" TEXT,

    CONSTRAINT "UsoHerramienta_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."SolicitudHerramienta" (
    "id" SERIAL NOT NULL,
    "fechaSolicitud" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fechaAprobacion" TIMESTAMP(3),
    "estado" "public"."EstadoSolicitud" NOT NULL DEFAULT 'PENDIENTE',
    "observacionRespuesta" TEXT,
    "conjuntoId" TEXT NOT NULL,
    "empresaId" TEXT,

    CONSTRAINT "SolicitudHerramienta_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."SolicitudHerramientaItem" (
    "id" SERIAL NOT NULL,
    "solicitudId" INTEGER NOT NULL,
    "herramientaId" INTEGER NOT NULL,
    "cantidad" DECIMAL(14,4) NOT NULL,

    CONSTRAINT "SolicitudHerramientaItem_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Herramienta_empresaId_nombre_unidad_key" ON "public"."Herramienta"("empresaId", "nombre", "unidad");

-- CreateIndex
CREATE INDEX "ConjuntoHerramientaStock_conjuntoId_estado_idx" ON "public"."ConjuntoHerramientaStock"("conjuntoId", "estado");

-- CreateIndex
CREATE UNIQUE INDEX "ConjuntoHerramientaStock_conjuntoId_herramientaId_estado_key" ON "public"."ConjuntoHerramientaStock"("conjuntoId", "herramientaId", "estado");

-- CreateIndex
CREATE INDEX "UsoHerramienta_tareaId_idx" ON "public"."UsoHerramienta"("tareaId");

-- CreateIndex
CREATE INDEX "UsoHerramienta_herramientaId_idx" ON "public"."UsoHerramienta"("herramientaId");

-- CreateIndex
CREATE INDEX "SolicitudHerramienta_conjuntoId_estado_idx" ON "public"."SolicitudHerramienta"("conjuntoId", "estado");

-- CreateIndex
CREATE UNIQUE INDEX "SolicitudHerramientaItem_solicitudId_herramientaId_key" ON "public"."SolicitudHerramientaItem"("solicitudId", "herramientaId");

-- CreateIndex
CREATE INDEX "MaquinariaConjunto_tareaId_idx" ON "public"."MaquinariaConjunto"("tareaId");

-- AddForeignKey
ALTER TABLE "public"."Herramienta" ADD CONSTRAINT "Herramienta_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ConjuntoHerramientaStock" ADD CONSTRAINT "ConjuntoHerramientaStock_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ConjuntoHerramientaStock" ADD CONSTRAINT "ConjuntoHerramientaStock_herramientaId_fkey" FOREIGN KEY ("herramientaId") REFERENCES "public"."Herramienta"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UsoHerramienta" ADD CONSTRAINT "UsoHerramienta_tareaId_fkey" FOREIGN KEY ("tareaId") REFERENCES "public"."Tarea"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UsoHerramienta" ADD CONSTRAINT "UsoHerramienta_herramientaId_fkey" FOREIGN KEY ("herramientaId") REFERENCES "public"."Herramienta"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UsoHerramienta" ADD CONSTRAINT "UsoHerramienta_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "public"."Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."SolicitudHerramienta" ADD CONSTRAINT "SolicitudHerramienta_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."SolicitudHerramienta" ADD CONSTRAINT "SolicitudHerramienta_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."SolicitudHerramientaItem" ADD CONSTRAINT "SolicitudHerramientaItem_solicitudId_fkey" FOREIGN KEY ("solicitudId") REFERENCES "public"."SolicitudHerramienta"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."SolicitudHerramientaItem" ADD CONSTRAINT "SolicitudHerramientaItem_herramientaId_fkey" FOREIGN KEY ("herramientaId") REFERENCES "public"."Herramienta"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MaquinariaConjunto" ADD CONSTRAINT "MaquinariaConjunto_tareaId_fkey" FOREIGN KEY ("tareaId") REFERENCES "public"."Tarea"("id") ON DELETE SET NULL ON UPDATE CASCADE;
