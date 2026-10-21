// src/aplicacion/personal.ts
//
// Casos de uso de personal (operarios y supervisores) para el MCP. Las
// escrituras usan GerenteService y ConjuntoNecesidadService: la jerarquia de
// roles, la sincronizacion de actividades al cambiar el titular de una plaza
// y el bloqueo por tareas abiertas al trasladar son los de la app.
// Nunca se devuelven cedulas, datos de salud, tallas ni direccion.
import { randomBytes } from "crypto";
import { EstadoTarea, type PrismaClient } from "@prisma/client";
import { z } from "zod";

import { CrearOperarioDTO } from "../model/Operario";
import { CrearUsuarioDTO } from "../model/Usuario";
import { ConjuntoNecesidadService } from "../services/ConjuntoNecesidadService";
import { GerenteService } from "../services/GerenteServices";
import { actorAuditoria, errorAplicacion, noEncontrado, type ContextoAccion } from "./contexto";
import { asegurarPermiso, conjuntoAccesible, operarioDeEmpresa } from "./politicas";

const FUNCIONES = ["TODERO", "SALVAVIDAS", "ASEO", "PISCINERO", "JARDINERO"] as const;
const LIMITE_LISTADO = 200;
/** Estados de actividad que pasan al nuevo titular (docs/categorias-perfiles-operativos.md). */
const ESTADOS_PENDIENTES = [EstadoTarea.ASIGNADA, EstadoTarea.PENDIENTE_REPROGRAMACION];

function ultimosDigitos(cedula: string): string {
  return `…${cedula.slice(-4)}`;
}

/* --------------------------------- lecturas --------------------------------- */

export async function listarPersonal(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  filtro: { rol: "operario" | "supervisor"; conjuntoId?: string; texto?: string; incluirContacto: boolean },
) {
  await asegurarPermiso(prisma, ctx, "usuarios.gestionar", "tareas.crear", "cronograma.correctivas_programar");
  const texto = filtro.texto?.trim();
  const usuarioSelect = {
    nombre: true,
    activo: true,
    ...(filtro.incluirContacto ? { telefono: true, correo: true } : {}),
  } as const;

  if (filtro.rol === "supervisor") {
    const supervisores = await prisma.supervisor.findMany({
      where: {
        empresaId: ctx.empresaId,
        ...(texto ? { usuario: { nombre: { contains: texto, mode: "insensitive" } } } : {}),
      },
      select: { id: true, usuario: { select: usuarioSelect } },
      orderBy: { usuario: { nombre: "asc" } },
      take: LIMITE_LISTADO,
    });
    return supervisores.map((s: any) => ({
      id: s.id,
      tipo: "supervisor" as const,
      nombre: s.usuario.nombre,
      activo: s.usuario.activo,
      ...(filtro.incluirContacto
        ? { telefono: s.usuario.telefono?.toString() ?? null, correo: s.usuario.correo ?? null }
        : {}),
    }));
  }

  if (filtro.conjuntoId) await conjuntoAccesible(prisma, ctx, filtro.conjuntoId);
  const operarios = await prisma.operario.findMany({
    where: {
      empresaId: ctx.empresaId,
      ...(filtro.conjuntoId ? { conjuntos: { some: { nit: filtro.conjuntoId } } } : {}),
      ...(texto ? { usuario: { nombre: { contains: texto, mode: "insensitive" } } } : {}),
    },
    select: {
      id: true,
      funciones: true,
      usuario: { select: usuarioSelect },
      conjuntos: { select: { nit: true, nombre: true } },
      necesidadesOcupadas: {
        where: { activo: true },
        select: { id: true, etiqueta: true, conjuntoId: true },
      },
    },
    orderBy: { usuario: { nombre: "asc" } },
    take: LIMITE_LISTADO,
  });
  return operarios.map((o: any) => ({
    id: o.id,
    tipo: "operario" as const,
    nombre: o.usuario.nombre,
    activo: o.usuario.activo,
    funciones: o.funciones,
    conjuntos: o.conjuntos.map((c: any) => ({ conjuntoId: c.nit, nombre: c.nombre })),
    plazas: o.necesidadesOcupadas.map((p: any) => ({
      plazaId: p.id,
      etiqueta: p.etiqueta,
      conjuntoId: p.conjuntoId,
    })),
    ...(filtro.incluirContacto
      ? { telefono: o.usuario.telefono?.toString() ?? null, correo: o.usuario.correo ?? null }
      : {}),
  }));
}

