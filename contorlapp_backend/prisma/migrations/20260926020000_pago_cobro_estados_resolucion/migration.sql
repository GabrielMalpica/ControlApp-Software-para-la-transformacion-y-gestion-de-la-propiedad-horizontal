-- Cierres manuales de un cobro que quedo pagado pero no se pudo aplicar solo
-- (huerfano, duplicado, discrepancia): el dinero se devolvio, o se resolvio
-- por otra via. Ver PagoAdminService.resolver.
ALTER TYPE "EstadoCobro" ADD VALUE IF NOT EXISTS 'DEVUELTO';
ALTER TYPE "EstadoCobro" ADD VALUE IF NOT EXISTS 'RESUELTO';
