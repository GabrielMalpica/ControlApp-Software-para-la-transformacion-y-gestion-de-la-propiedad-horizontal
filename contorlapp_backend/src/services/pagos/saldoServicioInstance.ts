import { prisma } from "../../db/prisma";
import { CommerceLifecycleService } from "../CommerceLifecycleService";
import { NotificacionService } from "../NotificacionService";
import { pagoService } from "./pagoServiceInstance";
import { SaldoServicioService } from "./SaldoServicioService";

const notificaciones = new NotificacionService(prisma);
const lifecycle = new CommerceLifecycleService(prisma);

/** Instancia compartida por los controllers y por wiring.ts (canal SALDO_SERVICIO). */
export const saldoServicio = new SaldoServicioService(prisma, pagoService, {
  notificarUsuario: ({ usuarioId, ...aviso }) => notificaciones.crearParaUsuarios({ usuarioIds: [usuarioId], ...aviso }),
  alertarEquipo: (titulo, mensaje) => lifecycle.alertarConciliacion(titulo, mensaje),
});
