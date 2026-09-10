-- Estados de inventario y aprobacion.
ALTER TYPE "public"."EstadoMaquinaria" ADD VALUE IF NOT EXISTS 'EN_MANTENIMIENTO';
ALTER TYPE "public"."EstadoMaquinaria" ADD VALUE IF NOT EXISTS 'DANADA';
ALTER TYPE "public"."EstadoMaquinaria" ADD VALUE IF NOT EXISTS 'PERDIDA';
ALTER TYPE "public"."EstadoMaquinaria" ADD VALUE IF NOT EXISTS 'RETIRADA';
ALTER TYPE "public"."EstadoHerramienta" ADD VALUE IF NOT EXISTS 'EN_MANTENIMIENTO';
ALTER TYPE "public"."EstadoHerramienta" ADD VALUE IF NOT EXISTS 'FUERA_DE_SERVICIO';
ALTER TYPE "public"."EstadoHerramienta" ADD VALUE IF NOT EXISTS 'RETIRADA';
CREATE TYPE "public"."EstadoAprobacionActivo" AS ENUM ('PENDIENTE', 'APROBADA', 'RECHAZADA');

-- La empresa se identifica por NIT (texto), no por entero.
ALTER TABLE "public"."AuditoriaEvento"
ALTER COLUMN "empresaId" TYPE TEXT USING "empresaId"::TEXT;
CREATE INDEX "AUD_empresa_entidad_idx"
  ON "public"."AuditoriaEvento"("empresaId", "modulo", "entidad", "entidadId");

