// src/services/CronogramaMaquinariaService.ts
import {
  EstadoMaquinaria,
  TipoMaquinaria,
  TipoTarea,
  type PrismaClient,
} from "@prisma/client";
import { z } from "zod";

import {
  AccionAuditoria,
  EntidadAuditoria,
  ModuloAuditoria,
  type ActorAuditoria,
} from "../model/Auditoria";
import { buildMaquinariaNoDisponibleError } from "../utils/errorFormat";
import { parseNecesidadesMaquinaria } from "../utils/maquinariaNecesidades";
import { calcularRangoReserva } from "../utils/reservaMaquinaria";
import { AuditoriaService } from "./AuditoriaService";

const ESTADOS_NO_CRONOGRAMA = ["PENDIENTE_REPROGRAMACION"] as any;

const ListarNecesidadesDTO = z.object({
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
  tipo: z.nativeEnum(TipoMaquinaria).optional(),
  conjuntoId: z.string().min(3).optional(),
  soloPendientes: z.coerce.boolean().optional(),
});

const AsignarMaquinariaDTO = z.object({
  tareaIds: z.array(z.number().int().positive()).min(1).max(50),
  maquinariaId: z.number().int().positive(),
  observacion: z.string().trim().max(300).optional(),
});

const LiberarAsignacionDTO = z.object({
  usoId: z.coerce.number().int().positive(),
});

