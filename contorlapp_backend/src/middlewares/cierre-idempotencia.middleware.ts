// src/middlewares/cierre-idempotencia.middleware.ts
//
// La cola sin señal de la app reenvía un cierre si nunca recibió la respuesta.
// Con la cabecera X-Cliente-Cierre-Id se sabe, antes de que multer reciba y
// guarde las fotos, si ese cierre ya entró: se responde de una vez y no se
// vuelve a procesar nada. (Las fotos igual viajan; para ahorrar esos datos la
// app pregunta antes con GET /operario/operarios/:id/cierres/:clienteCierreId.)
import type { RequestHandler } from "express";
import { z } from "zod";

import { prisma } from "../db/prisma";

const Uuid = z.string().uuid();

type BuscarCierre = (clienteCierreId: string) => Promise<{ tareaId: number } | null>;

export function crearDedupeCierrePorCabecera(
  buscar: BuscarCierre = (clienteCierreId) =>
    prisma.cierreTareaIdempotencia.findUnique({
      where: { clienteCierreId },
      select: { tareaId: true },
    }),
): RequestHandler {
  return async (req, res, next) => {
    const cabecera = String(req.headers["x-cliente-cierre-id"] ?? "").trim();
    const parsed = Uuid.safeParse(cabecera);
    if (!parsed.success) {
      next();
      return;
    }

    try {
      const fila = await buscar(parsed.data);
      const tareaId = Number(req.params.tareaId);
      if (!fila || fila.tareaId !== tareaId) {
        // Si es de otra tarea, el servicio responde el error con su código.
        next();
        return;
      }
      // Descarta el cuerpo sin guardarlo y confirma: el cierre ya está hecho.
      req.resume();
      const responder = () => {
        if (!res.headersSent) res.json({ ok: true, duplicado: true });
      };
      if (req.readableEnded) responder();
      else {
        req.once("end", responder);
        req.once("error", responder);
      }
    } catch {
      // Ante cualquier falla, el camino normal (también idempotente) decide.
      next();
    }
  };
}

export const dedupeCierrePorCabecera = crearDedupeCierrePorCabecera();
