ALTER TABLE "Conjunto"
ADD COLUMN     "mapaConjuntoNombreArchivo" TEXT,
ADD COLUMN     "mapaConjuntoMimeType" TEXT,
ADD COLUMN     "mapaConjuntoBytes" BYTEA,
ADD COLUMN     "mapaConjuntoActualizadoEn" TIMESTAMP(3);
