// src/services/PlanillaPersonalService.ts
//
// Planilla de personal: todos los datos de cada usuario de la empresa en una
// fila, para la vista de tabla de "Gestión de usuarios" (copiar y pegar en
// Excel). Solo lectura. Nunca devuelve `contrasena` ni datos de sesión, y no
// se expone por MCP (datos personales: ver DECISIONES_POR_MODULO.usuarios).
// Regla de los días para vacaciones: docs/planilla-personal.md.
import { Prisma, Rol } from "@prisma/client";

import {
  exigirConjuntoEnAlcance,
  type AlcanceConjuntos,
} from "../aplicacion/alcanceConjuntos";
import type { DbClient } from "../db/types";

type HttpError = Error & { status: number };

function httpError(status: number, message: string): HttpError {
  const err = new Error(message) as HttpError;
  err.status = status;
  return err;
}

/**
 * Usuarios que ve la empresa en "Gestión de usuarios" (los mismos de
 * `GerenteService.listarUsuarios`): sus perfiles internos, los operarios, los
 * administradores de sus conjuntos y los administradores aún sin conjunto.
 */
export function whereUsuariosDeEmpresa(empresaId: string): Prisma.UsuarioWhereInput {
  return {
    OR: [
      { gerente: { empresaId } },
      { jefeOperaciones: { empresaId } },
      { supervisor: { empresaId } },
      { operario: { empresaId } },
      { administrador: { conjuntos: { some: { empresaId } } } },
      { administrador: { conjuntos: { none: {} } } },
      { residente: { conjunto: { empresaId } } },
    ],
  };
}

/**
 * Historia de vacaciones que se envía: lo justo para cubrir el período actual
 * (desde el último aniversario de ingreso, como mucho un año atrás) más un
 * margen, y todo lo programado hacia adelante.
 */
export const DIAS_HISTORIA_VACACIONES = 400;

/**
 * Dos días de vacaciones separados por hasta 2 días sin marcar (un fin de
 * semana o un festivo registrado con otro concepto) siguen siendo el mismo
 * bloque.
 */
export const MAX_SEPARACION_BLOQUE_DIAS = 3;

export type BloqueVacaciones = { desde: string; hasta: string };

export type ConjuntoPlanilla = { nit: string; nombre: string };

export type PlazaPlanilla = {
  etiqueta: string;
  conjuntoNit: string;
  conjuntoNombre: string;
  perfil: string | null;
};

export type FilaPlanilla = {
  cedula: string;
  nombre: string;
  correo: string;
  rol: string;
  activo: boolean;
  telefono: string;
  fechaNacimiento: string | null;
  direccion: string | null;
  estadoCivil: string | null;
  numeroHijos: number | null;
  padresVivos: boolean | null;
  contactoEmergenciaNombre: string | null;
  contactoEmergenciaParentesco: string | null;
  contactoEmergenciaTelefono: string | null;
  tipoSangre: string | null;
  eps: string | null;
  fondoPensiones: string | null;
  arl: string | null;
  cajaCompensacion: string | null;
  tallaCamisa: string | null;
  tallaPantalon: string | null;
  tallaCalzado: string | null;
  tipoContrato: string | null;
  jornadaLaboral: string | null;
  patronJornada: string | null;
  funciones: string[];
  conjuntos: ConjuntoPlanilla[];
  plazas: PlazaPlanilla[];
  fechaIngreso: string | null;
  fechaSalida: string | null;
  fechaUltimasVacaciones: string | null;
  cursoAlturas: boolean | null;
  cursoSalvamentoAcuatico: boolean | null;
  examenIngreso: boolean | null;
  observaciones: string | null;
  diaDescanso: string | null;
  trabajaDomingo: boolean | null;
  vacaciones: BloqueVacaciones[];
};

/**
 * Día puro (columnas de fecha sin hora): componentes UTC. Sirve igual para
 * fechas guardadas a medianoche UTC (`"2024-05-01"`) que a medianoche de
 * Bogotá (`...T05:00:00Z`, como las envía la app).
 */
export function diaYmd(fecha: Date | null | undefined): string | null {
  if (!fecha) return null;
  return fecha.toISOString().slice(0, 10);
}

/** Hoy en Colombia, sin depender del huso del proceso. */
export function hoyYmdBogota(ahora: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ahora);
}

function ymdComoUtc(ymd: string): Date {
  const [y, m, d] = ymd.split("-").map(Number);
  return new Date(Date.UTC(y, (m ?? 1) - 1, d ?? 1));
}

function diasEntre(desde: string, hasta: string): number {
  return Math.round((ymdComoUtc(hasta).getTime() - ymdComoUtc(desde).getTime()) / 86_400_000);
}

/**
 * Convierte los días marcados como vacaciones (un registro de asistencia por
 * día) en rangos `desde..hasta`. Ignora duplicados y el orden de entrada.
 */
