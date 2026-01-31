// src/services/DefinicionTareaPreventivaService.ts
import type { PrismaClient } from "../generated/prisma";
import {
  Prisma,
  TipoTarea,
  EstadoTarea,
  Frecuencia,
  DiaSemana,
} from "../generated/prisma";
import {
  CrearDefinicionPreventivaDTO,
  EditarDefinicionPreventivaDTO,
  FiltroDefinicionPreventivaDTO,
  GenerarCronogramaDTO,
  calcularMinutosEstimados,
} from "../model/DefinicionTareaPreventiva";
import { z } from "zod";
import { Bloqueo, HorarioDia } from "../utils/agenda";
import {
  buildAgendaPorOperarioDia,
  buscarHuecoDiaConSplitEarliest,
  findNextValidDay,
  getFestivosSet,
  intentarReemplazoPorPrioridadBaja,
  siguienteDiaHabil,
  splitMinutes,
  toDateAtMin,
  toMin,
} from "../utils/schedulerUtils";
import { buildMaquinariaNoDisponibleError } from "../utils/errorFormat";

/* ============== DTOs internos (Zod) ============== */

const DividirTareaBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.number().int().positive(),
  bloques: z
    .array(
      z.object({
        fechaInicio: z.coerce.date(),
        fechaFin: z.coerce.date(),
      }),
    )
    .min(2, "Debe dividirse en al menos 2 bloques"),
});

const EditarBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.number().int().positive(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  duracionMinutos: z.number().int().min(1).optional(),
  operariosIds: z.array(z.number().int().positive()).optional(),
});

const CrearBloqueBorradorDTO = z.object({
  descripcion: z.string().min(3),
  fechaInicio: z.coerce.date(),
  fechaFin: z.coerce.date(),
  ubicacionId: z.number().int().positive(),
  elementoId: z.number().int().positive(),
  operariosIds: z.array(z.number().int().positive()).optional(),
  supervisorId: z.number().int().positive().nullable().optional(),
  tiempoEstimadoMinutos: z.number().positive().optional(),
});

const DividirBloqueDTO = z.object({
  fechaInicio1: z.coerce.date(),
  fechaFin1: z.coerce.date(),
  fechaInicio2: z.coerce.date(),
  fechaFin2: z.coerce.date(),
});

