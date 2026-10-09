// Orquesta el informe mensual: consulta las tareas y el cronograma, baja las
// fotos de Drive en paralelo (reducidas con sharp) y genera el PDF.
import type { PrismaClient } from "@prisma/client";
import sharp from "sharp";
import { extraerDriveId, getEvidenciaBuffer } from "../utils/drive_evidencias";
import { CronogramaService } from "./CronogramaServices";
import {
  actividadesDelCuerpo,
  claveDia,
  construirInformeMensual,
  type CronogramaInformeMes,
  type InformeMensual,
  type ReemplazoInforme,
  type TareaDetalleInforme,
} from "./InformeMensualModelo";
import type { EjecutorInforme, ReportarProgreso } from "./InformeMensualJobs";
import {
  opcionesPorDefecto,
  type CalidadFotoInforme,
  type OpcionesInforme,
} from "./InformeMensualOpciones";
import {
  limpiarTexto,
  renderizarInformeMensual,
  type FotoCargada,
} from "./InformeMensualPdf";
import { ReporteService } from "./ReporteService";

// Se reexporta porque las pruebas del informe lo importan desde aqui.
export { extraerDriveId };

/** Lado maximo y calidad JPEG de las fotos dentro del PDF segun la calidad elegida. */
const CALIDAD_FOTO: Record<CalidadFotoInforme, { lado: number; jpeg: number }> = {
  LIVIANA: { lado: 600, jpeg: 60 },
  // La de siempre: nitida al imprimir y liviana.
  ESTANDAR: { lado: 800, jpeg: 72 },
  ALTA: { lado: 1200, jpeg: 80 },
};
/** Descargas/conversiones simultaneas en TODO el servidor (todos los informes). */
const FOTOS_SIMULTANEAS = Number(process.env.INFORME_PDF_FOTOS_SIMULTANEAS ?? 6);
const MAX_CONJUNTOS_CRONOGRAMA = 25;

/* ------------------------------ utilidades ------------------------------ */

function crearLimitador(maximo: number) {
  let activos = 0;
  const espera: Array<() => void> = [];
  const liberar = () => {
    activos -= 1;
    espera.shift()?.();
  };
  return async function limitar<T>(fn: () => Promise<T>): Promise<T> {
    if (activos >= maximo) await new Promise<void>((r) => espera.push(r));
    activos += 1;
    try {
      return await fn();
    } finally {
      liberar();
    }
  };
}

const limitarFotos = crearLimitador(Math.max(1, FOTOS_SIMULTANEAS));

async function cargarFotoDrive(
  raw: string,
  calidad: CalidadFotoInforme,
): Promise<FotoCargada | null> {
  const id = extraerDriveId(raw);
  if (!id) return null;
  const { lado, jpeg } = CALIDAD_FOTO[calidad] ?? CALIDAD_FOTO.ESTANDAR;
  for (let intento = 0; intento < 2; intento++) {
    try {
      const original = await getEvidenciaBuffer(id);
      const { data, info } = await sharp(original, { failOn: "none" })
        .rotate()
        .resize({
          width: lado,
          height: lado,
          fit: "inside",
          withoutEnlargement: true,
        })
        .flatten({ background: "#ffffff" })
        .jpeg({ quality: jpeg })
        .toBuffer({ resolveWithObject: true });
      return { buffer: data, width: info.width, height: info.height };
    } catch (err) {
      if (intento === 1) {
        console.warn(
          `[informe-mensual] no se pudo cargar la evidencia ${id}:`,
          err instanceof Error ? err.message : err,
        );
      }
    }
  }
  return null;
}

/** Meses (anio/mes en hora de Colombia) que toca el rango [desde, hasta]. */
export function mesesDelRango(
  desde: Date,
  hasta: Date,
): Array<{ anio: number; mes: number }> {
  const [y1, m1] = claveDia(desde).split("-").map(Number);
  const [y2, m2] = claveDia(hasta).split("-").map(Number);
  const out: Array<{ anio: number; mes: number }> = [];
  let y = y1;
  let m = m1;
  // Tope defensivo: un rango absurdo no debe disparar cientos de consultas.
  while ((y < y2 || (y === y2 && m <= m2)) && out.length < 24) {
    out.push({ anio: y, mes: m });
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
  }
  return out;
}

function nombreArchivoSeguro(v: string): string {
  const limpio = limpiarTexto(v)
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return limpio || "conjunto";
}

/* ------------------------------ generacion ------------------------------ */

export type ParametrosInforme = {
  prisma: PrismaClient;
  empresaId: string;
  conjuntoId?: string;
  desde: Date;
  hasta: Date;
  /** Rol de quien pidió el informe; solo afecta cómo se etiquetan las
   * tareas CORRECTIVA en el PDF ("actividad especial" para administrador). */
  rolSolicitante?: string;
  /** Ya normalizadas para el rol (ver normalizarOpciones). */
  opciones?: OpcionesInforme;
  /** Quien pidió el informe: su nombre va en la portada. */
  usuarioId?: string;
};

/** Nombres de usuarios en una sola consulta (sin N+1). */
async function nombresDeUsuarios(
  prisma: PrismaClient,
  ids: string[],
): Promise<Map<string, string>> {
  const unicos = Array.from(new Set(ids.filter((id) => id && id.trim())));
  if (unicos.length === 0) return new Map();
  const usuarios = await prisma.usuario.findMany({
    where: { id: { in: unicos } },
    select: { id: true, nombre: true },
  });
  return new Map(usuarios.map((u) => [u.id, u.nombre]));
}

