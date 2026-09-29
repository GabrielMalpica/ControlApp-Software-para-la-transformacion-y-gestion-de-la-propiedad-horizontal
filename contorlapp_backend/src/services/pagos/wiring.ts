import { CanalPago } from "@prisma/client";
import { prisma } from "../../db/prisma";
import { CommerceLifecycleService } from "../CommerceLifecycleService";
import { pagoService } from "./pagoServiceInstance";
import { PagoWooService } from "./PagoWooService";

/**
 * Conecta el nucleo de pagos (PagoService, sin reglas de negocio propias)
 * con el dominio de pedidos de ControlApp. Vive aparte de
 * CommerceLifecycleService.ts para que ese archivo no dependa de arrancar
 * nada: aqui solo se registran los callbacks que PagoService ya sabe llamar
 * (ver PagoService.registrarConfirmador/registrarPosConfirmacion/
 * registrarAlertador).
 *
 * Se importa una sola vez, por su efecto secundario, desde index.ts -antes
 * de que arranque el worker (PagoReconciler)-. El canal WOOCOMMERCE
 * (plugin de la tienda) se registra al final.
 */
const lifecycle = new CommerceLifecycleService(prisma);

pagoService.registrarConfirmador(CanalPago.CONTROLAPP, (tx, contexto) =>
  lifecycle.confirmarPagoSistema(tx, contexto),
);
pagoService.registrarPosConfirmacion(CanalPago.CONTROLAPP, (cobro) =>
  lifecycle.avisarPagoConfirmadoPorFactus(cobro),
);
pagoService.registrarPosFallo(CanalPago.CONTROLAPP, (cobro) => lifecycle.avisarPagoFallidoPorFactus(cobro));
pagoService.registrarAlertador((cobro, motivo) => lifecycle.alertarAccionManualPago(cobro, motivo));

// Canal de la tienda web (plugin controlapp-factus-pay).
const pagosWoo = new PagoWooService(prisma, pagoService, lifecycle);
pagoService.registrarConfirmador(CanalPago.WOOCOMMERCE, (tx, contexto) =>
  pagosWoo.confirmarEnDominio(tx, contexto),
);
pagoService.registrarPosConfirmacion(CanalPago.WOOCOMMERCE, (cobro) => pagosWoo.posConfirmacion(cobro));
pagoService.registrarPosFallo(CanalPago.WOOCOMMERCE, (cobro) => pagosWoo.posFallo(cobro));
