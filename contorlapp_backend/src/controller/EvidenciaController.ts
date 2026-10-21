// src/controller/EvidenciaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import { EvidenciaAccesoService } from "../services/EvidenciaAccesoService";
import { buscarDireccionGps } from "../utils/direccion_gps";
import { getEvidenciaStream } from "../utils/drive_evidencias";

// IDs de archivo de Google Drive: alfanuméricos + "-"/"_", normalmente 25-45 chars.
const FileIdParamSchema = z.object({
  fileId: z.string().regex(/^[a-zA-Z0-9_-]{10,80}$/),
});

const DireccionQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
});

export class EvidenciaController {
  // Una sola instancia: junta en una consulta las fotos que se piden a la vez.
  private acceso = new EvidenciaAccesoService(prisma);

  // GET /evidencias/direccion?lat=&lng=
  // La app la pide apenas se toma una foto de evidencia, en segundo plano:
  // así, al cerrar la tarea, la dirección de la marca de agua ya está en
  // caché y el cierre no espera al servicio de mapas.
  direccion: RequestHandler = async (req, res, next) => {
    try {
      const { lat, lng } = DireccionQuerySchema.parse(req.query);
      res.json({ direccion: await buscarDireccionGps(lat, lng) });
    } catch (err) {
      next(err);
    }
  };

  // GET /evidencias/:fileId
  // Solo si el archivo es de una tarea, diagnóstico o comprobante que el
  // usuario ya puede ver; si no, 404 sin confirmar que existe.
  obtener: RequestHandler = async (req, res, next) => {
    try {
      const { fileId } = FileIdParamSchema.parse(req.params);
      const empresaId = await empresaIdAutenticada(req);
      await this.acceso.autorizar(fileId, {
        id: String(req.user?.sub ?? "").trim(),
        rol: String(req.user?.rol ?? "").trim(),
        empresaId,
      });
      const { stream, mimeType } = await getEvidenciaStream(fileId);

      res.setHeader("Content-Type", mimeType);
      res.setHeader("Cache-Control", "private, max-age=86400");

      stream.on("error", (err) => {
        if (!res.headersSent) {
          res.status(404).json({ message: "No se pudo obtener la evidencia." });
        } else {
          res.destroy();
        }
        console.error("[evidencias] error leyendo stream de Drive:", err);
      });

      stream.pipe(res);
    } catch (err) {
      next(err);
    }
  };
}
