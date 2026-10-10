// src/services/PlazaTitularSync.ts
import { EstadoTarea, type Prisma } from "@prisma/client";

import {
  AccionAuditoria,
  EntidadAuditoria,
  ModuloAuditoria,
  type ActorAuditoria,
  type RegistroAuditoria,
} from "../model/Auditoria";
import { AuditoriaService } from "./AuditoriaService";

/**
 * Cuando cambia quien ocupa una plaza (necesidad operativa), las actividades
 * que todavía no se han trabajado y que nacieron de esa plaza pasan al nuevo
 * titular. Así el cronograma publicado (y el borrador) nunca muestra a quien
 * ya no está en el cargo. Lo ya trabajado o vencido conserva a su
 * responsable: es historia.
 */

/** Estados en los que la actividad todavía no se ha trabajado. */
export const ESTADOS_TAREA_SIN_TRABAJAR: EstadoTarea[] = [
  EstadoTarea.ASIGNADA,
  EstadoTarea.PENDIENTE_REPROGRAMACION,
];

export type CambioOperariosActividad = { quitar: string[]; agregar: string[] };

/**
 * Qué cambia en los operarios de UNA actividad cuando su plaza pasa de
 * `anteriorId` a `nuevoId` (cualquiera de los dos puede ser null: plaza que
 * se libera o que estaba vacante). Pura, para probarla sin base de datos.
 *
 * `titularesOtrasPlazas` son quienes ocupan hoy las OTRAS plazas vinculadas a
 * la actividad (una actividad compartida puede venir de varias plazas).
 *
 * 1. El titular anterior sale, salvo que siga en la actividad por otra plaza.
 * 2. El nuevo titular entra si reemplaza al anterior, o si nadie cubre el
 *    puesto de esta plaza en la actividad (todos sus operarios están ahí por
 *    otras plazas). Si alguien fue asignado a mano en ese puesto (una
 *    excepción puntual), se respeta y no se agrega a nadie más.
 */
export function calcularCambioOperariosActividad(params: {
  operariosActuales: Iterable<string>;
  titularesOtrasPlazas: Iterable<string>;
  anteriorId: string | null;
  nuevoId: string | null;
}): CambioOperariosActividad {
  const { anteriorId, nuevoId } = params;
  const quitar: string[] = [];
  const agregar: string[] = [];
  if (anteriorId === nuevoId) return { quitar, agregar };

  const operarios = new Set(params.operariosActuales);
  const otras = new Set(params.titularesOtrasPlazas);

  let salioAnterior = false;
  if (anteriorId && operarios.has(anteriorId) && !otras.has(anteriorId)) {
    operarios.delete(anteriorId);
    quitar.push(anteriorId);
    salioAnterior = true;
  }

  if (nuevoId && !operarios.has(nuevoId)) {
    const puestoCubierto = [...operarios].some((id) => !otras.has(id));
    if (salioAnterior || !puestoCubierto) agregar.push(nuevoId);
  }

  return { quitar, agregar };
}

/** Aplica el cambio a una lista ordenada de ids (quita y agrega al final). */
export function aplicarCambioOperarios(
  actuales: string[],
  cambio: CambioOperariosActividad,
): string[] {
  const sinQuitados = actuales.filter((id) => !cambio.quitar.includes(id));
  return [...sinQuitados, ...cambio.agregar.filter((id) => !sinQuitados.includes(id))];
}

export type ResultadoCambioTitular = {
  /** Actividades (publicadas o del borrador) a las que se les cambió el operario. */
  tareasActualizadas: number;
  /** De esas, cuántas quedaron a nombre del nuevo titular. */
  tareasAsignadasAlNuevo: number;
  /** De esas, cuántas quedaron sin ningún operario (la plaza quedó vacante). */
  tareasSinOperario: number;
  /** Excluidas pendientes del borrador cuyo operario sugerido cambió. */
  excluidasActualizadas: number;
};

export const SIN_CAMBIOS_TITULAR: ResultadoCambioTitular = {
  tareasActualizadas: 0,
  tareasAsignadasAlNuevo: 0,
  tareasSinOperario: 0,
  excluidasActualizadas: 0,
};

export function sumarResultadosTitular(
  a: ResultadoCambioTitular,
  b: ResultadoCambioTitular,
): ResultadoCambioTitular {
  return {
    tareasActualizadas: a.tareasActualizadas + b.tareasActualizadas,
    tareasAsignadasAlNuevo: a.tareasAsignadasAlNuevo + b.tareasAsignadasAlNuevo,
    tareasSinOperario: a.tareasSinOperario + b.tareasSinOperario,
    excluidasActualizadas: a.excluidasActualizadas + b.excluidasActualizadas,
  };
}