export async function listarPlazas(prisma: PrismaClient, ctx: ContextoAccion, conjuntoId: string) {
  await asegurarPermiso(prisma, ctx, "conjuntos.ver", "conjuntos.gestionar");
  const conjunto = await conjuntoAccesible(prisma, ctx, conjuntoId);
  const plazas = await new ConjuntoNecesidadService(prisma, conjunto.nit).listar();
  const titulares = plazas.map((p) => p.operarioId).filter((id): id is string => Boolean(id));
  const nombres = new Map(
    (
      await prisma.usuario.findMany({
        where: { id: { in: titulares } },
        select: { id: true, nombre: true },
      })
    ).map((u) => [u.id, u.nombre]),
  );
  return {
    conjunto: { conjuntoId: conjunto.nit, nombre: conjunto.nombre },
    plazas: plazas.map((p: any) => ({
      plazaId: p.id,
      etiqueta: p.etiqueta,
      activa: p.activo,
      funciones: p.roles,
      perfil: p.perfil?.nombre ?? null,
      titularId: p.operarioId ?? null,
      titular: p.operarioId ? nombres.get(p.operarioId) ?? null : null,
      vacante: !p.operarioId,
    })),
  };
}

/* --------------------------------- traslado --------------------------------- */

export async function previsualizarTraslado(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { operarioId: string; conjuntoDestinoId: string },
) {
  await asegurarPermiso(prisma, ctx, "usuarios.gestionar");
  const operario = await operarioDeEmpresa(prisma, ctx, params.operarioId);
  const destino = await conjuntoAccesible(prisma, ctx, params.conjuntoDestinoId);
  if (operario.conjuntos.length === 1 && operario.conjuntos[0].nit === destino.nit) {
    throw errorAplicacion(409, "El operario ya pertenece a ese conjunto.", "CONFLICTO");
  }
  const abiertas = await new GerenteService(prisma, ctx.empresaId).listarTareasAbiertasOperario(operario.id);
  if (abiertas.length > 0) {
    throw errorAplicacion(
      409,
      `${operario.usuario.nombre} tiene ${abiertas.length} tarea(s) abierta(s). Deben cerrarse en ControlApp antes de trasladarlo; el traslado es inmediato y no se puede programar.`,
      "TAREAS_ABIERTAS",
    );
  }
  const plazas = await prisma.conjuntoNecesidadOperario.findMany({
    where: { operarioId: operario.id, activo: true },
    select: { etiqueta: true, conjunto: { select: { nombre: true } } },
    orderBy: { id: "asc" },
  });
  return {
    resumen: `${operario.usuario.nombre} pasará a "${destino.nombre}" desde ahora y dejará ${
      operario.conjuntos.length ? operario.conjuntos.map((c) => `"${c.nombre}"`).join(", ") : "su conjunto actual"
    }. ${plazas.length ? `Quedarán vacantes ${plazas.length} plaza(s).` : "No ocupa plazas."}`,
    impacto: {
      operario: operario.usuario.nombre,
      conjuntosActuales: operario.conjuntos.map((c) => c.nombre),
      conjuntoDestino: destino.nombre,
      plazasQueQuedanVacantes: plazas.map((p) => `${p.etiqueta} (${p.conjunto.nombre})`),
    },
  };
}