CREATE TABLE "public"."TipoMaquinariaCatalogo" (
  "id" SERIAL NOT NULL,
  "nombre" TEXT NOT NULL,
  "nombreNormalizado" TEXT NOT NULL,
  "tipoLegacy" "public"."TipoMaquinaria",
  "activo" BOOLEAN NOT NULL DEFAULT true,
  "empresaId" TEXT NOT NULL,
  "estadoAprobacion" "public"."EstadoAprobacionActivo" NOT NULL DEFAULT 'APROBADA',
  "creadoPorId" TEXT,
  "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "aprobadoPorId" TEXT,
  "aprobadoEn" TIMESTAMP(3),
  "rechazadoPorId" TEXT,
  "rechazadoEn" TIMESTAMP(3),
  "motivoRechazo" TEXT,
  "actualizadoPorId" TEXT,
  "actualizadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "fusionadoEnId" INTEGER,
  CONSTRAINT "TipoMaquinariaCatalogo_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "TipoMaquinariaCatalogo_empresaId_nombreNormalizado_key"
  ON "public"."TipoMaquinariaCatalogo"("empresaId", "nombreNormalizado");

ALTER TABLE "public"."Herramienta"
  ADD COLUMN "nombreNormalizado" TEXT,
  ADD COLUMN "activo" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "estadoAprobacion" "public"."EstadoAprobacionActivo" NOT NULL DEFAULT 'APROBADA',
  ADD COLUMN "creadoPorId" TEXT,
  ADD COLUMN "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "aprobadoPorId" TEXT,
  ADD COLUMN "aprobadoEn" TIMESTAMP(3),
  ADD COLUMN "rechazadoPorId" TEXT,
  ADD COLUMN "rechazadoEn" TIMESTAMP(3),
  ADD COLUMN "motivoRechazo" TEXT,
  ADD COLUMN "actualizadoPorId" TEXT,
  ADD COLUMN "actualizadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "canonicaId" INTEGER;

ALTER TABLE "public"."Maquinaria"
  ADD COLUMN "tipoCatalogoId" INTEGER,
  ADD COLUMN "codigoInterno" TEXT,
  ADD COLUMN "alias" TEXT,
  ADD COLUMN "modelo" TEXT,
  ADD COLUMN "serial" TEXT,
  ADD COLUMN "estadoAprobacion" "public"."EstadoAprobacionActivo" NOT NULL DEFAULT 'APROBADA',
  ADD COLUMN "registroLoteId" TEXT,
  ADD COLUMN "creadoPorId" TEXT,
  ADD COLUMN "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "aprobadoPorId" TEXT,
  ADD COLUMN "aprobadoEn" TIMESTAMP(3),
  ADD COLUMN "rechazadoPorId" TEXT,
  ADD COLUMN "rechazadoEn" TIMESTAMP(3),
  ADD COLUMN "motivoRechazo" TEXT,
  ADD COLUMN "actualizadoPorId" TEXT,
  ADD COLUMN "actualizadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "retiradoPorId" TEXT,
  ADD COLUMN "retiradoEn" TIMESTAMP(3),
  ADD COLUMN "fotoDriveId" TEXT,
  ADD COLUMN "fotoNombre" TEXT,
  ADD COLUMN "fotoMimeType" TEXT,
  ADD COLUMN "fotoTamano" INTEGER,
  ADD COLUMN "fotoActualizadaEn" TIMESTAMP(3);

CREATE TABLE "public"."HerramientaItem" (
  "id" SERIAL NOT NULL,
  "codigoInterno" TEXT NOT NULL,
  "alias" TEXT,
  "marca" TEXT,
  "modelo" TEXT,
  "serial" TEXT,
  "empresaId" TEXT NOT NULL,
  "herramientaId" INTEGER NOT NULL,
  "propietarioTipo" "public"."PropietarioMaquinaria" NOT NULL,
  "conjuntoPropietarioId" TEXT,
  "estado" "public"."EstadoHerramienta" NOT NULL DEFAULT 'OPERATIVA',
  "estadoAprobacion" "public"."EstadoAprobacionActivo" NOT NULL DEFAULT 'PENDIENTE',
  "registroLoteId" TEXT,
  "creadoPorId" TEXT,
  "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "aprobadoPorId" TEXT,
  "aprobadoEn" TIMESTAMP(3),
  "rechazadoPorId" TEXT,
  "rechazadoEn" TIMESTAMP(3),
  "motivoRechazo" TEXT,
  "actualizadoPorId" TEXT,
  "actualizadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "retiradoPorId" TEXT,
  "retiradoEn" TIMESTAMP(3),
  "fotoDriveId" TEXT,
  "fotoNombre" TEXT,
  "fotoMimeType" TEXT,
  "fotoTamano" INTEGER,
  "fotoActualizadaEn" TIMESTAMP(3),
  CONSTRAINT "HerramientaItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "public"."HerramientaItemConjunto" (
  "id" SERIAL NOT NULL,
  "herramientaItemId" INTEGER NOT NULL,
  "conjuntoId" TEXT NOT NULL,
  "fechaInicio" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "fechaFin" TIMESTAMP(3),
  "fechaDevolucionEstimada" TIMESTAMP(3),
  "estado" "public"."EstadoAsignacionMaquinaria" NOT NULL DEFAULT 'ACTIVA',
  "responsableId" TEXT,
  "tareaId" INTEGER,
  "creadoPorId" TEXT,
  "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "HerramientaItemConjunto_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "public"."UsoHerramienta" ADD COLUMN "herramientaItemId" INTEGER;

ALTER TABLE "public"."TipoMaquinariaCatalogo" ADD CONSTRAINT "TipoMaquinariaCatalogo_empresaId_fkey"
  FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "public"."TipoMaquinariaCatalogo" ADD CONSTRAINT "TipoMaquinariaCatalogo_fusionadoEnId_fkey"
  FOREIGN KEY ("fusionadoEnId") REFERENCES "public"."TipoMaquinariaCatalogo"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "public"."Herramienta" ADD CONSTRAINT "Herramienta_canonicaId_fkey"
  FOREIGN KEY ("canonicaId") REFERENCES "public"."Herramienta"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "public"."Maquinaria" ADD CONSTRAINT "Maquinaria_tipoCatalogoId_fkey"
  FOREIGN KEY ("tipoCatalogoId") REFERENCES "public"."TipoMaquinariaCatalogo"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "public"."HerramientaItem" ADD CONSTRAINT "HerramientaItem_empresaId_fkey"
  FOREIGN KEY ("empresaId") REFERENCES "public"."Empresa"("nit") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "public"."HerramientaItem" ADD CONSTRAINT "HerramientaItem_herramientaId_fkey"
  FOREIGN KEY ("herramientaId") REFERENCES "public"."Herramienta"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "public"."HerramientaItem" ADD CONSTRAINT "HerramientaItem_conjuntoPropietarioId_fkey"
  FOREIGN KEY ("conjuntoPropietarioId") REFERENCES "public"."Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "public"."HerramientaItemConjunto" ADD CONSTRAINT "HerramientaItemConjunto_herramientaItemId_fkey"
  FOREIGN KEY ("herramientaItemId") REFERENCES "public"."HerramientaItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "public"."HerramientaItemConjunto" ADD CONSTRAINT "HerramientaItemConjunto_conjuntoId_fkey"
  FOREIGN KEY ("conjuntoId") REFERENCES "public"."Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "public"."UsoHerramienta" ADD CONSTRAINT "UsoHerramienta_herramientaItemId_fkey"
  FOREIGN KEY ("herramientaItemId") REFERENCES "public"."HerramientaItem"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- El NIT de empresa de maquinaria se completa desde su conjunto propietario cuando haga falta.
UPDATE "public"."Maquinaria" m
SET "empresaId" = c."empresaId"
FROM "public"."Conjunto" c
WHERE m."empresaId" IS NULL AND m."conjuntoPropietarioId" = c."nit";

WITH empresa_por_historial AS (
  SELECT mc."maquinariaId", min(c."empresaId") AS "empresaId"
  FROM "public"."MaquinariaConjunto" mc
  JOIN "public"."Conjunto" c ON c."nit" = mc."conjuntoId"
  WHERE c."empresaId" IS NOT NULL
  GROUP BY mc."maquinariaId"
  HAVING count(DISTINCT c."empresaId") = 1
)
UPDATE "public"."Maquinaria" m
SET "empresaId" = h."empresaId"
FROM empresa_por_historial h
WHERE m."empresaId" IS NULL AND m.id = h."maquinariaId";

-- Catálogo canónico de los tipos de maquinaria ya existentes. El nombre se
-- normaliza con la misma regla que usa la API, de modo que "Guadaña" y
-- "guadana" no puedan convertirse después en tipos diferentes.
WITH tipos_existentes AS (
  SELECT DISTINCT
    m."empresaId",
    m."tipo",
    CASE m."tipo"::text
      WHEN 'CORTASETOS_MANO' THEN 'Cortasetos manual'
      WHEN 'CORTASETOS_ALTURA' THEN 'Cortasetos de altura'
      WHEN 'GUADANIA' THEN 'Guadaña'
      WHEN 'PODADORA_CESPED' THEN 'Podadora de césped'
      WHEN 'HIDROLAVADORA_ELECTRICA' THEN 'Hidrolavadora eléctrica'
      WHEN 'HIDROLAVADORA_GASOLINA' THEN 'Hidrolavadora a gasolina'
      ELSE initcap(replace(m."tipo"::text, '_', ' '))
    END AS nombre
  FROM "public"."Maquinaria" m
  WHERE m."empresaId" IS NOT NULL AND m."tipo"::text <> 'OTRO'
)
INSERT INTO "public"."TipoMaquinariaCatalogo"
  ("nombre", "nombreNormalizado", "tipoLegacy", "empresaId", "estadoAprobacion", "aprobadoEn")
SELECT t.nombre,
       lower(regexp_replace(translate(t.nombre, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'), '[^a-zA-Z0-9]+', '', 'g')),
       t."tipo", t."empresaId", 'APROBADA', CURRENT_TIMESTAMP
FROM tipos_existentes t
ON CONFLICT ("empresaId", "nombreNormalizado") DO NOTHING;

INSERT INTO "public"."TipoMaquinariaCatalogo"
  ("nombre", "nombreNormalizado", "tipoLegacy", "empresaId", "estadoAprobacion", "aprobadoEn")
SELECT min(m."nombre"),
       lower(regexp_replace(translate(m."nombre", 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'), '[^a-zA-Z0-9]+', '', 'g')),
       'OTRO', m."empresaId", 'APROBADA', CURRENT_TIMESTAMP
FROM "public"."Maquinaria" m
WHERE m."empresaId" IS NOT NULL AND m."tipo"::text = 'OTRO'
GROUP BY m."empresaId", lower(regexp_replace(translate(m."nombre", 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'), '[^a-zA-Z0-9]+', '', 'g'))
ON CONFLICT ("empresaId", "nombreNormalizado") DO NOTHING;

UPDATE "public"."Maquinaria" m
SET "tipoCatalogoId" = c."id"
FROM "public"."TipoMaquinariaCatalogo" c
WHERE c."empresaId" = m."empresaId"
  AND ((m."tipo"::text <> 'OTRO' AND c."tipoLegacy" = m."tipo")
    OR (m."tipo"::text = 'OTRO' AND c."nombreNormalizado" = lower(regexp_replace(translate(m."nombre", 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'), '[^a-zA-Z0-9]+', '', 'g'))));

UPDATE "public"."Maquinaria"
SET "codigoInterno" = 'MAQ-' || lpad("id"::text, 6, '0'),
    "estadoAprobacion" = 'APROBADA',
    "aprobadoEn" = COALESCE("aprobadoEn", CURRENT_TIMESTAMP);

-- Las variantes de mayúsculas/espaciado quedan como alias del ID menor.
WITH ranked AS (
  SELECT id,
         first_value(id) OVER (PARTITION BY "empresaId", lower(regexp_replace(translate("nombre", 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'), '[^a-zA-Z0-9]+', '', 'g')) ORDER BY id) AS canonical_id,
         lower(regexp_replace(translate("nombre", 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'), '[^a-zA-Z0-9]+', '', 'g')) AS normalized
  FROM "public"."Herramienta"
)
UPDATE "public"."Herramienta" h
SET "nombreNormalizado" = r.normalized,
    "canonicaId" = CASE WHEN r.id = r.canonical_id THEN NULL ELSE r.canonical_id END,
    "activo" = r.id = r.canonical_id,
    "estadoAprobacion" = 'APROBADA',
    "aprobadoEn" = CURRENT_TIMESTAMP
FROM ranked r WHERE h.id = r.id;

-- Consolida las cantidades de catálogos alias antes de crear las unidades
-- físicas. El alias se conserva para trazabilidad, pero las relaciones pasan a
-- la herramienta canónica y no quedan dos nombres para el mismo tipo.
INSERT INTO "public"."EmpresaHerramientaStock"
  ("empresaId", "herramientaId", "cantidad", "estado", "actualizadoEn")
SELECT s."empresaId", h."canonicaId", sum(s."cantidad"), s."estado", CURRENT_TIMESTAMP
FROM "public"."EmpresaHerramientaStock" s
JOIN "public"."Herramienta" h ON h.id = s."herramientaId"
WHERE h."canonicaId" IS NOT NULL
GROUP BY s."empresaId", h."canonicaId", s."estado"
ON CONFLICT ("empresaId", "herramientaId", "estado") DO UPDATE
SET "cantidad" = "EmpresaHerramientaStock"."cantidad" + EXCLUDED."cantidad",
    "actualizadoEn" = CURRENT_TIMESTAMP;
DELETE FROM "public"."EmpresaHerramientaStock" s
USING "public"."Herramienta" h
WHERE h.id = s."herramientaId" AND h."canonicaId" IS NOT NULL;

INSERT INTO "public"."ConjuntoHerramientaStock"
  ("conjuntoId", "herramientaId", "cantidad", "estado", "actualizadoEn")
SELECT s."conjuntoId", h."canonicaId", sum(s."cantidad"), s."estado", CURRENT_TIMESTAMP
FROM "public"."ConjuntoHerramientaStock" s
JOIN "public"."Herramienta" h ON h.id = s."herramientaId"
WHERE h."canonicaId" IS NOT NULL
GROUP BY s."conjuntoId", h."canonicaId", s."estado"
ON CONFLICT ("conjuntoId", "herramientaId", "estado") DO UPDATE
SET "cantidad" = "ConjuntoHerramientaStock"."cantidad" + EXCLUDED."cantidad",
    "actualizadoEn" = CURRENT_TIMESTAMP;
DELETE FROM "public"."ConjuntoHerramientaStock" s
USING "public"."Herramienta" h
WHERE h.id = s."herramientaId" AND h."canonicaId" IS NOT NULL;

INSERT INTO "public"."SolicitudHerramientaItem"
  ("solicitudId", "herramientaId", "cantidad")
SELECT s."solicitudId", h."canonicaId", sum(s."cantidad")
FROM "public"."SolicitudHerramientaItem" s
JOIN "public"."Herramienta" h ON h.id = s."herramientaId"
WHERE h."canonicaId" IS NOT NULL
GROUP BY s."solicitudId", h."canonicaId"
ON CONFLICT ("solicitudId", "herramientaId") DO UPDATE
SET "cantidad" = "SolicitudHerramientaItem"."cantidad" + EXCLUDED."cantidad";
DELETE FROM "public"."SolicitudHerramientaItem" s
USING "public"."Herramienta" h
WHERE h.id = s."herramientaId" AND h."canonicaId" IS NOT NULL;

UPDATE "public"."PrestamoHerramientaConjunto" p
SET "herramientaId" = h."canonicaId"
FROM "public"."Herramienta" h
WHERE h.id = p."herramientaId" AND h."canonicaId" IS NOT NULL;

UPDATE "public"."UsoHerramienta" u
SET "herramientaId" = h."canonicaId"
FROM "public"."Herramienta" h
WHERE h.id = u."herramientaId" AND h."canonicaId" IS NOT NULL;

-- Cada unidad de stock positivo se convierte en un item físico aprobado.
-- Se aborta ante cantidades fraccionarias para no redondear ni perder inventario.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM "public"."EmpresaHerramientaStock"
    WHERE "cantidad" > 0 AND "cantidad" <> trunc("cantidad")
    UNION ALL
    SELECT 1 FROM "public"."ConjuntoHerramientaStock"
    WHERE "cantidad" > 0 AND "cantidad" <> trunc("cantidad")
    UNION ALL
    SELECT 1 FROM "public"."PrestamoHerramientaConjunto"
    WHERE "fechaFin" IS NULL AND "cantidad" > 0
      AND "cantidad" <> trunc("cantidad")
  ) THEN
    RAISE EXCEPTION 'No se puede migrar stock fraccionario de herramientas a unidades físicas.';
  END IF;
END $$;
INSERT INTO "public"."HerramientaItem"
  ("codigoInterno", "empresaId", "herramientaId", "propietarioTipo", "estado", "estadoAprobacion", "registroLoteId", "creadoEn", "aprobadoEn")
SELECT 'HER-E-' || s.id::text || '-' || gs::text,
       s."empresaId", COALESCE(h."canonicaId", h.id), 'EMPRESA', s."estado", 'APROBADA',
       'MIG-EMPRESA-' || s.id::text, s."actualizadoEn", CURRENT_TIMESTAMP
FROM "public"."EmpresaHerramientaStock" s
JOIN "public"."Herramienta" h ON h.id = s."herramientaId"
CROSS JOIN LATERAL generate_series(1, floor(s."cantidad")::integer) gs
WHERE s."cantidad" > 0;

INSERT INTO "public"."HerramientaItem"
  ("codigoInterno", "empresaId", "herramientaId", "propietarioTipo", "conjuntoPropietarioId", "estado", "estadoAprobacion", "registroLoteId", "creadoEn", "aprobadoEn")
SELECT 'HER-C-' || s.id::text || '-' || gs::text,
       c."empresaId", COALESCE(h."canonicaId", h.id), 'CONJUNTO', s."conjuntoId", s."estado", 'APROBADA',
       'MIG-CONJUNTO-' || s.id::text, s."actualizadoEn", CURRENT_TIMESTAMP
FROM "public"."ConjuntoHerramientaStock" s
JOIN "public"."Conjunto" c ON c."nit" = s."conjuntoId"
JOIN "public"."Herramienta" h ON h.id = s."herramientaId"
CROSS JOIN LATERAL generate_series(1, floor(s."cantidad")::integer) gs
WHERE s."cantidad" > 0 AND c."empresaId" IS NOT NULL;

-- Los préstamos activos ya fueron descontados del stock empresarial legacy.
-- Se materializan como unidades empresariales adicionales y se conserva su custodia.
INSERT INTO "public"."HerramientaItem"
  ("codigoInterno", "empresaId", "herramientaId", "propietarioTipo", "estado", "estadoAprobacion", "registroLoteId", "creadoEn", "aprobadoEn")
SELECT 'HER-P-' || p.id::text || '-' || gs::text,
       p."empresaId", COALESCE(h."canonicaId", h.id), 'EMPRESA', p."estado", 'APROBADA',
       'MIG-PRESTAMO-' || p.id::text, p."fechaInicio", CURRENT_TIMESTAMP
FROM "public"."PrestamoHerramientaConjunto" p
JOIN "public"."Herramienta" h ON h.id = p."herramientaId"
CROSS JOIN LATERAL generate_series(1, floor(p."cantidad")::integer) gs
WHERE p."fechaFin" IS NULL AND p."cantidad" > 0;

INSERT INTO "public"."HerramientaItemConjunto"
  ("herramientaItemId", "conjuntoId", "fechaInicio", "fechaDevolucionEstimada", "estado", "creadoEn")
SELECT i.id, p."conjuntoId", p."fechaInicio", p."fechaDevolucionEstimada", 'ACTIVA', p."fechaInicio"
FROM "public"."PrestamoHerramientaConjunto" p
JOIN "public"."HerramientaItem" i
  ON i."registroLoteId" = 'MIG-PRESTAMO-' || p.id::text
WHERE p."fechaFin" IS NULL AND p."cantidad" > 0;

CREATE INDEX "TipoMaquinariaCatalogo_empresa_activo_aprobacion_idx"
  ON "public"."TipoMaquinariaCatalogo"("empresaId", "activo", "estadoAprobacion");
CREATE UNIQUE INDEX "Herramienta_canonica_nombre_normalizado_key"
  ON "public"."Herramienta"("empresaId", "nombreNormalizado") WHERE "canonicaId" IS NULL AND "activo" = true;
CREATE INDEX "Herramienta_empresa_nombre_normalizado_idx" ON "public"."Herramienta"("empresaId", "nombreNormalizado");
CREATE INDEX "Herramienta_empresa_activo_aprobacion_idx" ON "public"."Herramienta"("empresaId", "activo", "estadoAprobacion");
CREATE UNIQUE INDEX "Maquinaria_empresa_codigo_key" ON "public"."Maquinaria"("empresaId", "codigoInterno");
CREATE INDEX "Maquinaria_empresa_tipo_aprobacion_estado_idx" ON "public"."Maquinaria"("empresaId", "tipoCatalogoId", "estadoAprobacion", "estado");
CREATE INDEX "Maquinaria_conjunto_aprobacion_estado_idx" ON "public"."Maquinaria"("conjuntoPropietarioId", "estadoAprobacion", "estado");
CREATE INDEX "Maquinaria_registro_lote_idx" ON "public"."Maquinaria"("registroLoteId");
CREATE UNIQUE INDEX "HerramientaItem_empresa_codigo_key" ON "public"."HerramientaItem"("empresaId", "codigoInterno");
CREATE INDEX "HerramientaItem_empresa_catalogo_aprobacion_estado_idx" ON "public"."HerramientaItem"("empresaId", "herramientaId", "estadoAprobacion", "estado");
CREATE INDEX "HerramientaItem_conjunto_aprobacion_estado_idx" ON "public"."HerramientaItem"("conjuntoPropietarioId", "estadoAprobacion", "estado");
CREATE INDEX "HerramientaItem_lote_idx" ON "public"."HerramientaItem"("registroLoteId");
CREATE INDEX "HerramientaItemConjunto_item_estado_idx" ON "public"."HerramientaItemConjunto"("herramientaItemId", "estado");
CREATE INDEX "HerramientaItemConjunto_conjunto_estado_idx" ON "public"."HerramientaItemConjunto"("conjuntoId", "estado");
CREATE INDEX "HerramientaItemConjunto_tarea_idx" ON "public"."HerramientaItemConjunto"("tareaId");
CREATE UNIQUE INDEX "HerramientaItemConjunto_activa_unica_idx"
  ON "public"."HerramientaItemConjunto"("herramientaItemId") WHERE "estado" IN ('RESERVADA', 'ACTIVA');
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "public"."MaquinariaConjunto"
    WHERE "estado" IN ('RESERVADA', 'ACTIVA')
    GROUP BY "maquinariaId"
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Hay maquinaria con más de una asignación activa o reservada; corrige esas asignaciones antes de migrar.';
  END IF;
END $$;
DROP INDEX IF EXISTS "public"."MaquinariaConjunto_conjuntoId_maquinariaId_estado_key";
CREATE UNIQUE INDEX "MaquinariaConjunto_activa_unica_idx"
  ON "public"."MaquinariaConjunto"("maquinariaId") WHERE "estado" IN ('RESERVADA', 'ACTIVA');
CREATE INDEX "UsoHerramienta_herramientaItemId_idx" ON "public"."UsoHerramienta"("herramientaItemId");

-- Corrige filas legacy imposibles sin descartar el activo y deja un evento
-- explícito. Si decía EMPRESA prevalece ese dueño y se limpia el conjunto
-- accidental; si decía CONJUNTO pero no tenía conjunto identificable, queda
-- temporalmente como inventario general de empresa.
INSERT INTO "public"."AuditoriaEvento"
  ("empresaId", "conjuntoId", "modulo", "entidad", "entidadId", "accion", "origen", "descripcion", "datosAntes")
SELECT m."empresaId", m."conjuntoPropietarioId", 'INVENTARIO_MAQUINARIA', 'Maquinaria', m.id::text,
       'NORMALIZAR_PROPIETARIO_MIGRACION', 'MIGRACION',
       'Se normalizó una combinación legacy inconsistente de propietario y conjunto.',
       jsonb_build_object('propietarioTipo', m."propietarioTipo", 'conjuntoPropietarioId', m."conjuntoPropietarioId")
FROM "public"."Maquinaria" m
WHERE (m."propietarioTipo" = 'EMPRESA' AND m."conjuntoPropietarioId" IS NOT NULL)
   OR (m."propietarioTipo" = 'CONJUNTO' AND m."conjuntoPropietarioId" IS NULL);

UPDATE "public"."Maquinaria"
SET "conjuntoPropietarioId" = NULL
WHERE "propietarioTipo" = 'EMPRESA' AND "conjuntoPropietarioId" IS NOT NULL;
UPDATE "public"."Maquinaria"
SET "propietarioTipo" = 'EMPRESA'
WHERE "propietarioTipo" = 'CONJUNTO' AND "conjuntoPropietarioId" IS NULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "public"."Maquinaria" WHERE "empresaId" IS NULL) THEN
    RAISE EXCEPTION 'Hay maquinaria sin empresa identificable; asigna su empresa antes de migrar.';
  END IF;
END $$;
ALTER TABLE "public"."Maquinaria" ALTER COLUMN "empresaId" SET NOT NULL;

ALTER TABLE "public"."Maquinaria" ADD CONSTRAINT "Maquinaria_propietario_check"
  CHECK (("propietarioTipo" = 'EMPRESA' AND "conjuntoPropietarioId" IS NULL)
      OR ("propietarioTipo" = 'CONJUNTO' AND "conjuntoPropietarioId" IS NOT NULL));
ALTER TABLE "public"."HerramientaItem" ADD CONSTRAINT "HerramientaItem_propietario_check"
  CHECK (("propietarioTipo" = 'EMPRESA' AND "conjuntoPropietarioId" IS NULL)
      OR ("propietarioTipo" = 'CONJUNTO' AND "conjuntoPropietarioId" IS NOT NULL));
