// src/utils/recursosPlanTarea.ts
import type { PrismaClient } from "@prisma/client";

import { parseNecesidadesHerramienta } from "./herramientaNecesidades";
import { parseNecesidadesMaquinaria } from "./maquinariaNecesidades";

/** Recurso que pide una tarea, listo para mostrar en el cronograma. */
export type RecursoPlanPublico = {
  clase: "MAQUINARIA" | "HERRAMIENTA";
  tipoNombre: string;
  cantidad: number;
  obligatorio: boolean;
  /** Solo en tareas publicadas (necesidad materializada). */
  asignadas: number | null;
  unidades: string[];
};

type TareaConPlan = {
  id: number;
  borrador?: boolean | null;
  maquinariaPlanJson?: unknown;
  herramientasPlanJson?: unknown;
};

function nombreLegado(tipo: string): string {
  const fijos: Record<string, string> = {
    CORTASETOS_MANO: "Cortasetos manual",
    CORTASETOS_ALTURA: "Cortasetos de altura",
    GUADANIA: "Guadaña",
    PODADORA_CESPED: "Podadora de césped",
    HIDROLAVADORA_ELECTRICA: "Hidrolavadora eléctrica",
    HIDROLAVADORA_GASOLINA: "Hidrolavadora a gasolina",
  };
  return (
    fijos[tipo] ??
    tipo
      .toLowerCase()
      .split("_")
      .map((p) => p.charAt(0).toUpperCase() + p.slice(1))
      .join(" ")
  );
}

/**
 * Agrega `recursosPlan` a cada tarea: qué maquinaria/herramientas pide (con el
 * nombre del tipo, no solo su id) y, si ya está publicada, cuántas unidades
 * tiene asignadas en la agenda de recursos y cuáles. Consultas en bloque
 * (constantes, sin N+1).
 */
export async function adjuntarRecursosPlan<T extends TareaConPlan>(
  prisma: PrismaClient,
  tareas: T[],
): Promise<Array<T & { recursosPlan: RecursoPlanPublico[] }>> {
  if (!tareas.length) return [];

  const tipoIds = new Set<number>();
  const herramientaIds = new Set<number>();
  for (const t of tareas) {
    for (const n of parseNecesidadesMaquinaria(t.maquinariaPlanJson)) {
      if (n.tipoCatalogoId != null) tipoIds.add(n.tipoCatalogoId);
    }
    for (const n of parseNecesidadesHerramienta(t.herramientasPlanJson)) herramientaIds.add(n.herramientaId);
  }

  const publicadas = tareas.filter((t) => t.borrador === false).map((t) => t.id);
  const [tipos, herramientas, necesidades] = await Promise.all([
    tipoIds.size
      ? prisma.tipoMaquinariaCatalogo.findMany({
          where: { id: { in: Array.from(tipoIds) } },
          select: { id: true, nombre: true },
        })
      : Promise.resolve([] as Array<{ id: number; nombre: string }>),
    herramientaIds.size
      ? prisma.herramienta.findMany({
          where: { id: { in: Array.from(herramientaIds) } },
          select: { id: true, nombre: true },
        })
      : Promise.resolve([] as Array<{ id: number; nombre: string }>),
    publicadas.length
      ? prisma.necesidadRecursoTarea.findMany({
          where: { tareaId: { in: publicadas } },
          select: {
            tareaId: true,
            clase: true,
            cantidad: true,
            obligatorio: true,
            tipoMaquinaria: { select: { nombre: true } },
            herramienta: { select: { nombre: true } },
            reservas: {
              where: { estado: { not: "CANCELADA" }, tipo: "TAREA" },
              select: { recursoEtiqueta: true },
            },
          },
          orderBy: { id: "asc" },
        })
      : Promise.resolve([]),
  ]);

  const nombreTipo = new Map(tipos.map((t) => [t.id, t.nombre]));
  const nombreHerramienta = new Map(herramientas.map((h) => [h.id, h.nombre]));
  const necesidadesPorTarea = new Map<number, RecursoPlanPublico[]>();
  for (const n of necesidades) {
    const lista = necesidadesPorTarea.get(n.tareaId) ?? [];
    lista.push({
      clase: n.clase,
      tipoNombre:
        (n.clase === "MAQUINARIA" ? n.tipoMaquinaria?.nombre : n.herramienta?.nombre) ?? "Recurso",
      cantidad: n.cantidad,
      obligatorio: n.obligatorio,
      asignadas: n.reservas.length,
      unidades: n.reservas.map((r) => r.recursoEtiqueta),
    });
    necesidadesPorTarea.set(n.tareaId, lista);
  }

  return tareas.map((t) => {
    // Publicada con necesidades materializadas: esa es la verdad (con cobertura).
    const materializadas = necesidadesPorTarea.get(t.id);
    if (materializadas?.length) return { ...t, recursosPlan: materializadas };

    const plan: RecursoPlanPublico[] = [];
    for (const n of parseNecesidadesMaquinaria(t.maquinariaPlanJson)) {
      plan.push({
        clase: "MAQUINARIA",
        tipoNombre:
          (n.tipoCatalogoId != null ? nombreTipo.get(n.tipoCatalogoId) : undefined) ??
          (n.tipo ? nombreLegado(n.tipo) : "Maquinaria"),
        cantidad: n.cantidad,
        obligatorio: n.obligatorio,
        asignadas: null,
        unidades: [],
      });
    }
    for (const n of parseNecesidadesHerramienta(t.herramientasPlanJson)) {
      plan.push({
        clase: "HERRAMIENTA",
        tipoNombre: nombreHerramienta.get(n.herramientaId) ?? "Herramienta",
        cantidad: n.cantidad,
        obligatorio: n.obligatorio,
        asignadas: null,
        unidades: [],
      });
    }
    return { ...t, recursosPlan: plan };
  });
}
