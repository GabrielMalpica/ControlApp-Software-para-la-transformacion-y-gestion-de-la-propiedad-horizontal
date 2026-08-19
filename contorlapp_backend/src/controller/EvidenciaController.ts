// src/controller/EvidenciaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { getEvidenciaStream } from "../utils/drive_evidencias";

// IDs de archivo de Google Drive: alfanuméricos + "-"/"_", normalmente 25-45 chars.
const FileIdParamSchema = z.object({
  fileId: z.string().regex(/^[a-zA-Z0-9_-]{10,80}$/),
});

export class EvidenciaController {
  // GET /evidencias/:fileId
  obtener: RequestHandler = async (req, res, next) => {
    try {
      const { fileId } = FileIdParamSchema.parse(req.params);
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
