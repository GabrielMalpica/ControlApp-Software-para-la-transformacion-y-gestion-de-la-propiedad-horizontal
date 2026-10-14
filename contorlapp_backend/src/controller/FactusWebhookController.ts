import type { RequestHandler } from "express";
import { detalleErrorPagos } from "../services/pagos/errors";
import { factusWebhook } from "../services/pagos/factusWebhookInstance";

export class FactusWebhookController {
  /**
   * Aviso de Factus Pay de que un recaudo quedo pagado. Sin JWT: Factus manda
   * su llave en el query string (`?key=`), que se valida en el servicio. Se
   * responde apenas el aviso queda guardado (Factus espera 10 s) y la
   * verificacion por API corre despues. Nunca registrar req.url ni
   * req.originalUrl aqui: llevan la llave.
   */
  recibir: RequestHandler = async (req, res, next) => {
    try {
      const respuesta = await factusWebhook.recibir({
        key: req.query.key,
        body: req.body,
        rawBody: req.rawBody,
        ip: req.ip,
      });
      res.status(respuesta.status).json(respuesta.body);

      const webhookId = respuesta.webhookId;
      if (webhookId) {
        setImmediate(() => {
          factusWebhook.procesar(webhookId).catch((error) => {
            // La fila sigue RECIBIDO: el barrido del worker la retoma.
            console.error("[pagos] no se pudo procesar el aviso de Factus", { webhookId, ...detalleErrorPagos(error) });
          });
        });
      }
    } catch (error) {
      next(error);
    }
  };
}
