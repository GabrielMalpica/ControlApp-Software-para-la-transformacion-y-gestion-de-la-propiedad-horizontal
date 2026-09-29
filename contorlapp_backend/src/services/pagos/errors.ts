/** Error de comunicacion o de negocio al hablar con la API de Factus Pay. */
export class FactusPayError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly upstreamStatus?: number,
  ) {
    super(message);
    this.name = "FactusPayError";
  }
}

/**
 * La lanza un confirmador de pago (ver PagoService.registrarConfirmador)
 * cuando Factus confirmo el pago pero el pedido/orden ya no puede pasar a
 * pagado (por ejemplo, esta CANCELADO). PagoService la distingue de un fallo
 * real: en vez de reintentar, marca el cobro como PAGADO_HUERFANO y genera
 * una alerta para revision manual.
 */
export class PedidoNoConfirmableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PedidoNoConfirmableError";
  }
}
