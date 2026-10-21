// src/mcp/confirmaciones.ts
//
// Operaciones que cambian datos en dos pasos: previsualizar (no escribe nada
// y devuelve un `confirmacionId`) y confirmar_operacion. Garantias:
// - el id lo emite y guarda el servidor: la IA no puede fabricarlo;
// - es de un solo uso, vence y solo sirve en la misma conexion;
// - al confirmar se ejecutan los parametros GUARDADOS, no unos reenviados;
// - antes de ejecutar se vuelve a previsualizar: si el impacto cambio (otra
//   persona movio algo entretanto) se aborta y hay que previsualizar de nuevo;
// - las de alto riesgo esperan la aprobacion del gerente DENTRO de ControlApp
//   (fuera del alcance de la IA, aunque un texto inyectado la convenza).
import { createHash } from "crypto";
import type { Prisma, PrismaClient } from "@prisma/client";

import type { ContextoAccion } from "../aplicacion/contexto";
import { NotificacionService } from "../services/NotificacionService";

export const ESTADOS_CONFIRMACION = {
  PENDIENTE: "PENDIENTE",
  PENDIENTE_APROBACION: "PENDIENTE_APROBACION",
  APROBADA: "APROBADA",
  RECHAZADA: "RECHAZADA",
  EJECUTANDO: "EJECUTANDO",
  EJECUTADA: "EJECUTADA",
  FALLIDA: "FALLIDA",
  INVALIDADA: "INVALIDADA",
  EXPIRADA: "EXPIRADA",
} as const;

const VIGENCIA_CONFIRMAR_MS = 10 * 60_000;
const VIGENCIA_APROBACION_MS = 30 * 60_000;
export const VIGENCIA_TRAS_APROBAR_MS = 15 * 60_000;

export type Previsualizacion = { resumen: string; impacto: Record<string, unknown> };

export type OperacionConfirmable<P = any> = {
  nombre: string;
  titulo: string;
  scope: string;
  requiereAprobacionHumana: (params: P) => boolean;
  previsualizar: (prisma: PrismaClient, ctx: ContextoAccion, params: P) => Promise<Previsualizacion>;
  ejecutar: (prisma: PrismaClient, ctx: ContextoAccion, params: P) => Promise<unknown>;
  /** Entidades afectadas, para la bitacora. */
  entidades?: (params: P, resultado: unknown) => Array<{ tipo: string; id: string | number }>;
};

type HttpError = Error & { status: number; code: string };

function error(status: number, code: string, message: string): HttpError {
  return Object.assign(new Error(message), { status, code });
}