export function agruparDiasVacaciones(fechas: string[]): BloqueVacaciones[] {
  const dias = [...new Set(fechas)].sort();
  const bloques: BloqueVacaciones[] = [];
  for (const dia of dias) {
    const ultimo = bloques[bloques.length - 1];
    if (ultimo && diasEntre(ultimo.hasta, dia) <= MAX_SEPARACION_BLOQUE_DIAS) {
      ultimo.hasta = dia;
    } else {
      bloques.push({ desde: dia, hasta: dia });
    }
  }
  return bloques;
}

type PeriodoDisponibilidad = {
  fechaInicio: Date;
  fechaFin: Date | null;
  trabajaDomingo: boolean;
  diaDescanso: string | null;
};

/** Período de disponibilidad que rige hoy (el más reciente si se cruzan). */
export function periodoVigente<T extends PeriodoDisponibilidad>(
  periodos: T[],
  hoy: string,
): T | null {
  const vigentes = periodos
    .filter((p) => {
      const inicio = diaYmd(p.fechaInicio)!;
      const fin = diaYmd(p.fechaFin);
      return inicio <= hoy && (fin === null || fin >= hoy);
    })
    .sort((a, b) => b.fechaInicio.getTime() - a.fechaInicio.getTime());
  return vigentes[0] ?? null;
}

// Select explícito: solo lo que la planilla muestra. Nunca `contrasena`,
// `versionSesion` ni URLs de archivos.
export const planillaSelect = {
  id: true,
  nombre: true,
  correo: true,
  rol: true,
  activo: true,
  telefono: true,
  fechaNacimiento: true,
  direccion: true,
  estadoCivil: true,
  numeroHijos: true,
  padresVivos: true,
  contactoEmergenciaNombre: true,
  contactoEmergenciaParentesco: true,
  contactoEmergenciaTelefono: true,
  tipoSangre: true,
  eps: true,
  fondoPensiones: true,
  arl: true,
  cajaCompensacion: true,
  tallaCamisa: true,
  tallaPantalon: true,
  tallaCalzado: true,
  tipoContrato: true,
  jornadaLaboral: true,
  patronJornada: true,
  operario: {
    select: {
      funciones: true,
      cursoAlturas: true,
      cursoSalvamentoAcuatico: true,
      examenIngreso: true,
      fechaIngreso: true,
      fechaSalida: true,
      fechaUltimasVacaciones: true,
      observaciones: true,
      conjuntos: {
        select: { nit: true, nombre: true, empresaId: true },
        orderBy: { nombre: "asc" },
      },
      necesidadesOcupadas: {
        where: { activo: true },
        select: {
          etiqueta: true,
          conjunto: { select: { nit: true, nombre: true, empresaId: true } },
          perfil: { select: { nombre: true } },
        },
        orderBy: { orden: "asc" },
      },
      disponibilidadPeriodos: {
        select: {
          fechaInicio: true,
          fechaFin: true,
          trabajaDomingo: true,
          diaDescanso: true,
        },
      },
    },
  },
  administrador: {
    select: {
      conjuntos: {
        select: { nit: true, nombre: true, empresaId: true },
        orderBy: { nombre: "asc" },
      },
    },
  },
} satisfies Prisma.UsuarioSelect;

export type UsuarioPlanillaRow = Prisma.UsuarioGetPayload<{ select: typeof planillaSelect }>;

/**
 * Arma la fila pública. Los conjuntos (y plazas) se limitan a la empresa y,
 * para un administrador, a sus propios conjuntos: un administrador compartido
 * entre empresas no revela los conjuntos de otra.
 */
export function filaPlanilla(
  row: UsuarioPlanillaRow,
  input: {
    empresaId: string;
    alcance: AlcanceConjuntos;
    hoy: string;
    diasVacaciones: string[];
  },
): FilaPlanilla {
  const visible = (c: { nit: string; empresaId: string | null }) =>
    c.empresaId === input.empresaId && (input.alcance === null || input.alcance.includes(c.nit));

  const conjuntos = new Map<string, ConjuntoPlanilla>();
  for (const c of [...(row.operario?.conjuntos ?? []), ...(row.administrador?.conjuntos ?? [])]) {
    if (visible(c)) conjuntos.set(c.nit, { nit: c.nit, nombre: c.nombre });
  }

  const operario = row.operario;
  const plazas: PlazaPlanilla[] = (operario?.necesidadesOcupadas ?? [])
    .filter((p) => visible(p.conjunto))
    .map((p) => ({
      etiqueta: p.etiqueta,
      conjuntoNit: p.conjunto.nit,
      conjuntoNombre: p.conjunto.nombre,
      perfil: p.perfil?.nombre ?? null,
    }));
  const periodo = operario ? periodoVigente(operario.disponibilidadPeriodos, input.hoy) : null;

  return {
    cedula: row.id,
    nombre: row.nombre,
    correo: row.correo,
    rol: row.rol,
    activo: row.activo,
    telefono: row.telefono.toString(),
    fechaNacimiento: diaYmd(row.fechaNacimiento),
    direccion: row.direccion,
    estadoCivil: row.estadoCivil,
    numeroHijos: row.numeroHijos,
    padresVivos: row.padresVivos,
    contactoEmergenciaNombre: row.contactoEmergenciaNombre,
    contactoEmergenciaParentesco: row.contactoEmergenciaParentesco,
    contactoEmergenciaTelefono: row.contactoEmergenciaTelefono,
    tipoSangre: row.tipoSangre,
    eps: row.eps,
    fondoPensiones: row.fondoPensiones,
    arl: row.arl,
    cajaCompensacion: row.cajaCompensacion,
    tallaCamisa: row.tallaCamisa,
    tallaPantalon: row.tallaPantalon,
    tallaCalzado: row.tallaCalzado,
    tipoContrato: row.tipoContrato,
    jornadaLaboral: row.jornadaLaboral,
    patronJornada: row.patronJornada,
    funciones: operario?.funciones ?? [],
    conjuntos: [...conjuntos.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, "es")),
    plazas,
    fechaIngreso: diaYmd(operario?.fechaIngreso),
    fechaSalida: diaYmd(operario?.fechaSalida),
    fechaUltimasVacaciones: diaYmd(operario?.fechaUltimasVacaciones),
    cursoAlturas: operario?.cursoAlturas ?? null,
    cursoSalvamentoAcuatico: operario?.cursoSalvamentoAcuatico ?? null,
    examenIngreso: operario?.examenIngreso ?? null,
    observaciones: operario?.observaciones ?? null,
    diaDescanso: periodo?.diaDescanso ?? null,
    trabajaDomingo: periodo ? periodo.trabajaDomingo : null,
    vacaciones: agruparDiasVacaciones(input.diasVacaciones),
  };
}

