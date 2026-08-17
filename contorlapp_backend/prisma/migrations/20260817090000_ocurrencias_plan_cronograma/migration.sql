ALTER TABLE "Tarea"
ADD COLUMN "ocurrenciaPlanId" TEXT;

ALTER TABLE "PreventivaExcluidaBorrador"
ADD COLUMN "ocurrenciaPlanId" TEXT;

CREATE TABLE "PreventivaOcurrenciaPlan" (
    "id" TEXT NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "periodoAnio" INTEGER NOT NULL,
    "periodoMes" INTEGER NOT NULL,
    "borrador" BOOLEAN NOT NULL DEFAULT true,
    "defId" INTEGER,
    "descripcion" TEXT NOT NULL,
    "frecuencia" "Frecuencia",
    "prioridad" INTEGER NOT NULL DEFAULT 2,
    "fechaObjetivo" TIMESTAMP(3) NOT NULL,
    "duracionEsperadaMin" INTEGER NOT NULL,
    "ubicacionId" INTEGER NOT NULL,
    "ubicacionNombre" TEXT,
    "elementoId" INTEGER NOT NULL,
    "elementoNombre" TEXT,
    "operariosEsperadosIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "operariosEsperadosNombres" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "estado" TEXT NOT NULL DEFAULT 'PENDIENTE',
    "motivoCodigo" TEXT,
    "motivoMensaje" TEXT,
    "fechaRealInicio" TIMESTAMP(3),
    "fechaRealFin" TIMESTAMP(3),
    "creadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadaEn" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "PreventivaOcurrenciaPlan_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "Tarea_ocurrenciaPlanId_idx" ON "Tarea"("ocurrenciaPlanId");
CREATE INDEX "PEB_ocurrenciaPlanId_idx" ON "PreventivaExcluidaBorrador"("ocurrenciaPlanId");
CREATE INDEX "POP_periodo_idx" ON "PreventivaOcurrenciaPlan"("conjuntoId", "periodoAnio", "periodoMes", "borrador");
CREATE INDEX "POP_defId_idx" ON "PreventivaOcurrenciaPlan"("defId");
CREATE INDEX "POP_fechaObjetivo_idx" ON "PreventivaOcurrenciaPlan"("fechaObjetivo");

