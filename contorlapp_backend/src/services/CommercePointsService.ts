import {
  Prisma,
  Rol,
  TipoMovimientoPuntos,
  TipoPedidoApp,
  type EstadoPedidoInterno,
  type PrismaClient,
} from "@prisma/client";
import {
  AjustarPuntosDTO,
  ConfigurarPuntosDTO,
  PuntosContextoDTO,
  RedimirBeneficioDTO,
} from "../model/Commerce";
import {
  CommerceAccessService,
  commerceHttpError,
  type CommerceActor,
} from "./CommerceAccessService";

type TransactionClient = Prisma.TransactionClient;

type PedidoParaPuntos = {
  id: number;
  usuarioId: string;
  conjuntoId: string | null;
  tipo: TipoPedidoApp;
  estado: EstadoPedidoInterno;
  total: Prisma.Decimal;
  puntosAplicados: boolean;
};

export class CommercePointsService {
  private readonly access: CommerceAccessService;

  constructor(private prisma: PrismaClient) {
    this.access = new CommerceAccessService(prisma);
  }

  private async resolveConjunto(actor: CommerceActor, conjuntoId?: string) {
    const requestedId = conjuntoId?.trim();
    if (actor.rol === Rol.residente) {
      if (!actor.residente) {
        throw commerceHttpError(403, "Tu usuario no tiene un residente asociado");
      }
      if (requestedId && requestedId !== actor.residente.conjuntoId) {
        throw commerceHttpError(403, "No tienes acceso a los puntos de ese conjunto");
      }
      return actor.residente.conjuntoId;
    }

    if (!this.access.esRolOperativo(actor)) {
      throw commerceHttpError(403, "Tu rol no tiene acceso al programa de puntos");
    }
    const authorizedIds = await this.access.getAuthorizedConjuntoIds(actor);
    const resolvedId = requestedId ?? authorizedIds[0];
    if (!resolvedId || !authorizedIds.includes(resolvedId)) {
      throw commerceHttpError(403, "Selecciona un conjunto al que tengas acceso");
    }
    return resolvedId;
  }

  private serializeConfig(
    config: {
      id: number;
      conjuntoId: string;
      activo: boolean;
      montoPorPuntoResidente: Prisma.Decimal;
      montoPorPuntoConjunto: Prisma.Decimal;
      minimoRedencionPuntos: number;
      beneficios: Array<{
        id: number;
        nombre: string;
        descripcion: string | null;
        puntosCosto: number;
        valorDescuento: Prisma.Decimal;
        activo: boolean;
      }>;
    } | null,
    conjuntoId: string,
  ) {
    return {
      id: config?.id ?? null,
      conjuntoId,
      activo: config?.activo ?? false,
      montoPorPuntoResidente: Number(config?.montoPorPuntoResidente ?? 1000),
      montoPorPuntoConjunto: Number(config?.montoPorPuntoConjunto ?? 1000),
      minimoRedencionPuntos: config?.minimoRedencionPuntos ?? 100,
      beneficios: (config?.beneficios ?? []).map((beneficio) => ({
        ...beneficio,
        valorDescuento: Number(beneficio.valorDescuento),
      })),
    };
  }

  private async getSaldo(
    client: TransactionClient | PrismaClient,
    usuarioId: string,
    conjuntoId: string,
  ) {
    const aggregate = await client.movimientoPuntos.aggregate({
      where: { usuarioId, conjuntoId },
      _sum: { puntos: true },
    });
    return aggregate._sum.puntos ?? 0;
  }

  async getResumen(userId: string, query: unknown) {
    const { conjuntoId: requestedId } = PuntosContextoDTO.parse(query);
    const actor = await this.access.getActor(userId);
    const conjuntoId = await this.resolveConjunto(actor, requestedId);
    const [config, saldo, movimientos, conjunto] = await Promise.all([
      this.prisma.configPuntosConjunto.findUnique({
        where: { conjuntoId },
        include: {
          beneficios: {
            where: { activo: true },
            orderBy: [{ puntosCosto: "asc" }, { nombre: "asc" }],
          },
        },
      }),
      this.getSaldo(this.prisma, userId, conjuntoId),
      this.prisma.movimientoPuntos.findMany({
        where: { usuarioId: userId, conjuntoId },
        include: {
          beneficio: { select: { nombre: true } },
          pedido: { select: { id: true, tipo: true } },
        },
        orderBy: { creadoEn: "desc" },
        take: 100,
      }),
      this.prisma.conjunto.findUnique({
        where: { nit: conjuntoId },
        select: { nombre: true },
      }),
    ]);

    const serializedConfig = this.serializeConfig(config, conjuntoId);
    return {
      conjuntoId,
      conjuntoNombre: conjunto?.nombre ?? conjuntoId,
      saldo,
      config: serializedConfig,
      beneficios: serializedConfig.beneficios.map((beneficio) => ({
        ...beneficio,
        disponible: serializedConfig.activo && saldo >= beneficio.puntosCosto,
      })),
      movimientos: movimientos.map((movimiento) => ({
        id: movimiento.id,
        tipo: movimiento.tipo,
        puntos: movimiento.puntos,
        descripcion: movimiento.descripcion,
        creadoEn: movimiento.creadoEn,
        pedidoId: movimiento.pedidoId,
        pedidoTipo: movimiento.pedido?.tipo ?? null,
        beneficioNombre: movimiento.beneficio?.nombre ?? null,
      })),
    };
  }

