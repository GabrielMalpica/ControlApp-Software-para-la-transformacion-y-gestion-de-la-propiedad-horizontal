// src/controllers/GerenteController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { Rol } from "@prisma/client";
import { prisma } from "../db/prisma";
import { GerenteService } from "../services/GerenteServices";
import { PermissionService } from "../services/PermissionService";
import { conSupervisorPorDefecto } from "../services/TareaServices";
import { ListarUsuariosDTO, UsuarioIdParam } from "../model/Gerente";
import { extraerActorAuditoriaConNombre } from "../utils/auditoria";
import { alcanceConjuntos } from "../aplicacion/alcanceConjuntos";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import { PlanillaPersonalService } from "../services/PlanillaPersonalService";

// â”€â”€ Schemas de params simples â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const IdParam = z.object({ id: z.coerce.number().int().positive() });
const AdminIdParam = z.object({ adminId: z.coerce.number().int().positive() });
const OperarioIdParam = z.object({
  operarioId: z.coerce.number().int().positive(),
});
const SupervisorIdParam = z.object({
  supervisorId: z.coerce.number().int().positive(),
});
const TareaIdParam = z.object({ tareaId: z.coerce.number().int().positive() });
const MaquinariaIdParam = z.object({
  maquinariaId: z.coerce.number().int().positive(),
});
const ConjuntoIdParam = z.object({ conjuntoId: z.string().min(3) });
const EliminarConjuntoQuery = z.object({
  confirmar: z.coerce.boolean().optional().default(false),
});

// Para endpoints que agregan insumo a conjunto por URL + body
const AddInsumoBody = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

// Para asignar operario a conjunto por URL + body
const AsignarOperarioBody = z.object({
  operarioId: z.number().int().positive(),
});

// Actualizar lÃ­mite de horas semanales
const LimiteHorasBody = z.object({
  limiteHorasSemana: z.coerce.number().int().min(1).max(84),
});

const PlanillaUsuariosQuery = z.object({
  conjuntoId: z.string().trim().min(3).optional(),
});

const QuitarOperarioBody = z.object({
  operarioId: z.string().min(1),
});

const ActualizarMatrizPermisosBody = z.object({
  matrix: z.record(
    z.string(),
    z.record(z.string(), z.boolean()),
  ),
});

const permissionService = new PermissionService(prisma);

function serviceFor(req: Parameters<RequestHandler>[0]) {
  return new GerenteService(prisma, req.user?.empresaId);
}

/** Para gestionar usuarios: el servicio aplica la jerarquia de roles y audita con este actor. */
async function serviceConActor(req: Parameters<RequestHandler>[0]) {
  const actor = await extraerActorAuditoriaConNombre(req);
  return new GerenteService(prisma, req.user?.empresaId, actor);
}

/**
 * Para crear/editar/eliminar tareas: siempre con actor, asi el servicio limita
 * la tarea al alcance del rol (sin usuario en el token no hay rol y editar o
 * eliminar se rechaza).
 */
async function serviceParaTareas(req: Parameters<RequestHandler>[0]) {
  const actor = (await extraerActorAuditoriaConNombre(req)) ?? { id: null, rol: null };
  return new GerenteService(prisma, req.user?.empresaId, actor);
}

/** Quien crea una tarea, tal como viene en el token. */
function actorDeTareas(req: Parameters<RequestHandler>[0]) {
  return {
    id: String(req.user?.sub ?? "").trim(),
    rol: String(req.user?.rol ?? "").trim(),
  };
}

export class GerenteController {
  obtenerCatalogoPermisos: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const empresaId = await permissionService.resolveEmpresaIdForUser(
        actorUserId,
        Rol.gerente,
      );

