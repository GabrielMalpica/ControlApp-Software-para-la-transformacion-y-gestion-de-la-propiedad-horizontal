import { z } from "zod";

import * as plan from "../../aplicacion/planEsperanza";
import {
  crearConfirmacion,
  type ContextoConfirmacion,
  type OperacionConfirmable,
} from "../confirmaciones";
import { OPERACIONES_CONFIRMABLES } from "../operaciones";
import { definirHerramienta, type ContextoHerramienta } from "./tipos";

const conjuntoId = z.string().trim().min(1).max(40).describe("NIT del conjunto.");
const checklist = z.array(z.object({
  textoLibre_texto: z.string().trim().min(1).max(300),
  completado: z.boolean(),
}).strict()).max(50);

const cambioDiagnostico = z.object({
  diagnosticoId: z.number().int().positive(),
  valoracion: z.number().min(0).max(5).nullable().optional(),
  textoLibre_observaciones: z.string().max(4000).nullable().optional(),
  checklist: checklist.optional(),
}).strict();

const lote = z.object({
  conjuntoId,
  faseId: z.number().int().positive(),
  diagnosticos: z.array(cambioDiagnostico).min(1).max(200),
}).strict();

function contextoConfirmacion(ctx: ContextoHerramienta): ContextoConfirmacion {
  return {
    accion: ctx.accion,
    conexionId: ctx.conexionId,
    clienteNombre: ctx.clienteNombre,
    scopes: ctx.scopes,
  };
}

function operacionGuardar(): OperacionConfirmable<{ lotes: plan.LotePlanEsperanza[] }> {
  const operacion = OPERACIONES_CONFIRMABLES.get("guardar_plan_esperanza");
  if (!operacion) throw new Error("La operación Plan Esperanza no está registrada.");
  return operacion as OperacionConfirmable<{ lotes: plan.LotePlanEsperanza[] }>;
}

function normalizarLotes(entrada: Array<{
  conjuntoId: string;
  faseId: number;
  diagnosticos: Array<{
    diagnosticoId: number;
    valoracion?: number | null;
    textoLibre_observaciones?: string | null;
    checklist?: Array<{ textoLibre_texto: string; completado: boolean }>;
  }>;
}>): plan.LotePlanEsperanza[] {
  return entrada.map((lote) => ({
    conjuntoId: lote.conjuntoId,
    faseId: lote.faseId,
    diagnosticos: lote.diagnosticos.map((diagnostico) => ({
      diagnosticoId: diagnostico.diagnosticoId,
      valoracion: diagnostico.valoracion,
      observaciones: diagnostico.textoLibre_observaciones,
      checklist: diagnostico.checklist?.map((item) => ({
        texto: item.textoLibre_texto,
        completado: item.completado,
      })),
    })),
  }));
}

async function previsualizar(
  ctx: ContextoHerramienta,
  args: { lotes: plan.LotePlanEsperanza[] },
) {
  const vista = await crearConfirmacion(
    ctx.prisma,
    contextoConfirmacion(ctx),
    operacionGuardar(),
    args,
  );
  return { datos: vista, resultado: "PREVIEW" as const, confirmacionId: vista.confirmacionId };
}

export const herramientasPlanEsperanza = [
  definirHerramienta({
    nombre: "consultar_plan_esperanza",
    titulo: "Consultar cronología del Plan Esperanza",
    descripcion: "Consulta los ciclos contractuales, las seis fases, sus fechas y el avance de las áreas del conjunto. Usa el NIT de listar_conjuntos. No devuelve enlaces de fotos.",
    modulo: "plan_esperanza",
    version: 1,
    scope: "plan_esperanza:read",
    riesgo: "LECTURA",
    entrada: z.object({ conjuntoId }).strict(),
    ejecutar: async (ctx, args) => {
      const cronologia = await plan.consultarPlanEsperanza(ctx.prisma, ctx.accion, args.conjuntoId);
      return {
        datos: {
          conjuntoId: cronologia.conjuntoId,
          conjuntoNombre: cronologia.conjuntoNombre,
          fechaInicioContrato: cronologia.fechaInicioContrato,
          fechaFinContrato: cronologia.fechaFinContrato,
          ciclos: cronologia.ciclos.map((ciclo) => ({
            cicloId: ciclo.id,
            fechaInicio: ciclo.fechaInicio,
            fechaFin: ciclo.fechaFin,
            fases: ciclo.fases.map((fase) => ({
              faseId: fase.id,
              clave: fase.clave,
              mesObjetivo: fase.mesObjetivo,
              fechaProgramada: fase.fechaProgramada,
              estado: fase.estado,
              completado: fase.completado,
              areasEvaluadas: fase.areasEvaluadas,
              totalAreas: fase.totalAreas,
              diagnosticos: fase.diagnosticos.map((d) => ({
                diagnosticoId: d.id,
                elementoNombre: d.elementoNombre,
                ubicacionNombre: d.ubicacionNombre,
                valoracion: d.valoracion,
                textoLibre_observaciones: d.observaciones,
                checklist: d.checklist.map((item) => ({
                  textoLibre_texto: item.texto,
                  completado: item.completado,
                })),
              })),
            })),
          })),
        },
      };
    },
  }),
  definirHerramienta({
    nombre: "previsualizar_guardado_plan_esperanza",
    titulo: "Revisar cambios del Plan Esperanza",
    descripcion: "Valida evaluaciones en una o varias fases y conjuntos y devuelve un resumen sin guardar. Muestra el resumen al gerente y llama confirmar_operacion solo si lo confirma. Más de diez conjuntos requieren aprobación dentro de ControlApp.",
    modulo: "plan_esperanza",
    version: 1,
    scope: "plan_esperanza:write",
    riesgo: "ESCRITURA",
    entrada: z.object({ lotes: z.array(lote).min(1).max(50) }).strict(),
    ejecutar: (ctx, args) => previsualizar(ctx, { lotes: normalizarLotes(args.lotes) }),
  }),
  definirHerramienta({
    nombre: "adjuntar_foto_plan_esperanza",
    titulo: "Adjuntar foto a una evaluación",
    descripcion: "Adjunta una foto JPG, PNG o WebP a un diagnóstico del ciclo indicado. Reemplaza la foto anterior si existe. Pide confirmación al gerente antes de llamar. El cliente debe transferir la imagen en fotoBase64.",
    modulo: "plan_esperanza",
    version: 1,
    scope: "plan_esperanza:write",
    riesgo: "ESCRITURA",
    destructiva: true,
    entrada: z.object({
      conjuntoId,
      diagnosticoId: z.number().int().positive(),
      mimeType: z.enum(["image/jpeg", "image/png", "image/webp"]),
      fotoBase64: z.string().min(1).max(5_600_000).describe("Imagen adjunta codificada en Base64; máximo 4 MB al decodificar."),
    }).strict(),
    ejecutar: async (ctx, args) => ({
      datos: await plan.adjuntarFotoPlanEsperanza(ctx.prisma, ctx.accion, args),
      entidades: [{ tipo: "DiagnosticoArea", id: args.diagnosticoId }],
    }),
  }),
];
