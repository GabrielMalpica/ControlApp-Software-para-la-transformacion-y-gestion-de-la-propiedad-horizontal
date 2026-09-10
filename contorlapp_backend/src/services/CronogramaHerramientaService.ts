// src/services/CronogramaHerramientaService.ts
import { TipoTarea, type PrismaClient } from "@prisma/client";
import { z } from "zod";

import {
  AccionAuditoria,
  EntidadAuditoria,
  ModuloAuditoria,
  type ActorAuditoria,
} from "../model/Auditoria";
import {
  agruparNecesidadesPorHerramienta,
  parseNecesidadesHerramienta,
} from "../utils/herramientaNecesidades";
import { calcularRangoReserva } from "../utils/reservaMaquinaria";
import { AuditoriaService } from "./AuditoriaService";

const ESTADOS_NO_CRONOGRAMA = ["PENDIENTE_REPROGRAMACION"] as any;
const ESTADOS_USO_ACTIVOS = ["RESERVADA", "EN_USO"] as const;

const ListarNecesidadesDTO = z.object({
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
  herramientaId: z.coerce.number().int().positive().optional(),
  conjuntoId: z.string().min(3).optional(),
  soloPendientes: z.coerce.boolean().optional(),
});

const AsignarHerramientaDTO = z.object({
  tareaIds: z.array(z.number().int().positive()).min(1).max(50),
  herramientaId: z.number().int().positive(),
  // Si se omite, se asigna toda la cantidad pendiente (flujo de un solo clic).
  cantidad: z.coerce.number().positive().optional(),
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
 * Cronograma general de herramientas de la empresa.
 *
 * Las preventivas ya declaran QUE HERRAMIENTA del catalogo necesitan y cuanta
 * cantidad; aqui se ve, mes a mes y con todos los conjuntos a la vez, cuanto hace
 * falta cada dia y se cubre la necesidad: primero contra el stock propio del
 * conjunto y, si no alcanza, contra el stock de la empresa (prestamo automatico,
 * igual que ya funciona el cronograma de maquinaria). La asignacion es una fila de
 * `UsoHerramienta`, que es lo que alimenta la agenda de herramientas.
 */
export class CronogramaHerramientaService {
  private auditoria: AuditoriaService;

  constructor(
    private prisma: PrismaClient,
    private empresaId: string,
    private actor?: ActorAuditoria,
  ) {
    this.auditoria = new AuditoriaService(prisma);
  }

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
      return { anio: dto.anio, mes: dto.mes, necesidades: [] as unknown[] };
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
        herramientasPlanJson: true,
        conjuntoId: true,
        conjunto: { select: { nombre: true } },
        operarios: { select: { usuario: { select: { nombre: true } } } },
        usoHerramientas: {
          select: {
            id: true,
            herramientaId: true,
            cantidad: true,
            origenStock: true,
            estado: true,
            fechaInicio: true,
            fechaFin: true,
          },
        },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    type Grupo = {
      clave: string;
      herramientaId: number;
      fecha: Date;
      conjuntoId: string;
      conjuntoNombre: string;
      cantidadRequerida: number;
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
        cantidad: number;
        origenStock: string;
        entrega: Date;
        recogida: Date;
      }>;
    };

    const grupos = new Map<string, Grupo>();

    for (const tarea of tareas) {
      const necesidades = parseNecesidadesHerramienta(tarea.herramientasPlanJson);
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
        if (dto.herramientaId && necesidad.herramientaId !== dto.herramientaId) {
          continue;
        }

        const clave = `${necesidad.herramientaId}|${tarea.conjuntoId}|${claveDia(fecha)}`;
        const grupo = grupos.get(clave) ?? {
          clave,
          herramientaId: necesidad.herramientaId,
          fecha,
          conjuntoId: tarea.conjuntoId!,
          conjuntoNombre: tarea.conjunto?.nombre ?? tarea.conjuntoId!,
          cantidadRequerida: 0,
          tareas: [],
          asignaciones: [],
        };

        grupo.cantidadRequerida += necesidad.cantidad;

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

        for (const uso of tarea.usoHerramientas) {
          if (uso.herramientaId !== necesidad.herramientaId) continue;
          if (!ESTADOS_USO_ACTIVOS.includes(uso.estado as any)) continue;
          if (grupo.asignaciones.some((item) => item.usoId === uso.id)) continue;
          grupo.asignaciones.push({
            usoId: uso.id,
            cantidad: Number(uso.cantidad),
            origenStock: uso.origenStock,
            entrega: uso.fechaInicio,
            recogida: uso.fechaFin ?? uso.fechaInicio,
          });
        }

        grupos.set(clave, grupo);
      }
    }

    const herramientaIds = Array.from(
      new Set(Array.from(grupos.values()).map((g) => g.herramientaId)),
    );
    const conjuntoIds = Array.from(
      new Set(Array.from(grupos.values()).map((g) => g.conjuntoId)),
    );

    const [herramientas, stocksConjunto, stocksEmpresa] = await Promise.all([
      this.prisma.herramienta.findMany({
        where: { id: { in: herramientaIds }, empresaId: this.empresaId },
        select: { id: true, nombre: true, unidad: true, categoria: true, modoControl: true },
      }),
      this.prisma.conjuntoHerramientaStock.findMany({
        where: {
          conjuntoId: { in: conjuntoIds },
          herramientaId: { in: herramientaIds },
          estado: "OPERATIVA",
        },
        select: { conjuntoId: true, herramientaId: true, cantidad: true },
      }),
      this.prisma.empresaHerramientaStock.findMany({
        where: {
          empresaId: this.empresaId,
          herramientaId: { in: herramientaIds },
          estado: "OPERATIVA",
        },
        select: { herramientaId: true, cantidad: true },
      }),
    ]);

    const herramientaPorId = new Map(herramientas.map((h) => [h.id, h]));
    const capacidadConjunto = new Map<string, number>();
    for (const s of stocksConjunto) {
      capacidadConjunto.set(`${s.conjuntoId}|${s.herramientaId}`, Number(s.cantidad));
    }
    const capacidadEmpresa = new Map<number, number>();
    for (const s of stocksEmpresa) {
      capacidadEmpresa.set(
        s.herramientaId,
        (capacidadEmpresa.get(s.herramientaId) ?? 0) + Number(s.cantidad),
      );
    }

    let necesidades = Array.from(grupos.values()).map((grupo) => {
      const asignadas = grupo.asignaciones.reduce((s, a) => s + a.cantidad, 0);
      const herramienta = herramientaPorId.get(grupo.herramientaId);
      return {
        ...grupo,
        herramientaNombre: herramienta?.nombre ?? `Herramienta #${grupo.herramientaId}`,
        herramientaUnidad: herramienta?.unidad ?? "UNIDAD",
        herramientaCategoria: herramienta?.categoria ?? null,
        modoControl: herramienta?.modoControl ?? null,
        asignadas,
        pendientes: Math.max(0, grupo.cantidadRequerida - asignadas),
        capacidadConjunto:
          capacidadConjunto.get(`${grupo.conjuntoId}|${grupo.herramientaId}`) ?? 0,
        capacidadEmpresa: capacidadEmpresa.get(grupo.herramientaId) ?? 0,
      };
    });

    if (dto.soloPendientes) {
      necesidades = necesidades.filter((item) => item.pendientes > 0);
    }

    necesidades.sort((a, b) => {
      const porHerramienta = a.herramientaNombre.localeCompare(b.herramientaNombre);
      if (porHerramienta !== 0) return porHerramienta;
      const porConjunto = a.conjuntoNombre.localeCompare(b.conjuntoNombre);
      if (porConjunto !== 0) return porConjunto;
      return a.fecha.getTime() - b.fecha.getTime();
    });

    return { anio: dto.anio, mes: dto.mes, necesidades };
  }

  /** Cantidad de `herramientaId` libre para reservar en `rango`, para el origen dado. */
  private async disponibilidad(params: {
    herramientaId: number;
    origen: "CONJUNTO" | "EMPRESA";
    conjuntoId: string | null;
    rango: ReturnType<typeof calcularRangoReserva>;
    excluirTareaIds: number[];
  }): Promise<number> {
    const { herramientaId, origen, conjuntoId, rango, excluirTareaIds } = params;

    const capacidadAgg =
      origen === "CONJUNTO"
        ? await this.prisma.conjuntoHerramientaStock.aggregate({
            where: { conjuntoId: conjuntoId!, herramientaId, estado: "OPERATIVA" },
            _sum: { cantidad: true },
          })
        : await this.prisma.empresaHerramientaStock.aggregate({
            where: { empresaId: this.empresaId, herramientaId, estado: "OPERATIVA" },
            _sum: { cantidad: true },
          });

    const capacidad = Number(capacidadAgg._sum.cantidad ?? 0);
    if (capacidad <= 0) return 0;

    const reservas = await this.prisma.usoHerramienta.findMany({
      where: {
        herramientaId,
        origenStock: origen,
        estado: { in: ESTADOS_USO_ACTIVOS as any },
        tareaId: { notIn: excluirTareaIds },
        fechaInicio: { lte: rango.finReserva },
        OR: [{ fechaFin: { gte: rango.iniReserva } }, { fechaFin: null }],
        ...(origen === "CONJUNTO" ? { tarea: { conjuntoId: conjuntoId! } } : {}),
      },
      select: { cantidad: true },
    });

    const reservado = reservas.reduce((total, r) => total + Number(r.cantidad), 0);
    return capacidad - reservado;
  }

  async asignarHerramienta(payload: unknown) {
    const dto = AsignarHerramientaDTO.parse(payload);
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
        herramientasPlanJson: true,
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

    const herramienta = await this.prisma.herramienta.findFirst({
      where: {
        id: dto.herramientaId,
        empresaId: this.empresaId,
        activo: true,
        estadoAprobacion: "APROBADA",
      },
      select: { id: true, nombre: true, unidad: true },
    });
    if (!herramienta) {
      throw new Error("La herramienta seleccionada no existe para esta empresa.");
    }

    const tareaIds = tareas.map((tarea) => tarea.id);

    const cantidadRequerida = tareas.reduce(
      (total, tarea) =>
        total +
        (agruparNecesidadesPorHerramienta(
          parseNecesidadesHerramienta(tarea.herramientasPlanJson),
        ).get(herramienta.id) ?? 0),
      0,
    );
    if (cantidadRequerida <= 0) {
      throw new Error(`Estas tareas no requieren ${herramienta.nombre}.`);
    }

    const yaAsignada = await this.prisma.usoHerramienta.aggregate({
      where: {
        tareaId: { in: tareaIds },
        herramientaId: herramienta.id,
        estado: { in: ESTADOS_USO_ACTIVOS as any },
      },
      _sum: { cantidad: true },
    });
    const asignadaActual = Number(yaAsignada._sum.cantidad ?? 0);
    const pendiente = Math.max(0, cantidadRequerida - asignadaActual);
    if (pendiente <= 0) {
      throw new Error(`La necesidad de ${herramienta.nombre} ya está completamente cubierta.`);
    }

    const cantidadSolicitada = dto.cantidad ?? pendiente;
    if (cantidadSolicitada > pendiente + 1e-9) {
      throw new Error(
        `Solo faltan ${pendiente} ${herramienta.unidad} de ${herramienta.nombre}; no se pueden asignar ${cantidadSolicitada}.`,
      );
    }

    const inicioUso = new Date(
      Math.min(...tareas.map((tarea) => tarea.fechaInicio.getTime())),
    );
    const finUso = new Date(
      Math.max(...tareas.map((tarea) => tarea.fechaFin.getTime())),
    );
    const rango = calcularRangoReserva({ fechaInicioUso: inicioUso, fechaFinUso: finUso });

    const disponibleConjunto = await this.disponibilidad({
      herramientaId: herramienta.id,
      origen: "CONJUNTO",
      conjuntoId,
      rango,
      excluirTareaIds: tareaIds,
    });
    const tomarConjunto = Math.min(cantidadSolicitada, Math.max(0, disponibleConjunto));
    const restante = cantidadSolicitada - tomarConjunto;

    let tomarEmpresa = 0;
    if (restante > 1e-9) {
      const disponibleEmpresa = await this.disponibilidad({
        herramientaId: herramienta.id,
        origen: "EMPRESA",
        conjuntoId: null,
        rango,
        excluirTareaIds: tareaIds,
      });
      if (restante > disponibleEmpresa + 1e-9) {
        throw new Error(
          `No hay suficiente ${herramienta.nombre} disponible para esas fechas: el conjunto tiene ` +
            `${Math.max(0, disponibleConjunto)} y la empresa puede prestar ${Math.max(0, disponibleEmpresa)} más.`,
        );
      }
      tomarEmpresa = restante;
    }

    const tareaRepresentante = tareas[0];

    const usoIds = await this.prisma.$transaction(async (tx) => {
      const creados: number[] = [];

      if (tomarConjunto > 0) {
        const uso = await tx.usoHerramienta.create({
          data: {
            tarea: { connect: { id: tareaRepresentante.id } },
            herramienta: { connect: { id: herramienta.id } },
            cantidad: tomarConjunto,
            origenStock: "CONJUNTO",
            estado: "RESERVADA",
            fechaInicio: rango.iniReserva,
            fechaFin: rango.finReserva,
            observacion: dto.observacion ?? "Asignada desde el cronograma (stock del conjunto).",
          },
          select: { id: true },
        });
        creados.push(uso.id);
      }

      if (tomarEmpresa > 0) {
        const uso = await tx.usoHerramienta.create({
          data: {
            tarea: { connect: { id: tareaRepresentante.id } },
            herramienta: { connect: { id: herramienta.id } },
            cantidad: tomarEmpresa,
            origenStock: "EMPRESA",
            estado: "RESERVADA",
            fechaInicio: rango.iniReserva,
            fechaFin: rango.finReserva,
            observacion:
              dto.observacion ??
              `Préstamo de la empresa asignado desde el cronograma (${claveDia(rango.entregaDia)}→${claveDia(rango.recogidaDia)}).`,
          },
          select: { id: true },
        });
        creados.push(uso.id);
      }

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.CRONOGRAMA,
        entidad: EntidadAuditoria.TAREA,
        entidadId: tareaRepresentante.id,
        accion: AccionAuditoria.ASIGNAR_HERRAMIENTA,
        conjuntoId,
        actor: this.actor,
        descripcion:
          `Se asignaron ${cantidadSolicitada} ${herramienta.unidad} de ${herramienta.nombre} a ` +
          `'${tareaRepresentante.descripcion}' (${tomarConjunto} del conjunto, ${tomarEmpresa} prestadas por la empresa).`,
        periodoAnio: tareaRepresentante.periodoAnio,
        periodoMes: tareaRepresentante.periodoMes,
        metadataJson: {
          usoIds: creados,
          herramientaId: herramienta.id,
          tareaIds,
          tomarConjunto,
          tomarEmpresa,
          entrega: rango.entregaDia.toISOString(),
          recogida: rango.recogidaDia.toISOString(),
        },
      });

      return creados;
    });

    return {
      ok: true,
      usoIds,
      herramientaId: herramienta.id,
      tomarConjunto,
      tomarEmpresa,
      entrega: rango.entregaDia,
      recogida: rango.recogidaDia,
    };
  }

  async liberarAsignacion(payload: unknown) {
    const dto = LiberarAsignacionDTO.parse(payload);
    const nits = await this.conjuntosDeLaEmpresa();

    const uso = await this.prisma.usoHerramienta.findUnique({
      where: { id: dto.usoId },
      select: {
        id: true,
        herramientaId: true,
        cantidad: true,
        origenStock: true,
        herramienta: { select: { nombre: true } },
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
      await tx.usoHerramienta.delete({ where: { id: uso.id } });

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.CRONOGRAMA,
        entidad: EntidadAuditoria.TAREA,
        entidadId: uso.tarea!.id,
        accion: AccionAuditoria.LIBERAR_HERRAMIENTA,
        conjuntoId,
        actor: this.actor,
        descripcion:
          `Se liberaron ${Number(uso.cantidad)} de ${uso.herramienta.nombre} ` +
          `(${uso.origenStock === "EMPRESA" ? "préstamo de empresa" : "stock del conjunto"}) ` +
          `de '${uso.tarea!.descripcion}'.`,
        periodoAnio: uso.tarea!.periodoAnio,
        periodoMes: uso.tarea!.periodoMes,
        metadataJson: {
          usoId: uso.id,
          herramientaId: uso.herramientaId,
          cantidad: Number(uso.cantidad),
          origenStock: uso.origenStock,
        },
      });
    });

    return { ok: true };
  }
}
