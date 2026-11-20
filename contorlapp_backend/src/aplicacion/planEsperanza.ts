import { createHash, randomUUID } from "crypto";
import fs from "fs/promises";
import os from "os";
import path from "path";
import type { PrismaClient } from "@prisma/client";

import { PlanEsperanzaService } from "../services/PlanEsperanzaService";
import { AuditoriaService } from "../services/AuditoriaService";
import { inicioMesEnBogota } from "../utils/planEsperanzaCronologia";
import { actorAuditoria, errorAplicacion, type ContextoAccion } from "./contexto";
import { asegurarPermiso, conjuntoAccesible } from "./politicas";

export type CambioDiagnosticoPlan = {
  diagnosticoId: number;
  valoracion?: number | null;
  observaciones?: string | null;
  checklist?: Array<{ texto: string; completado: boolean }>;
};

export type LotePlanEsperanza = {
  conjuntoId: string;
  faseId: number;
  diagnosticos: CambioDiagnosticoPlan[];
};

async function validarLote(prisma: PrismaClient, ctx: ContextoAccion, lotes: LotePlanEsperanza[]) {
  await asegurarPermiso(prisma, ctx, "plan_esperanza.acceso");
  if (!lotes.length || lotes.length > 50) {
    throw errorAplicacion(400, "El lote debe incluir entre 1 y 50 fases.", "ENTRADA_INVALIDA");
  }
  const vistos = new Set<number>();
  for (const lote of lotes) {
    await conjuntoAccesible(prisma, ctx, lote.conjuntoId);
    const fase = await prisma.planEsperanza.findFirst({
      where: { id: lote.faseId, conjuntoId: lote.conjuntoId, cicloId: { not: null } },
      select: { id: true, fechaProgramada: true },
    });
    if (!fase) throw errorAplicacion(404, "Fase no encontrada.", "NO_ENCONTRADO");
    const hoy = new Date();
    const hoyMes = inicioMesEnBogota(hoy);
    if (!fase.fechaProgramada || fase.fechaProgramada > hoyMes) {
      throw errorAplicacion(409, "La fase todavía no se ha habilitado.", "FASE_BLOQUEADA");
    }
    for (const cambio of lote.diagnosticos) {
      if (vistos.has(cambio.diagnosticoId)) {
        throw errorAplicacion(400, "No repita un diagnóstico dentro del lote.", "ENTRADA_INVALIDA");
      }
      vistos.add(cambio.diagnosticoId);
      const diagnostico = await prisma.diagnosticoArea.findFirst({
        where: { id: cambio.diagnosticoId, planEsperanzaId: fase.id },
        select: { id: true },
      });
      if (!diagnostico) throw errorAplicacion(404, "Diagnóstico no encontrado.", "NO_ENCONTRADO");
      if (cambio.valoracion != null && (cambio.valoracion < 0 || cambio.valoracion > 5)) {
        throw errorAplicacion(400, "La valoración debe estar entre 0 y 5.", "ENTRADA_INVALIDA");
      }
    }
  }
}

export async function consultarPlanEsperanza(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  conjuntoId: string,
) {
  await asegurarPermiso(prisma, ctx, "plan_esperanza.acceso");
  await conjuntoAccesible(prisma, ctx, conjuntoId);
  return new PlanEsperanzaService(prisma).obtenerCronologia(conjuntoId);
}

export async function previsualizarGuardadoPlanEsperanza(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  lotes: LotePlanEsperanza[],
) {
  await validarLote(prisma, ctx, lotes);
  const conjuntos = new Set(lotes.map((lote) => lote.conjuntoId));
  const totalDiagnosticos = lotes.reduce((total, lote) => total + lote.diagnosticos.length, 0);
  const diagnosticoIds = lotes.flatMap((lote) => lote.diagnosticos.map((item) => item.diagnosticoId));
  const actuales = await prisma.diagnosticoArea.findMany({
    where: { id: { in: diagnosticoIds } },
    select: { id: true, valoracion: true, observaciones: true, checklist: true, urlFoto: true },
    orderBy: { id: "asc" },
  });
  const estadoActualHash = createHash("sha256").update(JSON.stringify(actuales)).digest("hex");
  return {
    resumen: `Guardar ${totalDiagnosticos} evaluación(es) del Plan Esperanza en ${conjuntos.size} conjunto(s).`,
    impacto: { conjuntos: conjuntos.size, fases: lotes.length, diagnosticos: totalDiagnosticos, estadoActualHash },
  };
}