function inicioDelDia(fecha: Date): Date {
  return new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate(), 0, 0, 0, 0);
}

/**
 * Lleva el cambio de titular de la plaza `plazaId` a las actividades que aún
 * no se han trabajado (desde `desde`, por defecto ahora) y a las excluidas
 * pendientes de sus preventivas. Debe llamarse DENTRO de la misma
 * transacción y DESPUÉS de guardar el nuevo `operarioId` de la plaza: los
 * titulares de las demás plazas se leen del estado ya actualizado.
 */
export async function sincronizarActividadesConTitularDePlaza(
  tx: Prisma.TransactionClient,
  params: {
    conjuntoId: string;
    plazaId: number;
    anteriorId: string | null;
    nuevoId: string | null;
    desde?: Date;
    actor?: ActorAuditoria | null;
  },
): Promise<ResultadoCambioTitular> {
  const { conjuntoId, plazaId, anteriorId, nuevoId } = params;
  if (anteriorId === nuevoId) return { ...SIN_CAMBIOS_TITULAR };
  const desde = params.desde ?? new Date();

  const tareas = await tx.tarea.findMany({
    where: {
      conjuntoId,
      necesidades: { some: { id: plazaId } },
      estado: { in: ESTADOS_TAREA_SIN_TRABAJAR },
      fechaInicio: { gte: desde },
    },
    select: {
      id: true,
      descripcion: true,
      periodoAnio: true,
      periodoMes: true,
      operarios: { select: { id: true } },
      necesidades: { select: { id: true, operarioId: true } },
    },
  });

  const quitarDe: number[] = [];
  const agregarA: number[] = [];
  const auditables: Array<{
    id: number;
    descripcion: string;
    periodoAnio: number | null;
    periodoMes: number | null;
    antes: string[];
    despues: string[];
  }> = [];
  let tareasSinOperario = 0;

  for (const tarea of tareas) {
    const actuales = tarea.operarios.map((o) => o.id);
    const cambio = calcularCambioOperariosActividad({
      operariosActuales: actuales,
      titularesOtrasPlazas: (tarea.necesidades ?? [])
        .filter((n) => n.id !== plazaId && n.operarioId != null)
        .map((n) => n.operarioId as string),
      anteriorId,
      nuevoId,
    });
    if (!cambio.quitar.length && !cambio.agregar.length) continue;
    if (cambio.quitar.length) quitarDe.push(tarea.id);
    if (cambio.agregar.length) agregarA.push(tarea.id);
    const despues = aplicarCambioOperarios(actuales, cambio);
    if (!despues.length) tareasSinOperario++;
    auditables.push({
      id: tarea.id,
      descripcion: tarea.descripcion,
      periodoAnio: tarea.periodoAnio ?? null,
      periodoMes: tarea.periodoMes ?? null,
      antes: actuales,
      despues,
    });
  }

  // Un solo update por operario (desconectar/conectar en lote) en vez de uno
  // por actividad: una plaza puede tener cientos de actividades por delante.
  if (anteriorId && quitarDe.length) {
    await tx.operario.update({
      where: { id: anteriorId },
      data: { tareas: { disconnect: quitarDe.map((id) => ({ id })) } },
    });
  }
  if (nuevoId && agregarA.length) {
    await tx.operario.update({
      where: { id: nuevoId },
      data: { tareas: { connect: agregarA.map((id) => ({ id })) } },
    });
  }

  const excluidasActualizadas = await sincronizarExcluidasPendientes(tx, {
    conjuntoId,
    plazaId,
    anteriorId,
    nuevoId,
    desde: inicioDelDia(desde),
  });

  if (auditables.length) {
    const [plaza, nombres] = await Promise.all([
      tx.conjuntoNecesidadOperario.findUnique({
        where: { id: plazaId },
        select: { etiqueta: true },
      }),
      nombresDeUsuarios(tx, [anteriorId, nuevoId]),
    ]);
    const etiqueta = plaza?.etiqueta ?? `#${plazaId}`;
    const nombreAnterior = anteriorId ? (nombres.get(anteriorId) ?? anteriorId) : null;
    const nombreNuevo = nuevoId ? (nombres.get(nuevoId) ?? nuevoId) : null;
    const descripcionCambio = nombreNuevo
      ? nombreAnterior
        ? `${nombreAnterior} → ${nombreNuevo}`
        : `ahora la ocupa ${nombreNuevo}`
      : `${nombreAnterior ?? "el operario"} dejó la plaza (vacante)`;

    const eventos: RegistroAuditoria[] = auditables.map((t) => ({
      modulo: ModuloAuditoria.TAREA,
      entidad: EntidadAuditoria.TAREA,
      entidadId: t.id,
      accion: AccionAuditoria.REASIGNAR_OPERARIO,
      conjuntoId,
      actor: params.actor ?? null,
      descripcion: `Cambio de titular de la plaza "${etiqueta}" (${descripcionCambio}): la actividad '${t.descripcion}' se actualizó.`,
      periodoAnio: t.periodoAnio,
      periodoMes: t.periodoMes,
      datosAntes: { operariosIds: t.antes },
      datosDespues: { operariosIds: t.despues },
      metadataJson: {
        motivo: "CAMBIO_TITULAR_PLAZA",
        plazaId,
        plazaEtiqueta: etiqueta,
        anteriorId,
        nuevoId,
      },
    }));
    await new AuditoriaService(tx).registrarLote(eventos);
  }

  return {
    tareasActualizadas: auditables.length,
    tareasAsignadasAlNuevo: agregarA.length,
    tareasSinOperario,
    excluidasActualizadas,
  };
}

