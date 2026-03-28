ALTER TABLE "public"."Elemento"
ADD COLUMN "padreId" INTEGER;

CREATE INDEX "Elemento_ubicacionId_padreId_idx"
ON "public"."Elemento"("ubicacionId", "padreId");

ALTER TABLE "public"."Elemento"
ADD CONSTRAINT "Elemento_padreId_fkey"
FOREIGN KEY ("padreId") REFERENCES "public"."Elemento"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
