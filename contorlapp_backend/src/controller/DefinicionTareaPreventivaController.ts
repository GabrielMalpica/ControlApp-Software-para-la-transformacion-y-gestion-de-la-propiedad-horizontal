import { Request, Response } from "express";
import { prisma } from "../db/prisma";
import { DefinicionTareaPreventivaService } from "../services/DefinicionTareaPreventivaService";
import {
  CrearDefinicionPreventivaDTO,
  EditarDefinicionPreventivaDTO,
  GenerarCronogramaDTO,
} from "../model/DefinicionTareaPreventiva";

export const asyncHandler =
  (fn: (req: Request, res: Response) => Promise<any>) =>
  (req: Request, res: Response) =>
    fn(req, res).catch((err) => {
      console.error(err);
      res.status(400).json({ error: err?.message ?? "Error inesperado" });
    });

export class DefinicionTareaPreventivaController {

  /** POST /conjuntos/:nit/preventivas */
  crear = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const dto = CrearDefinicionPreventivaDTO.parse({
      ...req.body,
      conjuntoId,
    });

    const svc = new DefinicionTareaPreventivaService(prisma);
    const def = await svc.crear(dto);
    res.status(201).json(def);
  };

  /** GET /conjuntos/:nit/preventivas */
  listar = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const svc = new DefinicionTareaPreventivaService(prisma);
    const defs = await svc.listarPorConjunto(conjuntoId);
    res.json(defs);
  };

  /** PATCH /conjuntos/:nit/preventivas/:id */
  actualizar = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");

    const dto = EditarDefinicionPreventivaDTO.parse(req.body);
    const svc = new DefinicionTareaPreventivaService(prisma);
    const def = await svc.actualizar(conjuntoId, id, dto);
    res.json(def);
  };

  /** DELETE /conjuntos/:nit/preventivas/:id */
  eliminar = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");

    const svc = new DefinicionTareaPreventivaService(prisma);
    await svc.eliminar(conjuntoId, id);
    res.status(204).send();
  };

  /** POST /conjuntos/:nit/preventivas/generar-cronograma */
  generarCronogramaMensual = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const dto = GenerarCronogramaDTO.parse({
      ...req.body,
      conjuntoId,
    });

    const svc = new DefinicionTareaPreventivaService(prisma);
    const resultado = await svc.generarCronograma(dto);
    res.status(201).json(resultado);
  };

  /** POST /conjuntos/:nit/preventivas/publicar?anio=&mes=&consolidar=true|false */
  publicarCronograma = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;

    const anio = Number(req.body.anio ?? req.query.anio);
    const mes = Number(req.body.mes ?? req.query.mes);

    const consolidarRaw = (req.body.consolidar ?? req.query.consolidar) as
      | string
      | boolean
      | undefined;
    const consolidar =
      consolidarRaw === true || consolidarRaw === "true" ? true : false;

    if (
      !conjuntoId ||
      !Number.isFinite(anio) ||
      !Number.isFinite(mes) ||
      mes < 1 ||
      mes > 12
    ) {
      return res.status(400).json({
        error: "conjuntoId (nit), anio y mes son obligatorios y válidos",
      });
    }

    const svc = new DefinicionTareaPreventivaService(prisma);
    const result = await svc.publicarCronograma({
      conjuntoId,
      anio,
      mes,
    });

    return res.json(result);
  };

  listarMaquinariaDisponible = async (req: Request, res: Response) => {
    const conjuntoId = String(req.params.nit || req.params.conjuntoId || "");
    if (!conjuntoId) {
      return res.status(400).json({ ok: false, reason: "FALTA_CONJUNTO" });
    }

    const fi = String(req.query.fechaInicioUso || "");
    const ff = String(req.query.fechaFinUso || "");
    if (!fi || !ff) {
      return res.status(400).json({
        ok: false,
        reason: "FALTAN_FECHAS",
        message: "Debe enviar fechaInicioUso y fechaFinUso (ISO).",
      });
    }

    const fechaInicioUso = new Date(fi);
    const fechaFinUso = new Date(ff);

    if (
      Number.isNaN(fechaInicioUso.getTime()) ||
      Number.isNaN(fechaFinUso.getTime())
    ) {
      return res.status(400).json({
        ok: false,
        reason: "FECHAS_INVALIDAS",
        message: "Use formato ISO: 2026-01-01T00:00:00.000Z",
      });
    }

    const excluirTareaIdRaw = req.query.excluirTareaId;
    const excluirTareaId =
      excluirTareaIdRaw != null && String(excluirTareaIdRaw).trim() !== ""
        ? Number(excluirTareaIdRaw)
        : undefined;

    const svc = new DefinicionTareaPreventivaService(prisma);

    const r = await svc.listarMaquinariaDisponible({
      conjuntoId,
      fechaInicioUso,
      fechaFinUso,
      excluirTareaId: Number.isFinite(excluirTareaId)
        ? excluirTareaId
        : undefined,
    });

    if (!r.ok) return res.status(400).json(r);

    return res.status(200).json(r);
  };

  /** PATCH /conjuntos/:nit/preventivas/borrador/tareas/:id */
  editarBorrador = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const tareaId = Number(req.params.id);
    const svc = new DefinicionTareaPreventivaService(prisma);

    const out = await svc.editarTareaBorrador({
      conjuntoId,
      tareaId,
      ...req.body, // fechaInicio, fechaFin, duracionHoras, operariosIds
    });
    res.json(out);
  };

  /** POST /conjuntos/:nit/preventivas/borrador/tarea */
  crearBloqueBorrador = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const svc = new DefinicionTareaPreventivaService(prisma);
    const out = await svc.crearBloqueBorrador(conjuntoId, req.body);
    res.status(201).json(out);
  };

  /** PATCH /conjuntos/:nit/preventivas/borrador/tarea/:id */
  editarBloqueBorrador = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");
    const svc = new DefinicionTareaPreventivaService(prisma);
    const out = await svc.editarBloqueBorrador(conjuntoId, id, req.body);
    res.json(out);
  };

  /** DELETE /conjuntos/:nit/preventivas/borrador/tarea/:id */
  eliminarBloqueBorrador = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");
    const svc = new DefinicionTareaPreventivaService(prisma);
    await svc.eliminarBloqueBorrador(conjuntoId, id);
    res.status(204).send();
  };

  /** GET /conjuntos/:nit/preventivas/borrador?anio=&mes= */
  listarBorrador = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const anio = Number(req.query.anio);
    const mes = Number(req.query.mes);
    if (
      !Number.isFinite(anio) ||
      !Number.isFinite(mes) ||
      mes < 1 ||
      mes > 12
    ) {
      res.status(400).json({ error: "Parámetros anio/mes inválidos." });
      return;
    }
    const svc = new DefinicionTareaPreventivaService(prisma);
    const out = await svc.listarBorrador({ conjuntoId, anio, mes }); // método simple en el service
    res.json(out);
  };
}
