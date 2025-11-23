/*
  Warnings:

  - The primary key for the `Administrador` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `Gerente` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `JefeOperaciones` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `Operario` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `Supervisor` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `Usuario` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `_OperarioConjuntos` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `_TareaOperarios` table will be changed. If it partially fails, the table could be left without primary key constraint.

*/
-- DropForeignKey
ALTER TABLE "public"."Administrador" DROP CONSTRAINT "Administrador_id_fkey";

-- DropForeignKey
ALTER TABLE "public"."Conjunto" DROP CONSTRAINT "Conjunto_administradorId_fkey";

-- DropForeignKey
ALTER TABLE "public"."ConsumoInsumo" DROP CONSTRAINT "ConsumoInsumo_operarioId_fkey";

-- DropForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" DROP CONSTRAINT "DefinicionTareaPreventiva_responsableSugeridoId_fkey";

-- DropForeignKey
ALTER TABLE "public"."Gerente" DROP CONSTRAINT "Gerente_id_fkey";

-- DropForeignKey
ALTER TABLE "public"."JefeOperaciones" DROP CONSTRAINT "JefeOperaciones_id_fkey";

-- DropForeignKey
ALTER TABLE "public"."Maquinaria" DROP CONSTRAINT "Maquinaria_operarioId_fkey";

-- DropForeignKey
ALTER TABLE "public"."Operario" DROP CONSTRAINT "Operario_id_fkey";

-- DropForeignKey
ALTER TABLE "public"."SolicitudMaquinaria" DROP CONSTRAINT "SolicitudMaquinaria_operarioId_fkey";

-- DropForeignKey
ALTER TABLE "public"."Supervisor" DROP CONSTRAINT "Supervisor_id_fkey";

-- DropForeignKey
ALTER TABLE "public"."Tarea" DROP CONSTRAINT "Tarea_supervisorId_fkey";

-- DropForeignKey
ALTER TABLE "public"."_OperarioConjuntos" DROP CONSTRAINT "_OperarioConjuntos_B_fkey";

-- DropForeignKey
ALTER TABLE "public"."_TareaOperarios" DROP CONSTRAINT "_TareaOperarios_A_fkey";

-- AlterTable
ALTER TABLE "public"."Administrador" DROP CONSTRAINT "Administrador_pkey",
ALTER COLUMN "id" SET DATA TYPE TEXT,
ADD CONSTRAINT "Administrador_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "public"."Conjunto" ALTER COLUMN "administradorId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "public"."ConsumoInsumo" ALTER COLUMN "operarioId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD COLUMN     "cuadrillaSugerida" INTEGER,
ADD COLUMN     "factoresSugeridosJson" JSONB,
ADD COLUMN     "insumosSiteOverrideJson" JSONB,
ADD COLUMN     "rendimientoId" INTEGER,
ALTER COLUMN "responsableSugeridoId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "public"."Gerente" DROP CONSTRAINT "Gerente_pkey",
ALTER COLUMN "id" SET DATA TYPE TEXT,
ADD CONSTRAINT "Gerente_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "public"."JefeOperaciones" DROP CONSTRAINT "JefeOperaciones_pkey",
ALTER COLUMN "id" SET DATA TYPE TEXT,
ADD CONSTRAINT "JefeOperaciones_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "public"."Maquinaria" ALTER COLUMN "operarioId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "public"."Operario" DROP CONSTRAINT "Operario_pkey",
ALTER COLUMN "id" SET DATA TYPE TEXT,
ADD CONSTRAINT "Operario_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "public"."SolicitudMaquinaria" ALTER COLUMN "operarioId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "public"."Supervisor" DROP CONSTRAINT "Supervisor_pkey",
ALTER COLUMN "id" SET DATA TYPE TEXT,
ADD CONSTRAINT "Supervisor_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "public"."Tarea" ADD COLUMN     "rendimientoId" INTEGER,
ADD COLUMN     "rendimientoVersion" INTEGER,
ALTER COLUMN "supervisorId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "public"."Usuario" DROP CONSTRAINT "Usuario_pkey",
ALTER COLUMN "id" SET DATA TYPE TEXT,
ADD CONSTRAINT "Usuario_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "public"."_OperarioConjuntos" DROP CONSTRAINT "_OperarioConjuntos_AB_pkey",
ALTER COLUMN "B" SET DATA TYPE TEXT,
ADD CONSTRAINT "_OperarioConjuntos_AB_pkey" PRIMARY KEY ("A", "B");

-- AlterTable
ALTER TABLE "public"."_TareaOperarios" DROP CONSTRAINT "_TareaOperarios_AB_pkey",
ALTER COLUMN "A" SET DATA TYPE TEXT,
ADD CONSTRAINT "_TareaOperarios_AB_pkey" PRIMARY KEY ("A", "B");

