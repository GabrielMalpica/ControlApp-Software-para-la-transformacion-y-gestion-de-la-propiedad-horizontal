import { prisma } from "../../db/prisma";
import { PagoService } from "./PagoService";

// Instancia unica: la comparten las rutas (para registrar el confirmador de
// cada canal, ver CommerceLifecycleController/futuro plugin de WooCommerce)
// y el worker arrancado en index.ts (ver PagoReconciler). Un PagoService por
// request perderia los confirmadores registrados.
export const pagoService = new PagoService(prisma);
