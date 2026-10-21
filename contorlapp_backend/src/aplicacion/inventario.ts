// src/aplicacion/inventario.ts
//
// Inventario de insumos y maquinaria para el MCP, sobre ConjuntoService e
// InventarioActivoService (el mismo kardex y las mismas validaciones de la
// app). El insumo siempre se valida contra la empresa y el conjunto.
import type { PrismaClient } from "@prisma/client";

import { ConjuntoService } from "../services/ConjuntoServices";
import { InventarioActivoService } from "../services/InventarioActivoService";
import { actorAuditoria, errorAplicacion, noEncontrado, type ContextoAccion } from "./contexto";
import { alcanceDe, asegurarPermiso, conjuntoAccesible } from "./politicas";

const MAX_CONJUNTOS_RECORRIDOS = 60;

function resumenInsumo(i: any) {
  return {
    insumoId: i.insumoId ?? i.insumo?.id ?? i.id,
    nombre: i.nombre ?? i.insumo?.nombre,
    unidad: i.unidad ?? i.insumo?.unidad ?? null,
    categoria: i.categoria ?? i.insumo?.categoria ?? null,
    cantidad: i.cantidad != null ? Number(i.cantidad) : null,
    umbral: i.umbralUsado ?? i.umbralMinimo ?? i.umbralBajo ?? null,
  };
}

export async function inventarioDeConjunto(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; texto?: string },
) {
  await asegurarPermiso(prisma, ctx, "inventario.ver");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const items: any = await new ConjuntoService(prisma, conjunto.nit).listarInventario({
    nombre: params.texto?.trim() || undefined,
  });
  const lista = Array.isArray(items) ? items : items?.data ?? [];
  return {
    conjunto: { conjuntoId: conjunto.nit, nombre: conjunto.nombre },
    insumos: lista.slice(0, 300).map(resumenInsumo),
  };
}

export async function insumosBajos(prisma: PrismaClient, ctx: ContextoAccion, params: { conjuntoId?: string }) {
  await asegurarPermiso(prisma, ctx, "inventario.ver");
  let conjuntos: Array<{ nit: string; nombre: string }>;
  if (params.conjuntoId) {
    conjuntos = [await conjuntoAccesible(prisma, ctx, params.conjuntoId)];
  } else {
    const alcance = await alcanceDe(prisma, ctx);
    conjuntos = await prisma.conjunto.findMany({
      where: { empresaId: ctx.empresaId, activo: true, ...(alcance === null ? {} : { nit: { in: alcance } }) },
      select: { nit: true, nombre: true },
      orderBy: { nombre: "asc" },
      take: MAX_CONJUNTOS_RECORRIDOS,
    });
  }
  const resultado: Array<{ conjuntoId: string; conjunto: string; insumos: ReturnType<typeof resumenInsumo>[] }> = [];
  for (const conjunto of conjuntos) {
    const bajos: any[] = (await new ConjuntoService(prisma, conjunto.nit).listarInsumosBajos({ umbral: 5 })) as any;
    if (bajos.length) {
      resultado.push({
        conjuntoId: conjunto.nit,
        conjunto: conjunto.nombre,
        insumos: bajos.map(resumenInsumo),
      });
    }
  }
  return { conjuntosRevisados: conjuntos.length, conjuntosConInsumosBajos: resultado };
}

export async function registrarMovimientoInsumo(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; insumoId: number; tipo: "entrada" | "consumo"; cantidad: number; observacion?: string },
) {
  await asegurarPermiso(prisma, ctx, "inventario.gestionar");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  // Catalogo de la empresa (conjuntoId "") o insumo personalizado de este conjunto.
  const insumo = await prisma.insumo.findFirst({
    where: { id: params.insumoId, empresaId: ctx.empresaId, conjuntoId: { in: ["", conjunto.nit] } },
    select: { id: true, nombre: true, unidad: true },
  });
  if (!insumo) throw noEncontrado("Insumo no encontrado.");
  if (!(params.cantidad > 0)) throw errorAplicacion(400, "La cantidad debe ser mayor que cero.", "VALIDACION");

  const servicio = new ConjuntoService(prisma, conjunto.nit, actorAuditoria(ctx));
  const observacion = params.observacion?.trim() || "Registrado por integración de IA";
  if (params.tipo === "entrada") {
    await servicio.agregarStock({ insumoId: insumo.id, cantidad: params.cantidad, observacion });
  } else {
    await servicio.consumirStock({ insumoId: insumo.id, cantidad: params.cantidad, observacion });
  }
  return {
    conjunto: conjunto.nombre,
    insumo: insumo.nombre,
    unidad: insumo.unidad,
    tipo: params.tipo,
    cantidad: params.cantidad,
  };
}

export async function listarMaquinaria(prisma: PrismaClient, ctx: ContextoAccion, params: { conjuntoId?: string }) {
  await asegurarPermiso(prisma, ctx, "maquinaria.ver");
  if (params.conjuntoId) await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const servicio = new InventarioActivoService(prisma, ctx.empresaId, actorAuditoria(ctx));
  const out: any = await servicio.listarMaquinaria({ page: 1, pageSize: 100 }, params.conjuntoId);
  return {
    total: out.total,
    maquinas: (out.data ?? []).map((m: any) => ({
      maquinaId: m.id,
      codigo: m.codigoInterno ?? null,
      nombre: m.nombre ?? m.tipoCatalogo?.nombre ?? null,
      marca: m.marca ?? null,
      estado: m.estado ?? null,
      aprobacion: m.estadoAprobacion ?? null,
      propietario: m.propietarioTipo ?? null,
      conjuntoPropietario: m.conjuntoPropietario?.nombre ?? null,
      enUsoEn: m.asignaciones?.[0]?.conjunto?.nombre ?? m.asignacionActual?.conjunto?.nombre ?? null,
    })),
  };
}
