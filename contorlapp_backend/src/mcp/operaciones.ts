// src/mcp/operaciones.ts
//
// Operaciones que se ejecutan con confirmar_operacion. Cada una delega en un
// caso de uso de src/aplicacion (las mismas reglas que la app). Los
// parametros guardados usan ids internos: nunca vuelven a la IA.
import * as conjuntos from "../aplicacion/conjuntos";
import * as operacion from "../aplicacion/operacion";
import * as personal from "../aplicacion/personal";
import type { OperacionConfirmable } from "./confirmaciones";

/** A partir de este tamano, un lote de operarios necesita aprobacion en ControlApp. */
export const LOTE_OPERARIOS_SIN_APROBACION = 10;

const trasladarOperario: OperacionConfirmable<{ operarioId: string; conjuntoDestinoId: string }> = {
  nombre: "trasladar_operario",
  titulo: "Trasladar operario de conjunto",
  scope: "personal:write",
  requiereAprobacionHumana: () => false,
  previsualizar: personal.previsualizarTraslado,
  ejecutar: personal.trasladarOperario,
  entidades: (p) => [
    { tipo: "Operario", id: p.operarioId },
    { tipo: "Conjunto", id: p.conjuntoDestinoId },
  ],
};

const asignarPlaza: OperacionConfirmable<{
  conjuntoId: string;
  plazaId: number;
  operarioId: string;
  reemplazar: boolean;
}> = {
  nombre: "asignar_plaza",
  titulo: "Asignar titular de plaza",
  scope: "personal:write",
  requiereAprobacionHumana: () => false,
  previsualizar: personal.previsualizarAsignacionPlaza,
  ejecutar: personal.asignarPlaza,
  entidades: (p) => [
    { tipo: "ConjuntoNecesidadOperario", id: p.plazaId },
    { tipo: "Operario", id: p.operarioId },
  ],
};

const liberarPlaza: OperacionConfirmable<{ conjuntoId: string; plazaId: number }> = {
  nombre: "liberar_plaza",
  titulo: "Dejar plaza vacante",
  scope: "personal:write",
  requiereAprobacionHumana: () => false,
  previsualizar: personal.previsualizarLiberarPlaza,
  ejecutar: personal.liberarPlaza,
  entidades: (p) => [{ tipo: "ConjuntoNecesidadOperario", id: p.plazaId }],
};

const crearOperarios: OperacionConfirmable<{ filas: personal.NuevoOperarioMcp[] }> = {
  nombre: "crear_operarios",
  titulo: "Crear operarios",
  scope: "personal:write",
  requiereAprobacionHumana: (p) => p.filas.length > LOTE_OPERARIOS_SIN_APROBACION,
  previsualizar: (prisma, ctx, p) => personal.previsualizarCrearOperarios(prisma, ctx, p.filas),
  ejecutar: (prisma, ctx, p) => personal.crearOperarios(prisma, ctx, p.filas),
  entidades: (p) => p.filas.map((f) => ({ tipo: "Usuario", id: f.cedula })),
};

const crearConjunto: OperacionConfirmable<conjuntos.NuevoConjuntoMcp> = {
  nombre: "crear_conjunto",
  titulo: "Crear conjunto",
  scope: "conjuntos:write",
  requiereAprobacionHumana: () => false,
  previsualizar: conjuntos.previsualizarCrearConjunto,
  ejecutar: conjuntos.crearConjunto,
  entidades: (p) => [{ tipo: "Conjunto", id: p.nit }],
};

const publicarCronograma: OperacionConfirmable<{ conjuntoId: string; anio: number; mes: number }> = {
  nombre: "publicar_cronograma",
  titulo: "Publicar cronograma",
  scope: "cronograma:publicar",
  // Lo que ven todos los operarios del conjunto durante un mes: siempre con
  // aprobacion del gerente dentro de ControlApp.
  requiereAprobacionHumana: () => true,
  previsualizar: operacion.previsualizarPublicacion,
  ejecutar: operacion.publicarCronograma,
  entidades: (p) => [{ tipo: "CronogramaPeriodo", id: `${p.conjuntoId}:${p.anio}-${p.mes}` }],
};

export const OPERACIONES_CONFIRMABLES: ReadonlyMap<string, OperacionConfirmable> = new Map(
  [trasladarOperario, asignarPlaza, liberarPlaza, crearOperarios, crearConjunto, publicarCronograma].map(
    (op) => [op.nombre, op as OperacionConfirmable],
  ),
);
