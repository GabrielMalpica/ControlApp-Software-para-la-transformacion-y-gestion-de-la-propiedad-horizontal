-- Indices faltantes en tablas centrales que hoy hacen full scan (Postgres no
-- crea indices automaticos sobre columnas FK). Puramente aditiva: no toca
-- datos ni columnas existentes.

-- DefinicionTareaPreventiva: usada por estadoBorrador() en cada apertura de
-- la pagina de borrador, filtrando por (conjuntoId, activo).
CREATE INDEX "DefinicionTareaPreventiva_conjuntoId_activo_idx" ON "DefinicionTareaPreventiva"("conjuntoId", "activo");

-- Ubicacion: filtrada por conjuntoId en varias consultas de estructura.
CREATE INDEX "Ubicacion_conjuntoId_idx" ON "Ubicacion"("conjuntoId");

-- Conjunto: filtrada por empresaId en listarConjuntos y reportes.
CREATE INDEX "Conjunto_empresaId_idx" ON "Conjunto"("empresaId");

-- Tarea: cronogramaMensual filtra por (conjuntoId, periodoAnio, periodoMes,
-- borrador); los reportes generales filtran por (borrador, fechaInicio) sin
-- conjuntoId.
CREATE INDEX "Tarea_conjuntoId_periodoAnio_periodoMes_borrador_idx" ON "Tarea"("conjuntoId", "periodoAnio", "periodoMes", "borrador");
CREATE INDEX "Tarea_borrador_fechaInicio_idx" ON "Tarea"("borrador", "fechaInicio");
