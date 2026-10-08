// src/controller/RecursoAgendaController.ts
import { Rol } from "@prisma/client";
import { Request, RequestHandler } from "express";
import { z } from "zod";

import { prisma } from "../db/prisma";
import { AgendaRecursoService } from "../services/AgendaRecursoService";
import { PermissionService } from "../services/PermissionService";
import { ReservaRecursoService } from "../services/ReservaRecursoService";
import { extraerActorAuditoriaConNombre } from "../utils/auditoria";
import { errorNegocio, type ClaseRecursoStr } from "../utils/recursoAgendaCore";

const permissionService = new PermissionService(prisma);

const IdParam = z.coerce.number().int().positive();
const ClaseParam = z.enum(["MAQUINARIA", "HERRAMIENTA"]);

type Accion = "ver" | "asignar";

function permisoDeClase(clase: ClaseRecursoStr, accion: Accion): string {
  return `${clase === "MAQUINARIA" ? "maquinaria" : "herramientas"}.${accion}`;
}

/**
 * Las rutas exigen permiso sobre maquinaria O herramientas; aqui se exige el
 * de la clase concreta del recurso tocado (un rol con solo
 * `herramientas.asignar` no puede reservar maquinaria).
 */
async function assertPermisoClase(req: Request, clase: ClaseRecursoStr, accion: Accion) {
  const userId = req.user?.sub;
  const role = req.user?.rol;
  if (!userId || !role) throw errorNegocio(401, "No autenticado.");

  const requeridos =
    accion === "ver"
      ? [permisoDeClase(clase, "ver"), permisoDeClase(clase, "asignar")]
      : [permisoDeClase(clase, "asignar")];

  if (role === "gerente" && !req.user?.empresaId?.trim()) {
    const defaults = PermissionService.defaultPermissionsForRole(Rol.gerente);
    if (requeridos.some((p) => defaults.has(p))) return;
  }
  const empresaId =
    req.user?.empresaId?.trim() || (await permissionService.resolveEmpresaIdForUser(userId, role));
  const efectivos = await permissionService.getEffectivePermissionsForRole(empresaId, role);
  if (!PermissionService.hasAnyPermission(efectivos, requeridos)) {
    throw errorNegocio(
      403,
      clase === "MAQUINARIA"
        ? "Tu rol no tiene permiso para gestionar la agenda de maquinaria."
        : "Tu rol no tiene permiso para gestionar la agenda de herramientas.",
    );
  }
}

async function claseDeNecesidad(empresaId: string, necesidadId: number): Promise<ClaseRecursoStr> {
  const n = await prisma.necesidadRecursoTarea.findFirst({
    where: { id: necesidadId, tarea: { conjunto: { empresaId } } },
    select: { clase: true },
  });
  if (!n) throw errorNegocio(404, "La necesidad de recurso no existe para esta empresa.");
  return n.clase;
}

async function claseDeReserva(empresaId: string, reservaId: number): Promise<ClaseRecursoStr> {
  const r = await prisma.reservaRecurso.findFirst({
    where: { id: reservaId, empresaId },
    select: { clase: true },
  });
  if (!r) throw errorNegocio(404, "La reserva no existe para esta empresa.");
  return r.clase;
}

/** Empresa duena del conjunto (rutas por conjunto). */
async function empresaDeConjunto(nit: string): Promise<string> {
  const c = await prisma.conjunto.findUnique({ where: { nit }, select: { empresaId: true } });
  if (!c?.empresaId) throw errorNegocio(404, "El conjunto no existe.");
  return c.empresaId;
}

export class RecursoAgendaController {
  /* -------- lecturas -------- */

  // GET /empresas/:empresaNit/agenda
  agenda: RequestHandler = async (req, res, next) => {
    try {
      const clase = req.query.clase ? ClaseParam.parse(req.query.clase) : null;
      if (clase) await assertPermisoClase(req, clase, "ver");
      const service = new AgendaRecursoService(prisma, req.params.empresaNit);
      res.json(await service.agenda(req.query));
    } catch (err) {
      next(err);
    }
  };

  // GET /empresas/:empresaNit/necesidades
  necesidades: RequestHandler = async (req, res, next) => {
    try {
      const service = new AgendaRecursoService(prisma, req.params.empresaNit);
      res.json(await service.necesidades(req.query));
    } catch (err) {
      next(err);
    }
  };

