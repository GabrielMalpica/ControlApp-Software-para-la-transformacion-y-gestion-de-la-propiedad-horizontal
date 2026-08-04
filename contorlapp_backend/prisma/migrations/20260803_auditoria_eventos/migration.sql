CREATE TABLE "AuditoriaEvento" (
    "id" BIGSERIAL NOT NULL,
    "empresaId" INTEGER,
    "conjuntoId" TEXT,
    "modulo" TEXT NOT NULL,
    "entidad" TEXT NOT NULL,
    "entidadId" TEXT NOT NULL,
    "accion" TEXT NOT NULL,
    "actorId" TEXT,
    "actorRol" TEXT,
    "actorNombre" TEXT,
    "origen" TEXT NOT NULL DEFAULT 'USUARIO',
    "descripcion" TEXT,
    "datosAntes" JSONB,
    "datosDespues" JSONB,
    "metadataJson" JSONB,
    "periodoAnio" INTEGER,
    "periodoMes" INTEGER,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditoriaEvento_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AUD_entidad_idx" ON "AuditoriaEvento"("modulo", "entidad", "entidadId");

CREATE INDEX "AUD_periodo_idx" ON "AuditoriaEvento"("conjuntoId", "periodoAnio", "periodoMes", "modulo");

CREATE INDEX "AUD_creado_idx" ON "AuditoriaEvento"("creadoEn");
