// Opciones del informe detallado: que tareas entran, que se muestra de cada
// una, como se organiza el PDF y cuantas fotos lleva. Sin base de datos ni PDF.
// Sin opciones (o con un objeto vacio) el informe sale igual que antes de que
// existiera este panel.
import crypto from "crypto";
import { EstadoTarea } from "@prisma/client";
import { z } from "zod";

export const ORGANIZACIONES_INFORME = ["ACTIVIDAD", "UBICACION", "CRONOLOGICO"] as const;
export type OrganizacionInforme = (typeof ORGANIZACIONES_INFORME)[number];

export type CalidadFotoInforme = "LIVIANA" | "ESTANDAR" | "ALTA";

/** Tope de fotos por informe: mantiene acotados la memoria y el tamaño del PDF. */
export function limiteFotosInforme(calidad: CalidadFotoInforme): number {
  return calidad === "ALTA" ? 250 : 400;
}

/** Tope de fotos de una sola tarea, aunque se pidan "todas". */
export const MAX_FOTOS_POR_TAREA = 12;

/** Rol con vista de cliente: nunca recibe la informacion interna del informe. */
const ROL_CLIENTE = "administrador";

const textoOpcional = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .optional()
    .transform((v) => (v ? v : undefined));

const FiltrosSchema = z.object({
  tipos: z.array(z.enum(["PREVENTIVA", "CORRECTIVA"])).min(1).max(2).optional(),
  estados: z.array(z.nativeEnum(EstadoTarea)).min(1).max(8).optional(),
  /** Solo aplica a preventivas: las correctivas no tienen frecuencia. */
  frecuencias: z.array(z.string().trim().min(1).max(40)).min(1).max(30).optional(),
  ubicaciones: z.array(z.string().trim().min(1).max(160)).min(1).max(300).optional(),
  soloConEvidencia: z.boolean().default(false),
});

const SeccionesSchema = z.object({
  resumen: z.boolean().default(true),
  cumplimiento: z.boolean().default(false),
  detalle: z.boolean().default(true),
  novedades: z.boolean().default(false),
  reemplazadas: z.boolean().default(true),
  consolidadoRecursos: z.boolean().default(false),
  anexoTareas: z.boolean().default(false),
});

const CamposSchema = z.object({
  ubicacion: z.boolean().default(true),
  responsables: z.boolean().default(true),
  fechas: z.boolean().default(true),
  cifras: z.boolean().default(true),
  estado: z.boolean().default(false),
  puntualidad: z.boolean().default(false),
  insumos: z.boolean().default(true),
  maquinaria: z.boolean().default(true),
  herramientas: z.boolean().default(true),
  observaciones: z.boolean().default(true),
  reemplazos: z.boolean().default(true),
  numerosTarea: z.boolean().default(true),
  // Internos: el administrador del conjunto nunca los recibe.
  motivoRechazo: z.boolean().default(false),
  cerradoPor: z.boolean().default(false),
});

const FotosSchema = z.object({
  incluir: z.boolean().default(true),
  /** null = todas las de la tarea (hasta MAX_FOTOS_POR_TAREA). */
  porTarea: z.number().int().min(1).max(MAX_FOTOS_POR_TAREA).nullable().default(null),
  /** AUTO = diarias 3 registros repartidos con 1 foto; el resto, todos. */
  registrosPorActividad: z
    .union([z.enum(["AUTO", "TODOS"]), z.number().int().min(1).max(31)])
    .default("AUTO"),
  tamano: z.enum(["AUTO", "GRANDE", "MEDIANA", "PEQUENA"]).default("AUTO"),
  calidad: z.enum(["LIVIANA", "ESTANDAR", "ALTA"]).default("ESTANDAR"),
});

const TextosSchema = z.object({
  titulo: textoOpcional(80),
  observacionesGenerales: textoOpcional(1500),
});