  // GET /empresas/:empresaNit/necesidades/:necesidadId/candidatos
  candidatos: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = req.params.empresaNit;
      const necesidadId = IdParam.parse(req.params.necesidadId);
      await assertPermisoClase(req, await claseDeNecesidad(empresaId, necesidadId), "asignar");
      const service = new ReservaRecursoService(prisma, empresaId);
      res.json(await service.candidatos(necesidadId));
    } catch (err) {
      next(err);
    }
  };

  // GET /empresas/:empresaNit/alertas
  alertas: RequestHandler = async (req, res, next) => {
    try {
      const service = new AgendaRecursoService(prisma, req.params.empresaNit);
      res.json(await service.alertas(req.query));
    } catch (err) {
      next(err);
    }
  };

  // GET /empresas/:empresaNit/unidades/:clase/:unidadId/historial
  historial: RequestHandler = async (req, res, next) => {
    try {
      const clase = ClaseParam.parse(req.params.clase);
      await assertPermisoClase(req, clase, "ver");
      const service = new AgendaRecursoService(prisma, req.params.empresaNit);
      res.json(await service.historialUnidad(clase, IdParam.parse(req.params.unidadId)));
    } catch (err) {
      next(err);
    }
  };

  // GET /empresas/:empresaNit/configuracion
  obtenerConfiguracion: RequestHandler = async (req, res, next) => {
    try {
      const service = new ReservaRecursoService(prisma, req.params.empresaNit);
      res.json(await service.obtenerConfiguracion());
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/semana
  semanaConjunto: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaDeConjunto(req.params.nit);
      const service = new AgendaRecursoService(prisma, empresaId);
      res.json(await service.semanaConjunto(req.params.nit, req.query));
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/capacidad-borrador?anio=&mes=
  capacidadBorrador: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaDeConjunto(req.params.nit);
      const service = new AgendaRecursoService(prisma, empresaId);
      res.json(await service.capacidadBorrador(req.params.nit, req.query));
    } catch (err) {
      next(err);
    }
  };

  /* -------- escrituras -------- */

  // POST /empresas/:empresaNit/reservas
  reservar: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = req.params.empresaNit;
      const necesidadId = IdParam.parse(req.body?.necesidadId);
      await assertPermisoClase(req, await claseDeNecesidad(empresaId, necesidadId), "asignar");
      const service = new ReservaRecursoService(
        prisma,
        empresaId,
        await extraerActorAuditoriaConNombre(req),
      );
      res.status(201).json(await service.reservar(req.body));
    } catch (err) {
      next(err);
    }
  };

  // POST /empresas/:empresaNit/reservas/:reservaId/cancelar
  cancelar: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = req.params.empresaNit;
      const reservaId = IdParam.parse(req.params.reservaId);
      await assertPermisoClase(req, await claseDeReserva(empresaId, reservaId), "asignar");
      const service = new ReservaRecursoService(
        prisma,
        empresaId,
        await extraerActorAuditoriaConNombre(req),
      );
      res.json(await service.cancelar(reservaId, req.body));
    } catch (err) {
      next(err);
    }
  };

  // POST /empresas/:empresaNit/reservas/:reservaId/reemplazar
  reemplazar: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = req.params.empresaNit;
      const reservaId = IdParam.parse(req.params.reservaId);
      await assertPermisoClase(req, await claseDeReserva(empresaId, reservaId), "asignar");
      const service = new ReservaRecursoService(
        prisma,
        empresaId,
        await extraerActorAuditoriaConNombre(req),
      );
      res.json(await service.reemplazar(reservaId, req.body));
    } catch (err) {
      next(err);
    }
  };

  // POST /empresas/:empresaNit/mantenimientos
  mantenimiento: RequestHandler = async (req, res, next) => {
    try {
      const clase = ClaseParam.parse(req.body?.clase);
      await assertPermisoClase(req, clase, "asignar");
      const service = new ReservaRecursoService(
        prisma,
        req.params.empresaNit,
        await extraerActorAuditoriaConNombre(req),
      );
      res.status(201).json(await service.bloquearMantenimiento(req.body));
    } catch (err) {
      next(err);
    }
  };

  // PATCH /empresas/:empresaNit/configuracion
  actualizarConfiguracion: RequestHandler = async (req, res, next) => {
    try {
      const service = new ReservaRecursoService(
        prisma,
        req.params.empresaNit,
        await extraerActorAuditoriaConNombre(req),
      );
      res.json(await service.actualizarConfiguracion(req.body));
    } catch (err) {
      next(err);
    }
  };
}