export async function trasladarOperario(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { operarioId: string; conjuntoDestinoId: string },
) {
  await asegurarPermiso(prisma, ctx, "usuarios.gestionar");
  await operarioDeEmpresa(prisma, ctx, params.operarioId);
  await conjuntoAccesible(prisma, ctx, params.conjuntoDestinoId);
  await new GerenteService(prisma, ctx.empresaId, actorAuditoria(ctx)).trasladarOperario(params.operarioId, {
    conjuntoId: params.conjuntoDestinoId,
  });
  return { trasladado: true };
}

/* ---------------------------------- plazas ---------------------------------- */

async function plazaDelConjunto(prisma: PrismaClient, conjuntoId: string, plazaId: number) {
  const plaza = await prisma.conjuntoNecesidadOperario.findFirst({
    where: { id: plazaId, conjuntoId },
    select: { id: true, etiqueta: true, roles: true, operarioId: true, activo: true },
  });
  if (!plaza) throw noEncontrado("Plaza no encontrada en ese conjunto.");
  return plaza;
}

function actividadesPendientesDePlaza(prisma: PrismaClient, plazaId: number) {
  return prisma.tarea.count({
    where: {
      necesidades: { some: { id: plazaId } },
      estado: { in: ESTADOS_PENDIENTES },
      fechaInicio: { gte: new Date() },
    },
  });
}

export async function previsualizarAsignacionPlaza(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; plazaId: number; operarioId: string; reemplazar: boolean },
) {
  await asegurarPermiso(prisma, ctx, "conjuntos.gestionar");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const plaza = await plazaDelConjunto(prisma, conjunto.nit, params.plazaId);
  const operario = await operarioDeEmpresa(prisma, ctx, params.operarioId);
  if (!plaza.activo) throw errorAplicacion(409, `La plaza "${plaza.etiqueta}" no está activa.`, "CONFLICTO");
  if (plaza.operarioId === operario.id) {
    throw errorAplicacion(409, `Ese operario ya ocupa la plaza "${plaza.etiqueta}".`, "CONFLICTO");
  }
  if (plaza.operarioId && !params.reemplazar) {
    throw errorAplicacion(
      409,
      `La plaza "${plaza.etiqueta}" ya está ocupada. Usa reemplazar=true para cambiar al titular, o libérala primero.`,
      "CONFLICTO",
    );
  }
  const faltantes = plaza.roles.filter((rol) => !operario.funciones.includes(rol));
  if (faltantes.length) {
    throw errorAplicacion(
      400,
      `El operario no tiene la función ${faltantes.join(", ")} que exige la plaza; agrégasela en ControlApp antes de asignarlo.`,
      "VALIDACION",
    );
  }
  const anterior = plaza.operarioId
    ? await prisma.usuario.findUnique({ where: { id: plaza.operarioId }, select: { nombre: true } })
    : null;
  const otraPlaza = await prisma.conjuntoNecesidadOperario.findFirst({
    where: { operarioId: operario.id, conjuntoId: conjunto.nit, activo: true },
    select: { etiqueta: true },
  });
  const pendientes = await actividadesPendientesDePlaza(prisma, plaza.id);
  return {
    resumen: `${operario.usuario.nombre} quedará como titular de "${plaza.etiqueta}" en "${conjunto.nombre}"${
      anterior ? ` en lugar de ${anterior.nombre}` : ""
    }. ${pendientes} actividad(es) pendiente(s) de esa plaza pasarán a su nombre.${
      otraPlaza ? ` Dejará su plaza actual "${otraPlaza.etiqueta}", que queda vacante.` : ""
    }`,
    impacto: {
      conjunto: conjunto.nombre,
      plaza: plaza.etiqueta,
      nuevoTitular: operario.usuario.nombre,
      titularAnterior: anterior?.nombre ?? null,
      actividadesPendientesQueCambian: pendientes,
      plazaQueDejaVacante: otraPlaza?.etiqueta ?? null,
    },
  };
}

