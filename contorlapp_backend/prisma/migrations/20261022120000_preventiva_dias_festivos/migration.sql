CREATE TYPE "DiaProgramado" AS ENUM (
  'LUNES',
  'MARTES',
  'MIERCOLES',
  'JUEVES',
  'VIERNES',
  'SABADO',
  'DOMINGO',
  'FESTIVO'
);

ALTER TABLE "DefinicionTareaPreventiva"
ALTER COLUMN "diaSemanaProgramado" TYPE "DiaProgramado"
USING ("diaSemanaProgramado"::text::"DiaProgramado");

ALTER TABLE "Tarea"
ALTER COLUMN "diaSemanaProgramado" TYPE "DiaProgramado"
USING ("diaSemanaProgramado"::text::"DiaProgramado");

ALTER TABLE "PreventivaExcluidaBorrador"
ALTER COLUMN "diaSemanaProgramado" TYPE "DiaProgramado"
USING ("diaSemanaProgramado"::text::"DiaProgramado");

ALTER TABLE "DefinicionTareaPreventiva"
ADD COLUMN "diasSemanaProgramados" JSONB;
