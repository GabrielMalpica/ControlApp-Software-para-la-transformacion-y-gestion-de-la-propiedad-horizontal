// src/aplicacion/tareas.ts
//
// Lectura de tareas para el MCP con el mismo alcance por rol que la API
// (TareaService.obtenerTarea / CronogramaService.tareasEnRango). Las
// observaciones las escribe el personal: se marcan como texto libre.
import { EstadoTarea, type PrismaClient } from "@prisma/client";

import { CronogramaService } from "../services/CronogramaServices";
import { TareaService } from "../services/TareaServices";
import { errorAplicacion, type ContextoAccion } from "./contexto";
import { asegurarPermiso, conjuntoAccesible } from "./politicas";

const MAX_DIAS_RANGO = 62;
const MAX_TAREAS = 300;

function nombreOperario(o: any): string {
  return o?.usuario?.nombre ?? o?.nombre ?? "";
}

function resumenTarea(t: any) {
  return {
    tareaId: t.id,
    descripcion: t.descripcion,
    tipo: t.tipo,
    estado: t.estado,
    prioridad: t.prioridad,
    fechaInicio: t.fechaInicio,
    fechaFin: t.fechaFin,
    ubicacion: t.ubicacion?.nombre ?? null,
    elemento: t.elemento?.nombre ?? null,
    operarios: (t.operarios ?? []).map((o: any) => ({ id: o.id, nombre: nombreOperario(o) })),
  };
}

export async function listarTareas(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; desde: Date; hasta: Date; estado?: EstadoTarea; operarioId?: string },
) {
  await asegurarPermiso(prisma, ctx, "tareas.ver", "cronograma.ver");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  if (params.hasta < params.desde) throw errorAplicacion(400, "La fecha final es anterior a la inicial.", "VALIDACION");
  if ((params.hasta.getTime() - params.desde.getTime()) / 86_400_000 > MAX_DIAS_RANGO) {
    throw errorAplicacion(400, `El rango máximo es de ${MAX_DIAS_RANGO} días.`, "VALIDACION");
  }
  const tareas = await new CronogramaService(prisma, conjunto.nit).tareasEnRango({
    fechaInicio: params.desde,
    fechaFin: params.hasta,
  });
  const filtradas = tareas.filter(
    (t: any) =>
      (!params.estado || t.estado === params.estado) &&
      (!params.operarioId || (t.operarios ?? []).some((o: any) => o.id === params.operarioId)),
  );
  return {
    conjunto: { conjuntoId: conjunto.nit, nombre: conjunto.nombre },
    total: filtradas.length,
    truncado: filtradas.length > MAX_TAREAS,
    tareas: filtradas.slice(0, MAX_TAREAS).map(resumenTarea),
  };
}

export async function obtenerTarea(prisma: PrismaClient, ctx: ContextoAccion, tareaId: number) {
  await asegurarPermiso(prisma, ctx, "tareas.ver", "cronograma.ver");
  const t: any = await TareaService.obtenerTarea(prisma, tareaId, ctx.empresaId, {
    id: ctx.actor.id,
    rol: ctx.actor.rol,
  });
  return {
    ...resumenTarea(t),
    conjunto: t.conjunto ? { conjuntoId: t.conjunto.nit, nombre: t.conjunto.nombre } : null,
    supervisor: t.supervisor?.usuario?.nombre ?? null,
    duracionMinutos: t.duracionMinutos,
    finalizadaPorRol: t.finalizadaPorRol ?? null,
    evidencias: Array.isArray(t.evidencias) ? t.evidencias.length : 0,
    textoLibre_observaciones: t.observaciones ?? null,
    textoLibre_observacionesRechazo: t.observacionesRechazo ?? null,
  };
}

export const ESTADOS_TAREA = Object.values(EstadoTarea);