export async function asignarPlaza(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; plazaId: number; operarioId: string; reemplazar: boolean },
) {
  await asegurarPermiso(prisma, ctx, "conjuntos.gestionar");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  await operarioDeEmpresa(prisma, ctx, params.operarioId);
  const out: any = await new ConjuntoNecesidadService(prisma, conjunto.nit, actorAuditoria(ctx)).asignarOperario(
    params.plazaId,
    { operarioId: params.operarioId, reemplazar: params.reemplazar },
  );
  return { asignado: true, cronograma: out?.cronograma ?? null };
}

export async function previsualizarLiberarPlaza(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; plazaId: number },
) {
  await asegurarPermiso(prisma, ctx, "conjuntos.gestionar");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const plaza = await plazaDelConjunto(prisma, conjunto.nit, params.plazaId);
  if (!plaza.operarioId) throw errorAplicacion(409, `La plaza "${plaza.etiqueta}" ya está vacante.`, "CONFLICTO");
  const titular = await prisma.usuario.findUnique({ where: { id: plaza.operarioId }, select: { nombre: true } });
  const pendientes = await actividadesPendientesDePlaza(prisma, plaza.id);
  return {
    resumen: `La plaza "${plaza.etiqueta}" de "${conjunto.nombre}" quedará vacante; ${titular?.nombre ?? "el titular"} deja de ocuparla. ${pendientes} actividad(es) pendiente(s) quedarán sin operario hasta que se asigne a alguien.`,
    impacto: {
      conjunto: conjunto.nombre,
      plaza: plaza.etiqueta,
      titularQueSale: titular?.nombre ?? null,
      actividadesPendientesSinOperario: pendientes,
    },
  };
}

export async function liberarPlaza(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  params: { conjuntoId: string; plazaId: number },
) {
  await asegurarPermiso(prisma, ctx, "conjuntos.gestionar");
  const conjunto = await conjuntoAccesible(prisma, ctx, params.conjuntoId);
  const out: any = await new ConjuntoNecesidadService(prisma, conjunto.nit, actorAuditoria(ctx)).liberarOperario(
    params.plazaId,
  );
  return { liberada: true, cronograma: out?.cronograma ?? null };
}

/* ------------------------------ crear operarios ------------------------------ */

const fechaYmd = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Formato AAAA-MM-DD");

export const NuevoOperarioMcpDTO = z
  .object({
    cedula: z.string().trim().regex(/^\d{5,15}$/, "La cédula debe tener solo dígitos (5 a 15)"),
    nombre: z.string().trim().min(3).max(120),
    correo: z.string().trim().toLowerCase().email(),
    telefono: z.string().trim().regex(/^\d{7,15}$/, "El teléfono debe tener solo dígitos (7 a 15)"),
    fechaNacimiento: fechaYmd,
    fechaIngreso: fechaYmd,
    funciones: z.array(z.enum(FUNCIONES)).min(1).max(5),
    jornadaLaboral: z.enum(["COMPLETA", "MEDIO_TIEMPO", "FINES_DE_SEMANA"]).optional(),
    cursoAlturas: z.boolean().default(false),
    cursoSalvamentoAcuatico: z.boolean().default(false),
    examenIngreso: z.boolean().default(false),
    conjuntoId: z.string().trim().min(1).optional(),
    plazaId: z.number().int().positive().optional(),
  })
  .strict();

export type NuevoOperarioMcp = z.infer<typeof NuevoOperarioMcpDTO>;

function payloadUsuario(dto: NuevoOperarioMcp, contrasena: string) {
  return {
    id: dto.cedula,
    nombre: dto.nombre,
    correo: dto.correo,
    contrasena,
    rol: "operario",
    telefono: dto.telefono,
    fechaNacimiento: dto.fechaNacimiento,
    jornadaLaboral: dto.jornadaLaboral,
    activo: true,
  };
}

