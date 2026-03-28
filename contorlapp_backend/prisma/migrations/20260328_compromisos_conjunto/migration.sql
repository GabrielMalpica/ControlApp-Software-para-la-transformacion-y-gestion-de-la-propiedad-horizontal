CREATE TABLE "public"."CompromisoConjunto" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "titulo" TEXT NOT NULL,
    "completado" BOOLEAN NOT NULL DEFAULT false,
    "creadoPorId" TEXT,
    "creadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CompromisoConjunto_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "CompromisoConjunto_conjuntoId_completado_idx"
ON "public"."CompromisoConjunto"("conjuntoId", "completado");

CREATE INDEX "CompromisoConjunto_conjuntoId_creadaEn_idx"
ON "public"."CompromisoConjunto"("conjuntoId", "creadaEn");

ALTER TABLE "public"."CompromisoConjunto"
ADD CONSTRAINT "CompromisoConjunto_conjuntoId_fkey"
FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "public"."CompromisoConjunto"
ADD CONSTRAINT "CompromisoConjunto_creadoPorId_fkey"
FOREIGN KEY ("creadoPorId") REFERENCES "public"."Usuario"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
