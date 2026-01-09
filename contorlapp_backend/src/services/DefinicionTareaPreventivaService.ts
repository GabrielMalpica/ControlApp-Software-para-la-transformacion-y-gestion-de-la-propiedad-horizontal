// src/services/DefinicionTareaPreventivaService.ts
import {
  PrismaClient,
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
  calcularHorasEstimadas,
} from "../model/DefinicionTareaPreventiva";
import { z } from "zod";

type HHmm = `${string}:${string}`;
const DEFAULT_LIMITE_HORAS_SEMANA = 42;

/* ============== DTOs internos (Zod) ============== */

const DividirTareaBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.number().int().positive(),
  bloques: z
    .array(
      z.object({
        fechaInicio: z.coerce.date(),
        fechaFin: z.coerce.date(),
      })
    )
    .min(2, "Debe dividirse en al menos 2 bloques"),
});

const EditarBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.number().int().positive(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  duracionHoras: z.number().int().min(1).optional(),
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
  tiempoEstimadoHoras: z.number().positive().optional(),
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
  duracionHoras: z.number().int().positive().optional(),
  ubicacionId: z.number().int().positive().optional(),
  elementoId: z.number().int().positive().optional(),
  operariosIds: z.array(z.number().int().positive()).optional(),
  supervisorId: z.number().int().positive().nullable().optional(),
  tiempoEstimadoHoras: z.number().positive().nullable().optional(),
});

/* ============== SERVICE ============== */

export class DefinicionTareaPreventivaService {
  constructor(private prisma: PrismaClient) {}

  /* ============== CRUD BÁSICO ============== */

  async crear(payload: unknown) {
    const dto = CrearDefinicionPreventivaDTO.parse(payload);

    const data: Prisma.DefinicionTareaPreventivaCreateInput = {
      conjunto: { connect: { nit: dto.conjuntoId } },
      ubicacion: { connect: { id: dto.ubicacionId } },
      elemento: { connect: { id: dto.elementoId } },
      descripcion: dto.descripcion,
      frecuencia: dto.frecuencia,
      prioridad: dto.prioridad ?? 5,

      unidadCalculo: dto.unidadCalculo ?? null,
      areaNumerica:
        dto.areaNumerica != null ? new Prisma.Decimal(dto.areaNumerica) : null,
      rendimientoBase:
        dto.rendimientoBase != null
          ? new Prisma.Decimal(dto.rendimientoBase)
          : null,
      duracionHorasFija: dto.duracionHorasFija ?? null,

      insumoPrincipal: dto.insumoPrincipalId
        ? { connect: { id: dto.insumoPrincipalId } }
        : undefined,
      consumoPrincipalPorUnidad:
        dto.consumoPrincipalPorUnidad != null
          ? new Prisma.Decimal(dto.consumoPrincipalPorUnidad)
          : null,

      insumosPlanJson:
        dto.insumosPlanJson != null
          ? (dto.insumosPlanJson as Prisma.InputJsonValue)
          : undefined,
      maquinariaPlanJson:
        dto.maquinariaPlanJson != null
          ? (dto.maquinariaPlanJson as Prisma.InputJsonValue)
          : undefined,

      // supervisor de la definición
      supervisor:
        (dto as any).supervisorId == null
          ? undefined
          : { connect: { id: (dto as any).supervisorId.toString() } },

      activo: dto.activo ?? true,
    };

    // Operarios sugeridos:
    // - Si viene operariosIds → conectamos todos.
    // - Si solo viene responsableSugeridoId (modo viejo) → lo conectamos como único.
    if (
      Array.isArray((dto as any).operariosIds) &&
      (dto as any).operariosIds.length
    ) {
      const operariosIds: number[] = (dto as any).operariosIds;
      (data as any).operarios = {
        connect: operariosIds.map((id) => ({ id: id.toString() })),
      };
    } else if ((dto as any).responsableSugeridoId) {
      const idNum: number = (dto as any).responsableSugeridoId;
      (data as any).operarios = {
        connect: { id: idNum.toString() },
      };
    }

    return this.prisma.definicionTareaPreventiva.create({ data });
  }

  /** Listado con filtros (opcional) */
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

  /** Listado simple por conjunto (para GET /conjuntos/:nit/preventivas) */
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
      duracionHorasFija: dto.duracionHorasFija ?? undefined,

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