/**
 * Las excluidas pendientes guardan su propio "operario sugerido" (copia de
 * los titulares al generar el borrador): se actualizan con la misma regla,
 * usando las plazas de su preventiva.
 */
async function sincronizarExcluidasPendientes(
  tx: Prisma.TransactionClient,
  params: {
    conjuntoId: string;
    plazaId: number;
    anteriorId: string | null;
    nuevoId: string | null;
    desde: Date;
  },
): Promise<number> {
  const definiciones = await tx.definicionTareaPreventiva.findMany({
    where: { conjuntoId: params.conjuntoId, necesidades: { some: { id: params.plazaId } } },
    select: { id: true, necesidades: { select: { id: true, operarioId: true } } },
  });
  if (!definiciones.length) return 0;
  const otrasPorDefinicion = new Map<number, string[]>(
    definiciones.map((d) => [
      d.id,
      (d.necesidades ?? [])
        .filter((n) => n.id !== params.plazaId && n.operarioId != null)
        .map((n) => n.operarioId as string),
    ]),
  );

  const excluidas = await tx.preventivaExcluidaBorrador.findMany({
    where: {
      conjuntoId: params.conjuntoId,
      estado: "PENDIENTE",
      defId: { in: definiciones.map((d) => d.id) },
      fechaObjetivo: { gte: params.desde },
    },
    select: { id: true, defId: true, operariosIds: true },
  });

  const cambios: Array<{ id: number; operariosIds: string[] }> = [];
  for (const excluida of excluidas) {
    const cambio = calcularCambioOperariosActividad({
      operariosActuales: excluida.operariosIds,
      titularesOtrasPlazas: otrasPorDefinicion.get(excluida.defId as number) ?? [],
      anteriorId: params.anteriorId,
      nuevoId: params.nuevoId,
    });
    if (!cambio.quitar.length && !cambio.agregar.length) continue;
    cambios.push({
      id: excluida.id,
      operariosIds: aplicarCambioOperarios(excluida.operariosIds, cambio),
    });
  }
  if (!cambios.length) return 0;

  const nombres = await nombresDeUsuarios(
    tx,
    cambios.flatMap((c) => c.operariosIds),
  );
  for (const cambio of cambios) {
    await tx.preventivaExcluidaBorrador.update({
      where: { id: cambio.id },
      data: {
        operariosIds: cambio.operariosIds,
        operariosNombres: cambio.operariosIds.map((id) => nombres.get(id) ?? id),
      },
    });
  }
  return cambios.length;
}

async function nombresDeUsuarios(
  tx: Prisma.TransactionClient,
  ids: Array<string | null>,
): Promise<Map<string, string>> {
  const unicos = Array.from(new Set(ids.filter((id): id is string => !!id)));
  if (!unicos.length) return new Map();
  const usuarios = await tx.usuario.findMany({
    where: { id: { in: unicos } },
    select: { id: true, nombre: true },
  });
  return new Map(usuarios.map((u) => [u.id, u.nombre]));
}