/** JSON canonico (llaves ordenadas): mismo contenido => mismo hash. */
export function jsonCanonico(valor: unknown): string {
  if (valor === null || typeof valor !== "object") return JSON.stringify(valor ?? null);
  if (valor instanceof Date) return JSON.stringify(valor.toISOString());
  if (Array.isArray(valor)) return `[${valor.map(jsonCanonico).join(",")}]`;
  const entradas = Object.entries(valor as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return `{${entradas.map(([k, v]) => `${JSON.stringify(k)}:${jsonCanonico(v)}`).join(",")}}`;
}

export function hashCanonico(valor: unknown): string {
  return createHash("sha256").update(jsonCanonico(valor)).digest("hex");
}

export type ContextoConfirmacion = {
  accion: ContextoAccion;
  conexionId: string;
  clienteNombre: string;
  scopes: Set<string>;
};

export async function crearConfirmacion<P>(
  prisma: PrismaClient,
  ctx: ContextoConfirmacion,
  operacion: OperacionConfirmable<P>,
  params: P,
) {
  const vista = await operacion.previsualizar(prisma, ctx.accion, params);
  const requiereAprobacion = operacion.requiereAprobacionHumana(params);
  const ahora = Date.now();
  const confirmacion = await prisma.mcpConfirmacion.create({
    data: {
      conexionId: ctx.conexionId,
      usuarioId: ctx.accion.actor.id,
      empresaId: ctx.accion.empresaId,
      operacion: operacion.nombre,
      parametros: JSON.parse(JSON.stringify(params)) as Prisma.InputJsonValue,
      parametrosHash: hashCanonico(params),
      resumen: vista.resumen,
      impacto: JSON.parse(JSON.stringify(vista.impacto)) as Prisma.InputJsonValue,
      impactoHash: hashCanonico(vista.impacto),
      requiereAprobacionHumana: requiereAprobacion,
      estado: requiereAprobacion ? ESTADOS_CONFIRMACION.PENDIENTE_APROBACION : ESTADOS_CONFIRMACION.PENDIENTE,
      expiraEn: new Date(ahora + (requiereAprobacion ? VIGENCIA_APROBACION_MS : VIGENCIA_CONFIRMAR_MS)),
    },
    select: { id: true, expiraEn: true },
  });

  if (requiereAprobacion) {
    // Aviso en la campanita de ControlApp: el gerente aprueba desde la app.
    await new NotificacionService(prisma)
      .crearParaUsuarios({
        usuarioIds: [ctx.accion.actor.id],
        tipo: "mcp_aprobacion",
        titulo: "Una IA pide tu aprobación",
        mensaje: `${ctx.clienteNombre}: ${vista.resumen}`.slice(0, 480),
        referenciaTipo: "McpConfirmacion",
        data: { confirmacionId: confirmacion.id },
      })
      .catch(() => undefined);
  }

  return {
    confirmacionId: confirmacion.id,
    operacion: operacion.nombre,
    resumen: vista.resumen,
    impacto: vista.impacto,
    requiereAprobacionEnControlApp: requiereAprobacion,
    venceEn: confirmacion.expiraEn.toISOString(),
    siguientePaso: requiereAprobacion
      ? "Muestra el resumen al gerente. Esta operación es de alto riesgo: debe aprobarla en ControlApp (Configuración → Integraciones IA → Aprobaciones). Cuando la apruebe, llama confirmar_operacion con este confirmacionId."
      : "Muestra el resumen al gerente y pídele confirmación explícita. Solo si la confirma, llama confirmar_operacion con este confirmacionId.",
  };
}

export async function confirmarOperacion(
  prisma: PrismaClient,
  ctx: ContextoConfirmacion,
  operaciones: ReadonlyMap<string, OperacionConfirmable>,
  confirmacionId: string,
) {
  const conf = await prisma.mcpConfirmacion.findFirst({
    where: { id: confirmacionId, conexionId: ctx.conexionId, usuarioId: ctx.accion.actor.id },
  });
  if (!conf) throw error(404, "CONFIRMACION_NO_ENCONTRADA", "No existe esa confirmación en esta conexión.");

  const operacion = operaciones.get(conf.operacion);
  if (!operacion) throw error(400, "OPERACION_DESCONOCIDA", "La operación ya no está disponible.");
  if (!ctx.scopes.has(operacion.scope)) {
    throw error(403, "SCOPE_INSUFICIENTE", `La conexión no tiene el permiso ${operacion.scope}.`);
  }

  switch (conf.estado) {
    case ESTADOS_CONFIRMACION.EJECUTADA:
    case ESTADOS_CONFIRMACION.EJECUTANDO:
      throw error(409, "CONFIRMACION_USADA", "Esa confirmación ya se usó.");
    case ESTADOS_CONFIRMACION.RECHAZADA:
      throw error(409, "CONFIRMACION_RECHAZADA", "El gerente rechazó esta operación en ControlApp.");
    case ESTADOS_CONFIRMACION.PENDIENTE_APROBACION:
      throw error(
        409,
        "PENDIENTE_APROBACION",
        "Aún no está aprobada. El gerente debe aprobarla en ControlApp → Configuración → Integraciones IA.",
      );
    case ESTADOS_CONFIRMACION.PENDIENTE:
    case ESTADOS_CONFIRMACION.APROBADA:
      break;
    default:
      throw error(409, "CONFIRMACION_NO_VIGENTE", "Esa confirmación ya no es válida; vuelve a previsualizar.");
  }
  if (conf.expiraEn.getTime() <= Date.now()) {
    await prisma.mcpConfirmacion.updateMany({
      where: { id: conf.id, estado: conf.estado },
      data: { estado: ESTADOS_CONFIRMACION.EXPIRADA },
    });
    throw error(409, "CONFIRMACION_EXPIRADA", "La confirmación venció; vuelve a previsualizar.");
  }

  // Un solo uso, incluso con dos llamadas simultaneas: gana la que cambia el estado.
  const tomada = await prisma.mcpConfirmacion.updateMany({
    where: { id: conf.id, estado: conf.estado },
    data: { estado: ESTADOS_CONFIRMACION.EJECUTANDO },
  });
  if (tomada.count !== 1) throw error(409, "CONFIRMACION_USADA", "Esa confirmación ya se usó.");

  const params = conf.parametros as unknown;
  try {
    // El mundo pudo cambiar desde la previsualizacion: se vuelve a calcular.
    const vista = await operacion.previsualizar(prisma, ctx.accion, params);
    if (hashCanonico(vista.impacto) !== conf.impactoHash) {
      await prisma.mcpConfirmacion.update({
        where: { id: conf.id },
        data: { estado: ESTADOS_CONFIRMACION.INVALIDADA, resultado: { impactoNuevo: vista.impacto } as any },
      });
      throw error(
        409,
        "ESTADO_CAMBIO",
        `Los datos cambiaron desde la previsualización. Nuevo resumen: ${vista.resumen} Vuelve a previsualizar si quieres continuar.`,
      );
    }
    const resultado = await operacion.ejecutar(prisma, ctx.accion, params);
    await prisma.mcpConfirmacion.update({
      where: { id: conf.id },
      data: {
        estado: ESTADOS_CONFIRMACION.EJECUTADA,
        ejecutadaEn: new Date(),
        resultado: JSON.parse(JSON.stringify(resultado ?? null)) as Prisma.InputJsonValue,
      },
    });
    return {
      operacion: conf.operacion,
      resumen: conf.resumen,
      resultado,
      entidades: operacion.entidades?.(params, resultado) ?? [],
    };
  } catch (err) {
    const codigo = (err as { code?: string }).code;
    if (codigo !== "ESTADO_CAMBIO") {
      await prisma.mcpConfirmacion
        .update({
          where: { id: conf.id },
          data: {
            estado: ESTADOS_CONFIRMACION.FALLIDA,
            resultado: { error: err instanceof Error ? err.message.slice(0, 500) : "error" } as any,
          },
        })
        .catch(() => undefined);
    }
    throw err;
  }
}

export async function estadoConfirmacion(prisma: PrismaClient, ctx: ContextoConfirmacion, confirmacionId: string) {
  const conf = await prisma.mcpConfirmacion.findFirst({
    where: { id: confirmacionId, conexionId: ctx.conexionId, usuarioId: ctx.accion.actor.id },
    select: { id: true, operacion: true, estado: true, resumen: true, expiraEn: true, ejecutadaEn: true },
  });
  if (!conf) throw error(404, "CONFIRMACION_NO_ENCONTRADA", "No existe esa confirmación en esta conexión.");
  const vencida =
    conf.expiraEn.getTime() <= Date.now() &&
    [
      ESTADOS_CONFIRMACION.PENDIENTE,
      ESTADOS_CONFIRMACION.PENDIENTE_APROBACION,
      ESTADOS_CONFIRMACION.APROBADA,
    ].includes(conf.estado as any);
  return {
    confirmacionId: conf.id,
    operacion: conf.operacion,
    estado: vencida ? ESTADOS_CONFIRMACION.EXPIRADA : conf.estado,
    resumen: conf.resumen,
    venceEn: conf.expiraEn.toISOString(),
    ejecutadaEn: conf.ejecutadaEn?.toISOString() ?? null,
  };
}
