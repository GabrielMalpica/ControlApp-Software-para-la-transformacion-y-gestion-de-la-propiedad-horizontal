// src/services/ConjuntoNecesidadService.ts
import type { PrismaClient, Prisma, TipoFuncion } from "@prisma/client";
import {
  CrearNecesidadDTO,
  EditarNecesidadDTO,
  AsignarOperarioNecesidadDTO,
  necesidadPublicSelect,
} from "../model/ConjuntoNecesidad";

const ETIQUETA_ROL: Record<TipoFuncion, string> = {
  TODERO: "Todero",
  SALVAVIDAS: "Salvavidas",
  ASEO: "Aseo",
  PISCINERO: "Piscinero",
  JARDINERO: "Jardinero",
};

/** "Todero-Salvavidas" para una plaza combinada; "Todero" para una sola. */
function etiquetaRoles(roles: TipoFuncion[]): string {
  return roles.map((r) => ETIQUETA_ROL[r] ?? r).join("-");
}

/** Clave estable (orden-independiente) para agrupar plazas por combinación de roles. */
function claveRoles(roles: TipoFuncion[]): string {
  return [...roles].sort().join("+");
}

type ResultadoEliminar =
  | { ok: true }
  | {
      ok: false;
      requiresConfirmation: true;
      motivo: "OCUPADA" | "CON_DEFINICIONES" | "OCUPADA_Y_CON_DEFINICIONES";
      mensaje: string;
    };

/**
 * CRUD de necesidades operativas (plazas/cargos) de un conjunto. Ver el
 * análisis en el plan de "Necesidades operativas del conjunto": la
 * necesidad pertenece al conjunto, el operario es quien la ocupa
 * temporalmente (0..1 por necesidad, y un operario ocupa como máximo una
 * plaza por conjunto).
 */
export class ConjuntoNecesidadService {
  constructor(
    private prisma: PrismaClient,
    private conjuntoId: string,
  ) {}

