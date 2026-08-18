CREATE TABLE "ConfiguracionZonaCronograma" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "elementoZonaId" INTEGER NOT NULL,
    "orden" INTEGER NOT NULL,
    "colorHex" TEXT NOT NULL,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ConfiguracionZonaCronograma_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ConfiguracionZonaCronograma_elementoZonaId_key"
ON "ConfiguracionZonaCronograma"("elementoZonaId");

CREATE INDEX "ConfiguracionZonaCronograma_conjuntoId_orden_idx"
ON "ConfiguracionZonaCronograma"("conjuntoId", "orden");

ALTER TABLE "ConfiguracionZonaCronograma"
ADD CONSTRAINT "ConfiguracionZonaCronograma_conjuntoId_fkey"
FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ConfiguracionZonaCronograma"
ADD CONSTRAINT "ConfiguracionZonaCronograma_elementoZonaId_fkey"
FOREIGN KEY ("elementoZonaId") REFERENCES "Elemento"("id") ON DELETE CASCADE ON UPDATE CASCADE;
