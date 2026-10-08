-- Agenda de recursos: garantía en base de datos de que ninguna reserva queda
-- huérfana cuando una tarea cambia de estado o se elimina, sin importar qué
-- servicio hizo el cambio (cierre de supervisor/operario, aprobación del jefe,
-- reemplazos del generador, updateMany masivos...). Los cambios de FECHA se
-- manejan en la aplicación (ReservaRecursoService.reubicarReservasDeTarea)
-- porque requieren validar disponibilidad y responder 409.

CREATE OR REPLACE FUNCTION "reserva_recurso_sync_estado_tarea"() RETURNS trigger AS $$
DECLARE
  responsables jsonb;
BEGIN
  IF NEW."estado" IS NOT DISTINCT FROM OLD."estado" THEN
    RETURN NEW;
  END IF;

  IF NEW."estado" IN ('NO_COMPLETADA', 'PENDIENTE_REPROGRAMACION') THEN
    UPDATE "ReservaRecurso"
       SET "estado" = 'CANCELADA',
           "motivoCancelacion" = 'La tarea pasó a ' || lower(replace(NEW."estado"::text, '_', ' ')) || '.',
           "canceladoEn" = CURRENT_TIMESTAMP,
           "actualizadoEn" = CURRENT_TIMESTAMP
     WHERE "tareaId" = NEW."id" AND "estado" = 'RESERVADA' AND "tipo" = 'TAREA';

  ELSIF NEW."estado" IN ('COMPLETADA', 'APROBADA', 'PENDIENTE_APROBACION', 'RECHAZADA') THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('operarioId', u."id", 'nombre', u."nombre")), '[]'::jsonb)
      INTO responsables
      FROM "_TareaOperarios" t
      JOIN "Usuario" u ON u."id" = t."A"
     WHERE t."B" = NEW."id";

    UPDATE "ReservaRecurso"
       SET "estado" = 'FINALIZADA',
           "finalizadaEn" = CURRENT_TIMESTAMP,
           "responsablesJson" = responsables,
           "actualizadoEn" = CURRENT_TIMESTAMP
     WHERE "tareaId" = NEW."id" AND "estado" = 'RESERVADA' AND "tipo" = 'TAREA';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "Tarea_reserva_recurso_estado"
AFTER UPDATE OF "estado" ON "Tarea"
FOR EACH ROW
EXECUTE FUNCTION "reserva_recurso_sync_estado_tarea"();

-- Antes de borrar la tarea, sus reservas vigentes se cancelan (la FK
-- tareaId ON DELETE SET NULL conserva la fila con sus snapshots).
CREATE OR REPLACE FUNCTION "reserva_recurso_cancelar_por_borrado"() RETURNS trigger AS $$
BEGIN
  UPDATE "ReservaRecurso"
     SET "estado" = 'CANCELADA',
         "motivoCancelacion" = COALESCE("motivoCancelacion", 'La tarea fue eliminada.'),
         "canceladoEn" = CURRENT_TIMESTAMP,
         "actualizadoEn" = CURRENT_TIMESTAMP
   WHERE "tareaId" = OLD."id" AND "estado" = 'RESERVADA' AND "tipo" = 'TAREA';
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "Tarea_reserva_recurso_borrado"
BEFORE DELETE ON "Tarea"
FOR EACH ROW
EXECUTE FUNCTION "reserva_recurso_cancelar_por_borrado"();
