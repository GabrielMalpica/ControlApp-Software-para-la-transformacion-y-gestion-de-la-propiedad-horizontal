-- Ícono configurable de la categoría de tarea (se muestra en el cronograma
-- junto al color). Null = la app sugiere uno por el nombre de la categoría.
ALTER TABLE "CategoriaTarea" ADD COLUMN "icono" TEXT;
