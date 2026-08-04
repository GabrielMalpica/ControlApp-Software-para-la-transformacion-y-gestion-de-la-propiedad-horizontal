// src/services/AuditoriaService.ts
import type { Prisma, PrismaClient } from "@prisma/client";

import {
  AccionAuditoria,
  FiltroAuditoriaDTO,
  InformeAuditoriaDTO,
  OrigenAuditoria,
  TrazabilidadAuditoriaDTO,
  type ActorAuditoria,
  type AuditoriaEventoPublico,
  type RegistroAuditoria,
  type TrazabilidadEntidad,
} from "../model/Auditoria";

/** Cliente Prisma o cliente de transaccion: la auditoria debe poder escribir dentro de un $transaction. */
type ClientePrisma = PrismaClient | Prisma.TransactionClient;

/** Acciones que representan el nacimiento de la entidad, en orden de preferencia. */
const ACCIONES_DE_CREACION: string[] = [
  AccionAuditoria.CREAR,
  AccionAuditoria.GENERAR_BORRADOR,
  AccionAuditoria.AGENDAR_EXCLUIDA,
  AccionAuditoria.PROGRAMAR_CORRECTIVA,
];

function comoJson(value: unknown): Prisma.InputJsonValue | undefined {
  if (value == null) return undefined;
  return value as Prisma.InputJsonValue;
}

function normalizarActor(actor?: ActorAuditoria | null): ActorAuditoria | null {
  if (!actor) return null;
  const id = actor.id ?? null;
  const rol = actor.rol ?? null;
  const nombre = actor.nombre ?? null;
  if (id == null && rol == null && nombre == null) return null;
  return { id, rol, nombre };
}

function aDatosCreate(evento: RegistroAuditoria): Prisma.AuditoriaEventoCreateManyInput {
  const actor = normalizarActor(evento.actor);
  return {
    modulo: evento.modulo,
    entidad: evento.entidad,
    entidadId: String(evento.entidadId),
    accion: evento.accion,
    conjuntoId: evento.conjuntoId ?? null,
    empresaId: evento.empresaId ?? null,
    actorId: actor?.id ?? null,
    actorRol: actor?.rol ?? null,
    actorNombre: actor?.nombre ?? null,
    origen: evento.origen ?? OrigenAuditoria.USUARIO,
    descripcion: evento.descripcion ?? null,
    datosAntes: comoJson(evento.datosAntes),
    datosDespues: comoJson(evento.datosDespues),
    metadataJson: comoJson(evento.metadataJson),
    periodoAnio: evento.periodoAnio ?? null,
    periodoMes: evento.periodoMes ?? null,
  };
}

function aPublico(row: {
  id: bigint;
  modulo: string;
  entidad: string;
  entidadId: string;
  accion: string;
  conjuntoId: string | null;
  actorId: string | null;
  actorRol: string | null;
  actorNombre: string | null;
  origen: string;
  descripcion: string | null;
  metadataJson: Prisma.JsonValue | null;
  periodoAnio: number | null;
  periodoMes: number | null;
  creadoEn: Date;
}): AuditoriaEventoPublico {
  return {
    id: row.id.toString(),
    modulo: row.modulo,
    entidad: row.entidad,
    entidadId: row.entidadId,
    accion: row.accion,
    conjuntoId: row.conjuntoId,
    actorId: row.actorId,
    actorRol: row.actorRol,
    actorNombre: row.actorNombre,
    origen: row.origen,
    descripcion: row.descripcion,
    metadataJson: row.metadataJson ?? null,
    periodoAnio: row.periodoAnio,
    periodoMes: row.periodoMes,
    creadoEn: row.creadoEn,
  };
}

const eventoPublicSelect = {
  id: true,
  modulo: true,
  entidad: true,
  entidadId: true,
  accion: true,
  conjuntoId: true,
  actorId: true,
  actorRol: true,
  actorNombre: true,
  origen: true,
  descripcion: true,
  metadataJson: true,
  periodoAnio: true,
  periodoMes: true,
  creadoEn: true,
} as const;

/**
 * Bitacora transversal de "quien hizo que".
 *
 * Las escrituras son best-effort a proposito: perder un registro de auditoria es
 * preferible a que falle la operacion de negocio que se esta auditando.
 */
export class AuditoriaService {
  constructor(private prisma: ClientePrisma) {}

  async registrar(evento: RegistroAuditoria): Promise<void> {
    try {
      await this.prisma.auditoriaEvento.create({ data: aDatosCreate(evento) });
    } catch (error: any) {
      console.error("[auditoria] no se pudo registrar el evento:", error?.message ?? error);
    }
  }

