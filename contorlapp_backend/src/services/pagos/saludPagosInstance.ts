import { prisma } from "../../db/prisma";
import { CommerceLifecycleService } from "../CommerceLifecycleService";
import { SaludPagosService } from "./SaludPagosService";

const lifecycle = new CommerceLifecycleService(prisma);

// Instancia unica: el calendario de PagoService lee su modo (wiring.ts), el
// worker la reevalua (PagoReconciler) y el panel muestra su resumen.
export const saludPagos = new SaludPagosService(prisma, (titulo, mensaje) =>
  lifecycle.alertarConciliacion(titulo, mensaje),
);
