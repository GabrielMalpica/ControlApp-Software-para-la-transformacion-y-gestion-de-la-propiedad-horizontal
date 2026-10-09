// Render del informe mensual de actividades con pdfkit. El estilo sigue la
// plantilla "Modelos_Informes_Fotograficos_CONTROL": barras oscuras con texto
// blanco, cajas claras y fotos grandes en columnas.
import fs from "fs";
import PDFDocument from "pdfkit";
import { INFORME_LOGO_JPEG_BASE64 } from "../utils/informeLogo";
import {
  claveDia,
  etiquetaFrecuencia,
  type ActividadInforme,
  type InformeMensual,
  type PuntualidadTarea,
} from "./InformeMensualModelo";
import type { OpcionesInforme } from "./InformeMensualOpciones";

/* --------------------------------- estilo ------------------------------- */

const INK = "#293438";
const SOFT = "#F5F7F7";
const LINE = "#D9D9D9";
const MUTED = "#5B6267";
const MUTED_2 = "#697277";
const GREEN = "#0B8F45";
const RED = "#B42318";
const WHITE = "#FFFFFF";

const PAGE_W = 612;
const PAGE_H = 792;
const MARGIN_X = 46;
const CONTENT_W = PAGE_W - MARGIN_X * 2;
const TOP = 78;
const BOTTOM = PAGE_H - 58;

const F_REG = "Helvetica";
const F_BOLD = "Helvetica-Bold";
const F_ITALIC = "Helvetica-Oblique";

const MESES = [
  "ene", "feb", "mar", "abr", "may", "jun",
  "jul", "ago", "sep", "oct", "nov", "dic",
];
const MESES_LARGO = [
  "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
  "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
];

const ETIQUETA_ESTADO: Record<string, string> = {
  ASIGNADA: "Asignadas",
  EN_PROCESO: "En proceso",
  COMPLETADA: "Completadas",
  APROBADA: "Aprobadas",
  PENDIENTE_APROBACION: "Pendientes de aprobación",
  RECHAZADA: "Rechazadas",
  NO_COMPLETADA: "No completadas",
  PENDIENTE_REPROGRAMACION: "Pendientes de reprogramación",
};

/** Estados que se resaltan en rojo en tablas y cajas. */
const ESTADOS_EN_ROJO = new Set(["NO_COMPLETADA", "RECHAZADA", "PENDIENTE_REPROGRAMACION"]);

const ETIQUETA_ESTADO_SINGULAR: Record<string, string> = {
  ASIGNADA: "Asignada",
  EN_PROCESO: "En proceso",
  COMPLETADA: "Completada",
  APROBADA: "Aprobada",
  PENDIENTE_APROBACION: "Pend. aprobación",
  RECHAZADA: "Rechazada",
  NO_COMPLETADA: "No completada",
  PENDIENTE_REPROGRAMACION: "Pend. reprogramación",
};

/* -------------------------------- textos -------------------------------- */

// Helvetica (fuente estandar del PDF) solo cubre WinAnsi: lo demas se
// sustituye para que nunca salgan simbolos rotos.
const EXTRA_WINANSI = new Set([
  0x2013, 0x2014, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2026, 0x20ac, 0x2122,
]);

export function limpiarTexto(value: unknown): string {
  const base = String(value ?? "")
    .normalize("NFC")
    .replace(/[→⇒]/g, "->")
    .replace(/≥/g, ">=")
    .replace(/≤/g, "<=")
    .replace(/\p{Zs}/gu, " ")
    .replace(/[\r\t]+/g, " ");
  let out = "";
  for (const ch of base) {
    const code = ch.codePointAt(0)!;
    if (code === 10 || (code >= 32 && code <= 0xff) || EXTRA_WINANSI.has(code)) {
      if (code >= 0x7f && code <= 0x9f) continue;
      out += ch;
    }
  }
  return out.replace(/ {2,}/g, " ").trim();
}

function recortar(value: string, max: number): string {
  const v = limpiarTexto(value);
  return v.length <= max ? v : `${v.slice(0, max - 1).trimEnd()}...`;
}

function fechaCorta(d: Date | null | undefined): string {
  if (!d) return "-";
  const [y, m, day] = claveDia(d).split("-").map(Number);
  return `${day} ${MESES[m - 1]} ${y}`;
}

const fmtHora = new Intl.DateTimeFormat("es-CO", {
  timeZone: "America/Bogota",
  hour: "2-digit",
  minute: "2-digit",
  hour12: false,
});

function fechaHora(d: Date): string {
  return `${fechaCorta(d)}, ${fmtHora.format(d)}`;
}

/** "3 jun 2026, 08:00 a 09:00", o con las dos fechas si son de dias distintos. */
function rangoFechaHora(inicio: Date, fin: Date): string {
  if (claveDia(inicio) === claveDia(fin)) {
    return `${fechaHora(inicio)} a ${fmtHora.format(fin)}`;
  }
  return `${fechaHora(inicio)}  a  ${fechaHora(fin)}`;
}

function tituloPeriodo(desde: Date, hasta: Date): string {
  const [y1, m1] = claveDia(desde).split("-").map(Number);
  const [y2, m2] = claveDia(hasta).split("-").map(Number);
  if (y1 === y2 && m1 === m2) return `${MESES_LARGO[m1 - 1]} ${y1}`;
  return `${fechaCorta(desde)} al ${fechaCorta(hasta)}`;
}

function listaCorta(items: string[], max = 4): string {
  if (items.length <= max) return items.join(", ");
  return `${items.slice(0, max).join(", ")} y ${items.length - max} más`;
}