  private async conjuntoExiste() {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: this.conjuntoId },
      select: { nit: true },
    });
    if (!conjunto) throw new Error("Conjunto no encontrado.");
  }

  private async validarEtiquetaUnica(etiqueta: string, excluirId?: number) {
    const existente = await this.prisma.conjuntoNecesidadOperario.findFirst({
      where: {
        conjuntoId: this.conjuntoId,
        etiqueta,
        ...(excluirId != null ? { id: { not: excluirId } } : {}),
      },
      select: { id: true },
    });
    if (existente) {
      throw new Error(
        `Ya existe una necesidad con la etiqueta "${etiqueta}" en este conjunto.`,
      );
    }
  }

  /**
   * Valida que el operario tenga TODOS los roles requeridos (una plaza
   * combinada, p.ej. "Todero-Salvavidas", exige que quien la ocupe cumpla
   * cada uno); si no pertenece todavía al conjunto, lo conecta (regla H:
   * "si no, conectarlo en la misma transacción").
   *
   * Si el operario ya ocupa otra plaza en este conjunto: con
   * `moverSiOcupada` (usado por `asignarOperario`, para poder cambiar a
   * alguien de plaza sin el paso manual de liberar primero) la libera aquí
   * mismo; sin esa opción (usado por `crear`, donde pre-asignar un operario
   * a una plaza nueva es una acción más deliberada) rechaza la operación.
   */
  private async validarYPrepararOperario(
    operarioId: string,
    roles: TipoFuncion[],
    options: { moverSiOcupada?: boolean; tx?: Prisma.TransactionClient } = {},
  ) {
    const db = options.tx ?? this.prisma;
    const operario = await db.operario.findUnique({
      where: { id: operarioId },
      select: {
        id: true,
        funciones: true,
        conjuntos: { where: { nit: this.conjuntoId }, select: { nit: true } },
        necesidadesOcupadas: {
          where: { conjuntoId: this.conjuntoId, activo: true },
          select: { id: true, etiqueta: true },
        },
      },
    });
    if (!operario) throw new Error("Operario no encontrado.");
    const faltantes = roles.filter((r) => !operario.funciones.includes(r));
    if (faltantes.length > 0) {
      throw new Error(
        `El operario no tiene el rol ${etiquetaRoles(faltantes)}; agrégaselo antes de asignarlo a esta plaza.`,
      );
    }
    if (operario.necesidadesOcupadas.length > 0) {
      if (!options.moverSiOcupada) {
        throw new Error(
          `El operario ya ocupa la plaza "${operario.necesidadesOcupadas[0].etiqueta}" en este conjunto; libérala primero.`,
        );
      }
      await db.conjuntoNecesidadOperario.update({
        where: { id: operario.necesidadesOcupadas[0].id },
        data: { operarioId: null },
      });
    }
    if (!operario.conjuntos.length) {
      await db.conjunto.update({
        where: { nit: this.conjuntoId },
        data: { operarios: { connect: { id: operarioId } } },
      });
    }
  }

  async listar() {
    return this.prisma.conjuntoNecesidadOperario.findMany({
      where: { conjuntoId: this.conjuntoId },
      select: necesidadPublicSelect,
      orderBy: [{ orden: "asc" }, { etiqueta: "asc" }],
    });
  }

  async crear(payload: unknown) {
    await this.conjuntoExiste();
    const dto = CrearNecesidadDTO.parse(payload);
    await this.validarEtiquetaUnica(dto.etiqueta);
    if (dto.operarioId) {
      await this.validarYPrepararOperario(dto.operarioId, dto.roles);
    }

    return this.prisma.conjuntoNecesidadOperario.create({
      data: {
        conjuntoId: this.conjuntoId,
        roles: dto.roles,
        etiqueta: dto.etiqueta,
        orden: dto.orden,
        horarioEspecial: dto.horarioEspecial,
        observaciones: dto.observaciones ?? null,
        operarioId: dto.operarioId ?? null,
        horarios: dto.horarios.length
          ? {
              create: dto.horarios.map((h) => ({
                dia: h.dia,
                horaApertura: h.horaApertura,
                horaCierre: h.horaCierre,
                descansoInicio: h.descansoInicio ?? null,
                descansoFin: h.descansoFin ?? null,
              })),
            }
          : undefined,
      },
      select: necesidadPublicSelect,
    });
  }

  async editar(id: number, payload: unknown) {
    const dto = EditarNecesidadDTO.parse(payload);
    const actual = await this.prisma.conjuntoNecesidadOperario.findFirst({
      where: { id, conjuntoId: this.conjuntoId },
      select: { id: true, horarioEspecial: true, operarioId: true },
    });
    if (!actual) throw new Error("Necesidad no encontrada.");

    if (dto.etiqueta) await this.validarEtiquetaUnica(dto.etiqueta, id);

    // Si cambian los roles y la plaza está ocupada, el operario actual debe
    // seguir cumpliendo TODOS los roles nuevos (si no, primero hay que
    // liberar la plaza).
    if (dto.roles && actual.operarioId) {
      const operario = await this.prisma.operario.findUnique({
        where: { id: actual.operarioId },
        select: { funciones: true },
      });
      const faltantes = dto.roles.filter((r) => !(operario?.funciones.includes(r) ?? false));
      if (faltantes.length > 0) {
        throw new Error(
          `El operario que ocupa esta plaza no tiene el rol ${etiquetaRoles(faltantes)}; libera la plaza antes de cambiarlo.`,
        );
      }
    }

    // Invariante: si el horario especial queda activo, debe haber al menos
    // un día configurado al terminar esta edición (ya sea porque este
    // payload trae filas, o porque ya existían y no se tocaron).
    const horarioEspecialFinal = dto.horarioEspecial ?? actual.horarioEspecial;
    if (horarioEspecialFinal) {
      const cantidadFinal =
        dto.horarios != null
          ? dto.horarios.length
          : await this.prisma.conjuntoNecesidadHorario.count({ where: { necesidadId: id } });
      if (cantidadFinal === 0) {
        throw new Error(
          "Si el horario especial está activo, la plaza debe tener al menos un día configurado.",
        );
      }
    }

    return this.prisma.$transaction(async (tx) => {
      if (dto.horarios) {
        await tx.conjuntoNecesidadHorario.deleteMany({ where: { necesidadId: id } });
      }
      return tx.conjuntoNecesidadOperario.update({
        where: { id },
        data: {
          roles: dto.roles,
          etiqueta: dto.etiqueta,
          orden: dto.orden,
          horarioEspecial: dto.horarioEspecial,
          observaciones: dto.observaciones,
          activo: dto.activo,
          horarios: dto.horarios
            ? {
                create: dto.horarios.map((h) => ({
                  dia: h.dia,
                  horaApertura: h.horaApertura,
                  horaCierre: h.horaCierre,
                  descansoInicio: h.descansoInicio ?? null,
                  descansoFin: h.descansoFin ?? null,
                })),
              }
            : undefined,
        },
        select: necesidadPublicSelect,
      });
    });
  }

  async eliminar(id: number, options: { confirmar?: boolean } = {}): Promise<ResultadoEliminar> {
    const { confirmar = false } = options;
    const necesidad = await this.prisma.conjuntoNecesidadOperario.findFirst({
      where: { id, conjuntoId: this.conjuntoId },
      select: {
        id: true,
        etiqueta: true,
        operarioId: true,
        _count: { select: { definiciones: true } },
      },
    });
    if (!necesidad) throw new Error("Necesidad no encontrada.");

    const ocupada = necesidad.operarioId != null;
    const conDefiniciones = necesidad._count.definiciones > 0;
    if ((ocupada || conDefiniciones) && !confirmar) {
      const motivo =
        ocupada && conDefiniciones
          ? ("OCUPADA_Y_CON_DEFINICIONES" as const)
          : ocupada
            ? ("OCUPADA" as const)
            : ("CON_DEFINICIONES" as const);
      return {
        ok: false,
        requiresConfirmation: true,
        motivo,
        mensaje: ocupada
          ? `La plaza "${necesidad.etiqueta}" está ocupada${conDefiniciones ? " y tiene preventivas vinculadas" : ""}. Confirma para eliminarla de todas formas.`
          : `La plaza "${necesidad.etiqueta}" tiene preventivas vinculadas. Confirma para eliminarla de todas formas.`,
      };
    }

    await this.prisma.conjuntoNecesidadOperario.delete({ where: { id } });
    return { ok: true };
  }

  /**
   * Asigna un operario a una plaza vacante. Si el operario ya ocupa otra
   * plaza en este mismo conjunto, lo mueve: libera la anterior y ocupa esta,
   * en una sola transacción (evita el paso manual "liberar y luego
   * asignar" para cambiar a alguien de cargo).
   */
  async asignarOperario(id: number, payload: unknown) {
    const { operarioId } = AsignarOperarioNecesidadDTO.parse(payload);
    return this.prisma.$transaction(async (tx) => {
      const necesidad = await tx.conjuntoNecesidadOperario.findFirst({
        where: { id, conjuntoId: this.conjuntoId },
        select: { id: true, roles: true, operarioId: true, etiqueta: true },
      });
      if (!necesidad) throw new Error("Necesidad no encontrada.");
      if (necesidad.operarioId) {
        throw new Error(
          `La plaza "${necesidad.etiqueta}" ya está ocupada; libérala antes de asignar otro operario.`,
        );
      }
      await this.validarYPrepararOperario(operarioId, necesidad.roles, {
        moverSiOcupada: true,
        tx,
      });

      return tx.conjuntoNecesidadOperario.update({
        where: { id },
        data: { operarioId },
        select: necesidadPublicSelect,
      });
    });
  }

  async liberarOperario(id: number) {
    const necesidad = await this.prisma.conjuntoNecesidadOperario.findFirst({
      where: { id, conjuntoId: this.conjuntoId },
      select: { id: true },
    });
    if (!necesidad) throw new Error("Necesidad no encontrada.");
    return this.prisma.conjuntoNecesidadOperario.update({
      where: { id },
      data: { operarioId: null },
      select: necesidadPublicSelect,
    });
  }

  /**
   * Backfill idempotente (paso G.2 del plan de necesidades operativas):
   * crea una plaza por cada operario ya asignado al conjunto que todavía no
   * ocupa ninguna, con horarioEspecial=false. Al heredar el horario general
   * del conjunto, el cronograma generado queda idéntico al de antes de
   * migrar; el beneficio (reemplazo sin editar tareas) aparece a partir de
   * aquí hacia adelante.
   */
  async migrarDesdeOperariosActuales() {
    const [operarios, necesidadesExistentes] = await Promise.all([
      this.prisma.operario.findMany({
        where: { conjuntos: { some: { nit: this.conjuntoId } } },
        select: { id: true, funciones: true },
      }),
      this.prisma.conjuntoNecesidadOperario.findMany({
        where: { conjuntoId: this.conjuntoId },
        select: { operarioId: true, roles: true },
      }),
    ]);

    const ocupadas = new Set(
      necesidadesExistentes.map((n) => n.operarioId).filter((id): id is string => id != null),
    );
    // Cuenta por combinación de roles (p.ej. "Todero+Salvavidas" numera
    // aparte de "Todero" solo), para que la etiqueta sugerida ("Todero #2")
    // no choque entre plazas de distinta combinación.
    const contadorPorClave = new Map<string, number>();
    for (const n of necesidadesExistentes) {
      const clave = claveRoles(n.roles);
      contadorPorClave.set(clave, (contadorPorClave.get(clave) ?? 0) + 1);
    }

    const creadas: Array<{ etiqueta: string; operarioId: string }> = [];
    for (const operario of operarios) {
      if (ocupadas.has(operario.id)) continue;
      // Todos los roles actuales del operario pasan a la plaza (si tiene
      // varios, la plaza queda combinada desde el arranque).
      const roles = operario.funciones;
      if (!roles.length) continue; // sin funciones no hay de dónde inferir la plaza
      const clave = claveRoles(roles);
      const siguiente = (contadorPorClave.get(clave) ?? 0) + 1;
      contadorPorClave.set(clave, siguiente);
      const etiqueta = `${etiquetaRoles(roles)} #${siguiente}`;
      await this.prisma.conjuntoNecesidadOperario.create({
        data: {
          conjuntoId: this.conjuntoId,
          roles,
          etiqueta,
          orden: siguiente,
          horarioEspecial: false,
          operarioId: operario.id,
        },
      });
      creadas.push({ etiqueta, operarioId: operario.id });
    }
    return { creadas };
  }
}
