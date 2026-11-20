CREATE TABLE "public"."PlanEsperanzaCiclo" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "fechaInicioContrato" TIMESTAMP(3) NOT NULL,
    "fechaFinContrato" TIMESTAMP(3) NOT NULL,
    "fechaInicio" TIMESTAMP(3) NOT NULL,
    "fechaFin" TIMESTAMP(3) NOT NULL,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlanEsperanzaCiclo_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "public"."PlanEsperanza"
  ADD COLUMN "cicloId" INTEGER,
  ADD COLUMN "faseClave" TEXT,
  ADD COLUMN "mesObjetivo" INTEGER,
  ADD COLUMN "fechaProgramada" TIMESTAMP(3);

CREATE UNIQUE INDEX "PlanEsperanzaCiclo_conjuntoId_fechaInicio_key"
  ON "public"."PlanEsperanzaCiclo"("conjuntoId", "fechaInicio");
CREATE INDEX "PlanEsperanzaCiclo_conjuntoId_fechaFin_idx"
  ON "public"."PlanEsperanzaCiclo"("conjuntoId", "fechaFin");
CREATE INDEX "PlanEsperanza_cicloId_fechaProgramada_idx"
  ON "public"."PlanEsperanza"("cicloId", "fechaProgramada");
CREATE UNIQUE INDEX "PlanEsperanza_cicloId_faseClave_key"
  ON "public"."PlanEsperanza"("cicloId", "faseClave");

ALTER TABLE "public"."PlanEsperanzaCiclo"
  ADD CONSTRAINT "PlanEsperanzaCiclo_conjuntoId_fkey"
  FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "public"."PlanEsperanza"
  ADD CONSTRAINT "PlanEsperanza_cicloId_fkey"
  FOREIGN KEY ("cicloId") REFERENCES "public"."PlanEsperanzaCiclo"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