      supervisor:
        (dto as any).supervisorId === undefined
          ? undefined
          : (dto as any).supervisorId === null
          ? { disconnect: true }
          : { connect: { id: (dto as any).supervisorId.toString() } },
    };

    // Actualización de operarios sugeridos
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

  /** Adaptador al nombre del DTO público */
  async generarCronograma(payload: unknown) {
    const dto = GenerarCronogramaDTO.parse(payload);
    const creadas = await this.generarBorradorMensual({
      conjuntoId: dto.conjuntoId,
      periodoAnio: dto.anio,
      periodoMes: dto.mes,
      tamanoBloqueHoras: dto.tamanoBloqueHoras ?? 1,
    });
    return { creadas };
  }

  /* ============== OPERACIONES SOBRE TAREAS BORRADOR ============== */

  async dividirTareaBorrador(payload: unknown) {
    const { conjuntoId, tareaId, bloques } =
      DividirTareaBorradorDTO.parse(payload);

    // 1) Buscar la tarea original
    const original = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: { operarios: true },
    });

    if (!original || !original.borrador || original.conjuntoId !== conjuntoId) {
      throw new Error(
        "Tarea no encontrada, no es borrador o no pertenece a este conjunto."
      );
    }
    if (original.tipo !== TipoTarea.PREVENTIVA) {
      throw new Error("Solo se pueden dividir tareas preventivas en borrador.");
    }

    // 2) Validar que la suma de horas de los bloques = horas originales
    const horasOriginal = original.duracionHoras ?? 0;
    const horasBloques = bloques.reduce((acc, b) => {
      const diffMs = +b.fechaFin - +b.fechaInicio;
      const h = diffMs / 3_600_000; // ms → horas
      return acc + h;
    }, 0);

    const horasBloquesRedondeadas = Math.round(horasBloques);
    if (horasBloquesRedondeadas !== horasOriginal) {
      throw new Error(
        `La suma de horas de los bloques (${horasBloquesRedondeadas}h) ` +
          `no coincide con la duración original (${horasOriginal}h).`
      );
    }

    // 3) Operarios asignados a la tarea original
    const operariosIds = original.operarios.map((o) => o.id); // string[]

    // 4) Límite semanal (igual que en generarBorradorMensual)
    let limiteHorasSemana = 42;
    if (original.conjuntoId) {
      const conjunto = await this.prisma.conjunto.findUnique({
        where: { nit: original.conjuntoId },
        select: { empresaId: true },
      });
      if (conjunto?.empresaId) {
        const empresa = await this.prisma.empresa.findUnique({
          where: { nit: conjunto.empresaId },
          select: { limiteHorasSemana: true },
        });
        if (empresa?.limiteHorasSemana != null) {
          limiteHorasSemana = empresa.limiteHorasSemana;
        }
      }
    }

    await this.prisma.$transaction(async (tx) => {
      // 5) Validar solapes y horas semanales por cada operario / bloque
      for (const opId of operariosIds) {
        for (const b of bloques) {
          const inicioSemana = inicioSemanaFn(b.fechaInicio);
          const finSemana = new Date(inicioSemana);
          finSemana.setDate(inicioSemana.getDate() + 6);

          const tareasSemana = await tx.tarea.findMany({
            where: {
              conjuntoId,
              borrador: true,
              tipo: TipoTarea.PREVENTIVA,
              operarios: { some: { id: opId } },
              fechaFin: { gte: inicioSemana },
              fechaInicio: { lte: finSemana },
              id: { not: tareaId }, // excluir la original
            },
            select: { fechaInicio: true, fechaFin: true, duracionHoras: true },
          });

          const horasSemana = tareasSemana.reduce(
            (acc, t) => acc + (t.duracionHoras ?? 0),
            0
          );
          const duracionBloqueH =
            (+b.fechaFin - +b.fechaInicio) / 3_600_000 || 0;

          if (horasSemana + duracionBloqueH > limiteHorasSemana) {
            throw new Error(
              `El operario ${opId} superaría el límite semanal de horas con este bloque.`
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
            throw new Error(
              `Solape de agenda detectado para el operario ${opId} en uno de los bloques.`
            );
          }
        }
      }

      // 6) Eliminar la tarea original y crear los nuevos bloques
      await tx.tarea.delete({ where: { id: tareaId } });

      for (const b of bloques) {
        const duracionHoras = Math.max(
          1,
          Math.round((+b.fechaFin - +b.fechaInicio) / 3_600_000)
        );

        await tx.tarea.create({
          data: {
            descripcion: original.descripcion,
            fechaInicio: b.fechaInicio,
            fechaFin: b.fechaFin,
            duracionHoras,
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

            tiempoEstimadoHoras: original.tiempoEstimadoHoras,
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
    payload: unknown
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

    const operariosIds = original.operarios.map((o) => o.id); // string[]

    const dur1 = Math.max(
      1,
      Math.round((+dto.fechaFin1 - +dto.fechaInicio1) / 3600000)
    );
    const dur2 = Math.max(
      1,
      Math.round((+dto.fechaFin2 - +dto.fechaInicio2) / 3600000)
    );

    // Límite semanal por operario
    let limiteHorasSemana = 42;
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: { empresaId: true },
    });
    if (conjunto?.empresaId) {
      const empresa = await this.prisma.empresa.findUnique({
        where: { nit: conjunto.empresaId },
        select: { limiteHorasSemana: true },
      });
      if (empresa?.limiteHorasSemana != null) {
        limiteHorasSemana = empresa.limiteHorasSemana;
      }
    }

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
        const fin = new Date(ini);
        fin.setDate(ini.getDate() + 6);

        const tareasSemana = await this.prisma.tarea.findMany({
          where: {
            id: { not: tareaId },
            conjuntoId,
            borrador: true,
            tipo: TipoTarea.PREVENTIVA,
            operarios: { some: { id: opId } },
            fechaInicio: { lte: fin },
            fechaFin: { gte: ini },
          },
          select: { duracionHoras: true },
        });

        const horasSemana = tareasSemana.reduce(
          (acc, t) => acc + (t.duracionHoras ?? 0),
          0
        );

        if (horasSemana + extra > limiteHorasSemana) {
          throw new Error(
            `Al dividir esta tarea, el operario ${opId} superaría el límite semanal de horas.`
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
        throw new Error(
          `Solape de agenda con operario ${opId} al dividir la tarea (primer bloque).`
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
        throw new Error(
          `Solape de agenda con operario ${opId} al dividir la tarea (segundo bloque).`
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

      const dataBase = {
        descripcion: original.descripcion,
        estado: EstadoTarea.ASIGNADA,
        tipo: TipoTarea.PREVENTIVA,
        frecuencia: original.frecuencia,
        borrador: true as const,

        conjuntoId,
        ubicacionId: original.ubicacionId,
        elementoId: original.elementoId,
        supervisorId: original.supervisorId,

        tiempoEstimadoHoras: original.tiempoEstimadoHoras,
        insumoPrincipalId: original.insumoPrincipalId,
        consumoPrincipalPorUnidad: original.consumoPrincipalPorUnidad,
        consumoTotalEstimado: original.consumoTotalEstimado,
        insumosPlanJson: original.insumosPlanJson as Prisma.InputJsonValue,
        maquinariaPlanJson:
          original.maquinariaPlanJson as Prisma.InputJsonValue,
      };

      const tarea1 = await tx.tarea.create({
        data: {
          ...dataBase,
          fechaInicio: dto.fechaInicio1,
          fechaFin: dto.fechaFin1,
          duracionHoras: dur1,
          periodoAnio: periodoAnio1,
          periodoMes: periodoMes1,
          grupoPlanId: null,
          bloqueIndex: null,
          bloquesTotales: null,
          operarios: operariosIds.length
            ? {
                connect: operariosIds.map((id) => ({ id })),
              }
            : undefined,
        },
      });

      const tarea2 = await tx.tarea.create({
        data: {
          ...dataBase,
          fechaInicio: dto.fechaInicio2,
          fechaFin: dto.fechaFin2,
          duracionHoras: dur2,
          periodoAnio: periodoAnio2,
          periodoMes: periodoMes2,
          grupoPlanId: null,
          bloqueIndex: null,
          bloquesTotales: null,
          operarios: operariosIds.length
            ? {
                connect: operariosIds.map((id) => ({ id })),
              }
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
    consolidar?: boolean; // default=false
  }) {
    const { conjuntoId, anio, mes, consolidar = false } = params;

    const borradores = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        tipo: TipoTarea.PREVENTIVA,
      },
      include: { operarios: true },
      orderBy: [{ grupoPlanId: "asc" }, { bloqueIndex: "asc" }, { id: "asc" }],
    });

    if (borradores.length === 0) {
      return { publicadas: 0, gruposConsolidados: 0, publicadasSimples: 0 };
    }

    const porOperario: Record<string, { i: Date; f: Date }[]> = {};
    for (const t of borradores) {
      for (const op of t.operarios) {
        if (!porOperario[op.id]) porOperario[op.id] = [];
        porOperario[op.id].push({ i: t.fechaInicio, f: t.fechaFin });
      }
    }

    // validar solapes en borrador por operario
    for (const opId of Object.keys(porOperario)) {
      const arr = porOperario[opId].sort((a, b) => +a.i - +b.i);
      for (let i = 1; i < arr.length; i++) {
        const prev = arr[i - 1];
        const cur = arr[i];
        const haySolape = prev.i < cur.f && cur.i < prev.f;
        if (haySolape) {
          throw new Error(
            `Solape detectado para operario ${opId} en el borrador del período.`
          );
        }
      }
    }

    if (!consolidar) {
      const res = await this.prisma.tarea.updateMany({
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
        publicadas: res.count,
        gruposConsolidados: 0,
        publicadasSimples: res.count,
      };
    }

    const grupos = new Map<string, typeof borradores>();
    for (const t of borradores) {
      if (!t.grupoPlanId) continue;
      if (!grupos.has(t.grupoPlanId)) grupos.set(t.grupoPlanId, [] as any);
      grupos.get(t.grupoPlanId)!.push(t);
    }

    let gruposConsolidados = 0;
    let publicadasSimples = 0;

    await this.prisma.$transaction(async (tx) => {
      // Consolidar grupos
      for (const [, bloques] of grupos) {
        if (!bloques.length) continue;

        const base = bloques[0];
        const fechaInicio = new Date(
          Math.min(...bloques.map((b) => +b.fechaInicio))
        );
        const fechaFin = new Date(Math.max(...bloques.map((b) => +b.fechaFin)));
        const duracionTotal = bloques.reduce(
          (acc, b) => acc + (b.duracionHoras ?? 0),
          0
        );

        const operariosIds = Array.from(
          new Set(bloques.flatMap((b) => b.operarios.map((o) => o.id)))
        );

        await tx.tarea.create({
          data: {
            descripcion: base.descripcion,
            fechaInicio,
            fechaFin,
            duracionHoras: duracionTotal,
            estado: EstadoTarea.ASIGNADA,
            tipo: TipoTarea.PREVENTIVA,
            frecuencia: base.frecuencia,
            borrador: false,
            periodoAnio: base.periodoAnio,
            periodoMes: base.periodoMes,
            ubicacionId: base.ubicacionId,
            elementoId: base.elementoId,
            conjuntoId: base.conjuntoId!,
            supervisorId: base.supervisorId ?? null,
            tiempoEstimadoHoras: base.tiempoEstimadoHoras ?? null,
            insumoPrincipalId: base.insumoPrincipalId ?? null,
            consumoPrincipalPorUnidad: base.consumoPrincipalPorUnidad ?? null,
            consumoTotalEstimado: base.consumoTotalEstimado ?? null,
            insumosPlanJson: base.insumosPlanJson ?? undefined,
            maquinariaPlanJson: base.maquinariaPlanJson ?? undefined,
            operarios: operariosIds.length
              ? { connect: operariosIds.map((id) => ({ id })) }
              : undefined,
          },
        });

        await tx.tarea.deleteMany({
          where: { id: { in: bloques.map((b) => b.id) } },
        });

        gruposConsolidados++;
      }

      // Publicar las tareas sin grupo directamente
      const idsSinGrupo = borradores
        .filter((t) => !t.grupoPlanId)
        .map((t) => t.id);
      if (idsSinGrupo.length) {
        const res = await tx.tarea.updateMany({
          where: { id: { in: idsSinGrupo } },
          data: { borrador: false },
        });
        publicadasSimples = res.count;
      }
    });

    const publicadas = gruposConsolidados + publicadasSimples;
    return { publicadas, gruposConsolidados, publicadasSimples };
  }

  /**
   * Genera tareas PREVENTIVAS en modo "borrador" para un conjunto y mes.
   * - Respeta la frecuencia de cada definición activa.
   * - Usa la jornada de ConjuntoHorario (por día de semana).
   * - Controla horas semanales POR OPERARIO.
   * - Evita solapes POR OPERARIO.
   * - Usa TODOS los operarios asociados a la definición (si todos tienen cupo y sin solape).
   */
  async generarBorradorMensual(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number; // 1..12
    tamanoBloqueHoras?: number; // fallback si no hay estimación
  }): Promise<number> {
    const { conjuntoId, periodoAnio, periodoMes } = params;
    const tamanoBloqueHoras = params.tamanoBloqueHoras ?? 1;

    // 1) Definiciones preventivas activas del conjunto
    const defs = await this.prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId, activo: true },
      include: {
        operarios: true,
        supervisor: true,
        insumoPrincipal: true,
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });
    if (defs.length === 0) return 0;

    // 2) Horarios del conjunto por día de semana
    type HorarioDia = { start: number; end: number };
    const horarios = await this.prisma.conjuntoHorario.findMany({
      where: { conjuntoId },
    });
    const horariosPorDia = new Map<DiaSemana, HorarioDia>();
    for (const h of horarios) {
      const [hA] = (h.horaApertura as HHmm).split(":").map(Number);
      const [hC] = (h.horaCierre as HHmm).split(":").map(Number);
      horariosPorDia.set(h.dia, { start: hA, end: hC });
    }

    // 3) Limpiar borradores previos del mismo periodo (solo borrador)
    await this.prisma.tarea.deleteMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio,
        periodoMes,
        tipo: TipoTarea.PREVENTIVA,
      },
    });

    // 4) Rango de fechas del mes (1..último día)
    const month0 = periodoMes - 1;
    const inicioMes = new Date(periodoAnio, month0, 1, 0, 0, 0, 0);
    const finMes = new Date(periodoAnio, month0 + 1, 0, 23, 59, 59, 999);
    const fechasDelMes = enumerateDays(inicioMes, finMes);

    const ymd = (d: Date) => d.toISOString().slice(0, 10);
    let creadas = 0;
    const siguienteHoraPorDiaYOperario: Record<
      string,
      Record<string, number>
    > = {};

    // 5) Recorrer cada definición preventiva
    for (const def of defs) {
      // Tareas YA PUBLICADAS para esta definición en el mes (no tocar esos días)
      const publicadas = await this.prisma.tarea.findMany({
        where: {
          conjuntoId,
          borrador: false,
          tipo: TipoTarea.PREVENTIVA,
          periodoAnio,
          periodoMes,
          descripcion: def.descripcion,
          ubicacionId: def.ubicacionId,
          elementoId: def.elementoId,
        },
        select: { fechaInicio: true },
      });

      const diasYaPublicados = new Set<string>(
        publicadas.map((t) => ymd(t.fechaInicio))
      );

      // Días planificados según frecuencia
      const diasPlan = pickDaysByFrecuencia(fechasDelMes, def.frecuencia);
      if (diasPlan.length === 0) continue;

      // Días en los que SÍ vamos a generar (no duplicar publicados)
      const diasParaGenerar = diasPlan.filter(
        (d) => !diasYaPublicados.has(ymd(d))
      );
      if (diasParaGenerar.length === 0) continue;

      // Horas estimadas a partir de área/rendimiento o duración fija
      const horasEstimadasFloat =
        calcularHorasEstimadas({
          areaNumerica: def.areaNumerica ? Number(def.areaNumerica) : undefined,
          rendimientoBase: def.rendimientoBase
            ? Number(def.rendimientoBase)
            : undefined,
          duracionHorasFija: def.duracionHorasFija ?? undefined,
        }) ?? 0;

      const duracionBloque = Math.max(
        1,
        Math.round(
          horasEstimadasFloat > 0 ? horasEstimadasFloat : tamanoBloqueHoras
        )
      );

      // TODOS los operarios definidos en la preventiva
      const operariosIds = def.operarios.map((o) => o.id); // string[]

      // 6) Generar tareas por cada día aplicable
      for (const diaFecha of diasParaGenerar) {
        const diaSemana = dateToDiaSemana(diaFecha);
        const horario = horariosPorDia.get(diaSemana);
        if (!horario) continue;

        const { start, end } = horario;

        // si la duración ni siquiera cabe en la jornada, saltamos
        if (start + duracionBloque > end) continue;

        const diaKey = ymd(diaFecha);
        const mapaOperarios = (siguienteHoraPorDiaYOperario[diaKey] ??=
          {} as Record<string, number>);

        // Si no hay operarios definidos en la preventiva,
        // la dejamos a la hora de apertura.
        let horaInicioReal = start;

        if (operariosIds.length) {
          // Para los operarios de esta tarea, buscamos la hora
          // más tarde a la que todos estén libres ese día.
          const horasSiguientes = operariosIds.map(
            (id) => mapaOperarios[id] ?? start
          );
          horaInicioReal = Math.max(...horasSiguientes);

          // si ya no cabe en la jornada, saltamos este día
          if (horaInicioReal + duracionBloque > end) continue;
        }

        const fechaInicio = new Date(diaFecha);
        fechaInicio.setHours(horaInicioReal, 0, 0, 0);

        const fechaFin = new Date(fechaInicio);
        fechaFin.setHours(fechaInicio.getHours() + duracionBloque);

        // Creamos la tarea
        await this.prisma.tarea.create({
          data: {
            descripcion: def.descripcion,
            fechaInicio,
            fechaFin,
            duracionHoras: duracionBloque,
            estado: EstadoTarea.ASIGNADA,
            tipo: TipoTarea.PREVENTIVA,
            frecuencia: def.frecuencia,
            borrador: true,
            periodoAnio,
            periodoMes,

            grupoPlanId: null,
            bloqueIndex: null,
            bloquesTotales: null,

            supervisorId: def.supervisorId ?? null,
            ubicacionId: def.ubicacionId,
            elementoId: def.elementoId,
            conjuntoId,

            tiempoEstimadoHoras: new Prisma.Decimal(duracionBloque),
            insumoPrincipalId: def.insumoPrincipalId ?? null,
            consumoPrincipalPorUnidad:
              def.consumoPrincipalPorUnidad != null
                ? new Prisma.Decimal(def.consumoPrincipalPorUnidad)
                : null,
            consumoTotalEstimado: null,

            insumosPlanJson: def.insumosPlanJson
              ? (def.insumosPlanJson as Prisma.InputJsonValue)
              : undefined,
            maquinariaPlanJson: def.maquinariaPlanJson
              ? (def.maquinariaPlanJson as Prisma.InputJsonValue)
              : undefined,

            operarios: operariosIds.length
              ? {
                  connect: operariosIds.map((id) => ({ id })),
                }
              : undefined,
          },
        });

        // Actualizamos la "siguiente hora libre" de cada operario
        if (operariosIds.length) {
          const nuevaHoraLibre = horaInicioReal + duracionBloque;
          for (const opId of operariosIds) {
            mapaOperarios[opId] = nuevaHoraLibre;
          }
        }

        creadas++;
      }
    }

    return creadas;
  }

  async editarTareaBorrador(payload: unknown) {
    const dto = EditarBorradorDTO.parse(payload);

    const t = await this.prisma.tarea.findUnique({
      where: { id: dto.tareaId },
      select: { id: true, borrador: true, conjuntoId: true },
    });
    if (!t || !t.borrador || t.conjuntoId !== dto.conjuntoId) {
      throw new Error(
        "Tarea no existe, no es borrador o no pertenece a este conjunto."
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
        duracionHoras: dto.duracionHoras ?? undefined,
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
        const haySolape = await existeSolapeParaOperario(this.prisma, {
          conjuntoId,
          operarioId: opId,
          fechaInicio: dto.fechaInicio,
          fechaFin: dto.fechaFin,
          soloBorrador: true,
        });

        if (haySolape) {
          throw new Error(`Solape de agenda con operario ${opId}`);
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
        duracionHoras: Math.max(
          1,
          Math.round((+dto.fechaFin - +dto.fechaInicio) / 3600000)
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

        tiempoEstimadoHoras: dto.tiempoEstimadoHoras
          ? new Prisma.Decimal(dto.tiempoEstimadoHoras)
          : null,

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
    payload: unknown
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
          throw new Error(`Solape de agenda con operario ${opId}`);
        }
      }
    }

    return this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        descripcion: dto.descripcion ?? undefined,
        fechaInicio,
        fechaFin,
        duracionHoras:
          dto.duracionHoras ??
          (fechaInicio && fechaFin
            ? Math.max(1, Math.round((+fechaFin - +fechaInicio) / 3600000))
            : undefined),
        ubicacionId: dto.ubicacionId ?? undefined,
        elementoId: dto.elementoId ?? undefined,
        supervisorId:
          dto.supervisorId === undefined
            ? undefined
            : dto.supervisorId === null
            ? null
            : dto.supervisorId.toString(),
        tiempoEstimadoHoras:
          dto.tiempoEstimadoHoras === undefined
            ? undefined
            : dto.tiempoEstimadoHoras === null
            ? null
            : new Prisma.Decimal(dto.tiempoEstimadoHoras),
        operarios:
          dto.operariosIds === undefined
            ? undefined
            : {
                set: dto.operariosIds.map((id) => ({ id: id.toString() })),
              },
      },
    });
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
}

