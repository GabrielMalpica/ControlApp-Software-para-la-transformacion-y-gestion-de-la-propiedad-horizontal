-- DropForeignKey
ALTER TABLE "Conjunto" DROP CONSTRAINT "Conjunto_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "Gerente" DROP CONSTRAINT "Gerente_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "Insumo" DROP CONSTRAINT "Insumo_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "InsumoConsumoEmpresa" DROP CONSTRAINT "InsumoConsumoEmpresa_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "JefeOperaciones" DROP CONSTRAINT "JefeOperaciones_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "Maquinaria" DROP CONSTRAINT "Maquinaria_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "SolicitudInsumo" DROP CONSTRAINT "SolicitudInsumo_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "SolicitudMaquinaria" DROP CONSTRAINT "SolicitudMaquinaria_empresaId_fkey";

-- DropForeignKey
ALTER TABLE "SolicitudTarea" DROP CONSTRAINT "SolicitudTarea_empresaId_fkey";

-- AlterTable
ALTER TABLE "Conjunto" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "Gerente" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "Insumo" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "InsumoConsumoEmpresa" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "JefeOperaciones" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "Maquinaria" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "SolicitudInsumo" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "SolicitudMaquinaria" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AlterTable
ALTER TABLE "SolicitudTarea" ALTER COLUMN "empresaId" SET DATA TYPE TEXT;

-- AddForeignKey
ALTER TABLE "Gerente" ADD CONSTRAINT "Gerente_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "JefeOperaciones" ADD CONSTRAINT "JefeOperaciones_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Conjunto" ADD CONSTRAINT "Conjunto_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Insumo" ADD CONSTRAINT "Insumo_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Maquinaria" ADD CONSTRAINT "Maquinaria_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InsumoConsumoEmpresa" ADD CONSTRAINT "InsumoConsumoEmpresa_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudTarea" ADD CONSTRAINT "SolicitudTarea_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudInsumo" ADD CONSTRAINT "SolicitudInsumo_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudMaquinaria" ADD CONSTRAINT "SolicitudMaquinaria_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE SET NULL ON UPDATE CASCADE;
