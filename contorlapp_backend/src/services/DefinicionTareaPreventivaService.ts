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
import { v4 as uuid } from "uuid";
import { z } from "zod";

type HHmm = `${string}:${string}`;

const EditarBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.number().int().positive(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  duracionHoras: z.number().int().min(1).optional(),
  operariosIds: z.array(z.number().int().positive()).optional(),
});

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

      // JSON nullable en create: si viene null/undefined, OMITIR
      insumosPlanJson:
        dto.insumosPlanJson != null
          ? (dto.insumosPlanJson as Prisma.InputJsonValue)
          : undefined,
      maquinariaPlanJson:
        dto.maquinariaPlanJson != null
          ? (dto.maquinariaPlanJson as Prisma.InputJsonValue)
          : undefined,

      responsableSugerido: dto.responsableSugeridoId
        ? { connect: { id: dto.responsableSugeridoId } }
        : undefined,

      activo: dto.activo ?? true,
    };

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
        responsableSugerido: { include: { usuario: true } },
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
        responsableSugerido: { include: { usuario: true } },
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });
  }

  async actualizar(conjuntoId: string, id: number, payload: unknown) {
    const dto = EditarDefinicionPreventivaDTO.parse(payload);

    // validar pertenencia
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

      // JSON nullable en update: Prisma.JsonNull para forzar NULL
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

      responsableSugerido:
        dto.responsableSugeridoId === undefined
          ? undefined
          : dto.responsableSugeridoId === null
          ? { disconnect: true }
          : { connect: { id: dto.responsableSugeridoId } },
    };

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

  async publicarCronograma(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
    consolidar?: boolean; // default=false
  }) {
    const { conjuntoId, anio, mes, consolidar = false } = params;

    // 1) Traer todo el borrador del periodo (preventivas)
    const borradores = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        tipo: TipoTarea.PREVENTIVA,
      },
      include: { operarios: true }, // M:N
      orderBy: [{ grupoPlanId: "asc" }, { bloqueIndex: "asc" }, { id: "asc" }],
    });

    if (borradores.length === 0) {
      return { publicadas: 0, gruposConsolidados: 0, publicadasSimples: 0 };
    }

    // 2) Validación de solapes por operario (en borrador)
    const porOperario: Record<number, { i: Date; f: Date }[]> = {};
    for (const t of borradores) {
      for (const op of t.operarios) {
        if (!porOperario[op.id]) porOperario[op.id] = [];
        porOperario[op.id].push({ i: t.fechaInicio, f: t.fechaFin });
      }
    }
    for (const opId of Object.keys(porOperario)) {
      const arr = porOperario[+opId].sort((a, b) => +a.i - +b.i);
      for (let i = 1; i < arr.length; i++) {
        const prev = arr[i - 1],
          cur = arr[i];
        const haySolape = prev.i <= cur.f && cur.i <= prev.f;
        if (haySolape) {
          throw new Error(
            `Solape detectado para operario ${opId} en el borrador del período.`
          );
        }
      }
    }

    // 3A) Publicación simple (sin consolidar): pasar todo a borrador=false
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

    // 3B) Consolidación por grupoPlanId
    const grupos = new Map<string, typeof borradores>();
    for (const t of borradores) {
      if (!t.grupoPlanId) continue; // por seguridad
      if (!grupos.has(t.grupoPlanId)) grupos.set(t.grupoPlanId, []);
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

      // Publicar (sin consolidar) las que NO tienen grupoPlanId
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

    // total publicadas = consolidadas (1 por grupo) + simples sin grupo
    const publicadas = gruposConsolidados + publicadasSimples;
    return { publicadas, gruposConsolidados, publicadasSimples };
  }

  /**
   * Genera tareas PREVENTIVAS en modo "borrador" para un conjunto y mes.
   * - Respeta frecuencia de cada definición activa.
   * - Divide en bloques de 1h (o el tamaño que pases) dentro del horario del conjunto.
   * - Intenta asignar al responsable sugerido sin exceder horas semanales (Empresa.limiteHorasSemana, default 46).
   * - Evita solape de bloques para el MISMO operario.
   */
  async generarBorradorMensual(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number; // 1..12
    tamanoBloqueHoras?: number;
  }): Promise<number> {
    const { conjuntoId, periodoAnio, periodoMes } = params;
    const tamanoBloqueHoras = params.tamanoBloqueHoras ?? 1;

    // 1) Definiciones activas
    const defs = await this.prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId, activo: true },
      include: {
        responsableSugerido: { include: { usuario: true } },
        insumoPrincipal: true,
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });
    if (defs.length === 0) return 0;

    // 2) Horarios del conjunto
    const horarios = await this.prisma.conjuntoHorario.findMany({
      where: { conjuntoId },
    });
    const horariosPorDia = new Map<DiaSemana, { start: number; end: number }>();
    for (const h of horarios) {
      const [hA] = (h.horaApertura as HHmm).split(":").map(Number);
      const [hC] = (h.horaCierre as HHmm).split(":").map(Number);
      const start = hA;
      const end = hC; // exclusivo
      horariosPorDia.set(h.dia, { start, end });
    }

    // 3) Límite semanal de horas
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: { empresaId: true },
    });
    let limiteHorasSemana = 46;
    if (conjunto?.empresaId) {
      const empresa = await this.prisma.empresa.findUnique({
        where: { nit: conjunto.empresaId },
        select: { limiteHorasSemana: true },
      });
      if (empresa?.limiteHorasSemana != null) {
        limiteHorasSemana = empresa.limiteHorasSemana;
      }
    }

    // 4) (opcional) limpiar borradores del mismo período
    await this.prisma.tarea.deleteMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio,
        periodoMes,
        tipo: TipoTarea.PREVENTIVA,
      },
    });

    // 5) Fechas del mes
    const month0 = periodoMes - 1;
    const inicioMes = new Date(periodoAnio, month0, 1, 0, 0, 0, 0);
    const finMes = new Date(periodoAnio, month0 + 1, 0, 23, 59, 59, 999);
    const fechasDelMes = enumerateDays(inicioMes, finMes);

    // 6) Insertar bloques
    let creadas = 0;

    for (const def of defs) {
      const diasPlan = pickDaysByFrecuencia(fechasDelMes, def.frecuencia);

      const horasEstimadasFloat =
        calcularHorasEstimadas({
          areaNumerica: def.areaNumerica ? Number(def.areaNumerica) : undefined,
          rendimientoBase: def.rendimientoBase
            ? Number(def.rendimientoBase)
            : undefined,
          duracionHorasFija: def.duracionHorasFija ?? undefined,
        }) ?? 0;

      const totalBloques = Math.max(
        1,
        Math.ceil(horasEstimadasFloat / tamanoBloqueHoras)
      );
      const grupoPlanId = uuid();

      let bloqueIndex = 1;
      for (const diaFecha of diasPlan) {
        if (bloqueIndex > totalBloques) break;

        const diaSemana = dateToDiaSemana(diaFecha);
        const horario = horariosPorDia.get(diaSemana);
        if (!horario) continue;

        for (
          let hour = horario.start;
          hour + tamanoBloqueHoras <= horario.end;
          hour += tamanoBloqueHoras
        ) {
          if (bloqueIndex > totalBloques) break;

          const fechaInicio = new Date(diaFecha);
          fechaInicio.setHours(hour, 0, 0, 0);
          const fechaFin = new Date(fechaInicio);
          fechaFin.setHours(fechaInicio.getHours() + tamanoBloqueHoras);

          // Intentar asignar responsable sugerido
          let operarioId: number | null = null;
          if (def.responsableSugeridoId) {
            const horasSemana = await horasAsignadasEnSemana(
              this.prisma,
              def.responsableSugeridoId,
              fechaInicio
            );
            const haySolape = await existeSolapeParaOperario(
              this.prisma,
              def.responsableSugeridoId,
              fechaInicio,
              fechaFin,
              conjuntoId
            );
            if (
              !haySolape &&
              horasSemana + tamanoBloqueHoras <= limiteHorasSemana
            ) {
              operarioId = def.responsableSugeridoId;
            }
          }

          // Crear tarea con IDs escalares + conectar operario (M:N) si corresponde
          await this.prisma.tarea.create({
            data: {
              descripcion: def.descripcion,
              fechaInicio,
              fechaFin,
              duracionHoras: tamanoBloqueHoras,
              estado: EstadoTarea.ASIGNADA, // o un estado "PLAN"
              tipo: TipoTarea.PREVENTIVA,
              frecuencia: def.frecuencia,
              borrador: true,
              periodoAnio,
              periodoMes,
              grupoPlanId,
              bloqueIndex,
              bloquesTotales: totalBloques,

              ...(operarioId
                ? { operarios: { connect: { id: operarioId } } }
                : {}),
              supervisorId: null,

              ubicacionId: def.ubicacionId,
              elementoId: def.elementoId,
              conjuntoId,

              tiempoEstimadoHoras: new Prisma.Decimal(tamanoBloqueHoras),
              insumoPrincipalId: def.insumoPrincipalId ?? null,
              consumoPrincipalPorUnidad:
                def.consumoPrincipalPorUnidad != null
                  ? new Prisma.Decimal(def.consumoPrincipalPorUnidad)
                  : null,
              consumoTotalEstimado: null,

              // JSON nullable en create: omitir si es null/undefined
              insumosPlanJson:
                def.insumosPlanJson != null
                  ? (def.insumosPlanJson as Prisma.InputJsonValue)
                  : undefined,
              maquinariaPlanJson:
                def.maquinariaPlanJson != null
                  ? (def.maquinariaPlanJson as Prisma.InputJsonValue)
                  : undefined,
            },
          });

          creadas++;
          bloqueIndex++;
        }
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
            ? { set: dto.operariosIds.map((id) => ({ id })) }
            : undefined,
      },
      include: { operarios: { select: { id: true } } },
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
  // JS: 0=domingo..6=sábado
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

// Selecciona días del mes según frecuencia
function pickDaysByFrecuencia(days: Date[], f: Frecuencia): Date[] {
  switch (f) {
    case Frecuencia.DIARIA:
      return days;
    case Frecuencia.SEMANAL:
      // todos los lunes del mes
      return days.filter((d) => d.getDay() === 1);
    case Frecuencia.QUINCENAL:
      return days.filter((d) => {
        const dd = d.getDate();
        return dd === 1 || dd === 16;
      });
    case Frecuencia.MENSUAL:
      return days.filter((d) => d.getDate() === 1);
    case Frecuencia.BIMESTRAL: {
      // Ejecuta el 1 del mes si el mes (1..12) es par; ajusta si prefieres otra lógica
      return days.filter(
        (d) => (d.getMonth() + 1) % 2 === 0 && d.getDate() === 1
      );
    }
    case Frecuencia.TRIMESTRAL:
      return days.filter(
        (d) => d.getDate() === 1 && [0, 3, 6, 9].includes(d.getMonth())
      );
    case Frecuencia.SEMESTRAL:
      return days.filter(
        (d) => d.getDate() === 1 && [0, 6].includes(d.getMonth())
      );
    case Frecuencia.ANUAL:
      return days.filter((d) => d.getDate() === 1 && d.getMonth() === 0);
    default:
      return days;
  }
}

async function horasAsignadasEnSemana(
  prisma: PrismaClient,
  operarioId: number,
  fecha: Date
): Promise<number> {
  const inicio = inicioSemana(fecha);
  const fin = new Date(inicio);
  fin.setDate(inicio.getDate() + 6);

  const tareas = await prisma.tarea.findMany({
    where: {
      operarios: { some: { id: operarioId } },
      fechaInicio: { lte: fin },
      fechaFin: { gte: inicio },
      borrador: true, // contar solo borrador del plan actual
    },
    select: { duracionHoras: true },
  });
  return tareas.reduce((acc, t) => acc + t.duracionHoras, 0);
}

async function existeSolapeParaOperario(
  prisma: PrismaClient,
  operarioId: number,
  inicio: Date,
  fin: Date,
  conjuntoId: string
): Promise<boolean> {
  const overlap = await prisma.tarea.findFirst({
    where: {
      conjuntoId,
      operarios: { some: { id: operarioId } },
      // solape si: inicioA < finB && finA > inicioB
      fechaInicio: { lt: fin },
      fechaFin: { gt: inicio },
      borrador: true,
    },
    select: { id: true },
  });
  return Boolean(overlap);
}

function inicioSemana(fecha: Date): Date {
  const d = new Date(fecha);
  const day = d.getDay(); // 0..6 (domingo..sábado)
  const diff = d.getDate() - day + (day === 0 ? -6 : 1); // lunes
  return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
}