/* ============== Helpers de tiempo/agenda ============== */

// Genera array de fechas (00:00) entre dos fechas inclusivas
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

async function horasAsignadasEnSemana(
  prisma: PrismaClient,
  operarioId: string,
  fecha: Date,
  incluirPublicadas: boolean = false
): Promise<number> {
  const inicio = inicioSemana(fecha);
  const fin = new Date(inicio);
  fin.setDate(inicio.getDate() + 6);

  const where: any = {
    operarios: { some: { id: operarioId.toString() } },
    fechaInicio: { lte: fin },
    fechaFin: { gte: inicio },
  };

  if (!incluirPublicadas) {
    where.borrador = true;
  }

  const tareas = await prisma.tarea.findMany({
    where,
    select: { duracionHoras: true },
  });

  return tareas.reduce((acc, t) => acc + (t.duracionHoras ?? 0), 0);
}

async function existeSolapeParaOperario(
  prisma: PrismaClient,
  params: {
    conjuntoId: string;
    operarioId: string | number;
    fechaInicio: Date;
    fechaFin: Date;
    soloBorrador?: boolean; // default: true
    excluirTareaId?: number;
  }
): Promise<boolean> {
  const {
    conjuntoId,
    operarioId,
    fechaInicio,
    fechaFin,
    soloBorrador = true,
    excluirTareaId,
  } = params;

  const where: any = {
    conjuntoId,
    tipo: TipoTarea.PREVENTIVA,
    operarios: { some: { id: operarioId.toString() } },
    // solape clásico: (inicioA < finB) && (finA > inicioB)
    fechaInicio: { lt: fechaFin },
    fechaFin: { gt: fechaInicio },
  };

  if (soloBorrador) {
    where.borrador = true;
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

function inicioSemana(fecha: Date): Date {
  const d = new Date(fecha);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1); // lunes
  return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
}

function inicioSemanaFn(fecha: Date): Date {
  const d = new Date(fecha);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
}

// Selecciona días del mes según frecuencia
function pickDaysByFrecuencia(days: Date[], f: Frecuencia): Date[] {
  switch (f) {
    case Frecuencia.DIARIA:
      return days;
    case Frecuencia.SEMANAL:
      // todos los lunes
      return days.filter((d) => d.getDay() === 1);
    case Frecuencia.QUINCENAL:
      // típicamente 1 y 16
      return days.filter((d) => {
        const dd = d.getDate();
        return dd === 1 || dd === 16;
      });
    case Frecuencia.MENSUAL:
      return days.filter((d) => d.getDate() === 1);
    case Frecuencia.BIMESTRAL:
      // meses pares, día 1
      return days.filter(
        (d) => (d.getMonth() + 1) % 2 === 0 && d.getDate() === 1
      );
    case Frecuencia.TRIMESTRAL:
      // ene-abr-jul-oct, día 1
      return days.filter(
        (d) => d.getDate() === 1 && [0, 3, 6, 9].includes(d.getMonth())
      );
    case Frecuencia.SEMESTRAL:
      // enero y julio, día 1
      return days.filter(
        (d) => d.getDate() === 1 && [0, 6].includes(d.getMonth())
      );
    case Frecuencia.ANUAL:
      // 1 de enero
      return days.filter((d) => d.getDate() === 1 && d.getMonth() === 0);
    default:
      return days;
  }
}
