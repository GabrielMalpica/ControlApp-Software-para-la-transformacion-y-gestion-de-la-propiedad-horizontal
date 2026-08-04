-- La definicion preventiva pasa a declarar la NECESIDAD de maquinaria (tipo + cantidad)
-- en lugar de una maquina concreta. La maquina que se venia usando se conserva como
-- sugerencia para preseleccionarla en el cronograma de maquinaria.
--
-- Antes:   [{ "maquinariaId": 12, "cantidad": 1 }]
-- Despues: [{ "tipo": "GUADANIA", "cantidad": 1, "maquinariaSugeridaId": 12 }]
--
-- Los items cuya maquina ya no exista quedan sin "tipo" y el parser los descarta:
-- hoy tampoco reservaban nada.

UPDATE "DefinicionTareaPreventiva" d
SET "maquinariaPlanJson" = s.nuevo
FROM (
  SELECT d2.id,
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'tipo',                 COALESCE(item->>'tipo', m."tipo"::text),
           'cantidad',             COALESCE(NULLIF(item->>'cantidad', '')::numeric, 1),
           'maquinariaSugeridaId', COALESCE(
                                     NULLIF(item->>'maquinariaSugeridaId', '')::int,
                                     NULLIF(item->>'maquinariaId', '')::int
                                   )
         ))) AS nuevo
  FROM "DefinicionTareaPreventiva" d2
  CROSS JOIN LATERAL jsonb_array_elements(d2."maquinariaPlanJson") AS item
  LEFT JOIN "Maquinaria" m ON m.id = NULLIF(item->>'maquinariaId', '')::int
  WHERE jsonb_typeof(d2."maquinariaPlanJson") = 'array'
  GROUP BY d2.id
) s
WHERE d.id = s.id;

UPDATE "Tarea" t
SET "maquinariaPlanJson" = s.nuevo
FROM (
  SELECT t2.id,
         jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'tipo',                 COALESCE(item->>'tipo', m."tipo"::text),
           'cantidad',             COALESCE(NULLIF(item->>'cantidad', '')::numeric, 1),
           'maquinariaSugeridaId', COALESCE(
                                     NULLIF(item->>'maquinariaSugeridaId', '')::int,
                                     NULLIF(item->>'maquinariaId', '')::int
                                   )
         ))) AS nuevo
  FROM "Tarea" t2
  CROSS JOIN LATERAL jsonb_array_elements(t2."maquinariaPlanJson") AS item
  LEFT JOIN "Maquinaria" m ON m.id = NULLIF(item->>'maquinariaId', '')::int
  WHERE jsonb_typeof(t2."maquinariaPlanJson") = 'array'
  GROUP BY t2.id
) s
WHERE t.id = s.id;
