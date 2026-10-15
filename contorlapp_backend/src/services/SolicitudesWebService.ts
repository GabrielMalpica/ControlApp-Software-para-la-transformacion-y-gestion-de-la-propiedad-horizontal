import type { PrismaClient } from "@prisma/client";
import { prisma as prismaCompartido } from "../db/prisma";
import { enviarArchivoWebAPapelera } from "../utils/drive_evidencias";
import { commerceHttpError } from "./CommerceAccessService";
import { cacheGet, cacheSet, cached } from "./RedisService";
import { buildWooUrl, wooFetch, WooFetchError } from "./wooFetch";

/**
 * Solicitudes que llegan desde la pagina web, solo para consultar en
 * ControlApp: postulaciones de trabajadores (plugin control-marketplace,
 * GET clmk/v1/postulaciones) y conjuntos registrados (plugin
 * control_registro_conjuntos, GET clx/v1/registros-conjuntos). No hay tablas
 * en ControlApp: los datos viven en WordPress y los archivos en Drive.
 *
 * Sobre las postulaciones, el equipo puede ademas marcar "ya la revisamos"
 * (se guarda en el usuario de WordPress del postulante) y borrarlas; aprobar
 * o rechazar sigue en wp-admin.
 */

export type DocumentoWebDto = {
  tipo: string;
  etiqueta: string;
  driveFileId: string | null;
  mime: string | null;
  nombre: string | null;
  /** Archivo viejo que sigue en el servidor de WordPress (antes de usar Drive). */
  enServidor: boolean;
  /** Enlace publico del archivo viejo, si lo tiene (registros de conjuntos anteriores a Drive). */
  urlServidor: string | null;
  /** Recibido por la web pero todavia en cola para subir a Drive. */
  pendiente: boolean;
};

export type PostulacionWebDto = {
  id: number;
  nombres: string;
  apellidos: string;
  telefono: string | null;
  correo: string | null;
  documentoTipo: string | null;
  documentoUltimos4: string | null;
  habilidades: string[];
  zonas: string[];
  estado: string;
  estadoEtiqueta: string;
  observaciones: string | null;
  creadoEn: string | null;
  foto: DocumentoWebDto | null;
  documentos: DocumentoWebDto[];
  /** Marca de ControlApp "ya la revisamos" (no cambia el estado en WordPress). */
  revisada: boolean;
  revisadaEn: string | null;
  revisadaPor: string | null;
};

export type RegistroConjuntoWebDto = {
  id: number;
  nombre: string;
  nit: string | null;
  telefono: string | null;
  correo: string | null;
  estado: string;
  estadoEtiqueta: string;
  nota: string | null;
  registradoEn: string | null;
  documentos: DocumentoWebDto[];
};

export type PaginaWeb<T> = { items: T[]; total: number; pagina: number; porPagina: number };

const ESTADOS_CONJUNTO: Record<string, string> = {
  pending: "Pendiente de revisión",
  approved: "Aprobado",
  rejected: "Rechazado",
};

const DRIVE_ID = /^[a-zA-Z0-9_-]{10,80}$/;

function texto(valor: unknown): string | null {
  if (valor == null) return null;
  const limpio = String(valor).trim();
  return limpio ? limpio : null;
}

function entero(valor: unknown, defecto = 0): number {
  const n = Number(valor);
  return Number.isFinite(n) ? Math.trunc(n) : defecto;
}

function lista(valor: unknown): string[] {
  return Array.isArray(valor) ? valor.map(texto).filter((v): v is string => v !== null) : [];
}

function objeto(valor: unknown): Record<string, unknown> {
  return valor && typeof valor === "object" && !Array.isArray(valor) ? (valor as Record<string, unknown>) : {};
}

/** Nunca se entrega el numero completo del documento: solo los ultimos 4 digitos. */
export function ultimos4(valor: unknown): string | null {
  const digitos = String(valor ?? "").replace(/\D/g, "");
  return digitos ? digitos.slice(-4) : null;
}

