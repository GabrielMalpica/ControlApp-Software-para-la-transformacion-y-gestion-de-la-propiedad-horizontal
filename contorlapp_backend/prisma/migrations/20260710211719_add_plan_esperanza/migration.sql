-- AlterTable
ALTER TABLE "public"."CompromisoConjunto" ALTER COLUMN "actualizadaEn" DROP DEFAULT;

-- AlterTable
ALTER TABLE "public"."EmpresaHerramientaStock" ALTER COLUMN "actualizadoEn" DROP DEFAULT;

-- AlterTable
ALTER TABLE "public"."OperarioDisponibilidadPeriodo" ALTER COLUMN "actualizadoEn" DROP DEFAULT;

-- AlterTable
ALTER TABLE "public"."PermisoRol" ALTER COLUMN "updatedAt" DROP DEFAULT;

-- AlterTable
ALTER TABLE "public"."PrestamoHerramientaConjunto" ALTER COLUMN "actualizadoEn" DROP DEFAULT;

-- CreateTable
CREATE TABLE "public"."PlanEsperanzaConfig" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "intervaloMeses" INTEGER NOT NULL DEFAULT 6,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlanEsperanzaConfig_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."PlanEsperanza" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "fechaInicio" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fechaFin" TIMESTAMP(3),
    "completado" BOOLEAN NOT NULL DEFAULT false,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlanEsperanza_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."DiagnosticoArea" (
    "id" SERIAL NOT NULL,
    "planEsperanzaId" INTEGER NOT NULL,
    "elementoId" INTEGER NOT NULL,
    "urlFoto" TEXT,
    "valoracion" DOUBLE PRECISION,
    "observaciones" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DiagnosticoArea_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PlanEsperanzaConfig_conjuntoId_key" ON "public"."PlanEsperanzaConfig"("conjuntoId");

-- CreateIndex
CREATE INDEX "PlanEsperanza_conjuntoId_completado_idx" ON "public"."PlanEsperanza"("conjuntoId", "completado");

-- CreateIndex
CREATE INDEX "PlanEsperanza_conjuntoId_fechaInicio_idx" ON "public"."PlanEsperanza"("conjuntoId", "fechaInicio");

-- CreateIndex
CREATE INDEX "DiagnosticoArea_elementoId_idx" ON "public"."DiagnosticoArea"("elementoId");

-- CreateIndex
CREATE UNIQUE INDEX "DiagnosticoArea_planEsperanzaId_elementoId_key" ON "public"."DiagnosticoArea"("planEsperanzaId", "elementoId");

-- AddForeignKey
ALTER TABLE "public"."PlanEsperanzaConfig" ADD CONSTRAINT "PlanEsperanzaConfig_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."PlanEsperanza" ADD CONSTRAINT "PlanEsperanza_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DiagnosticoArea" ADD CONSTRAINT "DiagnosticoArea_planEsperanzaId_fkey" FOREIGN KEY ("planEsperanzaId") REFERENCES "public"."PlanEsperanza"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DiagnosticoArea" ADD CONSTRAINT "DiagnosticoArea_elementoId_fkey" FOREIGN KEY ("elementoId") REFERENCES "public"."Elemento"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- RenameIndex
ALTER INDEX "public"."OperarioDisponibilidadPeriodo_operarioId_fechaInicio_fechaFin_i" RENAME TO "OperarioDisponibilidadPeriodo_operarioId_fechaInicio_fechaF_idx";

-- RenameIndex
ALTER INDEX "public"."PreventivaBorradorEvento_conjuntoId_periodoAnio_periodoMe_tipo_" RENAME TO "PBE_periodo_tipo_idx";

-- RenameIndex
ALTER INDEX "public"."PreventivaBorradorEvento_conjuntoId_periodoAnio_periodoMes_idx" RENAME TO "PBE_periodo_idx";

-- RenameIndex
ALTER INDEX "public"."PreventivaExcluidaBorrador_conjuntoId_periodoAnio_periodoMe_e_i" RENAME TO "PEB_periodo_estado_idx";

-- RenameIndex
ALTER INDEX "public"."PreventivaExcluidaBorrador_conjuntoId_periodoAnio_periodoMe_f_i" RENAME TO "PEB_periodo_fecha_idx";

-- RenameIndex
ALTER INDEX "public"."PreventivaExcluidaBorrador_conjuntoId_periodoAnio_periodoMe_idx" RENAME TO "PEB_periodo_idx";