-- CreateTable
CREATE TABLE "public"."Rendimiento" (
    "id" SERIAL NOT NULL,
    "actividad" TEXT NOT NULL,
    "tipoServicio" "public"."TipoServicio" NOT NULL,
    "unidadCalculo" "public"."UnidadCalculo" NOT NULL,
    "rendimientoBasePorOperario" DECIMAL(14,4) NOT NULL,
    "curvaCuadrillaJson" JSONB,
    "factoresJson" JSONB,
    "insumosBaseJson" JSONB,
    "herramientasSugeridasJson" JSONB,
    "minutosSetup" INTEGER,
    "mermaPorcentaje" DECIMAL(5,2),
    "frecuenciaSugerida" "public"."Frecuencia",
    "version" INTEGER NOT NULL DEFAULT 1,
    "vigenteDesde" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
    "vigenteHasta" TIMESTAMP(3),
    "empresaId" TEXT,

    CONSTRAINT "Rendimiento_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."RendimientoAplicado" (
    "id" SERIAL NOT NULL,
    "tareaId" INTEGER NOT NULL,
    "rendimientoId" INTEGER NOT NULL,
    "cuadrillaPersonas" INTEGER NOT NULL,
    "factoresUsadosJson" JSONB,
    "areaNumerica" DECIMAL(14,4),
    "unidadCalculo" "public"."UnidadCalculo",
    "consumoBaseJson" JSONB,
    "herramientasJson" JSONB,
    "rendimientoCalculadoPorPersona" DECIMAL(14,4),
    "rendimientoCuadrilla" DECIMAL(14,4),
    "horasCalculadas" DECIMAL(14,4),
    "consumoTotalEstimado" DECIMAL(14,4),
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RendimientoAplicado_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Rendimiento_tipoServicio_actividad_idx" ON "public"."Rendimiento"("tipoServicio", "actividad");

-- CreateIndex
CREATE INDEX "Rendimiento_empresaId_idx" ON "public"."Rendimiento"("empresaId");

-- CreateIndex
CREATE UNIQUE INDEX "RendimientoAplicado_tareaId_key" ON "public"."RendimientoAplicado"("tareaId");

-- CreateIndex
CREATE INDEX "RendimientoAplicado_tareaId_idx" ON "public"."RendimientoAplicado"("tareaId");

-- CreateIndex
CREATE INDEX "RendimientoAplicado_rendimientoId_idx" ON "public"."RendimientoAplicado"("rendimientoId");

-- CreateIndex
CREATE INDEX "Tarea_rendimientoId_idx" ON "public"."Tarea"("rendimientoId");

-- AddForeignKey
ALTER TABLE "public"."Gerente" ADD CONSTRAINT "Gerente_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Administrador" ADD CONSTRAINT "Administrador_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."JefeOperaciones" ADD CONSTRAINT "JefeOperaciones_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Supervisor" ADD CONSTRAINT "Supervisor_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Operario" ADD CONSTRAINT "Operario_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_responsableSugeridoId_fkey" FOREIGN KEY ("responsableSugeridoId") REFERENCES "public"."Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_rendimientoId_fkey" FOREIGN KEY ("rendimientoId") REFERENCES "public"."Rendimiento"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Tarea" ADD CONSTRAINT "Tarea_supervisorId_fkey" FOREIGN KEY ("supervisorId") REFERENCES "public"."Supervisor"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Tarea" ADD CONSTRAINT "Tarea_rendimientoId_fkey" FOREIGN KEY ("rendimientoId") REFERENCES "public"."Rendimiento"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Conjunto" ADD CONSTRAINT "Conjunto_administradorId_fkey" FOREIGN KEY ("administradorId") REFERENCES "public"."Administrador"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ConsumoInsumo" ADD CONSTRAINT "ConsumoInsumo_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "public"."Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Maquinaria" ADD CONSTRAINT "Maquinaria_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "public"."Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."SolicitudMaquinaria" ADD CONSTRAINT "SolicitudMaquinaria_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "public"."Operario"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Rendimiento" ADD CONSTRAINT "Rendimiento_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."RendimientoAplicado" ADD CONSTRAINT "RendimientoAplicado_tareaId_fkey" FOREIGN KEY ("tareaId") REFERENCES "public"."Tarea"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."RendimientoAplicado" ADD CONSTRAINT "RendimientoAplicado_rendimientoId_fkey" FOREIGN KEY ("rendimientoId") REFERENCES "public"."Rendimiento"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."_TareaOperarios" ADD CONSTRAINT "_TareaOperarios_A_fkey" FOREIGN KEY ("A") REFERENCES "public"."Operario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."_OperarioConjuntos" ADD CONSTRAINT "_OperarioConjuntos_B_fkey" FOREIGN KEY ("B") REFERENCES "public"."Operario"("id") ON DELETE CASCADE ON UPDATE CASCADE;