function claveDia(d: Date): string {
  const mes = String(d.getMonth() + 1).padStart(2, "0");
  const dia = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${mes}-${dia}`;
}

/**
 * Cronograma general de maquinaria de la empresa.
 *
 * Las preventivas declaran solo QUE TIPO de maquina necesitan; aqui se ve, mes a mes
 * y con todos los conjuntos a la vez, cuantas maquinas de cada tipo hacen falta cada
 * dia y se asignan las maquinas reales. La asignacion es una fila de `UsoMaquinaria`,
 * que es lo que alimenta la agenda de maquinaria.
 */
export class CronogramaMaquinariaService {
  private auditoria: AuditoriaService;

  constructor(
    private prisma: PrismaClient,
    private empresaId: string,
    private actor?: ActorAuditoria,
  ) {
    this.auditoria = new AuditoriaService(prisma);
  }

  /** Nits de los conjuntos de la empresa. Acota todas las consultas. */
  private async conjuntosDeLaEmpresa(conjuntoId?: string): Promise<string[]> {
    const conjuntos = await this.prisma.conjunto.findMany({
      where: {
        empresaId: this.empresaId,
        ...(conjuntoId ? { nit: conjuntoId } : {}),
      },
      select: { nit: true },
    });
    return conjuntos.map((item) => item.nit);
  }

  async listarNecesidades(payload: unknown) {
    const dto = ListarNecesidadesDTO.parse(payload);
    const nits = await this.conjuntosDeLaEmpresa(dto.conjuntoId);

    if (!nits.length) {
      return {
        anio: dto.anio,
        mes: dto.mes,
        necesidades: [],
        maquinariasPorTipo: {} as Record<string, unknown[]>,
      };
    }

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: { in: nits },
        borrador: false,
        tipo: TipoTarea.PREVENTIVA,
        periodoAnio: dto.anio,
        periodoMes: dto.mes,
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
      },
      select: {
        id: true,
        descripcion: true,
        fechaInicio: true,
        fechaFin: true,
        grupoPlanId: true,
        maquinariaPlanJson: true,
        conjuntoId: true,
        conjunto: { select: { nombre: true } },
        operarios: { select: { usuario: { select: { nombre: true } } } },
        usoMaquinarias: {
          select: {
            id: true,
            fechaInicio: true,
            fechaFin: true,
            maquinaria: {
              select: { id: true, nombre: true, marca: true, tipo: true },
            },
          },
        },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    type Grupo = {
      clave: string;
      tipo: TipoMaquinaria;
      fecha: Date;
      conjuntoId: string;
      conjuntoNombre: string;
      cantidadRequerida: number;
      maquinariaSugeridaId: number | null;
      tareas: Array<{
        tareaId: number;
        descripcion: string;
        fechaInicio: Date;
        fechaFin: Date;
        grupoPlanId: string | null;
        operariosNombres: string[];
      }>;
      asignaciones: Array<{
        usoId: number;
        maquinariaId: number;
        maquinariaNombre: string;
        marca: string;
        entrega: Date;
        recogida: Date;
      }>;
    };

    const grupos = new Map<string, Grupo>();

    for (const tarea of tareas) {
      const necesidades = parseNecesidadesMaquinaria(tarea.maquinariaPlanJson);
      if (!necesidades.length) continue;

      const fecha = new Date(
        tarea.fechaInicio.getFullYear(),
        tarea.fechaInicio.getMonth(),
        tarea.fechaInicio.getDate(),
      );
      const operariosNombres = tarea.operarios
        .map((operario) => operario.usuario?.nombre ?? "")
        .filter((nombre) => nombre.trim().length > 0);

      for (const necesidad of necesidades) {
        if (dto.tipo && necesidad.tipo !== dto.tipo) continue;

        const clave = `${necesidad.tipo}|${tarea.conjuntoId}|${claveDia(fecha)}`;
        const grupo = grupos.get(clave) ?? {
          clave,
          tipo: necesidad.tipo,
          fecha,
          conjuntoId: tarea.conjuntoId!,
          conjuntoNombre: tarea.conjunto?.nombre ?? tarea.conjuntoId!,
          cantidadRequerida: 0,
          maquinariaSugeridaId: null,
          tareas: [],
          asignaciones: [],
        };

        grupo.cantidadRequerida += necesidad.cantidad;
        grupo.maquinariaSugeridaId ??= necesidad.maquinariaSugeridaId;

        if (!grupo.tareas.some((item) => item.tareaId === tarea.id)) {
          grupo.tareas.push({
            tareaId: tarea.id,
            descripcion: tarea.descripcion,
            fechaInicio: tarea.fechaInicio,
            fechaFin: tarea.fechaFin,
            grupoPlanId: tarea.grupoPlanId,
            operariosNombres,
          });
        }

        // Solo cuentan como asignadas las maquinas del tipo de esta necesidad.
        for (const uso of tarea.usoMaquinarias) {
          if (uso.maquinaria.tipo !== necesidad.tipo) continue;
          if (grupo.asignaciones.some((item) => item.usoId === uso.id)) continue;
          grupo.asignaciones.push({
            usoId: uso.id,
            maquinariaId: uso.maquinaria.id,
            maquinariaNombre: uso.maquinaria.nombre,
            marca: uso.maquinaria.marca,
            entrega: uso.fechaInicio,
            recogida: uso.fechaFin ?? uso.fechaInicio,
          });
        }

        grupos.set(clave, grupo);
      }
    }

    let necesidades = Array.from(grupos.values()).map((grupo) => ({
      ...grupo,
      pendientes: Math.max(0, grupo.cantidadRequerida - grupo.asignaciones.length),
    }));

    if (dto.soloPendientes) {
      necesidades = necesidades.filter((item) => item.pendientes > 0);
    }

    necesidades.sort((a, b) => {
      const porTipo = a.tipo.localeCompare(b.tipo);
      if (porTipo !== 0) return porTipo;
      const porConjunto = a.conjuntoNombre.localeCompare(b.conjuntoNombre);
      if (porConjunto !== 0) return porConjunto;
      return a.fecha.getTime() - b.fecha.getTime();
    });

    return {
      anio: dto.anio,
      mes: dto.mes,
      necesidades,
      maquinariasPorTipo: await this.catalogoPorTipo(nits),
    };
  }

  /** Maquinas operativas de la empresa y de sus conjuntos, agrupadas por tipo. */
  private async catalogoPorTipo(nits: string[]) {
    const maquinas = await this.prisma.maquinaria.findMany({
      where: {
        estado: EstadoMaquinaria.OPERATIVA,
        OR: [
          { empresaId: this.empresaId },
          { conjuntoPropietarioId: { in: nits } },
        ],
      },
      select: {
        id: true,
        nombre: true,
        marca: true,
        tipo: true,
        propietarioTipo: true,
        conjuntoPropietarioId: true,
      },
      orderBy: [{ tipo: "asc" }, { nombre: "asc" }],
    });

    const salida: Record<string, typeof maquinas> = {};
    for (const maquina of maquinas) {
      (salida[maquina.tipo] ??= []).push(maquina);
    }
    return salida;
  }

  async asignarMaquinaria(payload: unknown) {
    const dto = AsignarMaquinariaDTO.parse(payload);
    const nits = await this.conjuntosDeLaEmpresa();

    const tareas = await this.prisma.tarea.findMany({
      where: {
        id: { in: dto.tareaIds },
        conjuntoId: { in: nits },
        borrador: false,
        tipo: TipoTarea.PREVENTIVA,
      },
      select: {
        id: true,
        descripcion: true,
        conjuntoId: true,
        fechaInicio: true,
        fechaFin: true,
        periodoAnio: true,
        periodoMes: true,
        maquinariaPlanJson: true,
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    if (tareas.length !== dto.tareaIds.length) {
      throw new Error(
        "Alguna de las tareas no existe, no está publicada o no pertenece a esta empresa.",
      );
    }

    const conjuntoId = tareas[0].conjuntoId!;
    if (tareas.some((tarea) => tarea.conjuntoId !== conjuntoId)) {
      throw new Error(
        "Todas las tareas de una misma asignación deben ser del mismo conjunto.",
      );
    }

    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: dto.maquinariaId },
      select: { id: true, nombre: true, marca: true, tipo: true, estado: true },
    });
    if (!maquinaria) {
      throw new Error("La maquinaria seleccionada no existe.");
    }
    if (maquinaria.estado !== EstadoMaquinaria.OPERATIVA) {
      throw new Error(
        `${maquinaria.nombre} no está operativa y no se puede asignar.`,
      );
    }

    const tiposRequeridos = new Set(
      tareas.flatMap((tarea) =>
        parseNecesidadesMaquinaria(tarea.maquinariaPlanJson).map(
          (necesidad) => necesidad.tipo,
        ),
      ),
    );
    if (!tiposRequeridos.has(maquinaria.tipo)) {
      throw new Error(
        `${maquinaria.nombre} es de tipo ${maquinaria.tipo} y estas tareas no requieren ese tipo de máquina.`,
      );
    }

    const inicioUso = new Date(
      Math.min(...tareas.map((tarea) => tarea.fechaInicio.getTime())),
    );
    const finUso = new Date(
      Math.max(...tareas.map((tarea) => tarea.fechaFin.getTime())),
    );
    const rango = calcularRangoReserva({
      fechaInicioUso: inicioUso,
      fechaFinUso: finUso,
    });

    await this.validarSinSolape({
      maquinaria,
      conjuntoId,
      tareas,
      rango,
      inicioUso,
      finUso,
    });

    const tareaRepresentante = tareas[0];

    const uso = await this.prisma.$transaction(async (tx) => {
      const creado = await tx.usoMaquinaria.create({
        data: {
          tarea: { connect: { id: tareaRepresentante.id } },
          maquinaria: { connect: { id: maquinaria.id } },
          fechaInicio: rango.iniReserva,
          fechaFin: rango.finReserva,
          observacion:
            dto.observacion ??
            `Asignada desde el cronograma de maquinaria (${claveDia(rango.entregaDia)}→${claveDia(rango.recogidaDia)})`,
        },
        select: { id: true },
      });

      await tx.maquinariaConjunto.updateMany({
        where: { conjuntoId, maquinariaId: maquinaria.id, estado: "ACTIVA" },
        data: { tareaId: tareaRepresentante.id },
      });

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.CRONOGRAMA,
        entidad: EntidadAuditoria.TAREA,
        entidadId: tareaRepresentante.id,
        accion: AccionAuditoria.ASIGNAR_MAQUINARIA,
        conjuntoId,
        actor: this.actor,
        descripcion: `Se asignó ${maquinaria.nombre} (${maquinaria.tipo}) a '${tareaRepresentante.descripcion}'.`,
        periodoAnio: tareaRepresentante.periodoAnio,
        periodoMes: tareaRepresentante.periodoMes,
        metadataJson: {
          usoId: creado.id,
          maquinariaId: maquinaria.id,
          tareaIds: tareas.map((tarea) => tarea.id),
          entrega: rango.entregaDia.toISOString(),
          recogida: rango.recogidaDia.toISOString(),
        },
      });

      return creado;
    });

    return {
      ok: true,
      usoId: uso.id,
      maquinariaId: maquinaria.id,
      entrega: rango.entregaDia,
      recogida: rango.recogidaDia,
    };
  }

  /** Rechaza la asignación si la máquina ya está comprometida en esa ventana. */
  private async validarSinSolape(params: {
    maquinaria: { id: number; nombre: string; tipo: TipoMaquinaria };
    conjuntoId: string;
    tareas: Array<{ id: number; descripcion: string }>;
    rango: ReturnType<typeof calcularRangoReserva>;
    inicioUso: Date;
    finUso: Date;
  }) {
    const { maquinaria, conjuntoId, tareas, rango, inicioUso, finUso } = params;

    const choque = await this.prisma.usoMaquinaria.findFirst({
      where: {
        maquinariaId: maquinaria.id,
        tareaId: { notIn: tareas.map((tarea) => tarea.id) },
        fechaInicio: { lte: rango.finReserva },
        OR: [{ fechaFin: { gte: rango.iniReserva } }, { fechaFin: null }],
      },
      select: {
        id: true,
        fechaInicio: true,
        fechaFin: true,
        tarea: {
          select: {
            id: true,
            descripcion: true,
            estado: true,
            conjuntoId: true,
            conjunto: { select: { nombre: true } },
          },
        },
      },
      orderBy: { fechaInicio: "asc" },
    });

    if (!choque) return;

    const iso = (d: Date | null) => (d == null ? null : d.toISOString());

    throw buildMaquinariaNoDisponibleError({
      maquinariaId: maquinaria.id,
      maquinaNombre: maquinaria.nombre,
      conflictos: [
        {
          maquinariaId: maquinaria.id,
          maquinaNombre: maquinaria.nombre,
          tareaSolicitada: {
            tareaId: tareas[0].id,
            descripcion: tareas[0].descripcion,
            conjuntoId,
            usoInicio: iso(inicioUso),
            usoFin: iso(finUso),
            reservaInicio: iso(rango.iniReserva),
            reservaFin: iso(rango.finReserva),
            entrega: claveDia(rango.entregaDia),
            recogida: claveDia(rango.recogidaDia),
          },
          ocupadoPor: {
            usoId: choque.id,
            tareaId: choque.tarea?.id ?? null,
            conjuntoId: choque.tarea?.conjuntoId ?? null,
            conjuntoNombre: choque.tarea?.conjunto?.nombre ?? null,
            estado: choque.tarea?.estado ?? null,
            descripcion: choque.tarea?.descripcion ?? null,
            fuente: "RESERVA_PUBLICADA",
            usoInicio: iso(choque.fechaInicio),
            usoFin: iso(choque.fechaFin),
            reservaInicio: iso(choque.fechaInicio),
            reservaFin: iso(choque.fechaFin),
          },
          tipoSolape: "RESERVA_LOGISTICA",
          motivo: `${maquinaria.nombre} ya está reservada en esa ventana de entrega y recogida.`,
        } as any,
      ],
    });
  }

  async liberarAsignacion(payload: unknown) {
    const dto = LiberarAsignacionDTO.parse(payload);
    const nits = await this.conjuntosDeLaEmpresa();

    const uso = await this.prisma.usoMaquinaria.findUnique({
      where: { id: dto.usoId },
      select: {
        id: true,
        maquinariaId: true,
        tarea: {
          select: {
            id: true,
            descripcion: true,
            conjuntoId: true,
            periodoAnio: true,
            periodoMes: true,
          },
        },
      },
    });

    if (!uso || !uso.tarea?.conjuntoId || !nits.includes(uso.tarea.conjuntoId)) {
      throw new Error("La asignación no existe para esta empresa.");
    }

    const conjuntoId = uso.tarea.conjuntoId;

    await this.prisma.$transaction(async (tx) => {
      await tx.usoMaquinaria.delete({ where: { id: uso.id } });

      await tx.maquinariaConjunto.updateMany({
        where: {
          conjuntoId,
          maquinariaId: uso.maquinariaId,
          tareaId: uso.tarea!.id,
        },
        data: { tareaId: null },
      });

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.CRONOGRAMA,
        entidad: EntidadAuditoria.TAREA,
        entidadId: uso.tarea!.id,
        accion: AccionAuditoria.LIBERAR_MAQUINARIA,
        conjuntoId,
        actor: this.actor,
        descripcion: `Se liberó la maquinaria asignada a '${uso.tarea!.descripcion}'.`,
        periodoAnio: uso.tarea!.periodoAnio,
        periodoMes: uso.tarea!.periodoMes,
        metadataJson: { usoId: uso.id, maquinariaId: uso.maquinariaId },
      });
    });

    return { ok: true };
  }
}
