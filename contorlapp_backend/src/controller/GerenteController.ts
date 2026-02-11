// src/controllers/GerenteController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { GerenteService } from "../services/GerenteServices";
import { ListarUsuariosDTO, UsuarioIdParam } from "../model/Gerente";

// ── Schemas de params simples ────────────────────────────────────────────────
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

// Para endpoints que agregan insumo a conjunto por URL + body
const AddInsumoBody = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

// Para asignar operario a conjunto por URL + body
const AsignarOperarioBody = z.object({
  operarioId: z.number().int().positive(),
});

// Para reemplazos masivos de administradores
const ReemplazosBody = z.object({
  reemplazos: z.array(
    z.object({
      conjuntoId: z.string().min(3),
      nuevoAdminId: z.number().int().positive(),
    }),
  ),
});

// Actualizar límite de horas semanales
const LimiteHorasBody = z.object({
  limiteHorasSemana: z.coerce.number().int().min(1).max(84),
});

const QuitarOperarioBody = z.object({
  operarioId: z.string().min(1),
});

const service = new GerenteService(prisma);

export class GerenteController {
  // ── Empresa ────────────────────────────────────────────────────────────────
  crearEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const out = await service.crearEmpresa(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  actualizarLimiteHoras: RequestHandler = async (req, res, next) => {
    try {
      const { limiteHorasSemana } = LimiteHorasBody.parse(req.body);
      const out = await service.actualizarLimiteHorasEmpresa(limiteHorasSemana);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Usuarios ───────────────────────────────────────────────────────────────
  crearUsuario: RequestHandler = async (req, res, next) => {
    try {
      const out = await service.crearUsuario(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  editarUsuario: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const out = await service.editarUsuario(id.toString(), req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  listarUsuarios: RequestHandler = async (req, res, next) => {
    try {
      const dto = ListarUsuariosDTO.parse(req.query);

      const usuarios = await service.listarUsuarios(dto.rol);

      res.json(usuarios);
    } catch (err) {
      next(err);
    }
  };

  // ── Roles / Perfiles ──────────────────────────────────────────────────────
  asignarGerente: RequestHandler = async (req, res, next) => {
    try {
      const out = await service.asignarGerente(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const out = await service.asignarAdministrador(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarJefeOperaciones: RequestHandler = async (req, res, next) => {
    try {
      const out = await service.asignarJefeOperaciones(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const out = await service.asignarSupervisor(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  listarSupervisores: RequestHandler = async (_req, res, next) => {
    try {
      const supervisores = await service.listarSupervisores();
      res.json(supervisores);
    } catch (err) {
      console.error("Error al listar supervisores:", err);
      next(err);
    }
  };

  listarTareasPorConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const out = await service.listarTareasPorConjunto(conjuntoId);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarOperario: RequestHandler = async (req, res, next) => {
    try {
      const out = await service.asignarOperario(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Conjuntos ─────────────────────────────────────────────────────────────
  crearConjunto: RequestHandler = async (req, res, next) => {
    try {
      const out = await service.crearConjunto(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  listarConjuntos: RequestHandler = async (_req, res, next) => {
    try {
      const out = await service.listarConjuntos();
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  obtenerConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const out = await service.obtenerConjunto(conjuntoId);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  editarConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const out = await service.editarConjunto(conjuntoId, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarOperarioAConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const { operarioId } = AsignarOperarioBody.parse(req.body);

      await service.asignarOperarioAConjunto({
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

      await service.quitarOperarioDeConjunto({ conjuntoId, operarioId });
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // ── Inventario / Insumos ──────────────────────────────────────────────────
  agregarInsumoAConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const body = AddInsumoBody.parse(req.body);
      const out = await service.agregarInsumoAConjunto({
        conjuntoId,
        insumoId: body.insumoId,
        cantidad: body.cantidad,
      });
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Tareas ────────────────────────────────────────────────────────────────
  asignarTarea: RequestHandler = async (req, res, next) => {
    try {
      const body: any = req.body ?? {};

      const tipo = String(body?.tipo ?? "CORRECTIVA").toUpperCase();
      const prioridad = Number(body?.prioridad ?? 2);

      // ✅ 1) Correctiva P1: entra por reglas (buscar hueco / reemplazos P3/P2)
      if (tipo === "CORRECTIVA" && prioridad === 1) {
        const r = await service.crearCorrectivaP1ConReglas(body);

        // A) Creada sin reemplazo (en hueco) → 201
        if (r.ok && r.mode === "CREADA_SIN_REEMPLAZO") {
          res.status(201).json({
            ok: true,
            tareaId: r.createdP1Id,
            createdP1Id: r.createdP1Id,
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

        // B) Auto reemplazo P3 → 200 (para UI info)
        if (r.ok && r.mode === "AUTO_REEMPLAZO_P3") {
          res.status(200).json({
            ok: true,
            tareaId: r.createdP1Id,
            createdP1Id: r.createdP1Id,
            autoReplaced: r.info?.reemplazadas ?? [],
            reemplazadasIds: r.reemplazadasIds ?? [],
          });
          return;
        }

        // C) Requiere confirmación P2 → 200 con flag para UI
        if (r.ok && r.mode === "REQUIERE_CONFIRMACION_P2") {
          const reemplazablesP2 = (r.opciones ?? []).flatMap((op: any) => {
            return (op.tareas ?? []).map((t: any) => ({
              id: t.id,
              prioridad: t.prioridad,
              descripcion: t.descripcion,
              tipo: t.tipo ?? "PREVENTIVA",
              fechaInicio: t.fechaInicio,
              fechaFin: t.fechaFin,
            }));
          });

          res.status(200).json({
            needsReplacement: true,
            ok: false,
            message: r.message,
            reemplazablesP2,
            suggestedInicio: r.slotSugerido?.fechaInicio ?? null,
            suggestedFin: r.slotSugerido?.fechaFin ?? null,
          });
          return;
        }

        // D) No se pudo
        res.status(200).json({
          ok: false,
          reason: r.reason,
          message: r.message,
        });
        return;
      }

      // ✅ 2) No es P1: asignación normal (incluye validación solapes/sugerencias)
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
      const out = await service.asignarTareaConReemplazo(req.body);
      if (out?.ok === false) return res.status(400).json(out);
      return res.status(200).json(out);
    } catch (e: any) {
      return res
        .status(400)
        .json({ ok: false, message: e?.message ?? String(e) });
    }
  };

  editarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const out = await service.editarTarea(tareaId, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Eliminaciones con reglas ──────────────────────────────────────────────
  eliminarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const { adminId } = AdminIdParam.parse(req.params);
      await service.eliminarAdministrador(adminId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  reemplazarAdminEnVariosConjuntos: RequestHandler = async (req, res, next) => {
    try {
      const { reemplazos } = ReemplazosBody.parse(req.body);
      await service.reemplazarAdminEnVariosConjuntos(reemplazos);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      await service.eliminarOperario(operarioId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      await service.eliminarSupervisor(supervisorId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarUsuario: RequestHandler = async (req, res, next) => {
    try {
      const { id } = UsuarioIdParam.parse(req.params);
      await service.eliminarUsuario(id);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      await service.eliminarConjunto(conjuntoId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      await service.eliminarMaquinaria(maquinariaId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      await service.eliminarTarea(prisma, tareaId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // ── Ediciones rápidas ─────────────────────────────────────────────────────
  editarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const { adminId } = AdminIdParam.parse(req.params);
      await service.editarAdministrador(adminId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  editarOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      await service.editarOperario(operarioId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  editarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      await service.editarSupervisor(supervisorId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };
}