const EditarBloqueBorradorDTO = z.object({
  descripcion: z.string().min(3).optional(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  duracionMinutos: z.number().int().positive().optional(),
  ubicacionId: z.number().int().positive().optional(),
  elementoId: z.number().int().positive().optional(),
  operariosIds: z.array(z.number().int().positive()).optional(),
  supervisorId: z.number().int().positive().nullable().optional(),
  tiempoEstimadoMinutos: z.number().positive().nullable().optional(),
});

/* ============== SERVICE ============== */

export class DefinicionTareaPreventivaService {
  constructor(private prisma: PrismaClient) {}

  /* ============== CRUD BÁSICO ============== */

  async crear(payload: unknown) {
    const dto = CrearDefinicionPreventivaDTO.parse(payload);

    const duracionMinutosFija =
      dto.duracionMinutosFija ??
      (dto.duracionHorasFija != null
        ? Math.max(1, Math.round(Number(dto.duracionHorasFija) * 60))
        : null);

    const data: Prisma.DefinicionTareaPreventivaCreateInput = {
      conjunto: { connect: { nit: dto.conjuntoId } },
      ubicacion: { connect: { id: dto.ubicacionId } },
      elemento: { connect: { id: dto.elementoId } },

      descripcion: dto.descripcion,
      frecuencia: dto.frecuencia,
      prioridad: dto.prioridad ?? 2,

      diaSemanaProgramado: dto.diaSemanaProgramado ?? null,
      diaMesProgramado: dto.diaMesProgramado ?? null,

      duracionMinutosFija,
      diasParaCompletar: dto.diasParaCompletar ?? null,

      // ✅ default coherente
      rendimientoTiempoBase: dto.rendimientoTiempoBase ?? "POR_MINUTO",

      unidadCalculo: dto.unidadCalculo ?? null,
      areaNumerica:
        dto.areaNumerica != null ? new Prisma.Decimal(dto.areaNumerica) : null,
      rendimientoBase:
        dto.rendimientoBase != null
          ? new Prisma.Decimal(dto.rendimientoBase)
          : null,

      // Insumo principal
      insumoPrincipal: dto.insumoPrincipalId
        ? { connect: { id: dto.insumoPrincipalId } }
        : undefined,
      consumoPrincipalPorUnidad:
        dto.consumoPrincipalPorUnidad != null
          ? new Prisma.Decimal(dto.consumoPrincipalPorUnidad)
          : null,

      // JSON
      insumosPlanJson: dto.insumosPlanJson
        ? (dto.insumosPlanJson as unknown as Prisma.InputJsonValue)
        : undefined,

      maquinariaPlanJson: dto.maquinariaPlanJson
        ? (dto.maquinariaPlanJson as unknown as Prisma.InputJsonValue)
        : undefined,

      herramientasPlanJson: dto.herramientasPlanJson
        ? (dto.herramientasPlanJson as unknown as Prisma.InputJsonValue)
        : undefined,

      // supervisor (relación)
      supervisor: dto.supervisorId
        ? { connect: { id: dto.supervisorId.toString() } }
        : undefined,

      activo: dto.activo ?? true,
    };

    // Operarios: operariosIds > responsableSugeridoId
    if (dto.operariosIds?.length) {
      (data as any).operarios = {
        connect: dto.operariosIds.map((id) => ({ id: id.toString() })),
      };
    } else if (dto.responsableSugeridoId != null) {
      (data as any).operarios = {
        connect: { id: dto.responsableSugeridoId.toString() },
      };
    }

    return this.prisma.definicionTareaPreventiva.create({ data });
  }

  async listar(payload: unknown) {
    const f = FiltroDefinicionPreventivaDTO.parse(payload);
    return this.prisma.definicionTareaPreventiva.findMany({
      where: {
        conjuntoId: f.conjuntoId,
        ubicacionId: f.ubicacionId,
        elementoId: f.elementoId,
        frecuencia: f.frecuencia,
        activo: f.activo,
      },
      include: {
        ubicacion: true,
        elemento: true,
        operarios: { include: { usuario: true } },
        supervisor: { include: { usuario: true } },
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });
  }

  async listarPorConjunto(conjuntoId: string) {
    return this.prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId },
      include: {
        ubicacion: true,
        elemento: true,
        operarios: { include: { usuario: true } },
        supervisor: { include: { usuario: true } },
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });
  }

  async actualizar(conjuntoId: string, id: number, payload: unknown) {
    const dto = EditarDefinicionPreventivaDTO.parse(payload);

    const def = await this.prisma.definicionTareaPreventiva.findUnique({
      where: { id },
      select: { id: true, conjuntoId: true },
    });
    if (!def || def.conjuntoId !== conjuntoId) {
      throw new Error("Definición no encontrada para este conjunto.");
    }

    const durMinFija =
      (dto as any).duracionMinutosFija === undefined &&
      (dto as any).duracionHorasFija === undefined
        ? undefined
        : ((dto as any).duracionMinutosFija ??
          ((dto as any).duracionHorasFija != null
            ? Math.round(Number((dto as any).duracionHorasFija) * 60)
            : null));

    const data: Prisma.DefinicionTareaPreventivaUpdateInput = {
      descripcion: dto.descripcion,
      frecuencia: dto.frecuencia,
      prioridad: dto.prioridad,
      activo: dto.activo,

      ubicacion:
        dto.ubicacionId === undefined
          ? undefined
          : { connect: { id: dto.ubicacionId } },
      elemento:
        dto.elementoId === undefined
          ? undefined
          : { connect: { id: dto.elementoId } },

      unidadCalculo: dto.unidadCalculo ?? undefined,
      areaNumerica:
        dto.areaNumerica === undefined
          ? undefined
          : dto.areaNumerica === null
            ? null
            : new Prisma.Decimal(dto.areaNumerica),

      rendimientoBase:
        dto.rendimientoBase === undefined
          ? undefined
          : dto.rendimientoBase === null
            ? null
            : new Prisma.Decimal(dto.rendimientoBase),

      diaSemanaProgramado: (dto as any).diaSemanaProgramado ?? undefined,
      diaMesProgramado: (dto as any).diaMesProgramado ?? undefined,
      duracionMinutosFija: durMinFija,
      diasParaCompletar:
        (dto as any).diasParaCompletar === undefined
          ? undefined
          : ((dto as any).diasParaCompletar ?? null),

      insumoPrincipal:
        dto.insumoPrincipalId === undefined
          ? undefined
          : dto.insumoPrincipalId === null
            ? { disconnect: true }
            : { connect: { id: dto.insumoPrincipalId } },

      consumoPrincipalPorUnidad:
        dto.consumoPrincipalPorUnidad === undefined
          ? undefined
          : dto.consumoPrincipalPorUnidad === null
            ? null
            : new Prisma.Decimal(dto.consumoPrincipalPorUnidad),

      insumosPlanJson:
        dto.insumosPlanJson === undefined
          ? undefined
          : dto.insumosPlanJson === null
            ? Prisma.JsonNull
            : (dto.insumosPlanJson as Prisma.InputJsonValue),

      maquinariaPlanJson:
        dto.maquinariaPlanJson === undefined
          ? undefined
          : dto.maquinariaPlanJson === null
            ? Prisma.JsonNull
            : (dto.maquinariaPlanJson as Prisma.InputJsonValue),

      // ✅ NUEVO
      herramientasPlanJson:
        (dto as any).herramientasPlanJson === undefined
          ? undefined
          : (dto as any).herramientasPlanJson === null
            ? Prisma.JsonNull
            : ((dto as any).herramientasPlanJson as Prisma.InputJsonValue),

      supervisor:
        (dto as any).supervisorId === undefined
          ? undefined
          : (dto as any).supervisorId === null
            ? { disconnect: true }
            : { connect: { id: (dto as any).supervisorId.toString() } },
    };

    if ((dto as any).operariosIds !== undefined) {
      const operariosIds: number[] = (dto as any).operariosIds ?? [];
      (data as any).operarios = {
        set: operariosIds.map((id) => ({ id: id.toString() })),
      };
    } else if ((dto as any).responsableSugeridoId !== undefined) {
      const value = (dto as any).responsableSugeridoId;
      (data as any).operarios =
        value === null ? { set: [] } : { set: [{ id: value.toString() }] };
    }

    return this.prisma.definicionTareaPreventiva.update({
      where: { id },
      data,
    });
  }

  async eliminar(conjuntoId: string, id: number) {
    const deleted = await this.prisma.definicionTareaPreventiva.deleteMany({
      where: { id, conjuntoId },
    });
    if (deleted.count === 0) {
      throw new Error("Definición no encontrada para este conjunto.");
    }
  }

  /* ============== GENERACIÓN DE CRONOGRAMA (BORRADOR) ============== */

  async generarCronograma(payload: unknown) {
    const dto = GenerarCronogramaDTO.parse(payload);

    const tamanoBloqueMinutos =
      dto.tamanoBloqueMinutos ??
      (dto.tamanoBloqueHoras != null
        ? Math.round(dto.tamanoBloqueHoras * 60)
        : 60);

    const creadas = await this.generarBorradorMensual({
      conjuntoId: dto.conjuntoId,
      periodoAnio: dto.anio,
      periodoMes: dto.mes,
      tamanoBloqueMinutos,
      paisFestivos: "CO",
      incluirPublicadasEnAgenda: true,
    });

    return { creadas };
  }

  /* ============== OPERACIONES SOBRE TAREAS BORRADOR ============== */

  async dividirTareaBorrador(payload: unknown) {
    const { conjuntoId, tareaId, bloques } =
      DividirTareaBorradorDTO.parse(payload);

    const original = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: { operarios: true },
    });

    if (!original || !original.borrador || original.conjuntoId !== conjuntoId) {
      throw new Error(
        "Tarea no encontrada, no es borrador o no pertenece a este conjunto.",
      );
    }
    if (original.tipo !== TipoTarea.PREVENTIVA) {
      throw new Error("Solo se pueden dividir tareas preventivas en borrador.");
    }

    const originalMin = original.duracionMinutos ?? 0;

    const minutosBloques = bloques.reduce((acc, b) => {
      const diffMin = (+b.fechaFin - +b.fechaInicio) / 60000;
      return acc + diffMin;
    }, 0);

    const minutosBloquesRed = Math.round(minutosBloques);
    if (minutosBloquesRed !== originalMin) {
      throw new Error(
        `La suma de minutos de los bloques (${minutosBloquesRed} min) no coincide con la duración original (${originalMin} min).`,
      );
    }

    const operariosIds = original.operarios.map((o) => o.id);

    const limiteMinSemana = await getLimiteMinSemanaPorConjunto(
      this.prisma,
      conjuntoId,
    );

    await this.prisma.$transaction(async (tx) => {
      for (const opId of operariosIds) {
        for (const b of bloques) {
          const minSemana = await minutosAsignadosEnSemana(
            tx as any,
            conjuntoId,
            opId,
            b.fechaInicio,
            false, // en borrador, normalmente validas contra borradores; aquí estamos dentro de tx
          );

          const durBloqueMin = (+b.fechaFin - +b.fechaInicio) / 60000 || 0;

          if (minSemana + durBloqueMin > limiteMinSemana) {
            throw new Error(
              `El operario ${opId} superaría el límite semanal (${limiteMinSemana} min) con este bloque.`,
            );
          }

          const haySolape = await existeSolapeParaOperario(tx as any, {
            conjuntoId,
            operarioId: opId,
            fechaInicio: b.fechaInicio,
            fechaFin: b.fechaFin,
            soloBorrador: true,
            excluirTareaId: tareaId,
          });

          if (haySolape) {
            const nombre = await getOperarioNombre(this.prisma, opId);
            throw new Error(
              `Solape de agenda detectado para el operario ${nombre} en uno de los bloques.`,
            );
          }
        }
      }

      await tx.tarea.delete({ where: { id: tareaId } });

      for (const b of bloques) {
        const duracionMinutos = Math.max(
          1,
          Math.round((+b.fechaFin - +b.fechaInicio) / 60000),
        );

        await tx.tarea.create({
          data: {
            descripcion: original.descripcion,
            fechaInicio: b.fechaInicio,
            fechaFin: b.fechaFin,
            duracionMinutos,
            prioridad: (original as any).prioridad ?? 2,
            estado: original.estado,
            tipo: original.tipo,
            frecuencia: original.frecuencia,
            borrador: true,
            periodoAnio: b.fechaInicio.getFullYear(),
            periodoMes: b.fechaInicio.getMonth() + 1,

            conjuntoId: original.conjuntoId!,
            ubicacionId: original.ubicacionId,
            elementoId: original.elementoId,
            supervisorId: original.supervisorId,

            tiempoEstimadoMinutos: original.tiempoEstimadoMinutos,
            insumoPrincipalId: original.insumoPrincipalId,
            consumoPrincipalPorUnidad: original.consumoPrincipalPorUnidad,
            consumoTotalEstimado: original.consumoTotalEstimado,

            insumosPlanJson:
              original.insumosPlanJson == null
                ? undefined
                : (original.insumosPlanJson as Prisma.InputJsonValue),

            maquinariaPlanJson:
              original.maquinariaPlanJson == null
                ? undefined
                : (original.maquinariaPlanJson as Prisma.InputJsonValue),

            // ✅ NUEVO
            herramientasPlanJson:
              (original as any).herramientasPlanJson == null
                ? undefined
                : ((original as any)
                    .herramientasPlanJson as Prisma.InputJsonValue),

            grupoPlanId: null,
            bloqueIndex: null,
            bloquesTotales: null,

            operarios: operariosIds.length
              ? { connect: operariosIds.map((id) => ({ id })) }
              : undefined,
          },
        });
      }
    });

    return { ok: true, bloques: bloques.length };
  }

  async dividirBloqueBorrador(
    conjuntoId: string,
    tareaId: number,
    payload: unknown,
  ) {
    const dto = DividirBloqueDTO.parse(payload);

    if (dto.fechaFin1 < dto.fechaInicio1) {
      throw new Error("fechaFin1 debe ser >= fechaInicio1");
    }
    if (dto.fechaFin2 < dto.fechaInicio2) {
      throw new Error("fechaFin2 debe ser >= fechaInicio2");
    }

    const original = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: {
        operarios: { select: { id: true } },
      },
    });

    if (
      !original ||
      original.conjuntoId !== conjuntoId ||
      !original.borrador ||
      original.tipo !== TipoTarea.PREVENTIVA
    ) {
      throw new Error("No es un bloque borrador preventivo de este conjunto.");
    }

    const operariosIds = original.operarios.map((o) => o.id);

    const dur1 = Math.max(
      1,
      Math.round((+dto.fechaFin1 - +dto.fechaInicio1) / 60000),
    );
    const dur2 = Math.max(
      1,
      Math.round((+dto.fechaFin2 - +dto.fechaInicio2) / 60000),
    );

    const limiteMinSemana = await getLimiteMinSemanaPorConjunto(
      this.prisma,
      conjuntoId,
    );

    const semanaKey = (d: Date) => {
      const ini = inicioSemana(d);
      return ini.toISOString().slice(0, 10);
    };

    const semana1 = semanaKey(dto.fechaInicio1);
    const semana2 = semanaKey(dto.fechaInicio2);

    for (const opId of operariosIds) {
      const extraPorSemana: Record<string, number> = {};
      extraPorSemana[semana1] = (extraPorSemana[semana1] ?? 0) + dur1;
      extraPorSemana[semana2] = (extraPorSemana[semana2] ?? 0) + dur2;

      for (const [sem, extra] of Object.entries(extraPorSemana)) {
        const ini = inicioSemana(new Date(sem));
        const minSemana = await minutosAsignadosEnSemana(
          this.prisma,
          conjuntoId,
          opId,
          ini,
          false,
        );

        if (minSemana + extra > limiteMinSemana) {
          throw new Error(
            `Al dividir esta tarea, el operario ${opId} superaría el límite semanal (${limiteMinSemana} min).`,
          );
        }
      }
    }

    for (const opId of operariosIds) {
      const haySolape1 = await existeSolapeParaOperario(this.prisma, {
        conjuntoId,
        operarioId: opId,
        fechaInicio: dto.fechaInicio1,
        fechaFin: dto.fechaFin1,
        soloBorrador: true,
        excluirTareaId: tareaId,
      });

      if (haySolape1) {
        const nombre = await getOperarioNombre(this.prisma, opId);
        throw new Error(
          `Solape de agenda con operario ${nombre} al dividir la tarea (primer bloque).`,
        );
      }

      const haySolape2 = await existeSolapeParaOperario(this.prisma, {
        conjuntoId,
        operarioId: opId,
        fechaInicio: dto.fechaInicio2,
        fechaFin: dto.fechaFin2,
        soloBorrador: true,
        excluirTareaId: tareaId,
      });

      if (haySolape2) {
        const nombre = await getOperarioNombre(this.prisma, opId);
        throw new Error(
          `Solape de agenda con operario ${nombre} al dividir la tarea (segundo bloque).`,
        );
      }
    }

    return this.prisma.$transaction(async (tx) => {
      await tx.tarea.delete({
        where: { id: tareaId },
      });

      const periodoAnio1 = dto.fechaInicio1.getFullYear();
      const periodoMes1 = dto.fechaInicio1.getMonth() + 1;

      const periodoAnio2 = dto.fechaInicio2.getFullYear();
      const periodoMes2 = dto.fechaInicio2.getMonth() + 1;

      const dataBase: any = {
        descripcion: original.descripcion,
        estado: EstadoTarea.ASIGNADA,
        tipo: TipoTarea.PREVENTIVA,
        frecuencia: original.frecuencia,
        borrador: true as const,
        prioridad: (original as any).prioridad ?? 2,

        conjuntoId,
        ubicacionId: original.ubicacionId,
        elementoId: original.elementoId,
        supervisorId: original.supervisorId,

        tiempoEstimadoMinutos: original.tiempoEstimadoMinutos,
        insumoPrincipalId: original.insumoPrincipalId,
        consumoPrincipalPorUnidad: original.consumoPrincipalPorUnidad,
        consumoTotalEstimado: original.consumoTotalEstimado,

        insumosPlanJson: original.insumosPlanJson as Prisma.InputJsonValue,
        maquinariaPlanJson:
          original.maquinariaPlanJson as Prisma.InputJsonValue,

        // ✅ NUEVO
        herramientasPlanJson: (original as any)
          .herramientasPlanJson as Prisma.InputJsonValue,
      };

      const tarea1 = await tx.tarea.create({
        data: {
          ...dataBase,
          fechaInicio: dto.fechaInicio1,
          fechaFin: dto.fechaFin1,
          duracionMinutos: dur1,
          periodoAnio: periodoAnio1,
          periodoMes: periodoMes1,
          grupoPlanId: null,
          bloqueIndex: null,
          bloquesTotales: null,
          operarios: operariosIds.length
            ? { connect: operariosIds.map((id) => ({ id })) }
            : undefined,
        },
      });

      const tarea2 = await tx.tarea.create({
        data: {
          ...dataBase,
          fechaInicio: dto.fechaInicio2,
          fechaFin: dto.fechaFin2,
          duracionMinutos: dur2,
          periodoAnio: periodoAnio2,
          periodoMes: periodoMes2,
          grupoPlanId: null,
          bloqueIndex: null,
          bloquesTotales: null,
          operarios: operariosIds.length
            ? { connect: operariosIds.map((id) => ({ id })) }
            : undefined,
        },
      });

      return { tarea1, tarea2 };
    });
  }

  async publicarCronograma(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
  }) {
    const { conjuntoId, anio, mes } = params;

    const borradores = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        tipo: TipoTarea.PREVENTIVA,
      },
      select: {
        id: true,
        fechaInicio: true,
        fechaFin: true,
        maquinariaPlanJson: true,
        grupoPlanId: true,
      },
      orderBy: [{ id: "asc" }],
    });

    if (!borradores.length) {
      return { ok: true, publicadas: 0, reservas: 0 };
    }

    // ✅ 0) Rango del mes + buffer para logística (sábado anterior / miércoles posterior)
    const month0 = mes - 1;
    const inicioMes = new Date(anio, month0, 1, 0, 0, 0, 0);
    const finMes = new Date(anio, month0 + 1, 0, 23, 59, 59, 999);

    // Buffer recomendado: 20 días (cubre cambios por festivos + cambio de mes)
    const bufferDias = 20;

    const inicioRangoFestivos = new Date(inicioMes);
    inicioRangoFestivos.setDate(inicioRangoFestivos.getDate() - bufferDias);

    const finRangoFestivos = new Date(finMes);
    finRangoFestivos.setDate(finRangoFestivos.getDate() + bufferDias);

    // ✅ 1) Festivos (CO) para ese rango extendido
    const festivosSet = await getFestivosSet({
      prisma: this.prisma,
      pais: "CO",
      inicio: inicioRangoFestivos,
      fin: finRangoFestivos,
    });

    // ✅ 2) Validar (y crear reservas) *antes* de publicar
    const reservasResp = await this.crearReservasPlanificadasParaTareas({
      conjuntoId,
      tareas: borradores.map((t) => ({
        id: t.id,
        grupoPlanId: t.grupoPlanId ?? null,
        fechaInicio: t.fechaInicio,
        fechaFin: t.fechaFin,
        maquinariaPlanJson: t.maquinariaPlanJson,
      })),
      diasEntregaRecogida: new Set([1, 3, 6]), // L, X, S
      excluirTareaIds: [],
      festivosSet, // ✅ NUEVO (para saltar festivos logísticos)
    });

    // ✅ 3) Publicar tareas (ya pasó maquinaria)
    await this.prisma.tarea.updateMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        tipo: TipoTarea.PREVENTIVA,
      },
      data: { borrador: false },
    });

    return {
      ok: true,
      publicadas: borradores.length,
      reservas: reservasResp?.creadas ?? 0,
    };
  }

  /**
   * Genera tareas PREVENTIVAS en modo "borrador" para un conjunto y mes.
   * ✅ Respeta prioridad (1 primero)
   * ✅ Respeta festivos (tabla Festivo)
   * ✅ Evita solapes por operario (día)
   * ✅ Respeta límite semanal (minutos), usando override del conjunto o límite empresa
   */
  async generarBorradorMensual(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    tamanoBloqueMinutos?: number;
    paisFestivos?: string;
    incluirPublicadasEnAgenda?: boolean;
  }): Promise<number> {
    const {
      conjuntoId,
      periodoAnio,
      periodoMes,
      tamanoBloqueMinutos = 60,
      paisFestivos = "CO",
      incluirPublicadasEnAgenda = true,
    } = params;

    // 1️⃣ Definiciones activas (ya vienen por prioridad asc)
    const defs = await this.prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId, activo: true },
      include: { operarios: true, supervisor: true },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });

    if (!defs.length) return 0;

    // 2️⃣ Horarios del conjunto
    const horarios = await this.prisma.conjuntoHorario.findMany({
      where: { conjuntoId },
    });

    const horariosPorDia = new Map<
      DiaSemana,
      {
        startMin: number;
        endMin: number;
        descansoStartMin?: number;
        descansoEndMin?: number;
      }
    >();

    for (const h of horarios) {
      horariosPorDia.set(h.dia, {
        startMin: toMin(h.horaApertura),
        endMin: toMin(h.horaCierre),
        descansoStartMin: h.descansoInicio
          ? toMin(h.descansoInicio)
          : undefined,
        descansoEndMin: h.descansoFin ? toMin(h.descansoFin) : undefined,
      });
    }

    // 3️⃣ Rango del mes
    const month0 = periodoMes - 1;
    const inicioMes = new Date(periodoAnio, month0, 1, 0, 0, 0, 0);
    const finMes = new Date(periodoAnio, month0 + 1, 0, 23, 59, 59, 999);
    const fechasDelMes = enumerateDays(inicioMes, finMes);

    // 4️⃣ Festivos
    const festivosSet = await getFestivosSet({
      prisma: this.prisma,
      pais: paisFestivos,
      inicio: inicioMes,
      fin: finMes,
    });

    // 5️⃣ Limpiar borradores previos
    await this.prisma.tarea.deleteMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio,
        periodoMes,
        tipo: TipoTarea.PREVENTIVA,
      },
    });

    // 6️⃣ Límite semanal
    const limiteMinSemana = await getLimiteMinSemanaPorConjunto(
      this.prisma,
      conjuntoId,
    );

    let creadas = 0;

    // 7️⃣ Loop definiciones
    for (const def of defs) {
      const prioridad = Number((def as any).prioridad ?? 2);
      const operariosIds = def.operarios.map((o) => o.id);

      // evitar duplicar si ya fue publicada
      const yaPublicadaEstaDef = await this.prisma.tarea.count({
        where: {
          conjuntoId,
          periodoAnio,
          periodoMes,
          tipo: TipoTarea.PREVENTIVA,
          borrador: false,
          descripcion: def.descripcion,
          ubicacionId: def.ubicacionId,
          elementoId: def.elementoId,
          frecuencia: def.frecuencia,
        },
      });
      if (yaPublicadaEstaDef > 0) continue;

      // días teóricos según frecuencia
      const diasBase = pickDaysByFrecuencia(fechasDelMes, def);

      // solo días con horario
      const diasValidos = diasBase.filter((d) =>
        horariosPorDia.has(dateToDiaSemana(d)),
      );

      for (const diaBase of diasValidos) {
        // ✅ Festivos: prioridad 1 se mueve SÍ O SÍ; prioridad 2-3 se salta (tal cual tu helper)
        const diaProgramable = findNextValidDay({
          start: diaBase,
          periodoAnio,
          periodoMes,
          prioridad,
          horariosPorDia,
          festivosSet,
        });

        if (!diaProgramable) continue;

        // ✅ Duración REAL (aquí está el bug que te truncaba a 60)
        const minutosEstimados =
          calcularMinutosEstimados({
            cantidad:
              def.areaNumerica != null ? Number(def.areaNumerica) : undefined,
            rendimiento:
              def.rendimientoBase != null
                ? Number(def.rendimientoBase)
                : undefined,
            duracionMinutosFija: (def as any).duracionMinutosFija ?? undefined,
            rendimientoTiempoBase:
              (def as any).rendimientoTiempoBase ?? "POR_HORA",
          }) ??
          ((def as any).duracionMinutosFija != null
            ? Number((def as any).duracionMinutosFija)
            : null) ??
          ((def as any).duracionHorasFija != null
            ? Math.max(
                1,
                Math.round(Number((def as any).duracionHorasFija) * 60),
              )
            : null) ??
          null;

        const durMinTotal = minutosEstimados ?? tamanoBloqueMinutos;

        // ✅ diasParaCompletar: divide minutos (NO horas) en N días
        const diasParaCompletar = Math.max(
          1,
          Number((def as any).diasParaCompletar ?? 1),
        );
        const partesMin = splitMinutes(durMinTotal, diasParaCompletar);

        // Si multi-día, agrupar todo en el mismo grupoPlanId
        const grupoPlanId =
          partesMin.length > 1
            ? `BOR-${def.id}-${periodoAnio}-${periodoMes}-${Math.random().toString(36).slice(2, 8)}`
            : null;

        const totalBloquesEsperados = partesMin.length; // 1 bloque por día (si split descanso => puede ser 2 tareas, pero sigue en el mismo grupo)
        let bloqueIndexCursor = 1;

        // vamos agendando partes en días sucesivos hábiles
        let cursorDia = new Date(diaProgramable);

        for (let p = 0; p < partesMin.length; p++) {
          const durMinParte = partesMin[p];

          // buscamos un día válido dentro del mes (si cae festivo/ sin horario, avanza)
          let diaParte = findNextValidDay({
            start: cursorDia,
            periodoAnio,
            periodoMes,
            prioridad,
            horariosPorDia,
            festivosSet,
          });

          if (!diaParte) break;

          // intentar agendar en ese día; si prioridad 1 y no cabe => reemplazo; si aún no => buscar siguiente día hábil
          let agendada = false;

          for (let guardDia = 0; guardDia < 31; guardDia++) {
            if (!diaParte) break;

            const ds = dateToDiaSemana(diaParte);
            const horario = horariosPorDia.get(ds);
            if (!horario) {
              diaParte = siguienteDiaHabil({
                fecha: diaParte,
                festivosSet,
                horariosPorDia,
              });
              continue;
            }

            const bloqueos = buildBloqueosPorDescanso(horario);

            // agenda por operarios => ocupados global merged
            let ocupadosGlobal: Intervalo[] = [];
            if (operariosIds.length) {
              const agenda = await buildAgendaPorOperarioDia({
                prisma: this.prisma,
                conjuntoId,
                fechaDia: diaParte,
                operariosIds,
                incluirBorrador: true,
                bloqueosGlobales: bloqueos,
                excluirEstados: ["PENDIENTE_REPROGRAMACION"],
              });

              const all: Intervalo[] = [];
              for (const opId of Object.keys(agenda)) all.push(...agenda[opId]);
              ocupadosGlobal = mergeIntervalos(all);
            } else {
              ocupadosGlobal = mergeIntervalos(
                bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })),
              );
            }

            // buscar hueco (1 bloque o split descanso)
            const bloques = buscarHuecoDiaConSplitEarliest({
              startMin: horario.startMin,
              endMin: horario.endMin,
              durMin: durMinParte,
              ocupados: ocupadosGlobal,
              bloqueos,
              desiredStartMin: horario.startMin,
              maxBloques: 2,
            });

            if (bloques) {
              // ✅ validar límite semanal
              let pasaLimite = true;
              for (const opId of operariosIds) {
                const minSemana = await minutosAsignadosEnSemana(
                  this.prisma,
                  conjuntoId,
                  opId,
                  toDateAtMin(diaParte, bloques[0].i),
                  incluirPublicadasEnAgenda,
                );
                if (minSemana + durMinParte > limiteMinSemana) {
                  pasaLimite = false;
                  break;
                }
              }

              if (!pasaLimite) {
                // si no pasa límite, probamos siguiente día hábil (para prioridad 1) o lo saltamos (2-3)
                if (prioridad === 1) {
                  diaParte = siguienteDiaHabil({
                    fecha: diaParte,
                    festivosSet,
                    horariosPorDia,
                  });
                  continue;
                }
                break;
              }

              // ✅ crear tareas (1 o 2 bloques) manteniendo grupoPlanId
              for (const b of bloques) {
                const fechaInicio = toDateAtMin(diaParte, b.i);
                const fechaFin = toDateAtMin(diaParte, b.f);

                await this.prisma.tarea.create({
                  data: {
                    descripcion: def.descripcion,
                    fechaInicio,
                    fechaFin,
                    duracionMinutos: Math.max(1, b.f - b.i),

                    tipo: TipoTarea.PREVENTIVA,
                    prioridad,
                    estado: EstadoTarea.ASIGNADA,
                    frecuencia: def.frecuencia,

                    borrador: true,
                    periodoAnio,
                    periodoMes,

                    grupoPlanId,
                    bloqueIndex: grupoPlanId ? bloqueIndexCursor : null,
                    bloquesTotales: grupoPlanId ? totalBloquesEsperados : null,

                    ubicacionId: def.ubicacionId,
                    elementoId: def.elementoId,
                    conjuntoId,

                    supervisorId: def.supervisorId ?? null,

                    insumosPlanJson: def.insumosPlanJson
                      ? (def.insumosPlanJson as Prisma.InputJsonValue)
                      : undefined,

                    maquinariaPlanJson: def.maquinariaPlanJson
                      ? (def.maquinariaPlanJson as Prisma.InputJsonValue)
                      : undefined,

                    herramientasPlanJson: (def as any).herramientasPlanJson
                      ? ((def as any)
                          .herramientasPlanJson as Prisma.InputJsonValue)
                      : undefined,

                    operarios: operariosIds.length
                      ? { connect: operariosIds.map((id) => ({ id })) }
                      : undefined,
                  },
                });

                creadas++;
                if (grupoPlanId) bloqueIndexCursor++;
              }

              agendada = true;
              break;
            }

            // ❌ No hubo hueco
            if (prioridad === 1) {
              // ✅ reemplazo por prioridad baja (tu helper)
              const payload = {
                descripcion: def.descripcion,
                tipo: TipoTarea.PREVENTIVA,
                frecuencia: def.frecuencia ?? null,

                prioridad,
                supervisorId: def.supervisorId
                  ? def.supervisorId.toString()
                  : null,

                ubicacionId: def.ubicacionId,
                elementoId: def.elementoId,
                conjuntoId,

                borrador: true,
                periodoAnio,
                periodoMes,

                insumosPlanJson: def.insumosPlanJson ?? undefined,
                maquinariaPlanJson: def.maquinariaPlanJson ?? undefined,
                herramientasPlanJson:
                  (def as any).herramientasPlanJson ?? undefined,

                operariosIds,

                // ✅ mantener grupo/orden (con el mini cambio que te pedí arriba)
                grupoPlanId,
                bloqueIndexBase: grupoPlanId ? bloqueIndexCursor : undefined,
                bloquesTotalesOverride: grupoPlanId
                  ? totalBloquesEsperados
                  : undefined,

                // opcional trazabilidad si quieres
                marcarComoReprogramada: false,
              };

              const rep = await intentarReemplazoPorPrioridadBaja({
                prisma: this.prisma,
                conjuntoId,
                fechaDia: diaParte,
                startMin: horario.startMin,
                endMin: horario.endMin,
                bloqueos,
                durMin: durMinParte,
                payload,
                incluirBorradorEnAgenda: true,
                incluirPublicadasEnAgenda,
              });

              if (rep.ok) {
                // el helper ya creó la(s) tarea(s) con los bloques
                creadas += rep.nuevaTareaIds.length;

                if (grupoPlanId) {
                  // si split, el helper pudo crear 2 ids (bloques); ajusta cursor
                  bloqueIndexCursor += rep.nuevaTareaIds.length;
                }

                agendada = true;
                break;
              }

              // si no se pudo (sin hueco o sin candidatas), intenta el siguiente día hábil
              diaParte = siguienteDiaHabil({
                fecha: diaParte,
                festivosSet,
                horariosPorDia,
              });
              continue;
            }

            // prioridad 2-3: si no cabe, se omite (comportamiento original)
            break;
          }

          // mover cursor al día siguiente para la siguiente parte
          cursorDia = new Date(diaParte ?? cursorDia);
          cursorDia.setDate(cursorDia.getDate() + 1);

          // si no se pudo agendar esta parte, ya no seguimos (para no crear medio “multi-día” incoherente)
          if (!agendada) break;
        }
      }
    }

    return creadas;
  }

  // Helper para no duplicar código (1 bloque o 2 bloques split)
  private async _crearPreventivaEnBloques(params: {
    def: any;
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    prioridad: number;
    operariosIds: string[];
    fechaDia: Date;
    bloques: { i: number; f: number }[];
  }) {
    const {
      def,
      conjuntoId,
      periodoAnio,
      periodoMes,
      prioridad,
      operariosIds,
      fechaDia,
      bloques,
    } = params;

    if (bloques.length === 1) {
      const b = bloques[0];
      const fechaInicio = toDateAtMin(fechaDia, b.i);
      const fechaFin = toDateAtMin(fechaDia, b.f);
      const dur = Math.max(1, Math.round((+fechaFin - +fechaInicio) / 60000));

      await this.prisma.tarea.create({
        data: {
          descripcion: def.descripcion,
          fechaInicio,
          fechaFin,
          duracionMinutos: dur,

          prioridad,
          estado: EstadoTarea.ASIGNADA,
          tipo: TipoTarea.PREVENTIVA,
          frecuencia: def.frecuencia,
          borrador: true,
          periodoAnio,
          periodoMes,

          grupoPlanId: null,
          bloqueIndex: null,
          bloquesTotales: null,

          supervisorId: (def as any).supervisorId ?? null,
          ubicacionId: def.ubicacionId,
          elementoId: def.elementoId,
          conjuntoId,

          tiempoEstimadoMinutos: dur,

          insumosPlanJson: (def as any).insumosPlanJson
            ? ((def as any).insumosPlanJson as Prisma.InputJsonValue)
            : undefined,
          maquinariaPlanJson: (def as any).maquinariaPlanJson
            ? ((def as any).maquinariaPlanJson as Prisma.InputJsonValue)
            : undefined,
          herramientasPlanJson: (def as any).herramientasPlanJson
            ? ((def as any).herramientasPlanJson as Prisma.InputJsonValue)
            : undefined,

          operarios: operariosIds.length
            ? { connect: operariosIds.map((id) => ({ id })) }
            : undefined,
        },
      });
      return;
    }

    // 2 bloques (split descanso)
    const grupoPlanId = `SD-${
      def.id
    }-${periodoAnio}-${periodoMes}-${Math.random().toString(36).slice(2, 8)}`;
    const bloquesTotales = bloques.length;

    let idx = 1;
    for (const b of bloques) {
      const fechaInicio = toDateAtMin(fechaDia, b.i);
      const fechaFin = toDateAtMin(fechaDia, b.f);
      const dur = Math.max(1, Math.round((+fechaFin - +fechaInicio) / 60000));

      await this.prisma.tarea.create({
        data: {
          descripcion: def.descripcion,
          fechaInicio,
          fechaFin,
          duracionMinutos: dur,

          prioridad,
          estado: EstadoTarea.ASIGNADA,
          tipo: TipoTarea.PREVENTIVA,
          frecuencia: def.frecuencia,
          borrador: true,
          periodoAnio,
          periodoMes,

          grupoPlanId,
          bloqueIndex: idx,
          bloquesTotales,

          supervisorId: (def as any).supervisorId ?? null,
          ubicacionId: def.ubicacionId,
          elementoId: def.elementoId,
          conjuntoId,

          tiempoEstimadoMinutos: dur,

          insumosPlanJson: (def as any).insumosPlanJson
            ? ((def as any).insumosPlanJson as Prisma.InputJsonValue)
            : undefined,
          maquinariaPlanJson: (def as any).maquinariaPlanJson
            ? ((def as any).maquinariaPlanJson as Prisma.InputJsonValue)
            : undefined,
          herramientasPlanJson: (def as any).herramientasPlanJson
            ? ((def as any).herramientasPlanJson as Prisma.InputJsonValue)
            : undefined,

          operarios: operariosIds.length
            ? { connect: operariosIds.map((id) => ({ id })) }
            : undefined,
        },
      });

      idx++;
    }
  }

  async editarTareaBorrador(payload: unknown) {
    const dto = EditarBorradorDTO.parse(payload);

    const t = await this.prisma.tarea.findUnique({
      where: { id: dto.tareaId },
      select: { id: true, borrador: true, conjuntoId: true },
    });
    if (!t || !t.borrador || t.conjuntoId !== dto.conjuntoId) {
      throw new Error(
        "Tarea no existe, no es borrador o no pertenece a este conjunto.",
      );
    }
    if (dto.fechaInicio && dto.fechaFin && dto.fechaFin < dto.fechaInicio) {
      throw new Error("fechaFin debe ser >= fechaInicio");
    }

    return this.prisma.tarea.update({
      where: { id: dto.tareaId },
      data: {
        fechaInicio: dto.fechaInicio ?? undefined,
        fechaFin: dto.fechaFin ?? undefined,
        duracionMinutos: dto.duracionMinutos ?? undefined,
        operarios:
          dto.operariosIds !== undefined
            ? {
                set: dto.operariosIds.map((id) => ({ id: id.toString() })),
              }
            : undefined,
      },
      include: { operarios: { select: { id: true } } },
    });
  }

  async crearBloqueBorrador(conjuntoId: string, payload: unknown) {
    const dto = CrearBloqueBorradorDTO.parse(payload);
    if (dto.fechaFin < dto.fechaInicio)
      throw new Error("fechaFin >= fechaInicio");

    if (dto.operariosIds?.length) {
      for (const opId of dto.operariosIds) {
        const choque = await this.prisma.tarea.findFirst({
          where: {
            conjuntoId,
            borrador: true,
            tipo: TipoTarea.PREVENTIVA,
            fechaInicio: { lt: dto.fechaFin },
            fechaFin: { gt: dto.fechaInicio },
            operarios: { some: { id: opId.toString() } },
          },
          select: { id: true },
        });

        if (choque) {
          const nombre = await getOperarioNombre(this.prisma, opId);
          throw new Error(`Solape de agenda con ${nombre}`);
        }
      }
    }

    const anio = dto.fechaInicio.getFullYear();
    const mes = dto.fechaInicio.getMonth() + 1;

    return this.prisma.tarea.create({
      data: {
        descripcion: dto.descripcion,
        fechaInicio: dto.fechaInicio,
        fechaFin: dto.fechaFin,
        duracionMinutos: Math.max(
          1,
          Math.round((+dto.fechaFin - +dto.fechaInicio) / 60000),
        ),
        estado: EstadoTarea.ASIGNADA,
        tipo: TipoTarea.PREVENTIVA,
        frecuencia: null,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        grupoPlanId: null,

        ubicacionId: dto.ubicacionId,
        elementoId: dto.elementoId,
        conjuntoId,
        supervisorId:
          dto.supervisorId == null ? null : dto.supervisorId.toString(),

        tiempoEstimadoMinutos:
          dto.tiempoEstimadoMinutos === undefined
            ? null
            : Math.max(0, Math.round(dto.tiempoEstimadoMinutos)),

        operarios: dto.operariosIds?.length
          ? {
              connect: dto.operariosIds.map((id) => ({ id: id.toString() })),
            }
          : undefined,
      },
    });
  }

  async editarBloqueBorrador(
    conjuntoId: string,
    tareaId: number,
    payload: unknown,
  ) {
    const dto = EditarBloqueBorradorDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { id: true, conjuntoId: true, borrador: true, tipo: true },
    });
    if (
      !tarea ||
      tarea.conjuntoId !== conjuntoId ||
      !tarea.borrador ||
      tarea.tipo !== TipoTarea.PREVENTIVA
    ) {
      throw new Error("No es un bloque borrador preventivo de este conjunto.");
    }

    let operariosIdsFinal: string[] | undefined = undefined;

    if (dto.operariosIds) {
      operariosIdsFinal = dto.operariosIds.map((id) => id.toString());
    } else {
      const actuales = await this.prisma.tarea.findUnique({
        where: { id: tareaId },
        select: { operarios: { select: { id: true } } },
      });
      operariosIdsFinal = actuales?.operarios.map((o) => o.id);
    }

    const fechaInicio = dto.fechaInicio ?? undefined;
    const fechaFin = dto.fechaFin ?? undefined;

    if (fechaInicio && fechaFin && operariosIdsFinal?.length) {
      for (const opId of operariosIdsFinal) {
        const haySolape = await existeSolapeParaOperario(this.prisma, {
          conjuntoId,
          operarioId: opId,
          fechaInicio,
          fechaFin,
          soloBorrador: true,
          excluirTareaId: tareaId,
        });

        if (haySolape) {
          const nombre = await getOperarioNombre(this.prisma, opId);
          throw new Error(`Solape de agenda con operario ${nombre}`);
        }
      }
    }

    return this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        descripcion: dto.descripcion ?? undefined,
        fechaInicio,
        fechaFin,
        duracionMinutos:
          dto.duracionMinutos ??
          (fechaInicio && fechaFin
            ? Math.max(1, Math.round((+fechaFin - +fechaInicio) / 60000))
            : undefined),
        ubicacionId: dto.ubicacionId ?? undefined,
        elementoId: dto.elementoId ?? undefined,
        supervisorId:
          dto.supervisorId === undefined
            ? undefined
            : dto.supervisorId === null
              ? null
              : dto.supervisorId.toString(),
        tiempoEstimadoMinutos:
          dto.tiempoEstimadoMinutos === undefined
            ? undefined
            : dto.tiempoEstimadoMinutos === null
              ? null
              : Math.max(0, Math.round(dto.tiempoEstimadoMinutos)),

        operarios:
          dto.operariosIds === undefined
            ? undefined
            : {
                set: dto.operariosIds.map((id) => ({ id: id.toString() })),
              },
      },
    });
  }

  async listarMaquinariaDisponible(params: {
    conjuntoId: string;
    fechaInicioUso: Date;
    fechaFinUso: Date;
    excluirTareaId?: number;
  }) {
    const { conjuntoId, fechaInicioUso, fechaFinUso, excluirTareaId } = params;

    // Validaciones fuertes
    if (!(fechaInicioUso instanceof Date) || isNaN(+fechaInicioUso)) {
      return { ok: false, reason: "FECHA_INICIO_INVALIDA" };
    }
    if (!(fechaFinUso instanceof Date) || isNaN(+fechaFinUso)) {
      return { ok: false, reason: "FECHA_FIN_INVALIDA" };
    }
    if (+fechaFinUso < +fechaInicioUso) {
      return { ok: false, reason: "RANGO_INVERTIDO" };
    }

    const diasEntregaRecogida = new Set([1, 3, 6]); // Lunes, Miércoles, Sábado

    const { iniReserva, finReserva, entregaDia, recogidaDia } =
      this.calcularRangoReserva({
        fechaInicioUso,
        fechaFinUso,
        diasEntregaRecogida,
      });

    // 1) PROPIAS DEL CONJUNTO (desde MAQUINARIA)
    const propias = await this.prisma.maquinaria.findMany({
      where: {
        propietarioTipo: "CONJUNTO",
        conjuntoPropietarioId: conjuntoId,
        estado: "OPERATIVA",
      },
      select: {
        id: true,
        nombre: true,
        tipo: true,
        marca: true,
        estado: true,
      },
    });

    // 2) MAQUINARIA DE EMPRESA (desde MAQUINARIA)
    const empresa = await this.prisma.maquinaria.findMany({
      where: {
        propietarioTipo: "EMPRESA",
        estado: "OPERATIVA",
      },
      select: {
        id: true,
        nombre: true,
        tipo: true,
        marca: true,
        estado: true,
        empresaId: true,
      },
    });

    const idsInteres = Array.from(
      new Set([...propias.map((m) => m.id), ...empresa.map((m) => m.id)]),
    );

    if (!idsInteres.length) {
      return {
        ok: true,
        rango: { entregaDia, recogidaDia, iniReserva, finReserva },
        propiasDisponibles: [],
        empresaDisponibles: [],
        ocupadas: [],
      };
    }

    // 3) OCUPADAS por reservas reales (USO_MAQUINARIA)
    const ocupadas = await this.prisma.usoMaquinaria.findMany({
      where: {
        maquinariaId: { in: idsInteres },
        ...(excluirTareaId ? { tareaId: { not: excluirTareaId } } : {}),
        // cruce de rango: inicio < finReserva AND fin > iniReserva
        fechaInicio: { lt: finReserva },
        fechaFin: { gt: iniReserva },
      },
      select: {
        id: true,
        maquinariaId: true,
        tareaId: true,
        fechaInicio: true,
        fechaFin: true,
        tarea: {
          select: {
            id: true,
            conjuntoId: true,
            descripcion: true,
            fechaInicio: true,
            fechaFin: true,
          },
        },
      },
    });

    const ocupadasSet = new Set(ocupadas.map((o) => o.maquinariaId));

    // 4) DISPONIBLES
    const propiasDisponibles = propias
      .filter((m) => !ocupadasSet.has(m.id))
      .map((m) => ({
        id: m.id,
        nombre: m.nombre,
        tipo: m.tipo,
        marca: m.marca,
        origen: "CONJUNTO" as const,
      }));

    const empresaDisponibles = empresa
      .filter((m) => !ocupadasSet.has(m.id))
      .map((m) => ({
        id: m.id,
        nombre: m.nombre,
        tipo: m.tipo,
        marca: m.marca,
        origen: "EMPRESA" as const,
        empresaId: m.empresaId,
      }));

    // 5) Detalle ocupadas (motivo)
    const ocupadasDetalle = ocupadas.map((o) => ({
      maquinariaId: o.maquinariaId,
      ini: o.fechaInicio,
      fin: o.fechaFin,
      tareaId: o.tareaId,
      conjuntoId: o.tarea?.conjuntoId ?? null,
      descripcion: o.tarea?.descripcion ?? null,
    }));

    return {
      ok: true,
      rango: { entregaDia, recogidaDia, iniReserva, finReserva },
      propiasDisponibles,
      empresaDisponibles,
      ocupadas: ocupadasDetalle,
    };
  }

  async eliminarBloqueBorrador(conjuntoId: string, tareaId: number) {
    const res = await this.prisma.tarea.deleteMany({
      where: {
        id: tareaId,
        conjuntoId,
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
      },
    });
    if (res.count === 0)
      throw new Error("Bloque no encontrado o no es borrador preventivo.");
  }

  async listarBorrador({
    conjuntoId,
    anio,
    mes,
  }: {
    conjuntoId: string;
    anio: number;
    mes: number;
  }) {
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        tipo: TipoTarea.PREVENTIVA,
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
        supervisor: { include: { usuario: true } },
      },
      orderBy: [{ grupoPlanId: "asc" }, { bloqueIndex: "asc" }, { id: "asc" }],
    });
  }

  private async crearReservasPlanificadasParaTareas(params: {
    conjuntoId: string;
    tareas: Array<{
      id: number;
      grupoPlanId?: string | null;
      fechaInicio: Date;
      fechaFin: Date;
      maquinariaPlanJson: any;
    }>;
    diasEntregaRecogida: Set<number>;
    excluirTareaIds?: number[];
    festivosSet?: Set<string>;
  }) {
    const {
      conjuntoId,
      tareas,
      diasEntregaRecogida,
      excluirTareaIds = [],
      festivosSet,
    } = params;

    const getMaqIds = (json: any): number[] => {
      if (!Array.isArray(json)) return [];
      return json
        .map((x) => Number(x?.maquinariaId))
        .filter((n) => Number.isFinite(n) && n > 0);
    };

    const sameDayKey = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

    // ========= 1) AGRUPAR por grupoPlanId =========
    type Grupo = {
      key: string; // "G:<grupoPlanId>" o "T:<tareaId>"
      tareaIds: number[]; // todas las tareas del grupo
      tareaIdRepresentante: number; // para conectar en usoMaquinaria
      maqIds: number[];
      usoIni: Date; // min fechaInicio del grupo
      usoFin: Date; // max fechaFin del grupo
    };

    const grupos = new Map<string, Grupo>();

    for (const t of tareas) {
      const maqIds = getMaqIds(t.maquinariaPlanJson);
      if (!maqIds.length) continue;

      const key = t.grupoPlanId ? `G:${t.grupoPlanId}` : `T:${t.id}`;

      const g = grupos.get(key);
      if (!g) {
        grupos.set(key, {
          key,
          tareaIds: [t.id],
          tareaIdRepresentante: t.id,
          maqIds: Array.from(new Set(maqIds)),
          usoIni: t.fechaInicio,
          usoFin: t.fechaFin,
        });
      } else {
        g.tareaIds.push(t.id);
        g.maqIds = Array.from(new Set(g.maqIds.concat(maqIds)));
        if (+t.fechaInicio < +g.usoIni) g.usoIni = t.fechaInicio;
        if (+t.fechaFin > +g.usoFin) g.usoFin = t.fechaFin;

        // por si quieres que el representante sea el de menor id:
        if (t.id < g.tareaIdRepresentante) g.tareaIdRepresentante = t.id;
      }
    }

    // ========= 2) Armar plan (ya agrupado) =========
    const plan = Array.from(grupos.values()).map((g) => {
      const { entregaDia, recogidaDia, iniReserva, finReserva } =
        this.calcularRangoReserva({
          fechaInicioUso: g.usoIni,
          fechaFinUso: g.usoFin,
          diasEntregaRecogida,
          festivosSet,
        });

      return {
        key: g.key,
        tareaIds: g.tareaIds,
        tareaIdRepresentante: g.tareaIdRepresentante,
        maqIds: g.maqIds,
        entregaDia,
        recogidaDia,
        iniReserva,
        finReserva,
      };
    });

    if (!plan.length) return { ok: true, creadas: 0 };

    // ========= 3) Query única de ocupaciones =========
    const allMaqIds = Array.from(new Set(plan.flatMap((p) => p.maqIds)));

    const minIni = new Date(Math.min(...plan.map((p) => +p.iniReserva)));
    const maxFin = new Date(Math.max(...plan.map((p) => +p.finReserva)));

    const allPlanTareaIds = Array.from(
      new Set(plan.flatMap((p) => p.tareaIds)),
    );

    const conflictosDB = await this.prisma.usoMaquinaria.findMany({
      where: {
        maquinariaId: { in: allMaqIds },
        fechaInicio: { lt: maxFin },
        OR: [{ fechaFin: null }, { fechaFin: { gt: minIni } }],
        ...(excluirTareaIds.length
          ? { tareaId: { notIn: excluirTareaIds } }
          : {}),
        // ✅ excluir tareas del mismo lote (idempotencia)
        tareaId: { notIn: allPlanTareaIds.concat(excluirTareaIds) },
      },
      select: {
        id: true,
        maquinariaId: true,
        tareaId: true,
        fechaInicio: true,
        fechaFin: true,
        tarea: {
          select: {
            id: true,
            conjuntoId: true,
            descripcion: true,
            fechaInicio: true,
            fechaFin: true,
          },
        },
      },
    });

    // ========= 4) Validación exacta =========
    const overlaps = (aIni: Date, aFin: Date, bIni: Date, bFin: Date) =>
      aIni < bFin && bIni < aFin;

    const OPEN_END_FAR_FUTURE = new Date(2099, 11, 31, 23, 59, 59, 999);

    const byMaq = new Map<number, typeof conflictosDB>();
    for (const u of conflictosDB) {
      const arr = byMaq.get(u.maquinariaId) ?? [];
      arr.push(u);
      byMaq.set(u.maquinariaId, arr);
    }

    const conflictos: Array<{
      tareaId: number;
      maquinariaId: number;
      rangoSolicitado: {
        ini: string;
        fin: string;
        entrega: string;
        recogida: string;
      };
      ocupadoPor: {
        usoId: number;
        tareaId: number;
        conjuntoId: string | null;
        descripcion: string | null;
        ini: string;
        fin: string;
      };
    }> = [];

    for (const p of plan) {
      for (const maquinariaId of p.maqIds) {
        const ocup = byMaq.get(maquinariaId) ?? [];
        for (const u of ocup) {
          const uFin = u.fechaFin ?? OPEN_END_FAR_FUTURE;

          if (overlaps(p.iniReserva, p.finReserva, u.fechaInicio, uFin)) {
            conflictos.push({
              tareaId: p.tareaIdRepresentante,
              maquinariaId,
              rangoSolicitado: {
                ini: p.iniReserva.toISOString(),
                fin: p.finReserva.toISOString(),
                entrega: sameDayKey(p.entregaDia),
                recogida: sameDayKey(p.recogidaDia),
              },
              ocupadoPor: {
                usoId: u.id,
                tareaId: u.tareaId,
                conjuntoId: u.tarea?.conjuntoId ?? null,
                descripcion: u.tarea?.descripcion ?? null,
                ini: u.fechaInicio.toISOString(),
                fin: (u.fechaFin ?? OPEN_END_FAR_FUTURE).toISOString(),
              },
            });
            break;
          }
        }
      }
    }

    if (conflictos.length) {
      const maqIdsConflict = Array.from(
        new Set(conflictos.map((c) => c.maquinariaId)),
      );
      const maqs = await this.prisma.maquinaria.findMany({
        where: { id: { in: maqIdsConflict } },
        select: { id: true, nombre: true },
      });
      const nombrePorId = new Map(maqs.map((m) => [m.id, m.nombre]));

      const first = conflictos[0];
      const maquinaNombre = nombrePorId.get(first.maquinariaId);

      throw buildMaquinariaNoDisponibleError({
        maquinariaId: first.maquinariaId,
        maquinaNombre,
        conflictos: conflictos as any,
      });
    }

    // ========= 5) Crear reservas (1 por grupo) =========
    const creadasIds: number[] = [];

    await this.prisma.$transaction(async (tx) => {
      for (const p of plan) {
        for (const maquinariaId of p.maqIds) {
          const existe = await tx.usoMaquinaria.findFirst({
            where: {
              tareaId: p.tareaIdRepresentante,
              maquinariaId,
              fechaInicio: p.iniReserva,
              fechaFin: p.finReserva,
            },
            select: { id: true },
          });

          if (!existe) {
            const created = await tx.usoMaquinaria.create({
              data: {
                tarea: { connect: { id: p.tareaIdRepresentante } },
                maquinaria: { connect: { id: maquinariaId } },
                fechaInicio: p.iniReserva,
                fechaFin: p.finReserva,
                observacion: `Reserva preventiva (${sameDayKey(p.entregaDia)}→${sameDayKey(p.recogidaDia)})`,
              },
              select: { id: true },
            });
            creadasIds.push(created.id);
          }

          await tx.maquinariaConjunto.updateMany({
            where: { conjuntoId, maquinariaId, estado: "ACTIVA" },
            data: { tareaId: p.tareaIdRepresentante },
          });
        }
      }
    });

    return { ok: true, creadas: creadasIds.length, ids: creadasIds };
  }

  private buscarDiaPermitidoAnterior(
    fecha: Date,
    diasPermitidos: Set<number>,
    festivosSet?: Set<string>, // "YYYY-MM-DD"
  ) {
    const atStartOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
    const key = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

    let d = atStartOfDay(fecha);
    d.setDate(d.getDate() - 1); // ✅ estricto: arrancar en el día anterior

    for (let guard = 0; guard < 62; guard++) {
      const k = key(d);
      const esFestivo = festivosSet?.has(k) ?? false;

      if (diasPermitidos.has(d.getDay()) && !esFestivo) return new Date(d);
      d.setDate(d.getDate() - 1);
    }

    // fallback
    return atStartOfDay(fecha);
  }

  private buscarDiaPermitidoPosterior(
    fecha: Date,
    diasPermitidos: Set<number>,
    festivosSet?: Set<string>,
  ) {
    const atStartOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
    const key = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

    let d = atStartOfDay(fecha);
    d.setDate(d.getDate() + 1); // ✅ estricto: arrancar en el día siguiente

    for (let guard = 0; guard < 62; guard++) {
      const k = key(d);
      const esFestivo = festivosSet?.has(k) ?? false;

      if (diasPermitidos.has(d.getDay()) && !esFestivo) return new Date(d);
      d.setDate(d.getDate() + 1);
    }

    return atStartOfDay(fecha);
  }

  private calcularRangoReserva(params: {
    fechaInicioUso: Date;
    fechaFinUso: Date;
    diasEntregaRecogida: Set<number>; // JS getDay(): 0..6
    festivosSet?: Set<string>; // "YYYY-MM-DD"
  }) {
    const { fechaInicioUso, fechaFinUso, diasEntregaRecogida, festivosSet } =
      params;

    // ✅ Validaciones duras
    if (!(fechaInicioUso instanceof Date) || isNaN(+fechaInicioUso)) {
      throw new Error("fechaInicioUso inválida");
    }
    if (!(fechaFinUso instanceof Date) || isNaN(+fechaFinUso)) {
      throw new Error("fechaFinUso inválida");
    }

    // ✅ Blindado: si viene invertido, lo corrige
    const iniUso =
      +fechaInicioUso <= +fechaFinUso ? fechaInicioUso : fechaFinUso;
    const finUso =
      +fechaInicioUso <= +fechaFinUso ? fechaFinUso : fechaInicioUso;

    if (!diasEntregaRecogida || diasEntregaRecogida.size === 0) {
      throw new Error("diasEntregaRecogida vacío");
    }

    const atStartOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);

    const atEndOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);

    // ✅ Normalizar a día (sin hora)
    const usoInicioDia = atStartOfDay(iniUso);
    const usoFinDia = atStartOfDay(finUso);

    const entregaDia = this.buscarDiaPermitidoAnterior(
      usoInicioDia,
      diasEntregaRecogida,
      festivosSet,
    );

    const recogidaDia = this.buscarDiaPermitidoPosterior(
      usoFinDia,
      diasEntregaRecogida,
      festivosSet,
    );

    const iniReserva = atStartOfDay(entregaDia);
    const finReserva = atEndOfDay(recogidaDia);

    if (+finReserva < +iniReserva) {
      throw new Error("Rango de reserva inválido (fin < inicio)");
    }

    return { entregaDia, recogidaDia, iniReserva, finReserva };
  }
}

