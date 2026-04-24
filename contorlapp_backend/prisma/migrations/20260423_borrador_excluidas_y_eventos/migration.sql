CREATE TABLE "PreventivaExcluidaBorrador" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "periodoAnio" INTEGER NOT NULL,
    "periodoMes" INTEGER NOT NULL,
    "defId" INTEGER,
    "origenTareaId" INTEGER,
    "tareaProgramadaId" INTEGER,
    "descripcion" TEXT NOT NULL,
    "frecuencia" "Frecuencia",
    "prioridad" INTEGER NOT NULL DEFAULT 2,
    "duracionMinutos" INTEGER NOT NULL,
    "fechaObjetivo" TIMESTAMP(3) NOT NULL,
    "ubicacionId" INTEGER NOT NULL,
    "ubicacionNombre" TEXT,
    "elementoId" INTEGER NOT NULL,
    "elementoNombre" TEXT,
    "supervisorId" TEXT,
    "supervisorNombre" TEXT,
    "operariosIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "operariosNombres" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "motivoTipo" TEXT NOT NULL,
    "motivoMensaje" TEXT,
    "estado" TEXT NOT NULL DEFAULT 'PENDIENTE',
    "metadataJson" JSONB,
    "creadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadaEn" TIMESTAMP(3) NOT NULL,
    "resueltaEn" TIMESTAMP(3),

    CONSTRAINT "PreventivaExcluidaBorrador_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PreventivaBorradorEvento" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "periodoAnio" INTEGER NOT NULL,
    "periodoMes" INTEGER NOT NULL,
    "tareaId" INTEGER,
    "excluidaId" INTEGER,
    "tipo" TEXT NOT NULL,
    "detalle" TEXT,
    "metadataJson" JSONB,
    "actorId" TEXT,
    "actorRol" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PreventivaBorradorEvento_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "PreventivaExcluidaBorrador_conjuntoId_periodoAnio_periodoMe_idx"
ON "PreventivaExcluidaBorrador"("conjuntoId", "periodoAnio", "periodoMes");

CREATE INDEX "PreventivaExcluidaBorrador_conjuntoId_periodoAnio_periodoMe_f_idx"
ON "PreventivaExcluidaBorrador"("conjuntoId", "periodoAnio", "periodoMes", "fechaObjetivo");

CREATE INDEX "PreventivaExcluidaBorrador_conjuntoId_periodoAnio_periodoMe_e_idx"
ON "PreventivaExcluidaBorrador"("conjuntoId", "periodoAnio", "periodoMes", "estado");

CREATE INDEX "PreventivaBorradorEvento_conjuntoId_periodoAnio_periodoMes_idx"
ON "PreventivaBorradorEvento"("conjuntoId", "periodoAnio", "periodoMes");

CREATE INDEX "PreventivaBorradorEvento_conjuntoId_periodoAnio_periodoMe_tipo_idx"
ON "PreventivaBorradorEvento"("conjuntoId", "periodoAnio", "periodoMes", "tipo");