  async getConfiguracion(userId: string, query: unknown) {
    const { conjuntoId: requestedId } = PuntosContextoDTO.parse(query);
    const actor = await this.access.getActor(userId);
    if (!this.access.esRolOperativo(actor)) {
      throw commerceHttpError(403, "Tu rol no puede administrar reglas de puntos");
    }
    const conjuntoId = await this.resolveConjunto(actor, requestedId);
    const config = await this.prisma.configPuntosConjunto.findUnique({
      where: { conjuntoId },
      include: { beneficios: { orderBy: { puntosCosto: "asc" } } },
    });
    return this.serializeConfig(config, conjuntoId);
  }

  async configurar(userId: string, payload: unknown) {
    const dto = ConfigurarPuntosDTO.parse(payload);
    const actor = await this.access.getActor(userId);
    if (!this.access.esRolOperativo(actor)) {
      throw commerceHttpError(403, "Tu rol no puede administrar reglas de puntos");
    }
    await this.access.assertConjuntoAccess(actor, dto.conjuntoId);

    await this.prisma.$transaction(async (tx) => {
      const config = await tx.configPuntosConjunto.upsert({
        where: { conjuntoId: dto.conjuntoId },
        create: {
          conjuntoId: dto.conjuntoId,
          activo: dto.activo,
          montoPorPuntoResidente: new Prisma.Decimal(dto.montoPorPuntoResidente),
          montoPorPuntoConjunto: new Prisma.Decimal(dto.montoPorPuntoConjunto),
          minimoRedencionPuntos: dto.minimoRedencionPuntos,
        },
        update: {
          activo: dto.activo,
          montoPorPuntoResidente: new Prisma.Decimal(dto.montoPorPuntoResidente),
          montoPorPuntoConjunto: new Prisma.Decimal(dto.montoPorPuntoConjunto),
          minimoRedencionPuntos: dto.minimoRedencionPuntos,
        },
      });

      const ids = dto.beneficios.flatMap((beneficio) =>
        beneficio.id ? [beneficio.id] : [],
      );
      await tx.beneficioPuntos.updateMany({
        where: { configId: config.id, ...(ids.length ? { id: { notIn: ids } } : {}) },
        data: { activo: false },
      });

      for (const beneficio of dto.beneficios) {
        const data = {
          nombre: beneficio.nombre,
          descripcion: beneficio.descripcion || null,
          puntosCosto: beneficio.puntosCosto,
          valorDescuento: new Prisma.Decimal(beneficio.valorDescuento),
          activo: beneficio.activo,
        };
        if (beneficio.id) {
          const updated = await tx.beneficioPuntos.updateMany({
            where: { id: beneficio.id, configId: config.id },
            data,
          });
          if (updated.count === 0) {
            throw commerceHttpError(400, "Uno de los beneficios no pertenece al conjunto");
          }
        } else {
          await tx.beneficioPuntos.create({ data: { ...data, configId: config.id } });
        }
      }
    });

    return this.getConfiguracion(userId, { conjuntoId: dto.conjuntoId });
  }

