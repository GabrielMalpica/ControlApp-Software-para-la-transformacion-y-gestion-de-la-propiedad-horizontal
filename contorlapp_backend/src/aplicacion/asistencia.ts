// src/aplicacion/asistencia.ts
//
// Asistencia para el MCP sobre AsistenciaService (el mismo grid que ve la
// app, con festivos, descansos de la plaza y alcance). Nunca se devuelven
// coordenadas GPS ni cedulas.
import type { PrismaClient } from "@prisma/client";

import { AsistenciaService } from "../services/AsistenciaService";
import { errorAplicacion, type ContextoAccion } from "./contexto";
import { alcanceDe, asegurarPermiso, conjuntoAccesible, operarioDeEmpresa } from "./politicas";

const CODIGO_FALTA = "F";

function partesFecha(fecha: string): { anio: number; mes: number; dia: number } {
  const [anio, mes, dia] = fecha.split("-").map(Number);
  if (!anio || !mes || !dia) throw errorAplicacion(400, "Fecha inválida (AAAA-MM-DD).", "VALIDACION");
  return { anio, mes, dia };
}

export async function listarConceptos(prisma: PrismaClient, ctx: ContextoAccion) {
  await asegurarPermiso(prisma, ctx, "asistencia.ver");
  const conceptos = await new AsistenciaService(prisma).listarConceptos(ctx.empresaId);
  return conceptos
    .filter((c) => c.activo)
    .map((c) => ({ codigo: c.codigo, nombre: c.nombre, cuentaComoTrabajado: c.cuentaComoTrabajado }));
}

async function grid(prisma: PrismaClient, ctx: ContextoAccion, anio: number, mes: number, conjuntoId?: string) {
  if (conjuntoId) await conjuntoAccesible(prisma, ctx, conjuntoId);
  return new AsistenciaService(prisma).getGrid({
    empresaId: ctx.empresaId,
    conjuntoId: conjuntoId ?? null,
    alcance: await alcanceDe(prisma, ctx),
    anio,
    mes,
  });
}

/** "¿Quién faltó hoy?": registros del dia, pendientes (sin registro) y descansos. */
export async function asistenciaDelDia(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { fecha: string; conjuntoId?: string },
) {
  await asegurarPermiso(prisma, ctx, "asistencia.ver");
  const { anio, mes, dia } = partesFecha(params.fecha);
  const datos: any = await grid(prisma, ctx, anio, mes, params.conjuntoId);

  const faltas: unknown[] = [];
  const sinRegistro: unknown[] = [];
  const novedades: unknown[] = [];
  let presentes = 0;
  let descanso = 0;

  for (const fila of datos.operarios ?? []) {
    const celda = (fila.dias ?? []).find((d: any) => d.dia === dia);
    if (!celda) continue;
    const persona = {
      operarioId: fila.operarioId,
      nombre: fila.nombre,
      conjunto: fila.conjuntos?.[0]?.nombre ?? null,
    };
    if (celda.registro) {
      const concepto = celda.registro.conceptoCodigo;
      if (concepto === CODIGO_FALTA) faltas.push(persona);
      else if (concepto === "A") presentes += 1;
      else novedades.push({ ...persona, novedad: celda.registro.conceptoNombre });
      continue;
    }
    if (celda.esDescansoNormal || celda.descansoProgramado) descanso += 1;
    else if (celda.pendiente) sinRegistro.push(persona);
  }

  return {
    fecha: params.fecha,
    conjuntoId: params.conjuntoId ?? null,
    nota: "Faltas = registradas como falta. Sin registro = no marcaron asistencia ni tienen novedad (posible falta o aún sin registrar).",
    totales: {
      presentes,
      faltasRegistradas: faltas.length,
      sinRegistro: sinRegistro.length,
      conNovedad: novedades.length,
      enDescanso: descanso,
    },
    faltas,
    sinRegistro,
    novedades,
  };
}

export async function resumenDelMes(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { anio: number; mes: number; conjuntoId?: string },
) {
  await asegurarPermiso(prisma, ctx, "asistencia.ver");
  const datos: any = await grid(prisma, ctx, params.anio, params.mes, params.conjuntoId);
  return {
    anio: params.anio,
    mes: params.mes,
    operarios: (datos.operarios ?? []).map((fila: any) => {
      const conteo: Record<string, number> = {};
      let pendientes = 0;
      for (const celda of fila.dias ?? []) {
        if (celda.registro) {
          const nombre = celda.registro.conceptoNombre;
          conteo[nombre] = (conteo[nombre] ?? 0) + 1;
        } else if (celda.pendiente) {
          pendientes += 1;
        }
      }
      return {
        operarioId: fila.operarioId,
        nombre: fila.nombre,
        conjunto: fila.conjuntos?.[0]?.nombre ?? null,
        dias: conteo,
        diasSinRegistro: pendientes,
      };
    }),
  };
}

export async function registrarNovedad(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { operarioId: string; fecha: string; conceptoCodigo: string; conjuntoId?: string; observacion?: string },
) {
  await asegurarPermiso(prisma, ctx, "asistencia.registrar_manual");
  partesFecha(params.fecha);
  const operario = await operarioDeEmpresa(prisma, ctx, params.operarioId);
  if (params.conjuntoId) await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const servicio = new AsistenciaService(prisma);
  const conceptos = await servicio.listarConceptos(ctx.empresaId);
  const concepto = conceptos.find(
    (c) => c.activo && c.codigo.toUpperCase() === params.conceptoCodigo.trim().toUpperCase(),
  );
  if (!concepto) {
    throw errorAplicacion(
      400,
      `Concepto desconocido. Usa uno de: ${conceptos
        .filter((c) => c.activo)
        .map((c) => `${c.codigo} (${c.nombre})`)
        .join(", ")}.`,
      "VALIDACION",
    );
  }
  const registro: any = await servicio.upsertRegistro({
    empresaId: ctx.empresaId,
    operarioId: operario.id,
    fecha: params.fecha,
    conceptoId: concepto.id,
    conjuntoId: params.conjuntoId ?? null,
    observacion: params.observacion ?? null,
    actorId: ctx.actor.id,
  });
  return {
    registroId: registro?.id ?? null,
    operario: operario.usuario.nombre,
    fecha: params.fecha,
    concepto: concepto.nombre,
  };
}
