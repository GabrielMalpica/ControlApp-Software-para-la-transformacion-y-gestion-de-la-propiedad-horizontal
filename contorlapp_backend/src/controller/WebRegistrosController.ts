import type { RequestHandler } from "express";
import fs from "fs";
import { z } from "zod";
import { SolicitudesWebService } from "../services/SolicitudesWebService";
import { getEvidenciaStream, uploadArchivoWebToDrive } from "../utils/drive_evidencias";

const service = new SolicitudesWebService();

// Campo "meta" del multipart que firma el plugin puente de WordPress.
const MetaArchivoDTO = z.object({
  caso: z.enum(["conjunto", "trabajador"]),
  carpeta: z.string().trim().min(1).max(150),
  nombre: z.string().trim().min(1).max(150).optional(),
});

const ConsultaDTO = z.object({
  estado: z
    .string()
    .trim()
    .regex(/^[a-z_]{0,32}$/)
    .optional(),
  pagina: z.coerce.number().int().min(1).max(500).optional(),
});

const FileIdParamDTO = z.object({
  fileId: z.string().regex(/^[a-zA-Z0-9_-]{10,80}$/),
});

const ConsultaPostulacionesDTO = ConsultaDTO.extend({
  revision: z.enum(["pendientes", "revisadas"]).optional(),
});

const PostulacionParamDTO = z.object({
  id: z.coerce.number().int().positive(),
});

const RevisionDTO = z.object({ revisada: z.boolean() });

/**
 * Archivos y solicitudes de la pagina web (rutas /commerce/web/*):
 * - POST /archivos: lo usa el plugin puente de WordPress (firma HMAC).
 * - GET /postulaciones, /conjuntos y /archivos/:fileId: pantalla "Solicitudes
 *   de la web" de ControlApp (gerente y jefe de operaciones).
 * - POST /postulaciones/:id/revision y DELETE /postulaciones/:id: marcar como
 *   revisada o borrar una postulacion (permiso web.solicitudes.gestionar).
 */
export class WebRegistrosController {
  subirArchivo: RequestHandler = async (req, res, next) => {
    const archivo = req.file;
    try {
      let metaRaw: unknown;
      try {
        metaRaw = JSON.parse(String(req.body?.meta ?? ""));
      } catch {
        res.status(400).json({ message: "Datos del archivo invalidos" });
        return;
      }
      const meta = MetaArchivoDTO.parse(metaRaw);
      const { fileId } = await uploadArchivoWebToDrive({
        filePath: archivo!.path,
        fileName: meta.nombre ?? archivo!.originalname,
        mimeType: archivo!.mimetype,
        caso: meta.caso,
        carpeta: meta.carpeta,
      });
      res.status(201).json({
        fileId,
        nombre: meta.nombre ?? archivo!.originalname,
        mime: archivo!.mimetype,
        tamano: archivo!.size,
      });
    } catch (error) {
      next(error);
    } finally {
      if (archivo) await fs.promises.unlink(archivo.path).catch(() => undefined);
    }
  };

  listarPostulaciones: RequestHandler = async (req, res, next) => {
    try {
      res.json(await service.listarPostulaciones(ConsultaPostulacionesDTO.parse(req.query)));
    } catch (error) {
      next(error);
    }
  };

  marcarRevision: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      const { id } = PostulacionParamDTO.parse(req.params);
      const { revisada } = RevisionDTO.parse(req.body);
      res.json(await service.marcarRevisionPostulacion(id, revisada, req.user.sub));
    } catch (error) {
      next(error);
    }
  };

  eliminarPostulacion: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      const { id } = PostulacionParamDTO.parse(req.params);
      res.json(await service.eliminarPostulacion(id, req.user.sub));
    } catch (error) {
      next(error);
    }
  };

  listarConjuntos: RequestHandler = async (req, res, next) => {
    try {
      res.json(await service.listarConjuntos(ConsultaDTO.parse(req.query)));
    } catch (error) {
      next(error);
    }
  };

  // A diferencia de /evidencias/:fileId, este proxy exige rol y permiso:
  // estos documentos incluyen cedulas y RUT.
  obtenerArchivo: RequestHandler = async (req, res, next) => {
    try {
      const { fileId } = FileIdParamDTO.parse(req.params);
      const { stream, mimeType } = await getEvidenciaStream(fileId);

      res.setHeader("Content-Type", mimeType);
      res.setHeader("Cache-Control", "private, no-store");

      stream.on("error", (err) => {
        if (!res.headersSent) {
          res.status(404).json({ message: "No se pudo obtener el archivo." });
        } else {
          res.destroy();
        }
        console.error("[web-archivos] error leyendo stream de Drive:", err);
      });

      stream.pipe(res);
    } catch (error) {
      next(error);
    }
  };
}