function payloadOperario(dto: NuevoOperarioMcp) {
  return {
    Id: dto.cedula,
    funciones: dto.funciones,
    cursoAlturas: dto.cursoAlturas,
    cursoSalvamentoAcuatico: dto.cursoSalvamentoAcuatico,
    examenIngreso: dto.examenIngreso,
    fechaIngreso: dto.fechaIngreso,
    disponibilidadPeriodos: [],
  };
}

function primerError(resultado: { success: boolean; error?: z.ZodError }): string | null {
  if (resultado.success || !resultado.error) return null;
  const issue = resultado.error.issues[0];
  return `${issue.path.join(".") || "datos"}: ${issue.message}`;
}

/** Valida una fila sin escribir nada. Devuelve el motivo o null. */
async function validarNuevoOperario(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  dto: NuevoOperarioMcp,
): Promise<{ motivo: string | null; conjunto?: string; plaza?: string }> {
  const errorUsuario = primerError(CrearUsuarioDTO.safeParse(payloadUsuario(dto, "x".repeat(16))));
  if (errorUsuario) return { motivo: errorUsuario };
  const errorOperario = primerError(CrearOperarioDTO.safeParse(payloadOperario(dto)));
  if (errorOperario) return { motivo: errorOperario };

  const [porId, porCorreo] = await Promise.all([
    prisma.usuario.findUnique({ where: { id: dto.cedula }, select: { id: true } }),
    prisma.usuario.findUnique({ where: { correo: dto.correo }, select: { id: true } }),
  ]);
  if (porId) return { motivo: `Ya existe un usuario con la cédula ${ultimosDigitos(dto.cedula)}.` };
  if (porCorreo) return { motivo: `Ya existe un usuario con el correo ${dto.correo}.` };

  if (dto.plazaId && !dto.conjuntoId) return { motivo: "Para asignar una plaza indica también el conjunto." };
  if (!dto.conjuntoId) return { motivo: null };
  let conjunto;
  try {
    conjunto = await conjuntoAccesible(prisma, ctx, dto.conjuntoId);
  } catch {
    return { motivo: `El conjunto ${dto.conjuntoId} no existe.` };
  }
  if (!dto.plazaId) return { motivo: null, conjunto: conjunto.nombre };
  const plaza = await prisma.conjuntoNecesidadOperario.findFirst({
    where: { id: dto.plazaId, conjuntoId: conjunto.nit },
    select: { etiqueta: true, roles: true, operarioId: true, activo: true },
  });
  if (!plaza || !plaza.activo) return { motivo: `La plaza ${dto.plazaId} no existe o no está activa en ${conjunto.nombre}.` };
  if (plaza.operarioId) return { motivo: `La plaza "${plaza.etiqueta}" ya está ocupada.` };
  const faltantes = plaza.roles.filter((rol) => !dto.funciones.includes(rol as (typeof FUNCIONES)[number]));
  if (faltantes.length) return { motivo: `La plaza "${plaza.etiqueta}" exige la función ${faltantes.join(", ")}.` };
  return { motivo: null, conjunto: conjunto.nombre, plaza: plaza.etiqueta };
}

function describirFila(dto: NuevoOperarioMcp, validacion: { conjunto?: string; plaza?: string }) {
  return {
    nombre: dto.nombre,
    cedula: ultimosDigitos(dto.cedula),
    funciones: dto.funciones,
    conjunto: validacion.conjunto ?? null,
    plaza: validacion.plaza ?? null,
  };
}