/**
 * Concepto de asistencia que cuenta como vacaciones: el código "V" del
 * catálogo por defecto, o uno propio de la empresa cuyo nombre diga
 * "vacaciones".
 */
export function whereConceptoVacaciones(empresaId: string): Prisma.ConceptoAsistenciaWhereInput {
  return {
    empresaId,
    OR: [
      { codigo: { equals: "V", mode: "insensitive" } },
      { nombre: { contains: "vacacion", mode: "insensitive" } },
    ],
  };
}

export class PlanillaPersonalService {
  constructor(private readonly db: DbClient) {}

  /**
   * Filas de la planilla, ordenadas por nombre. Con `conjuntoId`: el
   * administrador de ese conjunto y sus operarios (vinculados o en una de sus
   * plazas). Un conjunto de otra empresa o fuera del alcance responde 404.
   */
  async listar(input: {
    empresaId: string;
    alcance: AlcanceConjuntos;
    conjuntoId?: string | null;
    ahora?: Date;
  }): Promise<FilaPlanilla[]> {
    const { empresaId, alcance } = input;
    const conjuntoId = input.conjuntoId?.trim() || null;
    const hoy = hoyYmdBogota(input.ahora);

    const filtros: Prisma.UsuarioWhereInput[] = [
      whereUsuariosDeEmpresa(empresaId),
      { rol: { not: Rol.residente } },
    ];

    if (alcance !== null) {
      filtros.push(vinculadoAConjuntos({ in: alcance }));
    }

    if (conjuntoId) {
      exigirConjuntoEnAlcance(alcance, conjuntoId);
      const conjunto = await this.db.conjunto.findFirst({
        where: { nit: conjuntoId, empresaId },
        select: { nit: true },
      });
      if (!conjunto) throw httpError(404, "Conjunto no encontrado");
      filtros.push(vinculadoAConjuntos(conjuntoId));
    }

    const usuarios = await this.db.usuario.findMany({
      where: { AND: filtros },
      select: planillaSelect,
      orderBy: { nombre: "asc" },
    });

    const operarioIds = usuarios.filter((u) => u.operario).map((u) => u.id);
    const diasPorOperario = new Map<string, string[]>();
    if (operarioIds.length) {
      const desde = ymdComoUtc(hoy);
      desde.setUTCDate(desde.getUTCDate() - DIAS_HISTORIA_VACACIONES);
      const registros = await this.db.registroAsistencia.findMany({
        where: {
          operarioId: { in: operarioIds },
          fecha: { gte: desde },
          concepto: whereConceptoVacaciones(empresaId),
        },
        select: { operarioId: true, fecha: true },
        orderBy: { fecha: "asc" },
      });
      for (const r of registros) {
        const lista = diasPorOperario.get(r.operarioId) ?? [];
        lista.push(diaYmd(r.fecha)!);
        diasPorOperario.set(r.operarioId, lista);
      }
    }

    return usuarios.map((u) =>
      filaPlanilla(u, {
        empresaId,
        alcance,
        hoy,
        diasVacaciones: diasPorOperario.get(u.id) ?? [],
      }),
    );
  }
}

/** Administrador u operario (vinculado o en una plaza) de esos conjuntos. */
function vinculadoAConjuntos(nit: string | { in: string[] }): Prisma.UsuarioWhereInput {
  return {
    OR: [
      { administrador: { conjuntos: { some: { nit } } } },
      { operario: { conjuntos: { some: { nit } } } },
      { operario: { necesidadesOcupadas: { some: { conjuntoId: nit, activo: true } } } },
    ],
  };
}
