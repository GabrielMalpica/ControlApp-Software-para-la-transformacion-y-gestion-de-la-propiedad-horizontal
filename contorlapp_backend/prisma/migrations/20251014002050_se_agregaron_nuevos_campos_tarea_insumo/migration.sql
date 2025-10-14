-- CreateEnum
CREATE TYPE "public"."CategoriaInsumo" AS ENUM ('LIMPIEZA', 'JARDINERIA', 'PISCINA');

-- CreateEnum
CREATE TYPE "public"."Frecuencia" AS ENUM ('DIARIA', 'SEMANAL', 'QUINCENAL', 'MENSUAL', 'BIMESTRAL', 'TRIMESTRAL', 'SEMESTRAL', 'ANUAL');

-- CreateEnum
CREATE TYPE "public"."UnidadCalculo" AS ENUM ('UNIDAD', 'M2', 'M3', 'ML', 'LITRO', 'KILO', 'HORA');

-- CreateEnum
CREATE TYPE "public"."TipoTarea" AS ENUM ('PREVENTIVA', 'CORRECTIVA');

-- DropForeignKey
ALTER TABLE "public"."Tarea" DROP CONSTRAINT "Tarea_operarioId_fkey";

-- AlterTable
ALTER TABLE "public"."Empresa" ADD COLUMN     "limiteHorasSemana" INTEGER NOT NULL DEFAULT 42;

-- AlterTable
ALTER TABLE "public"."Insumo" ADD COLUMN     "categoria" "public"."CategoriaInsumo" NOT NULL DEFAULT 'LIMPIEZA';

-- AlterTable
ALTER TABLE "public"."InventarioInsumo" ADD COLUMN     "umbralMinimo" INTEGER;

-- AlterTable
ALTER TABLE "public"."Tarea" ADD COLUMN     "bloqueIndex" INTEGER,
ADD COLUMN     "bloquesTotales" INTEGER,
ADD COLUMN     "borrador" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "consumoPrincipalPorUnidad" DECIMAL(14,4),
ADD COLUMN     "consumoTotalEstimado" DECIMAL(14,4),
ADD COLUMN     "frecuencia" "public"."Frecuencia",
ADD COLUMN     "grupoPlanId" TEXT,
ADD COLUMN     "insumoPrincipalId" INTEGER,
ADD COLUMN     "insumosPlanJson" JSONB,
ADD COLUMN     "maquinariaPlanJson" JSONB,
ADD COLUMN     "observaciones" TEXT,
ADD COLUMN     "periodoAnio" INTEGER,
ADD COLUMN     "periodoMes" INTEGER,
ADD COLUMN     "tiempoEstimadoHoras" DECIMAL(14,4),
ADD COLUMN     "tipo" "public"."TipoTarea" NOT NULL DEFAULT 'CORRECTIVA',
ALTER COLUMN "evidencias" SET DEFAULT ARRAY[]::TEXT[],
ALTER COLUMN "insumosUsados" DROP NOT NULL,
ALTER COLUMN "operarioId" DROP NOT NULL;

-- CreateTable
CREATE TABLE "public"."ConfiguracionSistema" (
    "id" SERIAL NOT NULL,
    "clave" TEXT NOT NULL,
    "valor" TEXT NOT NULL,

    CONSTRAINT "ConfiguracionSistema_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."DefinicionTareaPreventiva" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "ubicacionId" INTEGER NOT NULL,
    "elementoId" INTEGER NOT NULL,
    "descripcion" TEXT NOT NULL,
    "frecuencia" "public"."Frecuencia" NOT NULL,
    "prioridad" INTEGER NOT NULL DEFAULT 5,
    "unidadCalculo" "public"."UnidadCalculo",
    "areaNumerica" DECIMAL(14,4),
    "rendimientoBase" DECIMAL(14,4),
    "duracionHorasFija" INTEGER,
    "insumoPrincipalId" INTEGER,
    "consumoPrincipalPorUnidad" DECIMAL(14,4),
    "insumosPlanJson" JSONB,
    "maquinariaPlanJson" JSONB,
    "responsableSugeridoId" INTEGER,
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DefinicionTareaPreventiva_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ConfiguracionSistema_clave_key" ON "public"."ConfiguracionSistema"("clave");

-- CreateIndex
CREATE INDEX "InventarioInsumo_inventarioId_cantidad_idx" ON "public"."InventarioInsumo"("inventarioId", "cantidad");

-- CreateIndex
CREATE INDEX "Tarea_conjuntoId_fechaInicio_idx" ON "public"."Tarea"("conjuntoId", "fechaInicio");

-- CreateIndex
CREATE INDEX "Tarea_conjuntoId_fechaFin_idx" ON "public"."Tarea"("conjuntoId", "fechaFin");

-- CreateIndex
CREATE INDEX "Tarea_periodoAnio_periodoMes_conjuntoId_idx" ON "public"."Tarea"("periodoAnio", "periodoMes", "conjuntoId");

-- CreateIndex
CREATE INDEX "Tarea_grupoPlanId_bloqueIndex_idx" ON "public"."Tarea"("grupoPlanId", "bloqueIndex");

-- AddForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_ubicacionId_fkey" FOREIGN KEY ("ubicacionId") REFERENCES "public"."Ubicacion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_elementoId_fkey" FOREIGN KEY ("elementoId") REFERENCES "public"."Elemento"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_insumoPrincipalId_fkey" FOREIGN KEY ("insumoPrincipalId") REFERENCES "public"."Insumo"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_responsableSugeridoId_fkey" FOREIGN KEY ("responsableSugeridoId") REFERENCES "public"."Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Tarea" ADD CONSTRAINT "Tarea_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "public"."Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Tarea" ADD CONSTRAINT "Tarea_insumoPrincipalId_fkey" FOREIGN KEY ("insumoPrincipalId") REFERENCES "public"."Insumo"("id") ON DELETE SET NULL ON UPDATE CASCADE;
