import { CanalPago } from "@prisma/client";
import { prisma } from "../../db/prisma";
import { CommerceLifecycleService } from "../CommerceLifecycleService";
import { pagoService } from "./pagoServiceInstance";
import { PagoWooService } from "./PagoWooService";
import { saldoServicio } from "./saldoServicioInstance";
import { esperaSegunModo } from "./SaludPagosService";
import { saludPagos } from "./saludPagosInstance";

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

// Cada cuanto se reconsulta un cobro pendiente: sondeo frecuente o, con el
// webhook como via principal y funcionando, unas pocas consultas de respaldo.
pagoService.registrarCalendario((cobro, ahora) => esperaSegunModo(saludPagos.modoEfectivo(), cobro, ahora));

// Canal de la tienda web (plugin controlapp-factus-pay).
const pagosWoo = new PagoWooService(prisma, pagoService, lifecycle);
pagoService.registrarConfirmador(CanalPago.WOOCOMMERCE, (tx, contexto) =>
  pagosWoo.confirmarEnDominio(tx, contexto),
);
pagoService.registrarPosConfirmacion(CanalPago.WOOCOMMERCE, (cobro) => pagosWoo.posConfirmacion(cobro));
pagoService.registrarPosFallo(CanalPago.WOOCOMMERCE, (cobro) => pagosWoo.posFallo(cobro));

// Saldo de servicios pagados con anticipo (app y tienda). Un cobro fallido no
// necesita aviso: el saldo sigue pendiente y se puede generar otro codigo.
pagoService.registrarConfirmador(CanalPago.SALDO_SERVICIO, (tx, contexto) =>
  saldoServicio.confirmarEnDominio(tx, contexto),
);
pagoService.registrarPosConfirmacion(CanalPago.SALDO_SERVICIO, (cobro) => saldoServicio.posConfirmacion(cobro));