  async registrarLote(eventos: RegistroAuditoria[]): Promise<void> {
    if (!eventos.length) return;
    try {
      await this.prisma.auditoriaEvento.createMany({ data: eventos.map(aDatosCreate) });
    } catch (error: any) {
      console.error("[auditoria] no se pudo registrar el lote de eventos:", error?.message ?? error);
    }
  }

  async listar(conjuntoId: string, payload: unknown): Promise<AuditoriaEventoPublico[]> {
    const dto = FiltroAuditoriaDTO.parse(payload ?? {});

    const rows = await this.prisma.auditoriaEvento.findMany({
      where: {
        conjuntoId,
        ...(dto.modulo ? { modulo: dto.modulo } : {}),
        ...(dto.entidad ? { entidad: dto.entidad } : {}),
        ...(dto.entidadId ? { entidadId: dto.entidadId } : {}),
        ...(dto.accion ? { accion: dto.accion } : {}),
        ...(dto.actorId ? { actorId: dto.actorId } : {}),
        ...(dto.anio != null ? { periodoAnio: dto.anio } : {}),
        ...(dto.mes != null ? { periodoMes: dto.mes } : {}),
      },
      select: eventoPublicSelect,
      orderBy: [{ creadoEn: "desc" }, { id: "desc" }],
      take: dto.limit ?? 200,
    });

    return rows.map(aPublico);
  }

  /**
   * Resumen "creado por / ultima modificacion" para un conjunto de entidades.
   * Una sola consulta para toda la pantalla: evita el N+1 al pintar el cronograma.
   */
  async trazabilidadPorEntidad(payload: unknown): Promise<Record<string, TrazabilidadEntidad>> {
    const dto = TrazabilidadAuditoriaDTO.parse(payload);
    if (!dto.entidadIds.length) return {};

    const rows = await this.prisma.auditoriaEvento.findMany({
      where: {
        entidad: dto.entidad,
        entidadId: { in: dto.entidadIds },
        ...(dto.modulo ? { modulo: dto.modulo } : {}),
      },
      select: eventoPublicSelect,
      orderBy: [{ creadoEn: "asc" }, { id: "asc" }],
    });

    const salida: Record<string, TrazabilidadEntidad> = {};

    for (const row of rows) {
      const actual =
        salida[row.entidadId] ??
        ({
          entidadId: row.entidadId,
          creadoPor: null,
          creadoEn: null,
          ultimaModificacion: null,
          totalEventos: 0,
        } satisfies TrazabilidadEntidad);

      actual.totalEventos += 1;

      const actor = normalizarActor({
        id: row.actorId,
        rol: row.actorRol,
        nombre: row.actorNombre,
      });

      if (actual.creadoEn == null && ACCIONES_DE_CREACION.includes(row.accion)) {
        actual.creadoPor = actor;
        actual.creadoEn = row.creadoEn;
      } else {
        // Las filas llegan en orden ascendente, asi que la ultima gana.
        actual.ultimaModificacion = {
          actor,
          accion: row.accion,
          descripcion: row.descripcion,
          fecha: row.creadoEn,
        };
      }

      salida[row.entidadId] = actual;
    }

    return salida;
  }

  /** Agrupado por accion y por actor, para la seccion de informe del cronograma. */
  async informePeriodo(conjuntoId: string, payload: unknown) {
    const dto = InformeAuditoriaDTO.parse(payload);

    const rows = await this.prisma.auditoriaEvento.findMany({
      where: {
        conjuntoId,
        periodoAnio: dto.anio,
        periodoMes: dto.mes,
        ...(dto.modulo ? { modulo: dto.modulo } : {}),
      },
      select: eventoPublicSelect,
      orderBy: [{ creadoEn: "asc" }, { id: "asc" }],
    });

    const porAccion = new Map<string, number>();
    const porActor = new Map<
      string,
      { actorId: string | null; actorNombre: string | null; actorRol: string | null; eventos: number }
    >();

    for (const row of rows) {
      porAccion.set(row.accion, (porAccion.get(row.accion) ?? 0) + 1);

      const claveActor = row.actorId ?? `origen:${row.origen}`;
      const acumulado = porActor.get(claveActor) ?? {
        actorId: row.actorId,
        actorNombre: row.actorNombre ?? (row.actorId ? null : row.origen),
        actorRol: row.actorRol,
        eventos: 0,
      };
      acumulado.eventos += 1;
      porActor.set(claveActor, acumulado);
    }

    return {
      anio: dto.anio,
      mes: dto.mes,
      totalEventos: rows.length,
      porAccion: Array.from(porAccion.entries())
        .map(([accion, eventos]) => ({ accion, eventos }))
        .sort((a, b) => b.eventos - a.eventos),
      porActor: Array.from(porActor.values()).sort((a, b) => b.eventos - a.eventos),
      eventos: rows.map(aPublico),
    };
  }
}