  private async withSerializable<T>(operation: (tx: TransactionClient) => Promise<T>) {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await this.prisma.$transaction(operation, {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        });
      } catch (error) {
        if (
          attempt < 2 &&
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === "P2034"
        ) {
          continue;
        }
        throw error;
      }
    }
    throw commerceHttpError(409, "No fue posible completar la operacion. Intenta nuevamente");
  }

  async redimir(userId: string, payload: unknown) {
    const dto = RedimirBeneficioDTO.parse(payload);
    const actor = await this.access.getActor(userId);
    const conjuntoId = await this.resolveConjunto(actor, dto.conjuntoId);

    const movimiento = await this.withSerializable(async (tx) => {
      const beneficio = await tx.beneficioPuntos.findFirst({
        where: {
          id: dto.beneficioId,
          activo: true,
          config: { conjuntoId, activo: true },
        },
        include: { config: true },
      });
      if (!beneficio) {
        throw commerceHttpError(404, "El beneficio no esta activo para este conjunto");
      }
      const saldo = await this.getSaldo(tx, userId, conjuntoId);
      if (saldo < beneficio.config.minimoRedencionPuntos) {
        throw commerceHttpError(
          409,
          `Necesitas al menos ${beneficio.config.minimoRedencionPuntos} puntos para canjear`,
        );
      }
      if (saldo < beneficio.puntosCosto) {
        throw commerceHttpError(
          409,
          `Te faltan ${beneficio.puntosCosto - saldo} puntos para este beneficio`,
        );
      }

      return tx.movimientoPuntos.create({
        data: {
          usuarioId: userId,
          conjuntoId,
          beneficioId: beneficio.id,
          tipo: TipoMovimientoPuntos.REDENCION,
          puntos: -beneficio.puntosCosto,
          descripcion: `Canje: ${beneficio.nombre}`,
        },
        include: { beneficio: { select: { nombre: true, valorDescuento: true } } },
      });
    });

    return {
      movimientoId: movimiento.id,
      beneficio: movimiento.beneficio?.nombre ?? "Beneficio",
      valorDescuento: Number(movimiento.beneficio?.valorDescuento ?? 0),
      saldo: await this.getSaldo(this.prisma, userId, conjuntoId),
      message: "Canje realizado. Presenta este movimiento al aplicar el beneficio",
    };
  }

  async ajustar(userId: string, payload: unknown) {
    const dto = AjustarPuntosDTO.parse(payload);
    const actor = await this.access.getActor(userId);
    if (actor.rol !== Rol.gerente && actor.rol !== Rol.jefe_operaciones) {
      throw commerceHttpError(403, "Solo gerencia u operaciones pueden ajustar puntos");
    }
    await this.access.assertConjuntoAccess(actor, dto.conjuntoId);

    const target = await this.prisma.usuario.findFirst({
      where: {
        id: dto.usuarioId,
        OR: [
          { residente: { conjuntoId: dto.conjuntoId } },
          { administrador: { conjuntos: { some: { nit: dto.conjuntoId } } } },
          { id: actor.id },
        ],
      },
      select: { id: true },
    });
    if (!target) {
      throw commerceHttpError(403, "El usuario no pertenece al contexto del conjunto");
    }

    const movimiento = await this.withSerializable(async (tx) => {
      const saldo = await this.getSaldo(tx, dto.usuarioId, dto.conjuntoId);
      if (saldo + dto.puntos < 0) {
        throw commerceHttpError(409, "El ajuste dejaria un saldo negativo");
      }
      return tx.movimientoPuntos.create({
        data: {
          usuarioId: dto.usuarioId,
          conjuntoId: dto.conjuntoId,
          tipo: TipoMovimientoPuntos.AJUSTE,
          puntos: dto.puntos,
          descripcion: dto.descripcion,
        },
      });
    });
    return { id: movimiento.id, message: "Ajuste de puntos registrado" };
  }

  async applyAccumulation(tx: TransactionClient, pedido: PedidoParaPuntos) {
    if (pedido.puntosAplicados || !pedido.conjuntoId) return 0;

    const claimed = await tx.pedidoApp.updateMany({
      where: { id: pedido.id, puntosAplicados: false },
      data: { puntosAplicados: true, puntosAplicadosEn: new Date() },
    });
    if (claimed.count === 0) return 0;

    const config = await tx.configPuntosConjunto.findUnique({
      where: { conjuntoId: pedido.conjuntoId },
    });
    if (!config?.activo) return 0;

    const montoPorPunto =
      pedido.tipo === TipoPedidoApp.RESIDENTE
        ? config.montoPorPuntoResidente
        : config.montoPorPuntoConjunto;
    const puntos = Math.floor(Number(pedido.total) / Number(montoPorPunto));
    if (puntos <= 0) return 0;

    await tx.movimientoPuntos.create({
      data: {
        usuarioId: pedido.usuarioId,
        conjuntoId: pedido.conjuntoId,
        pedidoId: pedido.id,
        tipo: TipoMovimientoPuntos.ACUMULACION,
        puntos,
        descripcion: `Puntos por entrega del pedido #${pedido.id}`,
      },
    });
    return puntos;
  }
}
