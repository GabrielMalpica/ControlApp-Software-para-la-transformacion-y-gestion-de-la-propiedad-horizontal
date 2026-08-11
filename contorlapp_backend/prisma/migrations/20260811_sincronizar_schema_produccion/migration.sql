-- Sincroniza produccion con el schema:
-- 1. La columna Usuario.requiereCambioContrasena se anadio al schema sin migracion.
-- 2. El valor 'residente' del enum Rol falta en la base de produccion.
-- NOTA: la tabla "Notificacion" se gestiona fuera de Prisma (bootstrap con SQL crudo
-- en NotificacionService.ts), por lo que NO se incluye su DROP aunque el diff la marque.

-- AlterEnum
ALTER TYPE "Rol" ADD VALUE 'residente';

-- AlterTable
ALTER TABLE "Usuario" ADD COLUMN     "requiereCambioContrasena" BOOLEAN NOT NULL DEFAULT false;
