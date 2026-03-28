CREATE TABLE "public"."PrestamoHerramientaConjunto" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "empresaId" TEXT NOT NULL,
    "herramientaId" INTEGER NOT NULL,
    "solicitudId" INTEGER,
    "cantidad" DECIMAL(14,4) NOT NULL,
    "estado" "public"."EstadoHerramienta" NOT NULL DEFAULT 'OPERATIVA',
    "fechaInicio" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fechaFin" TIMESTAMP(3),
    "fechaDevolucionEstimada" TIMESTAMP(3),
    "actualizadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrestamoHerramientaConjunto_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "PrestamoHerramientaConjunto_conjuntoId_estado_idx"
ON "public"."PrestamoHerramientaConjunto"("conjuntoId", "estado");

CREATE INDEX "PrestamoHerramientaConjunto_conjuntoId_fechaFin_idx"
ON "public"."PrestamoHerramientaConjunto"("conjuntoId", "fechaFin");

CREATE INDEX "PrestamoHerramientaConjunto_herramientaId_fechaFin_idx"
ON "public"."PrestamoHerramientaConjunto"("herramientaId", "fechaFin");

CREATE INDEX "PrestamoHerramientaConjunto_empresaId_fechaFin_idx"
ON "public"."PrestamoHerramientaConjunto"("empresaId", "fechaFin");

ALTER TABLE "public"."PrestamoHerramientaConjunto"
ADD CONSTRAINT "PrestamoHerramientaConjunto_conjuntoId_fkey"
FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "public"."PrestamoHerramientaConjunto"
ADD CONSTRAINT "PrestamoHerramientaConjunto_empresaId_fkey"
FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "public"."PrestamoHerramientaConjunto"
ADD CONSTRAINT "PrestamoHerramientaConjunto_herramientaId_fkey"
FOREIGN KEY ("herramientaId") REFERENCES "public"."Herramienta"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "public"."PrestamoHerramientaConjunto"
ADD CONSTRAINT "PrestamoHerramientaConjunto_solicitudId_fkey"
FOREIGN KEY ("solicitudId") REFERENCES "public"."SolicitudHerramienta"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