function duracionTexto(min: number): string {
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h} h ${m} min` : `${h} h`;
}

const fmtDiaLargo = new Intl.DateTimeFormat("es-CO", {
  timeZone: "America/Bogota",
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
});

function fechaLarga(d: Date): string {
  return fmtDiaLargo.format(d).replace(",", "");
}

/** "Cerrada 3 jun 2026, 10:15 (a tiempo). Duración real 45 min de 1 h programados" */
function textoPuntualidad(p: PuntualidadTarea): string {
  if (!p.cierreReal) return "Sin cierre registrado.";
  let t = `Cerrada ${fechaHora(p.cierreReal)}`;
  if (p.diasRetraso === 0) {
    t += " (a tiempo)";
  } else if (p.diasRetraso != null) {
    t += ` (${p.diasRetraso} ${p.diasRetraso === 1 ? "día" : "días"} después de lo programado)`;
  }
  if (p.duracionRealMin != null) {
    t += `. Duración real ${duracionTexto(p.duracionRealMin)}`;
    if (p.duracionProgramadaMin != null) {
      t += ` de ${duracionTexto(p.duracionProgramadaMin)} programados`;
    }
  }
  return t;
}

const ETIQUETA_ORGANIZACION: Record<OpcionesInforme["organizacion"], string> = {
  ACTIVIDAD: "Por actividad",
  UBICACION: "Por ubicación",
  CRONOLOGICO: "Tarea por tarea (cronológico)",
};

const ETIQUETA_TAMANO: Record<OpcionesInforme["fotos"]["tamano"], string> = {
  AUTO: "automático",
  GRANDE: "grande (2 por fila)",
  MEDIANA: "mediano (3 por fila)",
  PEQUENA: "pequeño (4 por fila)",
};

const ETIQUETA_CALIDAD: Record<OpcionesInforme["fotos"]["calidad"], string> = {
  LIVIANA: "liviana",
  ESTANDAR: "estándar",
  ALTA: "alta",
};

/* --------------------------------- fotos -------------------------------- */

export type FotoCargada = { buffer: Buffer; width: number; height: number };

export type OpcionesRender = {
  archivoDestino: string;
  cargarFoto: (raw: string) => FotoCargada | null | undefined;
  generadoEn?: Date;
  /** Rol de quien pidió el informe; solo cambia cómo se etiquetan las
   * tareas CORRECTIVA en el texto ("actividad especial" para administrador). */
  rolSolicitante?: string;
  /** Nombre de quien pidió el informe (va en los parámetros de la portada). */
  generadoPor?: string | null;
  /** Id del trabajo: su versión corta va en la portada y en cada pie de página. */
  idInforme?: string;
};

type ColumnaTabla = {
  titulo: string;
  ancho: number;
  alinear?: "left" | "center" | "right";
};

type FilaTabla = {
  celdas: string[];
  colores?: Array<string | undefined>;
  negrita?: boolean;
};

/* -------------------------------- render -------------------------------- */

export function renderizarInformeMensual(
  informe: InformeMensual,
  opciones: OpcionesRender,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: "LETTER",
      margins: { top: 0, bottom: 0, left: 0, right: 0 },
      bufferPages: true,
      autoFirstPage: true,
      info: {
        Title: `Informe mensual de actividades - ${limpiarTexto(informe.conjuntoNombre)}`,
        Author: "CONTROL S.A.S.",
      },
    });
    const salida = fs.createWriteStream(opciones.archivoDestino);
    salida.on("finish", () => resolve());
    salida.on("error", reject);
    doc.on("error", reject);
    doc.pipe(salida);

    try {
      dibujar(doc, informe, opciones);
      doc.end();
    } catch (err) {
      doc.end();
      reject(err);
    }
  });
}

function dibujar(
  doc: PDFKit.PDFDocument,
  informe: InformeMensual,
  opciones: OpcionesRender,
) {
  const logo = Buffer.from(INFORME_LOGO_JPEG_BASE64, "base64");
  const op = informe.opciones;
  const campos = op.campos;
  const idCorto = String(opciones.idInforme ?? "")
    .replace(/-/g, "")
    .slice(0, 8)
    .toUpperCase();
  let y = TOP;
  // Modo medicion: recorre el mismo codigo de dibujo sin escribir nada, para
  // saber cuanto espacio necesita un bloque antes de decidir si cabe en la pagina.
  let seco = false;

  // El administrador del conjunto ve las tareas CORRECTIVA como "actividad
  // especial" en toda la app; el resto de roles sigue viendo "correctiva".
  // El tipo en base de datos no cambia, es solo una etiqueta del PDF.
  const esAdminSolicitante =
    (opciones.rolSolicitante ?? "").trim().toLowerCase() === "administrador";
  const etiquetaCorrSingular = esAdminSolicitante
    ? "actividad especial"
    : "correctiva";
  const etiquetaCorrPlural = esAdminSolicitante
    ? "actividades especiales"
    : "correctivas";
  const etiquetaTipo = (tipo: string) =>
    tipo === "PREVENTIVA"
      ? "Preventiva"
      : esAdminSolicitante
        ? "Act. especial"
        : "Correctiva";

  /* ------------------------- utilidades de dibujo ------------------------ */

  const texto = (
    value: string,
    x: number,
    yy: number,
    w: number,
    o: {
      size?: number;
      font?: string;
      color?: string;
      align?: "left" | "center" | "right";
      lineGap?: number;
    } = {},
  ): number => {
    const t = limpiarTexto(value);
    if (!t) return 0;
    doc
      .font(o.font ?? F_REG)
      .fontSize(o.size ?? 9)
      .fillColor(o.color ?? INK);
    const opts = { width: w, align: o.align ?? "left", lineGap: o.lineGap ?? 1.5 };
    const h = doc.heightOfString(t, opts);
    if (!seco) doc.text(t, x, yy, opts);
    return h;
  };

  const altoTexto = (
    value: string,
    w: number,
    o: { size?: number; font?: string; lineGap?: number } = {},
  ): number => {
    const t = limpiarTexto(value);
    if (!t) return 0;
    doc.font(o.font ?? F_REG).fontSize(o.size ?? 9);
    return doc.heightOfString(t, { width: w, lineGap: o.lineGap ?? 1.5 });
  };

  const rect = (
    x: number,
    yy: number,
    w: number,
    h: number,
    fill: string,
    stroke?: string,
  ) => {
    if (seco) return;
    doc.rect(x, yy, w, h);
    if (stroke) doc.fillAndStroke(fill, stroke);
    else doc.fill(fill);
    doc.lineWidth(0.6);
  };

  const encabezado = () => {
    doc.image(logo, MARGIN_X, 13, { fit: [36, 39] });
    texto("CONTROL S.A.S.", MARGIN_X + 46, 26, 260, {
      size: 13,
      font: F_BOLD,
    });
    texto(
      `Informe ${tituloPeriodo(informe.desde, informe.hasta)}`,
      PAGE_W - MARGIN_X - 260,
      28,
      260,
      { size: 10, color: MUTED, align: "right" },
    );
    doc
      .moveTo(MARGIN_X, 58)
      .lineTo(PAGE_W - MARGIN_X, 58)
      .lineWidth(0.8)
      .strokeColor(LINE)
      .stroke();
  };

  const nuevaPagina = () => {
    if (seco) return;
    doc.addPage();
    encabezado();
    y = TOP;
  };

  const asegurar = (alto: number) => {
    if (y + alto > BOTTOM) nuevaPagina();
  };

  /** Altura que ocupa lo que dibuja `fn`, sin dibujarlo. */
  const medir = (fn: () => void): number => {
    const y0 = y;
    seco = true;
    try {
      fn();
    } finally {
      seco = false;
    }
    const alto = y - y0;
    y = y0;
    return alto;
  };

  /** Marcador en el panel lateral del lector de PDF (apunta a la pagina actual). */
  let marcadorSeccion: PDFKit.PDFOutline | null = null;
  const marcador = (titulo: string, padre?: PDFKit.PDFOutline | null) => {
    if (seco) return null;
    const t = recortar(titulo, 90);
    if (!t) return null;
    return (padre ?? doc.outline).addItem(t);
  };

  /* ------------------------------- portada ------------------------------- */

  encabezado();
  marcador("Portada");

  y += texto(
    `INFORME MENSUAL   |   ${tituloPeriodo(informe.desde, informe.hasta).toUpperCase()}`,
    MARGIN_X,
    y,
    CONTENT_W,
    { size: 8.5, font: F_BOLD, color: MUTED_2 },
  );
  y += 6;
  y += texto(
    op.textos.titulo || "Reporte visual de actividades",
    MARGIN_X,
    y,
    CONTENT_W,
    { size: 22, font: F_BOLD },
  );
  y += 8;

  const colW = CONTENT_W / 2;
  const meta = (k: string, v: string, x: number, yy: number) => {
    doc.font(F_BOLD).fontSize(9.5);
    const kw = doc.widthOfString(`${limpiarTexto(k)}  `);
    texto(`${k}  `, x, yy, kw + 2, { size: 9.5, font: F_BOLD, color: MUTED });
    return texto(v, x + kw, yy, colW - kw - 8, { size: 9.5 });
  };
  const r = informe.resumen;
  const m1 = meta("Conjunto", recortar(informe.conjuntoNombre, 60), MARGIN_X, y);
  const m2 = meta(
    "Periodo",
    `${fechaCorta(informe.desde)} al ${fechaCorta(informe.hasta)}`,
    MARGIN_X + colW,
    y,
  );
  y += Math.max(m1, m2) + 5;
  const m3 = meta(
    "Generado",
    fechaHora(opciones.generadoEn ?? new Date()),
    MARGIN_X,
    y,
  );
  const m4 =
    op.organizacion === "CRONOLOGICO"
      ? meta(
          "Tareas",
          `${r.totalTareas} (${r.preventivas} preventivas, ${r.correctivas} ${etiquetaCorrPlural})`,
          MARGIN_X + colW,
          y,
        )
      : meta(
          "Actividades",
          `${informe.preventivas.length} preventivas, ${informe.correctivas.length} ${etiquetaCorrPlural}`,
          MARGIN_X + colW,
          y,
        );
  y += Math.max(m3, m4) + 14;

  // Tarjetas de resumen: barra oscura con la etiqueta y caja clara con la cifra.
  const tarjeta = (
    etiqueta: string,
    valor: string,
    nota: string,
    x: number,
    yy: number,
    w: number,
    colorValor = INK,
  ) => {
    rect(x, yy, w, 17, INK);
    texto(etiqueta, x, yy + 5, w, {
      size: 7.5,
      font: F_BOLD,
      color: WHITE,
      align: "center",
    });
    rect(x, yy + 17, w, 46, SOFT, LINE);
    texto(valor, x, yy + 24, w, {
      size: 19,
      font: F_BOLD,
      color: colorValor,
      align: "center",
    });
    texto(nota, x + 4, yy + 49, w - 8, {
      size: 7,
      color: MUTED_2,
      align: "center",
    });
  };

  if (op.secciones.resumen) {
    const gap = 10;
    const tw = (CONTENT_W - gap * 3) / 4;
    if (r.hayCronograma) {
      const cumplimiento =
        r.previstas > 0 ? Math.round((r.realizadas / r.previstas) * 100) : 0;
      tarjeta("PREVISTAS", String(r.previstas), "en el cronograma", MARGIN_X, y, tw);
      tarjeta(
        "PROGRAMADAS",
        `${r.programadas} / ${r.previstas}`,
        "de las previstas",
        MARGIN_X + (tw + gap),
        y,
        tw,
      );
      tarjeta(
        "REALIZADAS",
        `${r.realizadas} / ${r.programadas}`,
        "de las programadas",
        MARGIN_X + (tw + gap) * 2,
        y,
        tw,
      );
      tarjeta(
        "CUMPLIMIENTO",
        `${cumplimiento}%`,
        "realizadas sobre previstas",
        MARGIN_X + (tw + gap) * 3,
        y,
        tw,
        cumplimiento >= 90 ? GREEN : cumplimiento >= 70 ? INK : RED,
      );
      y += 63 + 10;
    }
    tarjeta("PREVENTIVAS", String(r.preventivas), "tareas registradas", MARGIN_X, y, tw);
    tarjeta(
      etiquetaCorrPlural.toUpperCase(),
      String(r.correctivas),
      "tareas registradas",
      MARGIN_X + (tw + gap),
      y,
      tw,
    );
    tarjeta(
      "REEMPLAZADAS",
      String(r.reemplazadas),
      `por ${etiquetaCorrPlural}`,
      MARGIN_X + (tw + gap) * 2,
      y,
      tw,
    );
    tarjeta(
      "NO COMPLETADAS",
      String(r.noCompletadas),
      "sin cerrar",
      MARGIN_X + (tw + gap) * 3,
      y,
      tw,
      r.noCompletadas > 0 ? RED : INK,
    );
    y += 63 + 12;

    if (r.porEstado.length > 0) {
      const linea = r.porEstado
        .map((e) => `${ETIQUETA_ESTADO[e.estado] ?? e.estado}: ${e.cantidad}`)
        .join("   |   ");
      y += texto("Estado de las tareas  ", MARGIN_X, y, CONTENT_W, {
        size: 8,
        font: F_BOLD,
        color: MUTED,
      });
      y += texto(linea, MARGIN_X, y + 1, CONTENT_W, { size: 8.5, color: INK });
      y += 14;
    }
  }

  /* --------------------------- bloques reutilizables --------------------- */

  const barraSeccion = (
    titulo: string,
    cantidad: number,
    primero?: ActividadInforme,
  ) => {
    // La barra nunca queda sola al final de una pagina: viaja con el primer item.
    asegurar(22 + 12 + (primero ? altoMinimoActividad(primero) : 40));
    marcadorSeccion = marcador(titulo);
    rect(MARGIN_X, y, CONTENT_W, 22, INK);
    texto(titulo, MARGIN_X + 10, y + 7, CONTENT_W - 80, {
      size: 10,
      font: F_BOLD,
      color: WHITE,
    });
    texto(String(cantidad), MARGIN_X, y + 7, CONTENT_W - 10, {
      size: 10,
      font: F_BOLD,
      color: WHITE,
      align: "right",
    });
    y += 22 + 12;
  };

  const notaVacia = (mensaje: string) => {
    asegurar(30);
    y += texto(mensaje, MARGIN_X, y, CONTENT_W, {
      size: 9,
      font: F_ITALIC,
      color: MUTED,
    });
    y += 14;
  };

  const nota = (mensaje: string) => {
    y += texto(mensaje, MARGIN_X, y, CONTENT_W, {
      size: 7.5,
      font: F_ITALIC,
      color: MUTED_2,
    });
    y += 8;
  };

  const caja = (
    lineas: Array<{ etiqueta?: string; texto: string; color?: string }>,
    acento = INK,
  ) => {
    const padX = 10;
    const innerW = CONTENT_W - padX * 2 - 4;
    const partes = lineas.map((l) => {
      const t = l.etiqueta ? `${l.etiqueta}  ${l.texto}` : l.texto;
      return { ...l, completo: t, alto: altoTexto(t, innerW, { size: 8.5 }) };
    });
    const alto = partes.reduce((acc, p) => acc + p.alto + 3, 0) + 10;
    asegurar(alto + 6);
    rect(MARGIN_X, y, CONTENT_W, alto, SOFT);
    rect(MARGIN_X, y, 3, alto, acento);
    let yy = y + 6;
    for (const p of partes) {
      if (p.etiqueta) {
        doc.font(F_BOLD).fontSize(8.5);
        const ew = doc.widthOfString(`${limpiarTexto(p.etiqueta)}  `);
        texto(`${p.etiqueta}  `, MARGIN_X + padX + 4, yy, ew + 2, {
          size: 8.5,
          font: F_BOLD,
          color: MUTED,
        });
        const h = texto(p.texto, MARGIN_X + padX + 4 + ew, yy, innerW - ew, {
          size: 8.5,
          color: p.color ?? INK,
        });
        yy += Math.max(h, 10) + 3;
      } else {
        const h = texto(p.texto, MARGIN_X + padX + 4, yy, innerW, {
          size: 8.5,
          color: p.color ?? INK,
        });
        yy += Math.max(h, 10) + 3;
      }
    }
    y += alto + 6;
  };

  /** Tabla con encabezado oscuro que se repite al cambiar de pagina. */
  const tabla = (columnas: ColumnaTabla[], filas: FilaTabla[]) => {
    const padX = 4;
    const padY = 3.5;
    const size = 7.2;
    const anchos = columnas.map((c) => c.ancho * CONTENT_W);
    const xs: number[] = [];
    let acc = MARGIN_X;
    for (const w of anchos) {
      xs.push(acc);
      acc += w;
    }
    const altoFila = (celdas: string[], font: string) =>
      Math.max(
        10,
        ...celdas.map((c, j) =>
          altoTexto(c, anchos[j] - padX * 2, { size, font, lineGap: 1 }),
        ),
      ) +
      padY * 2;
    const titulos = columnas.map((c) => c.titulo);
    const altoCabecera = altoFila(titulos, F_BOLD);
    const cabecera = () => {
      rect(MARGIN_X, y, CONTENT_W, altoCabecera, INK);
      columnas.forEach((c, j) =>
        texto(c.titulo, xs[j] + padX, y + padY, anchos[j] - padX * 2, {
          size,
          font: F_BOLD,
          color: WHITE,
          align: c.alinear,
          lineGap: 1,
        }),
      );
      y += altoCabecera;
    };

    const primera = filas[0]
      ? altoFila(filas[0].celdas, filas[0].negrita ? F_BOLD : F_REG)
      : 0;
    asegurar(altoCabecera + primera);
    cabecera();
    filas.forEach((fila, i) => {
      const font = fila.negrita ? F_BOLD : F_REG;
      const h = altoFila(fila.celdas, font);
      if (y + h > BOTTOM) {
        nuevaPagina();
        cabecera();
      }
      if (fila.negrita) rect(MARGIN_X, y, CONTENT_W, h, "#E9EDEE");
      else if (i % 2 === 1) rect(MARGIN_X, y, CONTENT_W, h, SOFT);
      fila.celdas.forEach((c, j) =>
        texto(c, xs[j] + padX, y + padY, anchos[j] - padX * 2, {
          size,
          font,
          color: fila.colores?.[j] ?? INK,
          align: columnas[j].alinear,
          lineGap: 1,
        }),
      );
      if (!seco) {
        doc
          .moveTo(MARGIN_X, y + h)
          .lineTo(MARGIN_X + CONTENT_W, y + h)
          .lineWidth(0.4)
          .strokeColor(LINE)
          .stroke();
      }
      y += h;
    });
    y += 10;
  };

  /* ---------------------- parametros y observaciones --------------------- */

  const describirFiltros = (): string => {
    const f = op.filtros;
    const partes: string[] = [];
    if (f.tipos) {
      partes.push(
        `Tipo: ${f.tipos.map((t) => (t === "PREVENTIVA" ? "preventivas" : etiquetaCorrPlural)).join(", ")}`,
      );
    }
    if (f.estados) {
      partes.push(
        `Estados: ${f.estados.map((e) => (ETIQUETA_ESTADO[e] ?? e).toLowerCase()).join(", ")}`,
      );
    }
    if (f.frecuencias) {
      partes.push(
        `Frecuencias: ${f.frecuencias.map((x) => (etiquetaFrecuencia(x) ?? x).toLowerCase()).join(", ")}`,
      );
    }
    if (f.ubicaciones) partes.push(`Ubicaciones: ${listaCorta(f.ubicaciones, 6)}`);
    if (f.soloConEvidencia) partes.push("solo tareas con evidencia");
    return partes.length
      ? partes.join("  |  ")
      : "Ninguno: incluye todas las tareas del periodo.";
  };

  const describirFotos = (): string => {
    const fo = op.fotos;
    if (!fo.incluir) return "No incluidas en este informe.";
    const porTarea = fo.porTarea
      ? `hasta ${fo.porTarea} por tarea`
      : "todas las de cada tarea";
    const registros =
      fo.registrosPorActividad === "AUTO"
        ? "registros automáticos (en diarias, 3 repartidos en el periodo)"
        : fo.registrosPorActividad === "TODOS"
          ? "todos los registros con foto"
          : `${fo.registrosPorActividad} registros por actividad, repartidos en el periodo`;
    let t = `${informe.fotos.incluidas} en total; ${porTarea}; ${registros}; tamaño ${ETIQUETA_TAMANO[fo.tamano]}; calidad ${ETIQUETA_CALIDAD[fo.calidad]}.`;
    if (informe.fotos.omitidasPorLimite > 0) {
      t += ` Se omitieron ${informe.fotos.omitidasPorLimite} fotos para no superar el límite de ${informe.fotos.limite} por informe; quedan disponibles en la aplicación.`;
    }
    return t;
  };

  y += texto("Parámetros del informe", MARGIN_X, y, CONTENT_W, {
    size: 8,
    font: F_BOLD,
    color: MUTED,
  });
  y += 3;
  caja(
    [
      { etiqueta: "Organización", texto: ETIQUETA_ORGANIZACION[op.organizacion] },
      {
        etiqueta: "Filtros",
        texto: describirFiltros(),
        color: informe.filtrado ? RED : undefined,
      },
      { etiqueta: "Fotos", texto: describirFotos() },
      ...(opciones.generadoPor
        ? [{ etiqueta: "Generado por", texto: opciones.generadoPor }]
        : []),
      ...(idCorto ? [{ etiqueta: "ID del informe", texto: idCorto }] : []),
    ],
    informe.filtrado ? RED : MUTED_2,
  );

  if (op.textos.observacionesGenerales) {
    y += 4;
    y += texto("Observaciones generales", MARGIN_X, y, CONTENT_W, {
      size: 8,
      font: F_BOLD,
      color: MUTED,
    });
    y += 3;
    caja([{ texto: op.textos.observacionesGenerales }], GREEN);
  }
  y += 8;

  /* --------------------------- bloques de actividad ---------------------- */

  const estadisticas = (a: ActividadInforme) => {
    const cajas: Array<{
      etiqueta: string;
      valor: string;
      nota: string;
      progreso?: number;
      colorValor?: string;
    }> = [];
    if (a.tipo === "PREVENTIVA") {
      if (a.previstas != null && a.programadas != null) {
        cajas.push({
          etiqueta: "PROGRAMADAS",
          valor: `${a.programadas} / ${a.previstas}`,
          nota: `de las ${a.previstas} previstas del periodo`,
          progreso: a.previstas > 0 ? a.programadas / a.previstas : 0,
        });
        cajas.push({
          etiqueta: "REALIZADAS",
          valor: `${a.realizadas} / ${a.baseRealizadas}`,
          nota: `de las ${a.baseRealizadas} programadas`,
          progreso: a.baseRealizadas > 0 ? a.realizadas / a.baseRealizadas : 0,
        });
      } else {
        cajas.push({
          etiqueta: "REGISTROS",
          valor: String(a.registros),
          nota: "tareas en el periodo",
        });
        cajas.push({
          etiqueta: "REALIZADAS",
          valor: `${a.realizadas} / ${a.baseRealizadas}`,
          nota: "de las registradas",
          progreso: a.baseRealizadas > 0 ? a.realizadas / a.baseRealizadas : 0,
        });
      }
      if (a.noCompletadas > 0) {
        cajas.push({
          etiqueta: "NO COMPLETADAS",
          valor: String(a.noCompletadas),
          nota: "sin cerrar",
          colorValor: RED,
        });
      }
    }
    if (cajas.length === 0) return;

    const gapC = 10;
    const w = Math.min(190, (CONTENT_W - gapC * (cajas.length - 1)) / cajas.length);
    cajas.forEach((c, i) => {
      const x = MARGIN_X + i * (w + gapC);
      rect(x, y, w, 40, SOFT, LINE);
      texto(c.etiqueta, x + 8, y + 5, w - 16, {
        size: 6.8,
        font: F_BOLD,
        color: MUTED_2,
      });
      doc.font(F_BOLD).fontSize(14);
      const vw = doc.widthOfString(limpiarTexto(c.valor));
      texto(c.valor, x + 8, y + 14, vw + 4, {
        size: 14,
        font: F_BOLD,
        color: c.colorValor ?? INK,
      });
      texto(c.nota, x + 8 + vw + 6, y + 20, w - vw - 22, {
        size: 6.8,
        color: MUTED_2,
      });
      if (c.progreso != null) {
        rect(x + 8, y + 33, w - 16, 3, LINE);
        const pct = Math.max(0, Math.min(1, c.progreso));
        if (pct > 0) rect(x + 8, y + 33, (w - 16) * pct, 3, GREEN);
      }
    });
    y += 40 + 8;
  };

  const encabezadoActividad = (
    a: ActividadInforme,
    numero: number,
    continuacion: boolean,
  ) => {
    const numTxt = String(numero).padStart(2, "0");
    const titulo = `${recortar(a.titulo, 150)}${continuacion ? " (continuación)" : ""}`;
    const anchoNum = 26;
    const chipTxt = a.frecuenciaEtiqueta
      ? a.frecuenciaEtiqueta.toUpperCase()
      : a.tipo === "CORRECTIVA"
        ? etiquetaCorrSingular.toUpperCase()
        : "";
    doc.font(F_BOLD).fontSize(7.5);
    const chipW = chipTxt ? doc.widthOfString(chipTxt) + 16 : 0;
    const anchoTitulo = CONTENT_W - anchoNum - chipW - (chipW ? 10 : 0);

    texto(numTxt, MARGIN_X, y, anchoNum, {
      size: 15,
      font: F_BOLD,
      color: GREEN,
    });
    const h = texto(titulo, MARGIN_X + anchoNum, y + 1, anchoTitulo, {
      size: 12,
      font: F_BOLD,
    });
    if (chipTxt) {
      const cx = PAGE_W - MARGIN_X - chipW;
      rect(cx, y + 1, chipW, 15, INK);
      texto(chipTxt, cx, y + 5, chipW, {
        size: 7.5,
        font: F_BOLD,
        color: WHITE,
        align: "center",
      });
    }
    y += Math.max(h + 2, 18);

    const donde = campos.ubicacion
      ? [a.conjunto, a.ubicacion, a.elemento]
          .map((v) => limpiarTexto(v))
          .filter(Boolean)
          .join("  |  ")
      : "";
    if (donde) {
      y += texto(recortar(donde, 190), MARGIN_X + anchoNum, y, CONTENT_W - anchoNum, {
        size: 8.5,
        color: MUTED,
      });
    }
    y += 6;
  };

  const layoutFotos = (total: number) => {
    const tamano = op.fotos.tamano;
    const cols =
      tamano === "GRANDE"
        ? Math.min(2, Math.max(1, total))
        : tamano === "MEDIANA"
          ? 3
          : tamano === "PEQUENA"
            ? 4
            : total === 1
              ? 1
              : total === 2
                ? 2
                : 3;
    const gapF = 10;
    const cellW = cols === 1 ? 300 : (CONTENT_W - gapF * (cols - 1)) / cols;
    const imgH = cols === 1 ? 225 : cols === 2 ? cellW * 0.75 : cellW;
    const barH = 16;
    const capH = 13;
    return { cols, gapF, cellW, imgH, barH, capH, filaH: barH + imgH + capH };
  };

  const dibujarFotos = (a: ActividadInforme, numero: number) => {
    if (!op.fotos.incluir) return;
    if (a.fotos.length === 0) {
      asegurar(36);
      rect(MARGIN_X, y, CONTENT_W, 28, SOFT, LINE);
      texto("Sin evidencia adjunta", MARGIN_X, y + 9, CONTENT_W, {
        size: 9,
        font: F_ITALIC,
        color: MUTED,
        align: "center",
      });
      y += 28 + 10;
      return;
    }

    const total = a.fotos.length;
    const { cols, gapF, cellW, imgH, barH, filaH } = layoutFotos(total);
    const pequena = cols >= 4;

    for (let i = 0; i < total; i += cols) {
      if (y + filaH > BOTTOM) {
        nuevaPagina();
        encabezadoActividad(a, numero, true);
      }
      const fila = a.fotos.slice(i, i + cols);
      fila.forEach((foto, j) => {
        const x = MARGIN_X + j * (cellW + gapF);
        rect(x, y, cellW, barH, INK);
        texto(
          `${String(i + j + 1).padStart(2, "0")}  EVIDENCIA`,
          x,
          y + 4.5,
          cellW,
          { size: pequena ? 7 : 8, font: F_BOLD, color: WHITE, align: "center" },
        );
        rect(x, y + barH, cellW, imgH, SOFT, LINE);
        const cargada = opciones.cargarFoto(foto.raw);
        if (cargada) {
          try {
            doc.image(cargada.buffer, x + 2, y + barH + 2, {
              fit: [cellW - 4, imgH - 4],
              align: "center",
              valign: "center",
            });
          } catch {
            texto("Imagen no disponible", x, y + barH + imgH / 2 - 5, cellW, {
              size: 8,
              color: MUTED,
              align: "center",
            });
          }
        } else {
          texto("Imagen no disponible", x, y + barH + imgH / 2 - 5, cellW, {
            size: 8,
            color: MUTED,
            align: "center",
          });
        }
        const pie = campos.numerosTarea
          ? `Tarea #${foto.tareaId}  |  ${fechaHora(foto.fecha)}`
          : fechaHora(foto.fecha);
        texto(pie, x, y + barH + imgH + 3, cellW, {
          size: pequena ? 6.2 : 7,
          color: MUTED_2,
          align: "center",
        });
      });
      y += filaH + 8;
    }

    if (a.fotosOmitidas > 0) {
      const n = a.tareasConFoto;
      const mensaje =
        a.esDiaria && op.fotos.registrosPorActividad === "AUTO"
          ? `Actividad diaria: se muestran ${a.fotos.length} evidencias representativas de ${n} registros con foto (${a.fotosTotales} fotos en total). El resto queda disponible en la aplicación.`
          : `Se muestran ${a.fotos.length} de ${a.fotosTotales} fotos (${n} ${n === 1 ? "registro" : "registros"} con foto). El resto queda disponible en la aplicación.`;
      asegurar(24);
      y += texto(mensaje, MARGIN_X, y, CONTENT_W, {
        size: 8,
        font: F_ITALIC,
        color: MUTED,
      });
      y += 6;
    }
  };

  const responsables = (a: ActividadInforme) =>
    [
      a.supervisores.length ? `Supervisor: ${a.supervisores.join(", ")}` : "",
      a.operarios.length ? `Operarios: ${listaCorta(a.operarios, 5)}` : "",
    ]
      .filter(Boolean)
      .join("  |  ");

  const cabeceraActividad = (a: ActividadInforme, numero: number) => {
    encabezadoActividad(a, numero, false);
    // Una sola tarea no tiene cifras de actividad que mostrar.
    if (campos.cifras && !a.tarea) estadisticas(a);

    const filas: Array<{ etiqueta: string; texto: string; color?: string }> = [];
    if (a.tarea) {
      const t = a.tarea;
      const p = t.puntualidad;
      if (campos.numerosTarea) filas.push({ etiqueta: "Tarea", texto: `#${t.id}` });
      if (campos.fechas) {
        filas.push({
          etiqueta: "Fecha",
          texto: rangoFechaHora(p.programadaInicio, p.programadaFin),
        });
      }
      if (campos.estado) {
        filas.push({
          etiqueta: "Estado",
          texto: ETIQUETA_ESTADO_SINGULAR[t.estado] ?? t.estado,
          color: ESTADOS_EN_ROJO.has(t.estado) ? RED : undefined,
        });
        if (t.motivoNoCompletada) {
          filas.push({ etiqueta: "Motivo", texto: recortar(t.motivoNoCompletada, 260) });
        }
      }
      if (campos.puntualidad) {
        filas.push({
          etiqueta: "Cierre",
          texto: textoPuntualidad(p),
          color: p.diasRetraso != null && p.diasRetraso > 0 ? RED : undefined,
        });
      }
    } else if (campos.fechas && a.inicio && a.fin) {
      filas.push({
        etiqueta: "Periodo",
        texto: `${fechaCorta(a.inicio)} al ${fechaCorta(a.fin)}`,
      });
    }
    if (campos.responsables && (a.operarios.length || a.supervisores.length)) {
      filas.push({ etiqueta: "Responsables", texto: responsables(a) });
    }
    if (!a.tarea) {
      if (campos.numerosTarea && a.ids.length > 0 && a.ids.length <= 6) {
        filas.push({
          etiqueta: "Tareas",
          texto: a.ids.map((id) => `#${id}`).join(", "),
        });
      } else if (campos.numerosTarea && a.ids.length > 6) {
        filas.push({ etiqueta: "Tareas", texto: `${a.ids.length} registros` });
      }
      if (campos.estado && a.estados.length > 0) {
        filas.push({
          etiqueta: "Estados",
          texto: a.estados
            .map((e) => `${e.cantidad} ${(ETIQUETA_ESTADO[e.estado] ?? e.estado).toLowerCase()}`)
            .join(", "),
        });
      }
      if (campos.puntualidad && a.puntualidad.cerradas > 0) {
        const pu = a.puntualidad;
        filas.push({
          etiqueta: "Puntualidad",
          texto: `${pu.aTiempo} de ${pu.cerradas} cerradas el día programado${pu.conRetraso ? ` (${pu.conRetraso} con retraso)` : ""}`,
          color: pu.conRetraso > 0 ? RED : undefined,
        });
      }
    }
    if (campos.cerradoPor && a.cerradoPor.length) {
      filas.push({ etiqueta: "Cerrada por", texto: listaCorta(a.cerradoPor, 4) });
    }
    if (campos.motivoRechazo) {
      for (const m of a.motivosRechazo) {
        filas.push({ etiqueta: "Rechazo", texto: recortar(m, 220), color: RED });
      }
    }
    if (!op.fotos.incluir && a.fotosTotales > 0) {
      filas.push({
        etiqueta: "Evidencias",
        texto: `${a.fotosTotales} ${a.fotosTotales === 1 ? "foto registrada" : "fotos registradas"} en la aplicación`,
      });
    }
    if (filas.length) caja(filas);

    const recursos: Array<{ etiqueta: string; texto: string }> = [];
    if (campos.insumos && a.recursos.insumos) {
      recursos.push({ etiqueta: "Insumos", texto: a.recursos.insumos });
    }
    if (campos.maquinaria && a.recursos.maquinaria) {
      recursos.push({ etiqueta: "Maquinaria", texto: a.recursos.maquinaria });
    }
    if (campos.herramientas && a.recursos.herramientas) {
      recursos.push({ etiqueta: "Herramientas", texto: a.recursos.herramientas });
    }
    if (recursos.length) caja(recursos);

    if (campos.observaciones && a.observaciones.length) {
      caja(
        a.observaciones.map((o) => ({
          etiqueta: "Observación",
          texto: recortar(o, 260),
        })),
      );
    }

    if (campos.reemplazos && a.tipo === "CORRECTIVA" && a.reemplazaA.length > 0) {
      caja(
        a.reemplazaA.slice(0, 6).flatMap((rep) => [
          {
            etiqueta: "Reemplazó a",
            texto: `#${rep.tareaId}${rep.descripcion ? `  ${recortar(rep.descripcion, 110)}` : ""}`,
          },
          { etiqueta: "Motivo", texto: recortar(rep.motivo, 260) },
        ]),
        GREEN,
      );
    }

    if (campos.reemplazos && a.tipo === "PREVENTIVA" && a.reemplazadas.length > 0) {
      caja(
        a.reemplazadas.slice(0, 6).flatMap((rep) => [
          {
            etiqueta: "Reemplazada",
            texto: `#${rep.tareaId}  por  ${
              rep.porTareaId != null
                ? `#${rep.porTareaId}${rep.porDescripcion ? `  ${recortar(rep.porDescripcion, 100)}` : ""}`
                : "otra tarea"
            }`,
          },
          { etiqueta: "Motivo", texto: recortar(rep.motivo, 260) },
        ]),
        RED,
      );
    }
  };

  /** Lo minimo que debe caber junto: cabecera + primera fila de fotos (o el aviso). */
  const altoMinimoActividad = (a: ActividadInforme): number => {
    const cabecera = medir(() => cabeceraActividad(a, 1));
    if (!op.fotos.incluir) return cabecera + 8;
    return (
      cabecera + (a.fotos.length > 0 ? layoutFotos(a.fotos.length).filaH : 38) + 8
    );
  };

  const dibujarActividad = (a: ActividadInforme, numero: number) => {
    // La cabecera y la primera fila de fotos nunca se separan entre paginas.
    asegurar(altoMinimoActividad(a));
    marcador(`${String(numero).padStart(2, "0")} ${a.titulo}`, marcadorSeccion);
    cabeceraActividad(a, numero);
    dibujarFotos(a, numero);
    y += 8;
  };

  /* ---------------------------- cumplimiento ----------------------------- */

  if (op.secciones.cumplimiento) {
    barraSeccion("CUMPLIMIENTO DEL CRONOGRAMA", informe.cumplimiento.length);
    if (informe.cumplimiento.length === 0) {
      notaVacia("No hay actividades preventivas para medir en el periodo.");
    } else {
      const filas: FilaTabla[] = informe.cumplimiento.map((c) => ({
        celdas: [
          recortar(c.titulo, 110),
          c.frecuencia ?? "-",
          recortar(c.ubicacion ?? "-", 60),
          c.previstas != null ? String(c.previstas) : "-",
          c.programadas != null ? String(c.programadas) : "-",
          c.previstas != null ? String(c.realizadas) : `${c.realizadas} de ${c.base}`,
          c.porcentaje != null ? `${c.porcentaje}%` : "-",
        ],
        colores: [
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          c.porcentaje == null ? undefined : c.porcentaje >= 90 ? GREEN : c.porcentaje >= 70 ? INK : RED,
        ],
      }));
      // Las actividades sin cronograma se miden sobre sus registros: el total
      // muestra "realizadas de base" para no mezclar bases distintas.
      const totalRealizadas = informe.cumplimiento.reduce((acc, c) => acc + c.realizadas, 0);
      const totalBase = informe.cumplimiento.reduce((acc, c) => acc + c.base, 0);
      const conCronograma = informe.cumplimiento.filter((c) => c.previstas != null);
      const hayLibres = conCronograma.length < informe.cumplimiento.length;
      filas.push({
        negrita: true,
        celdas: [
          "TOTAL",
          "",
          "",
          conCronograma.length
            ? String(conCronograma.reduce((acc, c) => acc + (c.previstas ?? 0), 0))
            : "-",
          conCronograma.length
            ? String(conCronograma.reduce((acc, c) => acc + (c.programadas ?? 0), 0))
            : "-",
          hayLibres ? `${totalRealizadas} de ${totalBase}` : String(totalRealizadas),
          totalBase > 0 ? `${Math.round((totalRealizadas / totalBase) * 100)}%` : "-",
        ],
      });
      tabla(
        [
          { titulo: "Actividad", ancho: 0.31 },
          { titulo: "Frecuencia", ancho: 0.1 },
          { titulo: "Ubicación", ancho: 0.16 },
          { titulo: "Previstas", ancho: 0.1, alinear: "right" },
          { titulo: "Programadas", ancho: 0.13, alinear: "right" },
          { titulo: "Realizadas", ancho: 0.11, alinear: "right" },
          { titulo: "Cumpl.", ancho: 0.09, alinear: "right" },
        ],
        filas,
      );
      nota(
        "Realizadas: fechas del cronograma con todas sus tareas cerradas. Cumplimiento: realizadas sobre previstas. Sin cronograma se mide sobre las tareas registradas.",
      );
    }
    y += 4;
  }

  /* ------------------------------- detalle ------------------------------- */

  if (op.secciones.detalle) {
    const vacio = informe.filtrado
      ? "para los filtros elegidos."
      : "para el periodo seleccionado.";
    if (informe.secciones.length === 0) {
      barraSeccion("DETALLE DE TAREAS", 0);
      notaVacia(`No hay tareas ${vacio}`);
    }
    for (const s of informe.secciones) {
      let titulo: string;
      let mensajeVacio: string;
      if (s.tipo === "PREVENTIVAS") {
        titulo = "TAREAS PREVENTIVAS";
        mensajeVacio = `No hay tareas preventivas ${vacio}`;
      } else if (s.tipo === "CORRECTIVAS") {
        titulo = `TAREAS ${etiquetaCorrPlural.toUpperCase()}`;
        mensajeVacio = informe.filtrado
          ? `No hay tareas ${etiquetaCorrPlural} para los filtros elegidos.`
          : `No se registraron tareas ${etiquetaCorrPlural} en el periodo.`;
      } else if (s.tipo === "UBICACION") {
        titulo = `UBICACIÓN: ${recortar(s.titulo, 70).toUpperCase()}`;
        mensajeVacio = `No hay tareas ${vacio}`;
      } else {
        titulo = fechaLarga(s.fecha).toUpperCase();
        mensajeVacio = `No hay tareas ${vacio}`;
      }
      barraSeccion(titulo, s.actividades.length, s.actividades[0]);
      if (s.actividades.length === 0) notaVacia(mensajeVacio);
      s.actividades.forEach((a, i) => dibujarActividad(a, i + 1));
      y += 4;
    }
  }

  /* ------------------------------ novedades ------------------------------ */

  if (op.secciones.novedades) {
    barraSeccion("NOVEDADES Y PENDIENTES", informe.novedades.length);
    if (informe.novedades.length === 0) {
      notaVacia("No hay tareas no completadas, rechazadas ni vencidas en el periodo.");
    } else {
      const conNumero = campos.numerosTarea;
      const columnas: ColumnaTabla[] = [
        ...(conNumero ? [{ titulo: "#", ancho: 0.07 }] : []),
        { titulo: "Fecha", ancho: 0.11 },
        { titulo: "Actividad", ancho: conNumero ? 0.27 : 0.34 },
        { titulo: "Ubicación", ancho: 0.14 },
        { titulo: "Novedad", ancho: 0.14 },
        { titulo: "Motivo", ancho: 0.27 },
      ];
      tabla(
        columnas,
        informe.novedades.map((n) => {
          const novedad =
            n.novedad === "VENCIDA"
              ? "Vencida sin cierre"
              : (ETIQUETA_ESTADO_SINGULAR[n.novedad] ?? n.novedad);
          const celdas = [
            ...(conNumero ? [`#${n.tareaId}`] : []),
            fechaCorta(n.fecha),
            `${recortar(n.descripcion, 110)}${n.tipo !== "PREVENTIVA" ? ` (${etiquetaCorrSingular})` : ""}`,
            recortar(n.ubicacion ?? "-", 60),
            novedad,
            recortar(n.motivo, 200),
          ];
          const colores: Array<string | undefined> = celdas.map(() => undefined);
          colores[conNumero ? 4 : 3] = RED;
          return { celdas, colores };
        }),
      );
    }
    y += 4;
  }

  /* ----------------------------- reemplazadas ---------------------------- */

  if (op.secciones.reemplazadas) {
    barraSeccion("TAREAS REEMPLAZADAS", informe.reemplazadas.length);
    if (informe.reemplazadas.length === 0) {
      notaVacia("Ninguna tarea fue reemplazada en el periodo.");
    }
    informe.reemplazadas.forEach((rep, i) => {
      const lineas = [
        {
          etiqueta: "Reemplazada por",
          texto:
            rep.porTareaId != null
              ? `#${rep.porTareaId}${rep.porDescripcion ? `  ${recortar(rep.porDescripcion, 120)}` : ""}`
              : "otra tarea",
        },
        { etiqueta: "Motivo", texto: recortar(rep.motivo, 300) },
        ...(rep.fecha ? [{ etiqueta: "Fecha", texto: fechaHora(rep.fecha) }] : []),
        ...(rep.estadoActual
          ? [
              {
                etiqueta: "Estado actual",
                texto:
                  ETIQUETA_ESTADO_SINGULAR[rep.estadoActual] ?? rep.estadoActual,
              },
            ]
          : []),
        { texto: "Sin evidencia adjunta" },
      ];
      asegurar(110);
      const numTxt = String(i + 1).padStart(2, "0");
      texto(numTxt, MARGIN_X, y, 26, { size: 15, font: F_BOLD, color: GREEN });
      const h = texto(
        `${campos.numerosTarea ? `#${rep.tareaId}  ` : ""}${recortar(rep.descripcion, 150)}`,
        MARGIN_X + 26,
        y + 1,
        CONTENT_W - 26,
        { size: 12, font: F_BOLD },
      );
      y += Math.max(h + 2, 18) + 4;
      caja(lineas, RED);
      y += 6;
    });
  }

  /* ----------------------- consolidado de recursos ----------------------- */

  if (op.secciones.consolidadoRecursos) {
    const c = informe.consolidado;
    barraSeccion(
      "CONSOLIDADO DE RECURSOS",
      c.insumos.length + c.maquinaria.length + c.herramientas.length,
    );
    const cantidad = (n: number) =>
      Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/\.?0+$/, "");
    const subtitulo = (t: string) => {
      asegurar(40);
      y += texto(t, MARGIN_X, y, CONTENT_W, { size: 9, font: F_BOLD, color: MUTED });
      y += 4;
    };
    if (!c.insumos.length && !c.maquinaria.length && !c.herramientas.length) {
      notaVacia("No se registraron insumos, maquinaria ni herramientas en el periodo.");
    }
    if (c.insumos.length) {
      subtitulo("Insumos usados");
      tabla(
        [
          { titulo: "Insumo", ancho: 0.52 },
          { titulo: "Cantidad", ancho: 0.16, alinear: "right" },
          { titulo: "Unidad", ancho: 0.16 },
          { titulo: "Tareas", ancho: 0.16, alinear: "right" },
        ],
        c.insumos.map((r) => ({
          celdas: [recortar(r.nombre, 120), cantidad(r.cantidad), r.unidad || "-", String(r.tareas)],
        })),
      );
    }
    if (c.maquinaria.length) {
      subtitulo("Maquinaria");
      tabla(
        [
          { titulo: "Equipo", ancho: 0.6 },
          { titulo: "Usos", ancho: 0.2, alinear: "right" },
          { titulo: "Tareas", ancho: 0.2, alinear: "right" },
        ],
        c.maquinaria.map((r) => ({
          celdas: [recortar(r.nombre, 120), String(r.cantidad), String(r.tareas)],
        })),
      );
    }
    if (c.herramientas.length) {
      subtitulo("Herramientas");
      tabla(
        [
          { titulo: "Herramienta", ancho: 0.52 },
          { titulo: "Cantidad", ancho: 0.16, alinear: "right" },
          { titulo: "Unidad", ancho: 0.16 },
          { titulo: "Tareas", ancho: 0.16, alinear: "right" },
        ],
        c.herramientas.map((r) => ({
          celdas: [recortar(r.nombre, 120), cantidad(r.cantidad), r.unidad || "-", String(r.tareas)],
        })),
      );
    }
    y += 4;
  }

  /* --------------------------------- anexo ------------------------------- */

  if (op.secciones.anexoTareas) {
    barraSeccion("ANEXO: LISTADO DE TAREAS", informe.anexo.length);
    if (informe.anexo.length === 0) {
      notaVacia(`No hay tareas ${informe.filtrado ? "para los filtros elegidos." : "en el periodo."}`);
    } else {
      tabla(
        [
          { titulo: "#", ancho: 0.07 },
          { titulo: "Tipo", ancho: 0.09 },
          { titulo: "Programada", ancho: 0.11 },
          { titulo: "Cierre", ancho: 0.11 },
          { titulo: "Ubicación", ancho: 0.12 },
          { titulo: "Descripción", ancho: 0.21 },
          { titulo: "Estado", ancho: 0.1 },
          { titulo: "Responsable", ancho: 0.13 },
          { titulo: "Fotos", ancho: 0.06, alinear: "right" },
        ],
        informe.anexo.map((t) => ({
          celdas: [
            `#${t.tareaId}`,
            etiquetaTipo(t.tipo),
            fechaHora(t.fecha),
            t.cierre ? fechaHora(t.cierre) : "-",
            recortar(t.ubicacion ?? "-", 50),
            recortar(t.descripcion, 120),
            ETIQUETA_ESTADO_SINGULAR[t.estado] ?? t.estado,
            recortar(t.responsables || "-", 70),
            String(t.evidencias),
          ],
          colores: [
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            ESTADOS_EN_ROJO.has(t.estado) ? RED : undefined,
          ],
        })),
      );
    }
    y += 4;
  }

  /* -------------------------------- pie ---------------------------------- */

  const rango = doc.bufferedPageRange();
  for (let i = 0; i < rango.count; i++) {
    doc.switchToPage(rango.start + i);
    doc
      .moveTo(MARGIN_X, PAGE_H - 44)
      .lineTo(PAGE_W - MARGIN_X, PAGE_H - 44)
      .lineWidth(0.8)
      .strokeColor(LINE)
      .stroke();
    texto(
      `CONTROL S.A.S.  |  Informe mensual de actividades${idCorto ? `  |  ID ${idCorto}` : ""}`,
      MARGIN_X,
      PAGE_H - 36,
      360,
      { size: 8, color: MUTED },
    );
    texto(
      `Página ${i + 1} de ${rango.count}`,
      PAGE_W - MARGIN_X - 120,
      PAGE_H - 36,
      120,
      { size: 8, color: MUTED, align: "right" },
    );
  }
}