export function normalizarDocumentoWeb(raw: unknown): DocumentoWebDto {
  const d = objeto(raw);
  const driveFileId = texto(d.drive_file_id);
  const tipo = texto(d.tipo) ?? "otro";
  const url = texto(d.url_servidor);
  return {
    tipo,
    etiqueta: texto(d.etiqueta) ?? tipo,
    driveFileId: driveFileId && DRIVE_ID.test(driveFileId) ? driveFileId : null,
    mime: texto(d.mime),
    nombre: texto(d.nombre ?? d.nombre_original),
    enServidor: d.en_servidor === true,
    urlServidor: url && /^https?:\/\//i.test(url) ? url : null,
    pendiente: d.pendiente === true,
  };
}

export function normalizarPostulacion(raw: unknown): PostulacionWebDto {
  const p = objeto(raw);
  const documentos = Array.isArray(p.documentos) ? p.documentos.map(normalizarDocumentoWeb) : [];
  const estado = texto(p.estado) ?? "pendiente";
  return {
    id: entero(p.id),
    nombres: texto(p.nombres) ?? "",
    apellidos: texto(p.apellidos) ?? "",
    telefono: texto(p.telefono),
    correo: texto(p.correo),
    documentoTipo: texto(p.tipo_doc),
    documentoUltimos4: ultimos4(p.num_doc_ultimos4),
    habilidades: lista(p.habilidades),
    zonas: lista(p.zonas),
    estado,
    estadoEtiqueta: texto(p.estado_etiqueta) ?? estado,
    observaciones: texto(p.observaciones_admin),
    creadoEn: texto(p.creado_en),
    foto: documentos.find((d) => d.tipo === "foto") ?? null,
    documentos: documentos.filter((d) => d.tipo !== "foto"),
    revisada: p.revisada === true,
    revisadaEn: p.revisada === true ? texto(p.revisada_en) : null,
    revisadaPor: p.revisada === true ? texto(p.revisada_por) : null,
  };
}

export function normalizarRegistroConjunto(raw: unknown): RegistroConjuntoWebDto {
  const c = objeto(raw);
  const estado = texto(c.estado) ?? "pending";
  return {
    id: entero(c.id),
    nombre: texto(c.nombre) ?? "",
    nit: texto(c.nit),
    telefono: texto(c.telefono),
    correo: texto(c.correo),
    estado,
    estadoEtiqueta: ESTADOS_CONJUNTO[estado] ?? estado,
    nota: texto(c.nota),
    registradoEn: texto(c.registrado_en),
    documentos: Array.isArray(c.documentos) ? c.documentos.map(normalizarDocumentoWeb) : [],
  };
}

function normalizarPagina<T>(raw: unknown, normalizar: (item: unknown) => T): PaginaWeb<T> {
  const r = objeto(raw);
  const items = Array.isArray(r.items) ? r.items.map(normalizar) : [];
  return {
    items,
    total: entero(r.total, items.length),
    pagina: Math.max(1, entero(r.pagina, 1)),
    porPagina: Math.max(1, entero(r.por_pagina, items.length || 20)),
  };
}

export type ConsultaSolicitudesWeb = { estado?: string; pagina?: number };
export type RevisionPostulaciones = "pendientes" | "revisadas";
export type ConsultaPostulaciones = ConsultaSolicitudesWeb & { revision?: RevisionPostulaciones };

export type PostulacionEliminada = {
  eliminada: true;
  /** Documentos que estaban en Drive y quedaron en la papelera (recuperables 30 dias). */
  archivosEnPapelera: number;
  /** Documentos que no se pudieron mandar a la papelera (siguen en Drive). */
  archivosSinMover: number;
};

// Cambia cada vez que el equipo marca o borra una postulacion, para que el
// listado en cache (30 s) no muestre el estado anterior.
const GENERACION_POSTULACIONES = "web:postulaciones:generacion";

export class SolicitudesWebService {
  constructor(private readonly prisma: Pick<PrismaClient, "usuario"> = prismaCompartido) {}