/* ============== Helpers de tiempo/agenda ============== */

type Intervalo = { i: number; f: number };

function enumerateDays(start: Date, end: Date): Date[] {
  const out: Date[] = [];
  const cur = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  const last = new Date(end.getFullYear(), end.getMonth(), end.getDate());
  while (cur <= last) {
    out.push(new Date(cur));
    cur.setDate(cur.getDate() + 1);
  }
  return out;
}

export function buildBloqueosPorDescanso(horario: HorarioDia): Bloqueo[] {
  const ds = horario.descansoStartMin;
  const df = horario.descansoEndMin;

  if (ds == null || df == null) return [];

  if (!(horario.startMin < ds && ds < df && df < horario.endMin)) return [];

  return [{ startMin: ds, endMin: df, motivo: "DESCANSO" }];
}

function dateToDiaSemana(d: Date): DiaSemana {
  switch (d.getDay()) {
    case 0:
      return DiaSemana.DOMINGO;
    case 1:
      return DiaSemana.LUNES;
    case 2:
      return DiaSemana.MARTES;
    case 3:
      return DiaSemana.MIERCOLES;
    case 4:
      return DiaSemana.JUEVES;
    case 5:
      return DiaSemana.VIERNES;
    case 6:
      return DiaSemana.SABADO;
    default:
      return DiaSemana.LUNES;
  }
}

