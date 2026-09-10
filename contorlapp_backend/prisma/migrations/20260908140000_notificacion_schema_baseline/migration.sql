-- Incorpora al historial de Prisma la tabla que versiones anteriores creaban
-- de forma idempotente durante el arranque de la API.
-- Los IF NOT EXISTS preservan instalaciones que ya contienen notificaciones.
CREATE TABLE IF NOT EXISTS "public"."Notificacion" (
    "id" SERIAL NOT NULL,
    "usuarioId" TEXT NOT NULL,
    "tipo" TEXT NOT NULL,
    "titulo" TEXT NOT NULL,
    "mensaje" TEXT NOT NULL,
    "referenciaTipo" TEXT,
    "referenciaId" INTEGER,
    "data" JSONB,
    "leida" BOOLEAN NOT NULL DEFAULT false,
    "leidaEn" TIMESTAMPTZ,
    "creadaEn" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Notificacion_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "idx_notificacion_usuario_leida"
ON "public"."Notificacion"("usuarioId", "leida");

CREATE INDEX IF NOT EXISTS "idx_notificacion_usuario_creada"
ON "public"."Notificacion"("usuarioId", "creadaEn" DESC);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'Notificacion_usuarioId_fkey'
          AND conrelid = '"public"."Notificacion"'::regclass
    ) THEN
        ALTER TABLE "public"."Notificacion"
        ADD CONSTRAINT "Notificacion_usuarioId_fkey"
        FOREIGN KEY ("usuarioId") REFERENCES "public"."Usuario"("id")
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