  async listarPostulaciones(consulta: ConsultaPostulaciones): Promise<PaginaWeb<PostulacionWebDto>> {
    const estado = consulta.estado ?? "";
    const pagina = consulta.pagina ?? 1;
    const revision = consulta.revision ?? "";
    const generacion = (await cacheGet<number>(GENERACION_POSTULACIONES)) ?? 0;
    return cached(`web:postulaciones:v2:${generacion}:${revision}:${estado}:${pagina}`, 30, async () => {
      const data = await wooFetch<unknown>(
        buildWooUrl("clmk", "/postulaciones", { estado, pagina, revision }),
        {},
        { requireAuth: true, failureMessage: "No se pudieron consultar las postulaciones de la pagina web" },
      );
      return normalizarPagina(data, normalizarPostulacion);
    });
  }

  /** "Ya la revisamos" (o quitar la marca). Queda el nombre de quien la marco. */
  async marcarRevisionPostulacion(id: number, revisada: boolean, actorId: string): Promise<PostulacionWebDto> {
    const por = await this.nombreActor(actorId);
    const data = await this.llamarPostulacion(
      buildWooUrl("clmk", `/postulaciones/${id}/revision`),
      { method: "POST", body: JSON.stringify({ revisada, por }) },
      "No se pudo actualizar la postulacion en la pagina web",
    );
    await cacheSet(GENERACION_POSTULACIONES, Date.now(), 7 * 24 * 3600);
    return normalizarPostulacion(data);
  }

  /**
   * Borra la postulacion en WordPress (usuario, datos y documentos) y manda a
   * la papelera de Drive los documentos que ya estaban alla. WordPress se
   * niega (409) si la persona ya tiene servicios: eso se rechaza en wp-admin.
   */
  async eliminarPostulacion(id: number, actorId: string): Promise<PostulacionEliminada> {
    const por = await this.nombreActor(actorId);
    const data = await this.llamarPostulacion(
      buildWooUrl("clmk", `/postulaciones/${id}`, { por }),
      { method: "DELETE" },
      "No se pudo borrar la postulacion en la pagina web",
    );
    await cacheSet(GENERACION_POSTULACIONES, Date.now(), 7 * 24 * 3600);

    const ids = lista(objeto(data).drive_file_ids).filter((fileId) => DRIVE_ID.test(fileId));
    const resultados = await Promise.allSettled(ids.map((fileId) => enviarArchivoWebAPapelera(fileId)));
    const sinMover = resultados.filter((r) => r.status === "rejected").length;
    if (sinMover) {
      console.error(`[solicitudes-web] ${sinMover} documento(s) de la postulacion ${id} no pasaron a la papelera de Drive`);
    }
    return { eliminada: true, archivosEnPapelera: ids.length - sinMover, archivosSinMover: sinMover };
  }

  private async llamarPostulacion(url: string, init: RequestInit, failureMessage: string) {
    try {
      // mapConflict: el 409 de WordPress trae un mensaje claro para el equipo
      // (p. ej. "ya tiene servicios, rechazala en WordPress").
      return await wooFetch<unknown>(url, init, { requireAuth: true, mapConflict: true, failureMessage });
    } catch (error) {
      if (error instanceof WooFetchError && error.upstreamStatus === 404) {
        throw commerceHttpError(404, "Esa postulacion ya no existe en la pagina web. Actualiza la lista.");
      }
      throw error;
    }
  }

  private async nombreActor(actorId: string) {
    const usuario = await this.prisma.usuario.findUnique({ where: { id: actorId }, select: { nombre: true } });
    return usuario?.nombre?.trim().slice(0, 120) || "ControlApp";
  }

  async listarConjuntos(consulta: ConsultaSolicitudesWeb): Promise<PaginaWeb<RegistroConjuntoWebDto>> {
    const estado = consulta.estado ?? "";
    const pagina = consulta.pagina ?? 1;
    return cached(`web:registros-conjuntos:v1:${estado}:${pagina}`, 30, async () => {
      const data = await wooFetch<unknown>(
        buildWooUrl("clx", "/registros-conjuntos", { estado, pagina }),
        {},
        { requireAuth: true, failureMessage: "No se pudieron consultar los conjuntos registrados en la pagina web" },
      );
      return normalizarPagina(data, normalizarRegistroConjunto);
    });
  }
}