export const OpcionesInformeSchema = z
  .object({
    organizacion: z.enum(ORGANIZACIONES_INFORME).default("ACTIVIDAD"),
    filtros: FiltrosSchema.prefault({}),
    secciones: SeccionesSchema.prefault({}),
    campos: CamposSchema.prefault({}),
    fotos: FotosSchema.prefault({}),
    textos: TextosSchema.prefault({}),
  })
  .refine((o) => Object.values(o.secciones).some(Boolean), {
    path: ["secciones"],
    message: "Elige al menos una sección para el informe.",
  });

export type OpcionesInforme = z.output<typeof OpcionesInformeSchema>;

export function opcionesPorDefecto(): OpcionesInforme {
  return OpcionesInformeSchema.parse({});
}

function sinTildesMayus(v: string): string {
  return v.normalize("NFD").replace(/\p{M}/gu, "").trim().toUpperCase();
}

function unicosOrdenados(items: string[] | undefined, normalizar = false): string[] | undefined {
  if (!items) return undefined;
  const vistos = new Map<string, string>();
  for (const item of items) {
    const v = String(item ?? "").trim();
    if (!v) continue;
    const k = sinTildesMayus(v);
    if (!vistos.has(k)) vistos.set(k, normalizar ? k : v);
  }
  const out = Array.from(vistos.values()).sort((a, b) => a.localeCompare(b, "es"));
  return out.length ? out : undefined;
}

/**
 * Deja las opciones en forma canonica (arreglos ordenados, filtros que no
 * filtran nada eliminados) y aplica lo que el rol puede ver. Dos peticiones
 * equivalentes quedan iguales y comparten el mismo trabajo en la cola.
 */
export function normalizarOpciones(
  opciones: OpcionesInforme,
  rol: string | undefined,
): OpcionesInforme {
  const esCliente = (rol ?? "").trim().toLowerCase() === ROL_CLIENTE;
  const f = opciones.filtros;

  const tipos = unicosOrdenados(f.tipos, true) as OpcionesInforme["filtros"]["tipos"];
  const estados = unicosOrdenados(f.estados, true) as OpcionesInforme["filtros"]["estados"];
  const totalEstados = Object.keys(EstadoTarea).length;

  return {
    organizacion: opciones.organizacion,
    filtros: {
      tipos: tipos && tipos.length < 2 ? tipos : undefined,
      estados: estados && estados.length < totalEstados ? estados : undefined,
      frecuencias: unicosOrdenados(f.frecuencias, true),
      ubicaciones: unicosOrdenados(f.ubicaciones),
      soloConEvidencia: f.soloConEvidencia,
    },
    secciones: { ...opciones.secciones },
    campos: {
      ...opciones.campos,
      motivoRechazo: esCliente ? false : opciones.campos.motivoRechazo,
      cerradoPor: esCliente ? false : opciones.campos.cerradoPor,
    },
    fotos: { ...opciones.fotos },
    textos: {
      titulo: opciones.textos.titulo,
      observacionesGenerales: opciones.textos.observacionesGenerales,
    },
  };
}

/** True si el informe no incluye todas las tareas del periodo. */
export function hayFiltros(opciones: OpcionesInforme): boolean {
  const f = opciones.filtros;
  return Boolean(
    f.tipos || f.estados || f.frecuencias || f.ubicaciones || f.soloConEvidencia,
  );
}

function stringifyEstable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stringifyEstable).join(",")}]`;
  if (value && typeof value === "object") {
    const entradas = Object.entries(value as Record<string, unknown>)
      .filter(([, v]) => v !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entradas.map(([k, v]) => `${JSON.stringify(k)}:${stringifyEstable(v)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

/** Huella corta de las opciones (ya normalizadas) para la clave del trabajo. */
export function hashOpciones(opciones: OpcionesInforme): string {
  return crypto
    .createHash("sha1")
    .update(stringifyEstable(opciones))
    .digest("hex")
    .slice(0, 16);
}
