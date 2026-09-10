-- Las instalaciones antiguas crearon esta llave durante el arranque con
-- ON UPDATE NO ACTION. Se normaliza para que coincida con el modelo Prisma.
ALTER TABLE "public"."Notificacion"
DROP CONSTRAINT IF EXISTS "Notificacion_usuarioId_fkey";

ALTER TABLE "public"."Notificacion"
ADD CONSTRAINT "Notificacion_usuarioId_fkey"
FOREIGN KEY ("usuarioId") REFERENCES "public"."Usuario"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