function inicioSemana(fecha: Date): Date {
  const d = new Date(fecha);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1); // lunes
  return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
}

async function minutosAsignadosEnSemana(
  prisma: PrismaClient | Prisma.TransactionClient,
  conjuntoId: string,
  operarioId: string,
  fecha: Date,
  incluirPublicadas: boolean,
): Promise<number> {
  const ini = inicioSemana(fecha);
  const fin = new Date(ini);
  fin.setDate(ini.getDate() + 6);

  const where: any = {
    conjuntoId,
    operarios: { some: { id: operarioId.toString() } },
    fechaInicio: { lte: fin },
    fechaFin: { gte: ini },
  };

  if (!incluirPublicadas) {
    where.borrador = true;
  }

  const tareas = await prisma.tarea.findMany({
    where,
    select: { duracionMinutos: true },
  });

  return tareas.reduce((acc, t) => acc + (t.duracionMinutos ?? 0), 0);
}

async function existeSolapeParaOperario(
  prisma: PrismaClient | Prisma.TransactionClient,
  params: {
    conjuntoId: string;
    operarioId: string | number;
    fechaInicio: Date;
    fechaFin: Date;
    soloBorrador?: boolean;
    excluirTareaId?: number;
    excluirEstados?: string[];
  },
): Promise<boolean> {
  const {
    conjuntoId,
    operarioId,
    fechaInicio,
    fechaFin,
    soloBorrador = true,
    excluirTareaId,
    excluirEstados = [],
  } = params;

  const where: any = {
    conjuntoId,
    // ✅ ahora incluye preventivas y correctivas
    tipo: { in: [TipoTarea.PREVENTIVA, TipoTarea.CORRECTIVA] as any },
    operarios: { some: { id: operarioId.toString() } },
    fechaInicio: { lt: fechaFin },
    fechaFin: { gt: fechaInicio },
  };

  if (soloBorrador) where.borrador = true;

  if (excluirEstados.length) {
    where.estado = { notIn: excluirEstados as any };
  }

  if (excluirTareaId != null) {
    where.id = { not: excluirTareaId };
  }

  const overlap = await prisma.tarea.findFirst({
    where,
    select: { id: true },
  });

  return Boolean(overlap);
}

