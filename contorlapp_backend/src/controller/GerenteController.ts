// src/controllers/GerenteController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
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
    })
  ),
});

// Actualizar límite de horas semanales
const LimiteHorasBody = z.object({
  limiteHorasSemana: z.coerce.number().int().min(1).max(84),
});

export class GerenteController {
  private prisma: PrismaClient;
  private service: GerenteService;

  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
    this.service = new GerenteService(this.prisma);
  }

  // ── Empresa ────────────────────────────────────────────────────────────────
  crearEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.crearEmpresa(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  actualizarLimiteHoras: RequestHandler = async (req, res, next) => {
    try {
      const { limiteHorasSemana } = LimiteHorasBody.parse(req.body);
      const out = await this.service.actualizarLimiteHorasEmpresa(
        limiteHorasSemana
      );
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Catálogo de insumos (empresa corporativa) ─────────────────────────────
  agregarInsumoAlCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.agregarInsumoAlCatalogo(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  listarCatalogoInsumos: RequestHandler = async (_req, res, next) => {
    try {
      const out = await this.service.listarCatalogo();
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Usuarios ───────────────────────────────────────────────────────────────
  crearUsuario: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.crearUsuario(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  editarUsuario: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const out = await this.service.editarUsuario(id.toString(), req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  listarUsuarios: RequestHandler = async (req, res, next) => {
    try {
      const dto = ListarUsuariosDTO.parse(req.query);

      const usuarios = await this.service.listarUsuarios(dto.rol);

      res.json(usuarios);
    } catch (err) {
      next(err);
    }
  };

  // ── Roles / Perfiles ──────────────────────────────────────────────────────
  asignarGerente: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.asignarGerente(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.asignarAdministrador(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarJefeOperaciones: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.asignarJefeOperaciones(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.asignarSupervisor(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarOperario: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.asignarOperario(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Conjuntos ─────────────────────────────────────────────────────────────
  crearConjunto: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.crearConjunto(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  editarConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const out = await this.service.editarConjunto(conjuntoId, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  asignarOperarioAConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      const { operarioId } = AsignarOperarioBody.parse(req.body);
      await this.service.asignarOperarioAConjunto({ conjuntoId, operarioId });
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
      const out = await this.service.agregarInsumoAConjunto({
        conjuntoId,
        insumoId: body.insumoId,
        cantidad: body.cantidad,
      });
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Maquinaria ────────────────────────────────────────────────────────────
  crearMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.crearMaquinaria(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  editarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      const out = await this.service.editarMaquinaria(maquinariaId, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  entregarMaquinariaAConjunto: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.entregarMaquinariaAConjunto(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Tareas ────────────────────────────────────────────────────────────────
  asignarTarea: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.asignarTarea(req.body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  editarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const out = await this.service.editarTarea(tareaId, req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // ── Eliminaciones con reglas ──────────────────────────────────────────────
  eliminarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const { adminId } = AdminIdParam.parse(req.params);
      await this.service.eliminarAdministrador(adminId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  reemplazarAdminEnVariosConjuntos: RequestHandler = async (req, res, next) => {
    try {
      const { reemplazos } = ReemplazosBody.parse(req.body);
      await this.service.reemplazarAdminEnVariosConjuntos(reemplazos);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      await this.service.eliminarOperario(operarioId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      await this.service.eliminarSupervisor(supervisorId.toString());
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarUsuario: RequestHandler = async (req, res, next) => {
    try {
      const { id } = UsuarioIdParam.parse(req.params);
      await this.service.eliminarUsuario(id);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoIdParam.parse(req.params);
      await this.service.eliminarConjunto(conjuntoId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      await this.service.eliminarMaquinaria(maquinariaId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  eliminarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      await this.service.eliminarTarea(tareaId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // ── Ediciones rápidas ─────────────────────────────────────────────────────
  editarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const { adminId } = AdminIdParam.parse(req.params);
      await this.service.editarAdministrador(adminId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  editarOperario: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      await this.service.editarOperario(operarioId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  editarSupervisor: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      await this.service.editarSupervisor(supervisorId, req.body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };
}