      const matrix = await permissionService.getPermissionMatrix(empresaId);
      res.json(matrix);
    } catch (err) {
      next(err);
    }
  };

  actualizarMatrizPermisos: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const { matrix } = ActualizarMatrizPermisosBody.parse(req.body);
      const empresaId = await permissionService.resolveEmpresaIdForUser(
        actorUserId,
        Rol.gerente,
      );

      const actor = await extraerActorAuditoriaConNombre(req);
      const updated = await permissionService.replacePermissionMatrix(empresaId, matrix, actor);
      res.json(updated);
    } catch (err) {
      next(err);
    }
  };

  // â”€â”€ Empresa â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  crearEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const out = await serviceFor(req).crearEmpresa(req.body, req.user?.sub);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  actualizarLimiteHoras: RequestHandler = async (req, res, next) => {
    try {
      const { limiteHorasSemana } = LimiteHorasBody.parse(req.body);
      const out = await serviceFor(req).actualizarLimiteHorasEmpresa(limiteHorasSemana);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // â”€â”€ Usuarios â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  crearUsuario: RequestHandler = async (req, res, next) => {
    try {
      const service = await serviceConActor(req);
      const out = await service.crearUsuario(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  editarUsuario: RequestHandler = async (req, res, next) => {
    try {
      const { id } = UsuarioIdParam.parse(req.params);
      const service = await serviceConActor(req);
      const out = await service.editarUsuario(id, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  listarUsuarios: RequestHandler = async (req, res, next) => {
    try {
      const dto = ListarUsuariosDTO.parse(req.query);

      const usuarios = await serviceFor(req).listarUsuarios(dto.rol);

      res.json(usuarios);
    } catch (err) {
      next(err);
    }
  };

  /** Vista de tabla de usuarios: todos sus datos y sus vacaciones (sin contraseña). */
  planillaUsuarios: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = PlanillaUsuariosQuery.parse(req.query);
      const empresaId = await empresaIdAutenticada(req);
      const alcance = await alcanceConjuntos(prisma, {
        usuarioId: String(req.user?.sub ?? ""),
        rol: String(req.user?.rol ?? ""),
        empresaId,
      });
      const filas = await new PlanillaPersonalService(prisma).listar({
        empresaId,
        alcance,
        conjuntoId,
      });
      res.json(filas);
    } catch (err) {
      next(err);
    }
  };

  crearResidenteManual: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const out = await serviceFor(req).crearResidenteManual(actorUserId, req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  cargarResidentesMasivo: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const out = await serviceFor(req).cargarResidentesMasivo(actorUserId, req.body, req.file);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  listarResidentes: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const out = await serviceFor(req).listarResidentes(actorUserId, req.query);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  editarResidente: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const residenteId = String(req.params.residenteId ?? "").trim();
      const out = await serviceFor(req).editarResidente(actorUserId, residenteId, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  eliminarResidenteGestion: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const residenteId = String(req.params.residenteId ?? "").trim();
      const conjuntoId = String(req.query.conjuntoId ?? "").trim();
      const out = await serviceFor(req).eliminarResidenteGestion(actorUserId, residenteId, conjuntoId);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // â”€â”€ Roles / Perfiles â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  asignarGerente: RequestHandler = async (req, res, next) => {
    try {
      const service = await serviceConActor(req);
      const out = await service.asignarGerente(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const service = await serviceConActor(req);
      const out = await service.asignarAdministrador(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarJefeOperaciones: RequestHandler = async (req, res, next) => {
    try {
      const service = await serviceConActor(req);
      const out = await service.asignarJefeOperaciones(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const service = await serviceConActor(req);
      const out = await service.asignarSupervisor(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  listarSupervisores: RequestHandler = async (req, res, next) => {
    try {
      const supervisores = await serviceFor(req).listarSupervisores();
      res.json(supervisores);
    } catch (err) {
      console.error("Error al listar supervisores:", err);
      next(err);
    }
  };

  listarTareasPorConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const out = await serviceFor(req).listarTareasPorConjunto(conjuntoId);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarOperario: RequestHandler = async (req, res, next) => {
    try {
      const service = await serviceConActor(req);
      const out = await service.asignarOperario(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // â”€â”€ Conjuntos â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  crearConjunto: RequestHandler = async (req, res, next) => {
    try {
      const out = await serviceFor(req).crearConjunto(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  cargarConjuntoMasivo: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const out = await serviceFor(req).cargarConjuntoMasivo(actorUserId, req.file);
      res.status(out.creado ? 201 : 422).json(out);
    } catch (err) {
      next(err);
    }
  };

  descargarPlantillaConjunto: RequestHandler = async (req, res, next) => {
    try {
      const buffer = await serviceFor(req).generarPlantillaConjunto();
      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      );
      res.setHeader(
        "Content-Disposition",
        'attachment; filename="plantilla_conjunto.xlsx"',
      );
      res.status(200).send(buffer);
    } catch (err) {
      next(err);
    }
  };

  listarConjuntos: RequestHandler = async (req, res, next) => {
    try {
      const out = await serviceFor(req).listarConjuntos();
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  listarConjuntosSelector: RequestHandler = async (req, res, next) => {
    try {
      const out = await serviceFor(req).listarConjuntosSelector();
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  obtenerConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const out = await serviceFor(req).obtenerConjunto(conjuntoId);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  editarConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const out = await serviceFor(req).editarConjunto(conjuntoId, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarOperarioAConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const { operarioId } = AsignarOperarioBody.parse(req.body);

      await serviceFor(req).asignarOperarioAConjunto({
        conjuntoId,
        operarioId,
      });

      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  quitarOperarioDeConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const { operarioId } = QuitarOperarioBody.parse(req.body);

      await serviceFor(req).quitarOperarioDeConjunto({ conjuntoId, operarioId });
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // â”€â”€ Inventario / Insumos â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  agregarInsumoAConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const body = AddInsumoBody.parse(req.body);
      const out = await serviceFor(req).agregarInsumoAConjunto({
        conjuntoId,
        insumoId: body.insumoId,
        cantidad: body.cantidad,
      });
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // â”€â”€ Tareas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  asignarTarea: RequestHandler = async (req, res, next) => {
    try {
      const body: any = conSupervisorPorDefecto(actorDeTareas(req), req.body ?? {});
      // Con actor: el administrador solo crea en sus conjuntos (fuera, 404).
      const service = await serviceParaTareas(req);

      const tipo = String(body?.tipo ?? "CORRECTIVA").toUpperCase();
      const prioridad = Number(body?.prioridad ?? 2);

      // âœ… 1) Correctiva P1/P2/P3: entra por reglas de conflicto/reemplazo
      if (tipo === "CORRECTIVA" && [1, 2, 3].includes(prioridad)) {
        const r: any = await service.crearCorrectivaConReglas(body);

        // A) Creada sin reemplazo
        if (r.ok && r.mode === "CREADA_SIN_REEMPLAZO") {
          res.status(201).json({
            ok: true,
            tareaId: r.createdId ?? r.createdP1Id,
            createdId: r.createdId ?? r.createdP1Id,
            message: r.message,
            ajustadaAutomaticamente: r.ajustadaAutomaticamente ?? false,
            motivoAjuste: r.motivoAjuste ?? null,
            solicitadaInicio: r.solicitadaInicio ?? null,
            solicitadaFin: r.solicitadaFin ?? null,
            asignadaInicio: r.asignadaInicio ?? null,
            asignadaFin: r.asignadaFin ?? null,
          });
          return;
        }

        // B) Auto reemplazo
        if (r.ok && (r.mode === "AUTO_REEMPLAZO" || r.mode === "AUTO_REEMPLAZO_P3")) {
          res.status(200).json({
            ok: true,
            tareaId: r.createdId ?? r.createdP1Id,
            createdId: r.createdId ?? r.createdP1Id,
            autoReplaced: r.autoReplaced ?? r.info?.reemplazadas ?? [],
            reemplazadasIds: r.reemplazadasIds ?? [],
            reprogramadasIds: r.reprogramadasIds ?? [],
            canceladasIds: r.canceladasIds ?? [],
            canceladasSinCupoIds: r.canceladasSinCupoIds ?? [],
            noCompletadasIds: r.noCompletadasIds ?? [],
            message: r.message,
          });
          return;
        }

        // C) Requiere decisiÃ³n manual (mover/reemplazar o reemplazar directo)
        if (
          r.ok &&
          (r.mode === "REQUIERE_DECISION_REEMPLAZO" ||
            r.mode === "REQUIERE_CONFIRMACION_P2" ||
            r.mode === "REQUIERE_CONFIRMACION_P1")
        ) {
          const reemplazables = (r.opciones ?? []).flatMap((op: any) => {
            return (op.tareas ?? []).map((t: any) => ({
              id: t.id,
              prioridad: t.prioridad,
              descripcion: t.descripcion,
              tipo: t.tipo ?? "PREVENTIVA",
              fechaInicio: t.fechaInicio,
              fechaFin: t.fechaFin,
            }));
          });

          const replacementPriority = Number(r.prioridadObjetivo ?? prioridad);
          const isCritical = replacementPriority === 1;

          res.status(200).json({
            needsReplacement: true,
            ok: false,
            message: r.message,
            decisionMode: r.decisionMode ?? "REEMPLAZAR",
            replacementPriority,
            prioridadCorrectiva: Number(r.prioridadCorrectiva ?? prioridad),
            replacementNoticeOnly: r.replacementNoticeOnly ?? false,
            criticalConfirmation: isCritical,
            confirmationVariant: r.confirmationVariant ?? r.estiloConfirmacion,
            confirmationColor:
              (r.confirmationColor ?? r.colorConfirmacion) === "red"
                ? "#DC2626"
                : (r.confirmationColor ?? r.colorConfirmacion) === "blue"
                  ? "#2563EB"
                  : "#D97706",
            confirmationTitle: r.confirmationTitle ?? r.tituloConfirmacion,
            confirmationRequiresReason:
              r.confirmationRequiresReason ?? r.requiereMotivo ?? true,
            requiresReplacementAction: r.requiresReplacementAction ?? true,
            reasonHint:
              r.replacementNoticeOnly === true
                ? "Se mostrara el detalle de las preventivas P3 que se reemplazaran antes de continuar."
                : "Debes indicar por que se autoriza este reemplazo antes de confirmar.",
            reemplazables,
            reemplazablesP2: replacementPriority === 2 ? reemplazables : [],
            reemplazablesP1: replacementPriority === 1 ? reemplazables : [],
            opcionesAuto: r.opcionesAuto ?? [],
            opcionesConfirmacion: r.opcionesConfirmacion ?? [],
            suggestedInicio:
              r.suggestedInicio ?? r.slotSugerido?.fechaInicio ?? null,
            suggestedFin: r.suggestedFin ?? r.slotSugerido?.fechaFin ?? null,
          });
          return;
        }

        // D) No se pudo
        res.status(200).json({
          ok: false,
          reason: "reason" in r ? r.reason : "SIN_HUECO",
          message: r.message,
          suggestedInicio: r.suggestedInicio ?? null,
          suggestedFin: r.suggestedFin ?? null,
        });
        return;
      }

      // âœ… 2) No es P1: asignaciÃ³n normal (incluye validaciÃ³n solapes/sugerencias)
      const out: any = await service.asignarTarea(body);

      const status = out?.ok === true ? 201 : 200;
      res.status(status).json(out);
      return;
    } catch (err) {
      next(err);
    }
  };

  asignarTareaConReemplazo = async (req: any, res: any) => {
    try {
      const body = req.body ?? {};
      const service = await serviceParaTareas(req);
      const out = await service.asignarTareaConReemplazoV2({
        ...body,
        tarea: conSupervisorPorDefecto(actorDeTareas(req), body.tarea),
      });
      if (out?.ok === false) return res.status(400).json(out);
      return res.status(200).json(out);
    } catch (e: any) {
      // Un error con estado 4xx (p. ej. 404 fuera de alcance) lo conserva.
      const status = Number(e?.status);
      return res
        .status(status >= 400 && status < 500 ? status : 400)
        .json({ ok: false, message: e?.message ?? String(e) });
    }
  };

  editarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      // Con actor: el servicio limita la edición al alcance de su rol.
      const service = await serviceParaTareas(req);
      const out = await service.editarTarea(tareaId, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // â”€â”€ Eliminaciones con reglas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  eliminarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const { adminId } = AdminIdParam.parse(req.params);
      const service = await serviceConActor(req);
      await service.eliminarAdministrador(adminId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  reemplazarAdminEnVariosConjuntos: RequestHandler = async (req, res, next) => {
    try {
      // El servicio valida el body (ReemplazarAdministradoresDTO), la jerarquia y audita.
      const service = await serviceConActor(req);
      await service.reemplazarAdminEnVariosConjuntos(req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const service = await serviceConActor(req);
      await service.eliminarOperario(operarioId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      const service = await serviceConActor(req);
      await service.eliminarSupervisor(supervisorId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  reemplazarSupervisorYEliminar: RequestHandler = async (req, res, next) => {
    try {
      const supervisorId = String(req.params.supervisorId ?? "").trim();
      if (!supervisorId) throw new Error("Cédula de supervisor obligatoria.");
      const service = await serviceConActor(req);
      const result = await service.reemplazarSupervisorYEliminar(
        supervisorId,
        req.body,
      );
      res.json(result);
    } catch (err) {
      next(err);
    }
  };

  eliminarUsuario: RequestHandler = async (req, res, next) => {
    try {
      const { id } = UsuarioIdParam.parse(req.params);
      const service = await serviceConActor(req);
      await service.eliminarUsuario(id);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const { confirmar } = EliminarConjuntoQuery.parse(req.query);
      const result = await serviceFor(req).eliminarConjunto(conjuntoId, { confirmar });

      if (!result.ok && result.requiresConfirmation) {
        res.status(409).json(result);
        return;
      }

      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      await serviceFor(req).eliminarMaquinaria(maquinariaId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const service = await serviceParaTareas(req);
      await service.eliminarTarea(prisma, tareaId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // â”€â”€ Ediciones rÃ¡pidas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  editarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const { adminId } = AdminIdParam.parse(req.params);
      const service = await serviceConActor(req);
      await service.editarAdministrador(adminId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  editarOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const service = await serviceConActor(req);
      await service.editarOperario(operarioId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  editarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      const service = await serviceConActor(req);
      await service.editarSupervisor(supervisorId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  listarTareasAbiertasOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const out = await serviceFor(req).listarTareasAbiertasOperario(
        operarioId.toString(),
      );
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  cerrarTareasAbiertasOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const out = await serviceFor(req).cerrarTareasAbiertasOperario(
        operarioId.toString(),
        req.body,
        { id: String(req.user?.sub ?? ""), rol: String(req.user?.rol ?? "") },
      );
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  trasladarOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const service = await serviceConActor(req);
      const out = await service.trasladarOperario(
        operarioId.toString(),
        req.body,
      );
      res.json(out);
    } catch (err) {
      next(err);
    }
  };
}
