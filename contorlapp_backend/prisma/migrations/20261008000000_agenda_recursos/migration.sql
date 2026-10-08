-- Agenda de recursos: necesidad (NecesidadRecursoTarea) vs reserva (ReservaRecurso).
-- Ver docs/agenda-recursos.md.

-- btree_gist permite combinar igualdad/desigualdad escalar con solape de
-- rangos en las restricciones de exclusión de ReservaRecurso.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- CreateEnum
CREATE TYPE "ClaseRecurso" AS ENUM ('MAQUINARIA', 'HERRAMIENTA');

-- CreateEnum
CREATE TYPE "TipoReservaRecurso" AS ENUM ('TAREA', 'PRESTAMO', 'MANTENIMIENTO');

-- CreateEnum
CREATE TYPE "EstadoReservaRecurso" AS ENUM ('RESERVADA', 'FINALIZADA', 'CANCELADA');

-- CreateEnum
CREATE TYPE "OrigenRecurso" AS ENUM ('CONJUNTO', 'EMPRESA');

-- CreateEnum
CREATE TYPE "OrigenNecesidadRecurso" AS ENUM ('PLAN_PREVENTIVA', 'MANUAL');

-- AlterTable
ALTER TABLE "Empresa" ADD COLUMN     "diasEntregaRecursos" INTEGER[] DEFAULT ARRAY[1, 3, 6]::INTEGER[],
ADD COLUMN     "margenTrasladoMinutos" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "NecesidadRecursoTarea" (
    "id" SERIAL NOT NULL,
    "tareaId" INTEGER NOT NULL,
    "clase" "ClaseRecurso" NOT NULL,
    "tipoMaquinariaId" INTEGER,
    "herramientaId" INTEGER,
    "cantidad" INTEGER NOT NULL DEFAULT 1,
    "obligatorio" BOOLEAN NOT NULL DEFAULT true,
    "origen" "OrigenNecesidadRecurso" NOT NULL DEFAULT 'PLAN_PREVENTIVA',
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "NecesidadRecursoTarea_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ReservaRecurso" (
    "id" SERIAL NOT NULL,
    "empresaId" TEXT NOT NULL,
    "clase" "ClaseRecurso" NOT NULL,
    "maquinariaId" INTEGER,
    "herramientaItemId" INTEGER,
    "tipo" "TipoReservaRecurso" NOT NULL DEFAULT 'TAREA',
    "estado" "EstadoReservaRecurso" NOT NULL DEFAULT 'RESERVADA',
    "origen" "OrigenRecurso" NOT NULL,
    "conjuntoId" TEXT,
    "tareaId" INTEGER,
    "necesidadId" INTEGER,
    "usoInicio" TIMESTAMP(3) NOT NULL,
    "usoFin" TIMESTAMP(3) NOT NULL,
    "bloqueoInicio" TIMESTAMP(3) NOT NULL,
    "bloqueoFin" TIMESTAMP(3) NOT NULL,
    "recursoEtiqueta" TEXT NOT NULL,
    "tareaDescripcion" TEXT,
    "conjuntoNombre" TEXT,
    "responsablesJson" JSONB,
    "observacion" TEXT,
    "motivoCancelacion" TEXT,
    "prestamoMaquinariaId" INTEGER,
    "prestamoHerramientaId" INTEGER,
    "creadoPorId" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "canceladoPorId" TEXT,
    "canceladoEn" TIMESTAMP(3),
    "finalizadaEn" TIMESTAMP(3),
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ReservaRecurso_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "NecesidadRecursoTarea_tipoMaquinariaId_idx" ON "NecesidadRecursoTarea"("tipoMaquinariaId");

-- CreateIndex
CREATE INDEX "NecesidadRecursoTarea_herramientaId_idx" ON "NecesidadRecursoTarea"("herramientaId");

-- CreateIndex
CREATE UNIQUE INDEX "NecesidadRecursoTarea_tareaId_tipoMaquinariaId_key" ON "NecesidadRecursoTarea"("tareaId", "tipoMaquinariaId");

-- CreateIndex
CREATE UNIQUE INDEX "NecesidadRecursoTarea_tareaId_herramientaId_key" ON "NecesidadRecursoTarea"("tareaId", "herramientaId");

-- CreateIndex
CREATE INDEX "ReservaRecurso_maquinariaId_bloqueoInicio_idx" ON "ReservaRecurso"("maquinariaId", "bloqueoInicio");

-- CreateIndex
CREATE INDEX "ReservaRecurso_herramientaItemId_bloqueoInicio_idx" ON "ReservaRecurso"("herramientaItemId", "bloqueoInicio");

-- CreateIndex
CREATE INDEX "ReservaRecurso_empresaId_estado_bloqueoInicio_idx" ON "ReservaRecurso"("empresaId", "estado", "bloqueoInicio");

-- CreateIndex
CREATE INDEX "ReservaRecurso_conjuntoId_usoInicio_idx" ON "ReservaRecurso"("conjuntoId", "usoInicio");

-- CreateIndex
CREATE INDEX "ReservaRecurso_tareaId_idx" ON "ReservaRecurso"("tareaId");

-- CreateIndex
CREATE INDEX "ReservaRecurso_necesidadId_idx" ON "ReservaRecurso"("necesidadId");

-- CreateIndex
CREATE INDEX "ReservaRecurso_prestamoMaquinariaId_idx" ON "ReservaRecurso"("prestamoMaquinariaId");

-- CreateIndex
CREATE INDEX "ReservaRecurso_prestamoHerramientaId_idx" ON "ReservaRecurso"("prestamoHerramientaId");

-- AddForeignKey
ALTER TABLE "NecesidadRecursoTarea" ADD CONSTRAINT "NecesidadRecursoTarea_tareaId_fkey" FOREIGN KEY ("tareaId") REFERENCES "Tarea"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NecesidadRecursoTarea" ADD CONSTRAINT "NecesidadRecursoTarea_tipoMaquinariaId_fkey" FOREIGN KEY ("tipoMaquinariaId") REFERENCES "TipoMaquinariaCatalogo"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NecesidadRecursoTarea" ADD CONSTRAINT "NecesidadRecursoTarea_herramientaId_fkey" FOREIGN KEY ("herramientaId") REFERENCES "Herramienta"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_maquinariaId_fkey" FOREIGN KEY ("maquinariaId") REFERENCES "Maquinaria"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_herramientaItemId_fkey" FOREIGN KEY ("herramientaItemId") REFERENCES "HerramientaItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_tareaId_fkey" FOREIGN KEY ("tareaId") REFERENCES "Tarea"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_necesidadId_fkey" FOREIGN KEY ("necesidadId") REFERENCES "NecesidadRecursoTarea"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- ============================================================
-- Reglas que Prisma no modela (CHECK + EXCLUDE). Ver schema.prisma.
-- ============================================================

-- Una necesidad apunta exactamente a un tipo según su clase.
ALTER TABLE "NecesidadRecursoTarea" ADD CONSTRAINT "NecesidadRecursoTarea_clase_check"
  CHECK (("clase" = 'MAQUINARIA' AND "tipoMaquinariaId" IS NOT NULL AND "herramientaId" IS NULL)
      OR ("clase" = 'HERRAMIENTA' AND "herramientaId" IS NOT NULL AND "tipoMaquinariaId" IS NULL));
ALTER TABLE "NecesidadRecursoTarea" ADD CONSTRAINT "NecesidadRecursoTarea_cantidad_check"
  CHECK ("cantidad" >= 1);

-- Una reserva compromete exactamente una unidad física según su clase.
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_clase_check"
  CHECK (("clase" = 'MAQUINARIA' AND "maquinariaId" IS NOT NULL AND "herramientaItemId" IS NULL)
      OR ("clase" = 'HERRAMIENTA' AND "herramientaItemId" IS NOT NULL AND "maquinariaId" IS NULL));

-- Rangos coherentes: el bloqueo físico siempre contiene al uso.
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_rangos_check"
  CHECK ("usoFin" > "usoInicio"
     AND "bloqueoInicio" <= "usoInicio"
     AND "bloqueoFin" >= "usoFin");

-- Una reserva de tarea siempre tiene conjunto destino.
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_tarea_conjunto_check"
  CHECK ("tipo" <> 'TAREA' OR "conjuntoId" IS NOT NULL OR "estado" <> 'RESERVADA');

-- (1) Nunca dos usos simultáneos de la misma unidad (en ningún conjunto).
--     Los préstamos largos no "usan" la unidad: solo la ubican (regla 2).
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_maquinaria_uso_excl"
  EXCLUDE USING gist ("maquinariaId" WITH =, tsrange("usoInicio", "usoFin", '[)') WITH &&)
  WHERE ("estado" <> 'CANCELADA' AND "tipo" <> 'PRESTAMO' AND "maquinariaId" IS NOT NULL);

ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_herramienta_uso_excl"
  EXCLUDE USING gist ("herramientaItemId" WITH =, tsrange("usoInicio", "usoFin", '[)') WITH &&)
  WHERE ("estado" <> 'CANCELADA' AND "tipo" <> 'PRESTAMO' AND "herramientaItemId" IS NOT NULL);

-- (2) Nunca comprometida con dos conjuntos distintos en ventanas físicas que
--     se crucen (incluye entrega/recogida o margen de traslado). La misma
--     unidad sí puede encadenar varias reservas en el MISMO conjunto.
ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_maquinaria_ubicacion_excl"
  EXCLUDE USING gist ("maquinariaId" WITH =, (COALESCE("conjuntoId", '')) WITH <>, tsrange("bloqueoInicio", "bloqueoFin", '[)') WITH &&)
  WHERE ("estado" <> 'CANCELADA' AND "maquinariaId" IS NOT NULL);

ALTER TABLE "ReservaRecurso" ADD CONSTRAINT "ReservaRecurso_herramienta_ubicacion_excl"
  EXCLUDE USING gist ("herramientaItemId" WITH =, (COALESCE("conjuntoId", '')) WITH <>, tsrange("bloqueoInicio", "bloqueoFin", '[)') WITH &&)
  WHERE ("estado" <> 'CANCELADA' AND "herramientaItemId" IS NOT NULL);

-- Los días de entrega son 0..6 (domingo..sábado), igual que Date#getDay.
UPDATE "Empresa" SET "diasEntregaRecursos" = ARRAY[1, 3, 6] WHERE "diasEntregaRecursos" IS NULL;
ALTER TABLE "Empresa" ADD CONSTRAINT "Empresa_diasEntregaRecursos_check"
  CHECK ("diasEntregaRecursos" <@ ARRAY[0, 1, 2, 3, 4, 5, 6]);
ALTER TABLE "Empresa" ADD CONSTRAINT "Empresa_margenTrasladoMinutos_check"
  CHECK ("margenTrasladoMinutos" >= 0 AND "margenTrasladoMinutos" <= 1440);

-- ============================================================
-- Backfill: toda máquina queda con tipo de catálogo, porque las necesidades
-- ahora se expresan por TipoMaquinariaCatalogo (mismo patrón que la
-- migración 20260908150000_inventario_activos_individuales).
-- ============================================================
INSERT INTO "TipoMaquinariaCatalogo"
  ("nombre", "nombreNormalizado", "tipoLegacy", "empresaId", "estadoAprobacion", "aprobadoEn", "actualizadoEn")
SELECT t.nombre,
       lower(regexp_replace(translate(t.nombre, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'), '[^a-zA-Z0-9]+', '', 'g')),
       t."tipo", t."empresaId", 'APROBADA', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM (
  SELECT DISTINCT m."empresaId", m."tipo",
    CASE m."tipo"::text
      WHEN 'CORTASETOS_MANO' THEN 'Cortasetos manual'
      WHEN 'CORTASETOS_ALTURA' THEN 'Cortasetos de altura'
      WHEN 'GUADANIA' THEN 'Guadaña'
      WHEN 'PODADORA_CESPED' THEN 'Podadora de césped'
      WHEN 'HIDROLAVADORA_ELECTRICA' THEN 'Hidrolavadora eléctrica'
      WHEN 'HIDROLAVADORA_GASOLINA' THEN 'Hidrolavadora a gasolina'
      ELSE initcap(replace(m."tipo"::text, '_', ' '))
    END AS nombre
  FROM "Maquinaria" m
  WHERE m."tipoCatalogoId" IS NULL
    AND m."tipo"::text <> 'OTRO'
    AND NOT EXISTS (
      SELECT 1 FROM "TipoMaquinariaCatalogo" c
      WHERE c."empresaId" = m."empresaId" AND c."tipoLegacy" = m."tipo"
    )
) t
ON CONFLICT ("empresaId", "nombreNormalizado") DO NOTHING;

UPDATE "Maquinaria" m
SET "tipoCatalogoId" = (
  SELECT c."id" FROM "TipoMaquinariaCatalogo" c
  WHERE c."empresaId" = m."empresaId" AND c."tipoLegacy" = m."tipo"
  ORDER BY c."fusionadoEnId" NULLS FIRST, c."id"
  LIMIT 1
)
WHERE m."tipoCatalogoId" IS NULL AND m."tipo"::text <> 'OTRO';