async function getOperarioNombre(
  prisma: PrismaClient | Prisma.TransactionClient,
  operarioId: string | number,
): Promise<string> {
  const idStr = operarioId.toString();

  const op = await prisma.operario.findUnique({
    where: { id: idStr },
    include: { usuario: true },
  });

  return op?.usuario?.nombre ?? `Operario ${idStr}`;
}

function pickDaysByFrecuencia(days: Date[], def: any): Date[] {
  switch (def.frecuencia) {
    case Frecuencia.DIARIA:
      return days;

    case Frecuencia.SEMANAL: {
      const dia = def.diaSemanaProgramado ?? DiaSemana.LUNES;
      const target = diaSemanaToJsDay(dia);
      return days.filter((d) => d.getDay() === target);
    }

    case Frecuencia.MENSUAL: {
      const dd = def.diaMesProgramado ?? 1;
      return days.filter((d) => d.getDate() === dd);
    }

    default:
      return days;
  }
}

function diaSemanaToJsDay(d: DiaSemana): number {
  switch (d) {
    case DiaSemana.DOMINGO:
      return 0;
    case DiaSemana.LUNES:
      return 1;
    case DiaSemana.MARTES:
      return 2;
    case DiaSemana.MIERCOLES:
      return 3;
    case DiaSemana.JUEVES:
      return 4;
    case DiaSemana.VIERNES:
      return 5;
    case DiaSemana.SABADO:
      return 6;
  }
}

