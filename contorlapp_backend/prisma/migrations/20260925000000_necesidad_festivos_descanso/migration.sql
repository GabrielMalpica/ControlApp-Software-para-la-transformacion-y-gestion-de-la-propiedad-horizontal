-- AlterTable
ALTER TABLE "ConjuntoNecesidadOperario"
  ADD COLUMN "trabajaFestivos" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "festivoHoraApertura" TEXT,
  ADD COLUMN "festivoHoraCierre" TEXT,
  ADD COLUMN "festivoDescansoInicio" TEXT,
  ADD COLUMN "festivoDescansoFin" TEXT,
  ADD COLUMN "descansoCompensatorio" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "diasDescansoCompensatorio" INTEGER NOT NULL DEFAULT 1;
