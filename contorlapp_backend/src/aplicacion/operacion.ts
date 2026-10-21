// src/aplicacion/operacion.ts
//
// Solicitudes, indicadores, compromisos y cronograma para el MCP, sobre los
// servicios de la app y con el alcance del actor.
import type { PrismaClient } from "@prisma/client";

import { CompromisoConjuntoService } from "../services/CompromisoConjuntoService";
import { DefinicionTareaPreventivaService } from "../services/DefinicionTareaPreventivaService";
import { ReporteService } from "../services/ReporteService";
import { SolicitudInsumoService } from "../services/SolicitudInsumoServices";
import { conjuntoEnAlcance } from "./alcanceConjuntos";
import { actorAuditoria, errorAplicacion, type ContextoAccion } from "./contexto";
import { alcanceDe, asegurarPermiso, conjuntoAccesible } from "./politicas";

/* -------------------------------- solicitudes -------------------------------- */

export async function listarSolicitudesInsumo(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { estado: "pendientes" | "aprobadas" | "todas"; conjuntoId?: string },
) {
  await asegurarPermiso(prisma, ctx, "solicitudes.ver");
  if (params.conjuntoId) await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const alcance = await alcanceDe(prisma, ctx);
  const filas: any[] = await new SolicitudInsumoService(prisma).listar({
    empresaId: ctx.empresaId,
    conjuntoId: params.conjuntoId,
    aprobado: params.estado === "todas" ? undefined : params.estado === "aprobadas",
  });
  const nombres = new Map(
    (
      await prisma.conjunto.findMany({
        where: { empresaId: ctx.empresaId, nit: { in: [...new Set(filas.map((f) => f.conjuntoId))] } },
        select: { nit: true, nombre: true },
      })
    ).map((c) => [c.nit, c.nombre]),
  );
  return filas
    .filter((f) => conjuntoEnAlcance(alcance, f.conjuntoId))
    .slice(0, 100)
    .map((f) => ({
      solicitudId: f.id,
      conjunto: nombres.get(f.conjuntoId) ?? f.conjuntoId,
      fecha: f.fechaSolicitud,
      aprobada: f.aprobado,
      insumos: (f.insumosSolicitados ?? []).map((i: any) => ({
        nombre: i.insumo?.nombre ?? null,
        unidad: i.insumo?.unidad ?? null,
        cantidad: i.cantidad != null ? Number(i.cantidad) : null,
      })),
    }));
}

/* -------------------------------- indicadores -------------------------------- */

export async function indicadoresTareas(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { desde: Date; hasta: Date; conjuntoId?: string },
) {
  await asegurarPermiso(prisma, ctx, "reportes.ver");
  if (params.conjuntoId) await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const servicio = new ReporteService(prisma, ctx.empresaId, await alcanceDe(prisma, ctx));
  const out: any = await servicio.kpis({
    desde: params.desde,
    hasta: params.hasta,
    conjuntoId: params.conjuntoId,
  });
  return { total: out.total, porEstado: out.byEstado, indicadores: out.kpi };
}

/* -------------------------------- compromisos -------------------------------- */

export async function listarCompromisos(prisma: PrismaClient, ctx: ContextoAccion, params: { conjuntoId?: string }) {
  await asegurarPermiso(prisma, ctx, "compromisos.ver");
  const servicio = new CompromisoConjuntoService(prisma);
  let items: any[];
  if (params.conjuntoId) {
    await conjuntoAccesible(prisma, ctx, params.conjuntoId);
    items = (await servicio.listarPorConjunto(params.conjuntoId)) as any[];
  } else {
    const alcance = await alcanceDe(prisma, ctx);
    const global: any = await servicio.listarGlobal(ctx.empresaId);
    const lista: any[] = Array.isArray(global) ? global : global?.items ?? global?.data ?? [];
    items = lista.filter((c) => conjuntoEnAlcance(alcance, c.conjuntoId ?? c.conjunto?.nit));
  }
  return items.slice(0, 200).map((c) => ({
    compromisoId: c.id,
    conjunto: c.conjunto?.nombre ?? c.conjuntoNombre ?? c.conjuntoId ?? null,
    textoLibre_titulo: c.titulo,
    completado: Boolean(c.completado),
    creadoEn: c.creadaEn ?? null,
    ans: c.ansEstado ?? null,
  }));
}

export async function crearCompromiso(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; titulo: string },
) {
  await asegurarPermiso(prisma, ctx, "compromisos.gestionar");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const creado: any = await new CompromisoConjuntoService(prisma).crear({
    conjuntoId: conjunto.nit,
    titulo: params.titulo,
    creadoPorId: ctx.actor.id,
  });
  return { compromisoId: creado?.id ?? null, conjunto: conjunto.nombre };
}

/* --------------------------------- cronograma -------------------------------- */

async function conteosPeriodo(prisma: PrismaClient, conjuntoId: string, anio: number, mes: number) {
  const [borrador, publicadas, excluidas] = await Promise.all([
    prisma.tarea.count({ where: { conjuntoId, periodoAnio: anio, periodoMes: mes, borrador: true } }),
    prisma.tarea.count({ where: { conjuntoId, periodoAnio: anio, periodoMes: mes, borrador: false } }),
    prisma.preventivaExcluidaBorrador.count({
      where: { conjuntoId, periodoAnio: anio, periodoMes: mes, estado: "PENDIENTE" },
    }),
  ]);
  return { tareasEnBorrador: borrador, tareasPublicadas: publicadas, excluidasPendientes: excluidas };
}

export async function estadoCronograma(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; anio: number; mes: number },
) {
  await asegurarPermiso(prisma, ctx, "cronograma.ver");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  return {
    conjunto: { conjuntoId: conjunto.nit, nombre: conjunto.nombre },
    anio: params.anio,
    mes: params.mes,
    ...(await conteosPeriodo(prisma, conjunto.nit, params.anio, params.mes)),
  };
}

export async function previsualizarPublicacion(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; anio: number; mes: number },
) {
  await asegurarPermiso(prisma, ctx, "cronograma.publicar");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const conteos = await conteosPeriodo(prisma, conjunto.nit, params.anio, params.mes);
  if (conteos.tareasEnBorrador === 0) {
    throw errorAplicacion(409, "No hay borrador generado para ese mes; genéralo y revísalo en ControlApp.", "CONFLICTO");
  }
  return {
    resumen: `Se publicará el cronograma de ${String(params.mes).padStart(2, "0")}/${params.anio} de "${conjunto.nombre}": ${conteos.tareasEnBorrador} tarea(s) del borrador pasan al cronograma que ven los operarios.${
      conteos.excluidasPendientes ? ` Quedan ${conteos.excluidasPendientes} preventiva(s) excluida(s) sin agendar.` : ""
    }`,
    impacto: { conjunto: conjunto.nombre, anio: params.anio, mes: params.mes, ...conteos },
  };
}

export async function publicarCronograma(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; anio: number; mes: number },
) {
  await asegurarPermiso(prisma, ctx, "cronograma.publicar");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const out: any = await new DefinicionTareaPreventivaService(prisma, actorAuditoria(ctx)).publicarCronograma({
    conjuntoId: conjunto.nit,
    anio: params.anio,
    mes: params.mes,
  });
  return { publicado: true, detalle: out?.mensaje ?? out?.message ?? null };
}