export async function guardarPlanEsperanza(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  lotes: LotePlanEsperanza[],
) {
  await validarLote(prisma, ctx, lotes);
  const eventos: Array<{
    modulo: string;
    entidad: string;
    entidadId: number;
    accion: string;
    conjuntoId: string;
    actor: ReturnType<typeof actorAuditoria>;
    descripcion: string;
  }> = [];
  await prisma.$transaction(async (tx) => {
    const servicio = new PlanEsperanzaService(tx as PrismaClient);
    for (const lote of lotes) {
      for (const cambio of lote.diagnosticos) {
        await servicio.guardarDiagnostico(cambio.diagnosticoId, {
          valoracion: cambio.valoracion,
          observaciones: cambio.observaciones,
          checklist: cambio.checklist,
        });
        eventos.push({
          modulo: "PLAN_ESPERANZA",
          entidad: "DiagnosticoArea",
          entidadId: cambio.diagnosticoId,
          accion: "EDITAR",
          conjuntoId: lote.conjuntoId,
          actor: actorAuditoria(ctx),
          descripcion: "Evaluación actualizada desde MCP.",
        });
      }
    }
  });
  await new AuditoriaService(prisma).registrarLote(eventos);
  return { conjuntos: new Set(lotes.map((lote) => lote.conjuntoId)).size, fases: lotes.length, diagnosticosGuardados: lotes.reduce((n, lote) => n + lote.diagnosticos.length, 0) };
}

export async function adjuntarFotoPlanEsperanza(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  input: { conjuntoId: string; diagnosticoId: number; mimeType: string; fotoBase64: string },
) {
  await asegurarPermiso(prisma, ctx, "plan_esperanza.acceso");
  await conjuntoAccesible(prisma, ctx, input.conjuntoId);
  if (!["image/jpeg", "image/png", "image/webp"].includes(input.mimeType)) {
    throw errorAplicacion(400, "La imagen debe ser JPG, PNG o WebP.", "IMAGEN_INVALIDA");
  }
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(input.fotoBase64)) {
    throw errorAplicacion(400, "La imagen adjunta no tiene una codificación válida.", "IMAGEN_INVALIDA");
  }
  const buffer = Buffer.from(input.fotoBase64, "base64");
  if (!buffer.length || buffer.length > 4 * 1024 * 1024) {
    throw errorAplicacion(400, "La imagen supera el límite de 4 MB o está vacía.", "IMAGEN_INVALIDA");
  }
  const esJpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  const esPng = buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const esWebp = buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WEBP";
  if ((input.mimeType === "image/jpeg" && !esJpeg) || (input.mimeType === "image/png" && !esPng) || (input.mimeType === "image/webp" && !esWebp)) {
    throw errorAplicacion(400, "El formato real de la imagen no coincide con el tipo informado.", "IMAGEN_INVALIDA");
  }
  const diagnostico = await prisma.diagnosticoArea.findFirst({
    where: { id: input.diagnosticoId, planEsperanza: { conjuntoId: input.conjuntoId, cicloId: { not: null } } },
    select: { id: true, planEsperanza: { select: { id: true, fechaProgramada: true } } },
  });
  if (!diagnostico) throw errorAplicacion(404, "Diagnóstico no encontrado.", "NO_ENCONTRADO");
  const hoy = new Date();
  const hoyMes = inicioMesEnBogota(hoy);
  if (!diagnostico.planEsperanza.fechaProgramada || diagnostico.planEsperanza.fechaProgramada > hoyMes) {
    throw errorAplicacion(409, "La fase todavía no se ha habilitado.", "FASE_BLOQUEADA");
  }
  const conjunto = await prisma.conjunto.findUnique({ where: { nit: input.conjuntoId }, select: { nombre: true } });
  if (!conjunto) throw errorAplicacion(404, "Conjunto no encontrado.", "NO_ENCONTRADO");
  const directorio = await fs.mkdtemp(path.join(os.tmpdir(), "plan-esperanza-mcp-"));
  const extension = input.mimeType === "image/png" ? ".png" : input.mimeType === "image/webp" ? ".webp" : ".jpg";
  const filePath = path.join(directorio, `${randomUUID()}${extension}`);
  await fs.writeFile(filePath, buffer);
  try {
    await new PlanEsperanzaService(prisma).guardarDiagnostico(input.diagnosticoId, {
      filePath,
      fileName: `evidencia_${diagnostico.id}${extension}`,
      mimeType: input.mimeType,
      conjuntoNombre: conjunto.nombre,
    });
  } finally {
    await fs.rm(directorio, { recursive: true, force: true }).catch(() => undefined);
  }
  await new AuditoriaService(prisma).registrar({
    modulo: "PLAN_ESPERANZA",
    entidad: "DiagnosticoArea",
    entidadId: input.diagnosticoId,
    accion: "ADJUNTAR_EVIDENCIA",
    conjuntoId: input.conjuntoId,
    actor: actorAuditoria(ctx),
    descripcion: "Evidencia fotográfica adjuntada desde MCP.",
    metadataJson: { mimeType: input.mimeType, bytes: buffer.length },
  });
  return { imagenAdjunta: true, diagnosticoId: diagnostico.id };
}