export async function previsualizarCrearOperarios(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  filas: NuevoOperarioMcp[],
) {
  await asegurarPermiso(prisma, ctx, "usuarios.gestionar");
  const errores: Array<{ fila: number; nombre: string; motivo: string }> = [];
  const descripciones: ReturnType<typeof describirFila>[] = [];
  const vistos = { cedulas: new Set<string>(), correos: new Set<string>(), plazas: new Set<string>() };

  for (const [indice, dto] of filas.entries()) {
    const fila = indice + 1;
    const plazaClave = dto.plazaId ? `${dto.conjuntoId}:${dto.plazaId}` : null;
    if (vistos.cedulas.has(dto.cedula)) errores.push({ fila, nombre: dto.nombre, motivo: "Cédula repetida en el lote." });
    else if (vistos.correos.has(dto.correo)) errores.push({ fila, nombre: dto.nombre, motivo: "Correo repetido en el lote." });
    else if (plazaClave && vistos.plazas.has(plazaClave)) errores.push({ fila, nombre: dto.nombre, motivo: "Plaza repetida en el lote." });
    else {
      const validacion = await validarNuevoOperario(prisma, ctx, dto);
      if (validacion.motivo) errores.push({ fila, nombre: dto.nombre, motivo: validacion.motivo });
      else descripciones.push(describirFila(dto, validacion));
    }
    vistos.cedulas.add(dto.cedula);
    vistos.correos.add(dto.correo);
    if (plazaClave) vistos.plazas.add(plazaClave);
  }

  if (errores.length) {
    const detalle = errores.map((e) => `fila ${e.fila} (${e.nombre}): ${e.motivo}`).join(" | ");
    throw errorAplicacion(400, `No se creó nada. Corrige estas filas y vuelve a previsualizar: ${detalle}`, "VALIDACION");
  }

  return {
    resumen: `Se crearán ${filas.length} operario(s). Quedan sin contraseña utilizable: para darles acceso, restablece su contraseña desde ControlApp y entrégasela; al entrar deberán crear una nueva.`,
    impacto: { total: filas.length, operarios: descripciones },
  };
}

async function crearUnOperario(prisma: PrismaClient, ctx: ContextoAccion, dto: NuevoOperarioMcp) {
  const gerente = new GerenteService(prisma, ctx.empresaId, actorAuditoria(ctx));
  // Contrasena aleatoria que nadie conoce: ni la IA ni el chat la ven. El
  // gerente la restablece desde la app para entregar el acceso.
  const contrasena = randomBytes(24).toString("base64url");
  await gerente.crearUsuario(payloadUsuario(dto, contrasena));
  try {
    await gerente.asignarOperario(payloadOperario(dto));
    if (dto.conjuntoId && dto.plazaId) {
      await new ConjuntoNecesidadService(prisma, dto.conjuntoId, actorAuditoria(ctx)).asignarOperario(dto.plazaId, {
        operarioId: dto.cedula,
        reemplazar: false,
      });
    } else if (dto.conjuntoId) {
      await gerente.asignarOperarioAConjunto({ conjuntoId: dto.conjuntoId, operarioId: dto.cedula });
    }
  } catch (error) {
    // Compensacion: un operario a medias no debe quedar en la base.
    await gerente.eliminarUsuario(dto.cedula).catch(() => undefined);
    throw error;
  }
  return dto.cedula;
}

/**
 * Crea todas las filas o ninguna: si una falla, se eliminan las ya creadas
 * (los servicios no comparten transaccion) y se informa cual fallo.
 */
export async function crearOperarios(prisma: PrismaClient, ctx: ContextoAccion, filas: NuevoOperarioMcp[]) {
  await asegurarPermiso(prisma, ctx, "usuarios.gestionar");
  const gerente = new GerenteService(prisma, ctx.empresaId, actorAuditoria(ctx));
  const creados: string[] = [];
  for (const [indice, dto] of filas.entries()) {
    try {
      creados.push(await crearUnOperario(prisma, ctx, dto));
    } catch (error) {
      for (const cedula of creados.reverse()) {
        await gerente.eliminarUsuario(cedula).catch(() => undefined);
      }
      const motivo = error instanceof Error ? error.message : "error desconocido";
      throw errorAplicacion(
        409,
        `No se creó ningún operario: la fila ${indice + 1} (${dto.nombre}) falló (${motivo}) y se deshicieron las anteriores.`,
        "LOTE_REVERTIDO",
      );
    }
  }
  return { creados };
}