async function recolectarDatos(
  p: ParametrosInforme,
  opciones: OpcionesInforme,
  reportar: ReportarProgreso,
): Promise<InformeMensual> {
  reportar(5, "Consultando las tareas del periodo");
  const reportes = new ReporteService(p.prisma, p.empresaId);
  const detalle: any = await reportes.reporteMensualDetalle({
    desde: p.desde,
    hasta: p.hasta,
    conjuntoId: p.conjuntoId,
  });

  const tareas: TareaDetalleInforme[] = detalle.data ?? [];
  const reemplazos: ReemplazoInforme[] =
    detalle.reemplazosPreventivaPorCorrectiva ?? [];

  // Interno: solo se resuelve si se pidió y el rol puede verlo.
  if (opciones.campos.cerradoPor) {
    const nombres = await nombresDeUsuarios(
      p.prisma,
      tareas.map((t: any) => String(t.finalizadaPorId ?? "")),
    );
    for (const t of tareas as any[]) {
      t.cerradoPor = t.finalizadaPorId ? (nombres.get(t.finalizadaPorId) ?? null) : null;
    }
  }

  // Sin preventivas en el informe, el cronograma no aporta nada.
  const usaCronograma =
    !opciones.filtros.tipos || opciones.filtros.tipos.includes("PREVENTIVA");
  const conjuntoIds = !usaCronograma
    ? []
    : p.conjuntoId
    ? [p.conjuntoId]
    : Array.from(
        new Set(
          tareas
            .map((t) => t.conjunto?.id)
            .filter((id): id is string => typeof id === "string" && id.length > 0),
        ),
      ).slice(0, MAX_CONJUNTOS_CRONOGRAMA);

  reportar(15, "Leyendo el cronograma del periodo");
  const meses = mesesDelRango(p.desde, p.hasta);
  const cronogramas: CronogramaInformeMes[] = [];
  for (const conjuntoId of conjuntoIds) {
    const servicio = new CronogramaService(p.prisma, conjuntoId);
    for (const { anio, mes } of meses) {
      try {
        const informe: any = await servicio.informeActividadJerarquico({
          anio,
          mes,
          borrador: false,
        });
        cronogramas.push({ conjuntoId, ubicaciones: informe.ubicaciones ?? [] });
      } catch (err) {
        // Sin cronograma el informe sigue: solo se omiten previstas/programadas.
        console.warn(
          `[informe-mensual] sin cronograma ${conjuntoId} ${anio}-${mes}:`,
          err instanceof Error ? err.message : err,
        );
      }
    }
  }

  let conjuntoNombre = "Todos los conjuntos";
  if (p.conjuntoId) {
    conjuntoNombre =
      tareas.find((t) => t.conjunto?.nombre)?.conjunto?.nombre ??
      (
        await p.prisma.conjunto.findFirst({
          where: { nit: p.conjuntoId, empresaId: p.empresaId },
          select: { nombre: true },
        })
      )?.nombre ??
      p.conjuntoId;
  }

  return construirInformeMensual(
    {
      conjuntoNombre,
      desde: p.desde,
      hasta: p.hasta,
      tareas,
      reemplazos,
      cronogramas,
    },
    opciones,
  );
}

/** Descarga todas las fotos que el informe va a imprimir, en paralelo. */
async function precargarFotos(
  informe: InformeMensual,
  reportar: ReportarProgreso,
): Promise<Map<string, FotoCargada | null>> {
  const raws = new Set<string>();
  for (const a of actividadesDelCuerpo(informe)) {
    for (const f of a.fotos) raws.add(f.raw);
  }
  const calidad = informe.opciones.fotos.calidad;
  const fotos = new Map<string, FotoCargada | null>();
  const total = raws.size;
  if (total === 0) return fotos;

  let listas = 0;
  await Promise.all(
    Array.from(raws).map((raw) =>
      limitarFotos(async () => {
        fotos.set(raw, await cargarFotoDrive(raw, calidad));
        listas += 1;
        reportar(
          20 + (listas / total) * 65,
          `Preparando fotos (${listas} de ${total})`,
        );
      }),
    ),
  );
  return fotos;
}

export function crearEjecutorInforme(p: ParametrosInforme): EjecutorInforme {
  return async ({ jobId, archivoDestino, reportar }) => {
    const opciones = p.opciones ?? opcionesPorDefecto();
    const informe = await recolectarDatos(p, opciones, reportar);
    const fotos = await precargarFotos(informe, reportar);
    const generadoPor = p.usuarioId
      ? ((await nombresDeUsuarios(p.prisma, [p.usuarioId])).get(p.usuarioId) ?? null)
      : null;

    reportar(90, "Armando el PDF");
    await renderizarInformeMensual(informe, {
      archivoDestino,
      cargarFoto: (raw) => fotos.get(raw),
      rolSolicitante: p.rolSolicitante,
      generadoPor,
      idInforme: jobId,
    });
    fotos.clear();

    const [anio, mes] = claveDia(p.desde).split("-");
    // Un informe filtrado no debe confundirse con el completo.
    const sufijo = informe.filtrado ? "_filtrado" : "";
    return {
      nombreArchivo: `Informe_mensual_${nombreArchivoSeguro(informe.conjuntoNombre)}_${anio}_${mes}${sufijo}.pdf`,
    };
  };
}
