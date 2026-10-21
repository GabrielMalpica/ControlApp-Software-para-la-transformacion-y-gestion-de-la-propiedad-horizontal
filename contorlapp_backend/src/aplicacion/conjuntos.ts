// src/aplicacion/conjuntos.ts
//
// Casos de uso de conjuntos para entradas fuera de la API REST (MCP). Las
// escrituras pasan por GerenteService, igual que la app; aqui solo se
// autoriza, se valida antes de previsualizar y se devuelve lo minimo.
import type { PrismaClient } from "@prisma/client";
import { z } from "zod";

import { CrearConjuntoDTO } from "../model/Conjunto";
import { GerenteService } from "../services/GerenteServices";
import { ConjuntoNecesidadService } from "../services/ConjuntoNecesidadService";

import { actorAuditoria, errorAplicacion, type ContextoAccion } from "./contexto";
import { alcanceDe, asegurarPermiso, conjuntoAccesible } from "./politicas";

export async function listarConjuntos(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  filtro: { texto?: string; soloActivos?: boolean },
) {
  await asegurarPermiso(prisma, ctx, "conjuntos.ver", "conjuntos.gestionar");
  const alcance = await alcanceDe(prisma, ctx);
  const texto = filtro.texto?.trim();
  const conjuntos = await prisma.conjunto.findMany({
    where: {
      empresaId: ctx.empresaId,
      ...(alcance === null ? {} : { nit: { in: alcance } }),
      ...(filtro.soloActivos === false ? {} : { activo: true }),
      ...(texto
        ? {
            OR: [
              { nombre: { contains: texto, mode: "insensitive" } },
              { nit: { contains: texto } },
            ],
          }
        : {}),
    },
    select: {
      nit: true,
      nombre: true,
      direccion: true,
      activo: true,
      tipoServicio: true,
      _count: { select: { operarios: true } },
    },
    orderBy: { nombre: "asc" },
    take: 200,
  });
  return conjuntos.map((c) => ({
    conjuntoId: c.nit,
    nombre: c.nombre,
    direccion: c.direccion,
    activo: c.activo,
    servicios: c.tipoServicio,
    operarios: c._count.operarios,
  }));
}

export async function obtenerConjunto(prisma: PrismaClient, ctx: ContextoAccion, nit: string) {
  await asegurarPermiso(prisma, ctx, "conjuntos.ver", "conjuntos.gestionar");
  await conjuntoAccesible(prisma, ctx, nit);
  const detalle: any = await new GerenteService(prisma, ctx.empresaId).obtenerConjunto(nit);
  const plazas = await new ConjuntoNecesidadService(prisma, nit).listar();
  return {
    conjuntoId: detalle.nit,
    nombre: detalle.nombre,
    direccion: detalle.direccion,
    activo: detalle.activo,
    servicios: detalle.tipoServicio ?? [],
    administrador: detalle.administrador?.usuario?.nombre ?? null,
    horarios: (detalle.horarios ?? []).map((h: any) => ({
      dia: h.dia,
      horaApertura: h.horaApertura,
      horaCierre: h.horaCierre,
      descansoInicio: h.descansoInicio ?? null,
      descansoFin: h.descansoFin ?? null,
    })),
    ubicaciones: (detalle.ubicaciones ?? []).map((u: any) => ({
      ubicacionId: u.id,
      nombre: u.nombre,
      elementos: (u.elementos ?? []).length,
    })),
    operarios: (detalle.operarios ?? []).length,
    plazas: {
      total: plazas.filter((p) => p.activo).length,
      vacantes: plazas.filter((p) => p.activo && !p.operarioId).length,
    },
  };
}

/* ------------------------------ crear conjunto ------------------------------ */

/**
 * Lo que la IA puede indicar al crear un conjunto. Sin administrador, valores
 * del contrato ni enlace de Maps (el servidor lo resolveria por red): eso se
 * completa en la app.
 */
export const NuevoConjuntoMcpDTO = z
  .object({
    nit: z.string().trim().min(3).max(30),
    nombre: z.string().trim().min(2).max(120),
    direccion: z.string().trim().min(3).max(200),
    correo: z.string().trim().email(),
    servicios: z
      .array(z.enum(["JARDINERIA", "PISCINA", "ASEO", "MANTENIMIENTOS_LOCATIVOS", "SALVAMENTO_ACUATICO"]))
      .max(5)
      .default([]),
    horarios: z
      .array(
        z
          .object({
            dia: z.enum(["LUNES", "MARTES", "MIERCOLES", "JUEVES", "VIERNES", "SABADO", "DOMINGO"]),
            horaApertura: z.string(),
            horaCierre: z.string(),
            descansoInicio: z.string().nullable().optional(),
            descansoFin: z.string().nullable().optional(),
          })
          .strict(),
      )
      .max(7)
      .default([]),
    ubicaciones: z
      .array(
        z
          .object({
            nombre: z.string().trim().min(2).max(80),
            elementos: z.array(z.string().trim().min(1).max(80)).max(50).default([]),
          })
          .strict(),
      )
      .max(60)
      .default([]),
  })
  .strict();

export type NuevoConjuntoMcp = z.infer<typeof NuevoConjuntoMcpDTO>;

function aPayloadServicio(dto: NuevoConjuntoMcp) {
  return {
    nit: dto.nit,
    nombre: dto.nombre,
    direccion: dto.direccion,
    correo: dto.correo,
    tipoServicio: dto.servicios,
    horarios: dto.horarios,
    ubicaciones: dto.ubicaciones.map((u) => ({
      nombre: u.nombre,
      elementos: u.elementos.map((nombre) => ({ nombre })),
    })),
  };
}

export async function previsualizarCrearConjunto(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  dto: NuevoConjuntoMcp,
) {
  await asegurarPermiso(prisma, ctx, "conjuntos.gestionar");
  // Las mismas reglas que la app (horarios validos, descanso dentro de la
  // jornada...). Si algo falla, se reporta antes de pedir confirmacion.
  const parsed = CrearConjuntoDTO.safeParse(aPayloadServicio(dto));
  if (!parsed.success) {
    const detalle = parsed.error.issues
      .map((issue) => `${issue.path.join(".") || "datos"}: ${issue.message}`)
      .join("; ");
    throw errorAplicacion(400, `Revisa los datos del conjunto: ${detalle}`, "VALIDACION");
  }
  const existente = await prisma.conjunto.findUnique({ where: { nit: dto.nit }, select: { nit: true } });
  if (existente) throw errorAplicacion(409, "Ya existe un conjunto con ese NIT.", "CONFLICTO");

  return {
    resumen: `Se creará el conjunto "${dto.nombre}" (NIT ${dto.nit}) con ${dto.horarios.length} horario(s) y ${dto.ubicaciones.length} ubicación(es).`,
    impacto: {
      nit: dto.nit,
      nombre: dto.nombre,
      direccion: dto.direccion,
      servicios: dto.servicios,
      horarios: dto.horarios.length,
      ubicaciones: dto.ubicaciones.length,
      elementos: dto.ubicaciones.reduce((n, u) => n + u.elementos.length, 0),
    },
  };
}

export async function crearConjunto(prisma: PrismaClient, ctx: ContextoAccion, dto: NuevoConjuntoMcp) {
  await asegurarPermiso(prisma, ctx, "conjuntos.gestionar");
  const creado: any = await new GerenteService(prisma, ctx.empresaId, actorAuditoria(ctx)).crearConjunto(
    aPayloadServicio(dto),
  );
  return { conjuntoId: creado?.nit ?? dto.nit, nombre: creado?.nombre ?? dto.nombre };
}

