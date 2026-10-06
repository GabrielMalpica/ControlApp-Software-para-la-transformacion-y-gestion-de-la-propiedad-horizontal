-- AlterTable
ALTER TABLE "ConjuntoNecesidadOperario" ADD COLUMN     "perfilId" INTEGER;

-- AlterTable
ALTER TABLE "DefinicionTareaPreventiva" ADD COLUMN     "categoriaId" INTEGER,
ADD COLUMN     "ordenEnCategoria" INTEGER;

-- AlterTable
ALTER TABLE "Tarea" ADD COLUMN     "categoriaId" INTEGER,
ADD COLUMN     "necesidadPrevistaId" INTEGER,
ADD COLUMN     "ordenEnCategoria" INTEGER,
ADD COLUMN     "reasignadaAutomaticamente" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "CategoriaTarea" (
    "id" SERIAL NOT NULL,
    "empresaId" TEXT NOT NULL,
    "nombre" TEXT NOT NULL,
    "ordenProgramacion" INTEGER NOT NULL DEFAULT 100,
    "colorHex" TEXT,
    "palabrasClave" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "activa" BOOLEAN NOT NULL DEFAULT true,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CategoriaTarea_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PerfilOperativo" (
    "id" SERIAL NOT NULL,
    "empresaId" TEXT NOT NULL,
    "nombre" TEXT NOT NULL,
    "roles" "TipoFuncion"[],
    "descripcion" TEXT,
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PerfilOperativo_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PerfilOperativoCategoria" (
    "perfilId" INTEGER NOT NULL,
    "categoriaId" INTEGER NOT NULL,

    CONSTRAINT "PerfilOperativoCategoria_pkey" PRIMARY KEY ("perfilId","categoriaId")
);

-- CreateIndex
CREATE INDEX "CategoriaTarea_empresaId_activa_ordenProgramacion_idx" ON "CategoriaTarea"("empresaId", "activa", "ordenProgramacion");

-- CreateIndex
CREATE UNIQUE INDEX "CategoriaTarea_empresaId_nombre_key" ON "CategoriaTarea"("empresaId", "nombre");

-- CreateIndex
CREATE INDEX "PerfilOperativo_empresaId_activo_idx" ON "PerfilOperativo"("empresaId", "activo");

-- CreateIndex
CREATE UNIQUE INDEX "PerfilOperativo_empresaId_nombre_key" ON "PerfilOperativo"("empresaId", "nombre");

-- CreateIndex
CREATE INDEX "PerfilOperativoCategoria_categoriaId_idx" ON "PerfilOperativoCategoria"("categoriaId");

-- CreateIndex
CREATE INDEX "ConjuntoNecesidadOperario_perfilId_idx" ON "ConjuntoNecesidadOperario"("perfilId");

-- CreateIndex
CREATE INDEX "DefinicionTareaPreventiva_categoriaId_idx" ON "DefinicionTareaPreventiva"("categoriaId");

-- AddForeignKey
ALTER TABLE "ConjuntoNecesidadOperario" ADD CONSTRAINT "ConjuntoNecesidadOperario_perfilId_fkey" FOREIGN KEY ("perfilId") REFERENCES "PerfilOperativo"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CategoriaTarea" ADD CONSTRAINT "CategoriaTarea_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PerfilOperativo" ADD CONSTRAINT "PerfilOperativo_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PerfilOperativoCategoria" ADD CONSTRAINT "PerfilOperativoCategoria_perfilId_fkey" FOREIGN KEY ("perfilId") REFERENCES "PerfilOperativo"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PerfilOperativoCategoria" ADD CONSTRAINT "PerfilOperativoCategoria_categoriaId_fkey" FOREIGN KEY ("categoriaId") REFERENCES "CategoriaTarea"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_categoriaId_fkey" FOREIGN KEY ("categoriaId") REFERENCES "CategoriaTarea"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


-- ============================================================
-- Datos iniciales (idempotentes, sin tocar datos existentes)
-- ============================================================

-- 1) Categorías por defecto para cada empresa, en el orden operativo pedido.
INSERT INTO "CategoriaTarea" ("empresaId", "nombre", "ordenProgramacion", "colorHex", "palabrasClave", "actualizadoEn")
SELECT e."nit", c."nombre", c."orden", c."color", c."claves", CURRENT_TIMESTAMP
FROM "Empresa" e
CROSS JOIN (VALUES
  ('Mantenimiento de piscinas', 1, '#0288D1', ARRAY['piscin','shock','choque','choke','aspir','clorar','cloro','vidrios de encerramiento','parametros','cepillar paredes y fondo']),
  ('Poda', 2, '#558B2F', ARRAY['poda','podar','deshierb','deshoj','cesped','corte de']),
  ('Jardinería', 3, '#2E7D32', ARRAY['jardin','riego','fertiliz','herbicida','plaga','matera','zona verde','zonas verdes','maleza']),
  ('Aseo', 4, '#8E24AA', ARRAY['aseo','barr','trape','limpi','lav','desinfec','despapel','shut','vaciar','retirar residuos','recoger residuos','cepill','desempolv']),
  ('Mantenimientos básicos', 5, '#EF6C00', ARRAY['mantenimiento general','inspecc','revis','verific','extintor','repar']),
  ('Salvamento acuático', 6, '#D32F2F', ARRAY['salvavidas','salvamento']),
  ('Actividades de supervisión', 7, '#455A64', ARRAY['supervis'])
) AS c("nombre", "orden", "color", "claves")
ON CONFLICT ("empresaId", "nombre") DO NOTHING;

-- 2) Un perfil por cada combinación distinta de roles de las plazas
--    existentes (nombre = roles en orden del enum, p.ej. "Todero-Salvavidas").
--    Quedan SIN categorías: las capacidades las configura el usuario.
INSERT INTO "PerfilOperativo" ("empresaId", "nombre", "roles", "actualizadoEn")
SELECT DISTINCT p."empresaId", p."nombre", p."roles", CURRENT_TIMESTAMP
FROM (
  SELECT c."empresaId" AS "empresaId",
         (SELECT array_agg(r ORDER BY r) FROM unnest(n."roles") AS r) AS "roles",
         (SELECT string_agg(
                   CASE r::text WHEN 'TODERO' THEN 'Todero' WHEN 'SALVAVIDAS' THEN 'Salvavidas'
                                WHEN 'ASEO' THEN 'Aseo' WHEN 'PISCINERO' THEN 'Piscinero'
                                WHEN 'JARDINERO' THEN 'Jardinero' ELSE r::text END,
                   '-' ORDER BY r)
            FROM unnest(n."roles") AS r) AS "nombre"
  FROM "ConjuntoNecesidadOperario" n
  JOIN "Conjunto" c ON c."nit" = n."conjuntoId"
  WHERE c."empresaId" IS NOT NULL AND cardinality(n."roles") > 0
) p
ON CONFLICT ("empresaId", "nombre") DO NOTHING;

-- 3) Enlaza cada plaza con el perfil de su combinación de roles.
UPDATE "ConjuntoNecesidadOperario" n
SET "perfilId" = pf."id"
FROM "Conjunto" c, "PerfilOperativo" pf
WHERE c."nit" = n."conjuntoId"
  AND pf."empresaId" = c."empresaId"
  AND n."perfilId" IS NULL
  AND cardinality(n."roles") > 0
  AND pf."roles" = (SELECT array_agg(r ORDER BY r) FROM unnest(n."roles") AS r);
