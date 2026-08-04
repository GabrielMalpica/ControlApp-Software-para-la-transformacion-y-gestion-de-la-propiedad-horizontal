ALTER TABLE "Tarea"
ADD COLUMN "definicionId" INTEGER,
ADD COLUMN "diaSemanaProgramado" "DiaSemana";

ALTER TABLE "PreventivaExcluidaBorrador"
ADD COLUMN "diaSemanaProgramado" "DiaSemana";

CREATE INDEX "Tarea_definicionId_idx" ON "Tarea"("definicionId");
