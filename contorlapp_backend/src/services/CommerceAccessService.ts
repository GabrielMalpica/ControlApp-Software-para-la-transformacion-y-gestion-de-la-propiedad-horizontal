import { Rol, TipoPedidoApp, type PrismaClient } from "@prisma/client";

export type CommerceActor = {
  id: string;
  nombre: string;
  rol: Rol;
  empresaId: string | null;
  residente: { conjuntoId: string } | null;
};

export function commerceHttpError(status: number, message: string) {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export class CommerceAccessService {
  constructor(private prisma: PrismaClient) {}

  async getActor(userId: string): Promise<CommerceActor> {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: {
        id: true,
        nombre: true,
        rol: true,
        gerente: { select: { empresaId: true } },
        jefeOperaciones: { select: { empresaId: true } },
        residente: { select: { conjuntoId: true } },
      },
    });
    if (!usuario) throw commerceHttpError(404, "Usuario no encontrado");

    const rol = String(usuario.rol).trim().toLowerCase() as Rol;
    if (!Object.values(Rol).includes(rol)) {
      throw commerceHttpError(403, "Tu rol no tiene acceso al modulo de comercio");
    }

    return {
      id: usuario.id,
      nombre: usuario.nombre,
      rol,
      empresaId:
        rol === Rol.gerente
          ? usuario.gerente?.empresaId ?? null
          : rol === Rol.jefe_operaciones
            ? usuario.jefeOperaciones?.empresaId ?? null
            : null,
      residente: usuario.residente,
    };
  }

  esRolOperativo(actor: CommerceActor) {
    return (
      actor.rol === Rol.administrador ||
      actor.rol === Rol.gerente ||
      actor.rol === Rol.jefe_operaciones
    );
  }

  async getAuthorizedConjuntoIds(actor: CommerceActor) {
    if (actor.rol === Rol.residente) {
      return actor.residente ? [actor.residente.conjuntoId] : [];
    }
    if (actor.rol === Rol.administrador) {
      const conjuntos = await this.prisma.conjunto.findMany({
        where: { administradorId: actor.id },
        select: { nit: true },
      });
      return conjuntos.map((conjunto) => conjunto.nit);
    }
    if (actor.rol === Rol.gerente || actor.rol === Rol.jefe_operaciones) {
      if (!actor.empresaId) return [];
      const conjuntos = await this.prisma.conjunto.findMany({
        where: { empresaId: actor.empresaId },
        select: { nit: true },
      });
      return conjuntos.map((conjunto) => conjunto.nit);
    }
    return [];
  }

  async assertConjuntoAccess(actor: CommerceActor, conjuntoId: string) {
    const conjuntoIds = await this.getAuthorizedConjuntoIds(actor);
    if (!conjuntoIds.includes(conjuntoId)) {
      throw commerceHttpError(403, "No tienes acceso al conjunto de este pedido");
    }
  }

  async assertPedidoAccess(
    actor: CommerceActor,
    pedido: {
      tipo: TipoPedidoApp;
      usuarioId: string;
      conjuntoId: string | null;
    },
  ) {
    if (actor.rol === Rol.residente) {
      if (pedido.tipo !== TipoPedidoApp.RESIDENTE || pedido.usuarioId !== actor.id) {
        throw commerceHttpError(403, "Solo puedes consultar y gestionar tus propios pedidos");
      }
      return;
    }
    if (!this.esRolOperativo(actor) || !pedido.conjuntoId) {
      throw commerceHttpError(403, "Tu rol no puede gestionar este pedido");
    }
    await this.assertConjuntoAccess(actor, pedido.conjuntoId);
  }
}
