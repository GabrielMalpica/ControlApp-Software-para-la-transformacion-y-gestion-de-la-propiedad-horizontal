import { prisma } from "../../db/prisma";
import { CommerceLifecycleService } from "../CommerceLifecycleService";
import { consultarCobroFactus, isFactusPaySandbox } from "./FactusPayClient";
import { FactusWebhookService } from "./FactusWebhookService";
import { pagoService } from "./pagoServiceInstance";

const lifecycle = new CommerceLifecycleService(prisma);

// Instancia unica: la usan la ruta del webhook (recibir y procesar) y el
// worker (barrerPendientes), ver PagoReconciler.
export const factusWebhook = new FactusWebhookService(
  prisma,
  pagoService,
  consultarCobroFactus,
  (titulo, mensaje) => lifecycle.alertarConciliacion(titulo, mensaje),
  isFactusPaySandbox,
);
