-- Estado actual e historial inmutable de seguimiento de PQRS.
ALTER TABLE "CompromisoConjunto"
ADD COLUMN "estado" TEXT NOT NULL DEFAULT 'RECIBIDO';

UPDATE "CompromisoConjunto"
SET "estado" = 'CERRADO'
WHERE "completado" = TRUE;

CREATE TABLE "CompromisoActualizacion" (
    "id" SERIAL NOT NULL,
    "compromisoId" INTEGER NOT NULL,
    "estado" TEXT NOT NULL,
    "observacion" TEXT,
    "evidencias" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "actorId" TEXT,
    "creadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "CompromisoActualizacion_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "CompromisoActualizacion_compromisoId_creadaEn_idx"
ON "CompromisoActualizacion"("compromisoId", "creadaEn");

CREATE INDEX "CompromisoActualizacion_actorId_idx"
ON "CompromisoActualizacion"("actorId");

ALTER TABLE "CompromisoActualizacion"
ADD CONSTRAINT "CompromisoActualizacion_compromisoId_fkey"
FOREIGN KEY ("compromisoId") REFERENCES "CompromisoConjunto"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "CompromisoActualizacion"
ADD CONSTRAINT "CompromisoActualizacion_actorId_fkey"
FOREIGN KEY ("actorId") REFERENCES "Usuario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- La creación y los cierres previos sí se pueden reconstruir con los datos
-- existentes; no se inventan observaciones ni evidencias anteriores.
INSERT INTO "CompromisoActualizacion" ("compromisoId", "estado", "actorId", "creadaEn")
SELECT "id", 'RECIBIDO', "creadoPorId", "creadaEn"
FROM "CompromisoConjunto";

INSERT INTO "CompromisoActualizacion" ("compromisoId", "estado", "creadaEn")
SELECT "id", 'CERRADO', COALESCE("cerradaEn", "actualizadaEn")
FROM "CompromisoConjunto"
WHERE "completado" = TRUE;