function solapa(a: Intervalo, b: Intervalo) {
  return a.i < b.f && b.i < a.f;
}

function mergeIntervalos(xs: Intervalo[]): Intervalo[] {
  if (!xs.length) return [];
  const sorted = [...xs].sort((a, b) => a.i - b.i);

  const out: Intervalo[] = [sorted[0]];
  for (let k = 1; k < sorted.length; k++) {
    const last = out[out.length - 1];
    const cur = sorted[k];

    if (cur.i <= last.f) {
      // solapa o pega => unir
      last.f = Math.max(last.f, cur.f);
    } else {
      out.push({ ...cur });
    }
  }
  return out;
}

/**
 * ✅ Límite semanal (minutos) por conjunto:
 * - si Conjunto.limiteHorasSemanaOverride existe -> usa ese
 * - si no, usa Empresa.limiteHorasSemana de la empresa del conjunto
 * - fallback: 42h
 */
async function getLimiteMinSemanaPorConjunto(
  prisma: PrismaClient | Prisma.TransactionClient,
  conjuntoId: string,
): Promise<number> {
  const conjunto = await prisma.conjunto.findUnique({
    where: { nit: conjuntoId },
    select: {
      limiteHorasSemanaOverride: true,
      empresa: { select: { limiteHorasSemana: true } },
    },
  });

  const override = conjunto?.limiteHorasSemanaOverride;
  if (override != null) return override * 60;

  return (conjunto?.empresa?.limiteHorasSemana ?? 42) * 60;
}
