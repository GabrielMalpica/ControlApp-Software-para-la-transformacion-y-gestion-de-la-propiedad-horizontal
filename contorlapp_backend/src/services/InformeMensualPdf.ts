// Render del informe mensual de actividades con pdfkit. El estilo sigue la
// plantilla "Modelos_Informes_Fotograficos_CONTROL": barras oscuras con texto
// blanco, cajas claras y fotos grandes en columnas.
import fs from "fs";
import PDFDocument from "pdfkit";
import { INFORME_LOGO_JPEG_BASE64 } from "../utils/informeLogo";
import {
  claveDia,
  type ActividadInforme,
  type InformeMensual,
} from "./InformeMensualModelo";

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

/* --------------------------------- fotos -------------------------------- */

export type FotoCargada = { buffer: Buffer; width: number; height: number };

export type OpcionesRender = {
  archivoDestino: string;
  cargarFoto: (raw: string) => FotoCargada | null | undefined;
  generadoEn?: Date;
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
  let y = TOP;
  // Modo medicion: recorre el mismo codigo de dibujo sin escribir nada, para
  // saber cuanto espacio necesita un bloque antes de decidir si cabe en la pagina.
  let seco = false;

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

  /* ------------------------------- portada ------------------------------- */

  encabezado();

  y += texto(
    `INFORME MENSUAL   |   ${tituloPeriodo(informe.desde, informe.hasta).toUpperCase()}`,
    MARGIN_X,
    y,
    CONTENT_W,
    { size: 8.5, font: F_BOLD, color: MUTED_2 },
  );
  y += 6;
  y += texto("Reporte visual de actividades", MARGIN_X, y, CONTENT_W, {
    size: 22,
    font: F_BOLD,
  });
  y += 8;

  const colW = CONTENT_W / 2;
  const meta = (k: string, v: string, x: number, yy: number) => {
    doc.font(F_BOLD).fontSize(9.5);
    const kw = doc.widthOfString(`${limpiarTexto(k)}  `);
    texto(`${k}  `, x, yy, kw + 2, { size: 9.5, font: F_BOLD, color: MUTED });
    return texto(v, x + kw, yy, colW - kw - 8, { size: 9.5 });
  };
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
  const m4 = meta(
    "Actividades",
    `${informe.preventivas.length} preventivas, ${informe.correctivas.length} correctivas`,
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

  const gap = 10;
  const tw = (CONTENT_W - gap * 3) / 4;
  const r = informe.resumen;
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
    "CORRECTIVAS",
    String(r.correctivas),
    "tareas registradas",
    MARGIN_X + (tw + gap),
    y,
    tw,
  );
  tarjeta(
    "REEMPLAZADAS",
    String(r.reemplazadas),
    "por correctivas",
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

  /* --------------------------- bloques reutilizables --------------------- */

  const barraSeccion = (
    titulo: string,
    cantidad: number,
    primero?: ActividadInforme,
  ) => {
    // La barra nunca queda sola al final de una pagina: viaja con el primer item.
    asegurar(22 + 12 + (primero ? altoMinimoActividad(primero) : 40));
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
        ? "CORRECTIVA"
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

    const donde = [a.conjunto, a.ubicacion, a.elemento]
      .map((v) => limpiarTexto(v))
      .filter(Boolean)
      .join("  |  ");
    if (donde) {
      y += texto(recortar(donde, 190), MARGIN_X + anchoNum, y, CONTENT_W - anchoNum, {
        size: 8.5,
        color: MUTED,
      });
    }
    y += 6;
  };

  const layoutFotos = (total: number) => {
    const cols = total === 1 ? 1 : total === 2 ? 2 : 3;
    const gapF = 10;
    const cellW = cols === 1 ? 300 : (CONTENT_W - gapF * (cols - 1)) / cols;
    const imgH = cols === 1 ? 225 : cols === 2 ? cellW * 0.75 : cellW;
    const barH = 16;
    const capH = 13;
    return { cols, gapF, cellW, imgH, barH, capH, filaH: barH + imgH + capH };
  };

  const dibujarFotos = (a: ActividadInforme, numero: number) => {
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
          { size: 8, font: F_BOLD, color: WHITE, align: "center" },
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
        texto(
          `Tarea #${foto.tareaId}  |  ${fechaHora(foto.fecha)}`,
          x,
          y + barH + imgH + 3,
          cellW,
          { size: 7, color: MUTED_2, align: "center" },
        );
      });
      y += filaH + 8;
    }

    if (a.fotosOmitidas > 0) {
      const n = a.tareasConFoto;
      asegurar(24);
      y += texto(
        `Actividad diaria: se muestran ${a.fotos.length} evidencias representativas de ${n} registros con foto (${a.fotosTotales} fotos en total). El resto queda disponible en la aplicación.`,
        MARGIN_X,
        y,
        CONTENT_W,
        { size: 8, font: F_ITALIC, color: MUTED },
      );
      y += 6;
    }
  };

  const cabeceraActividad = (a: ActividadInforme, numero: number) => {
    encabezadoActividad(a, numero, false);
    estadisticas(a);

    if (a.tipo === "CORRECTIVA") {
      const t = a.ids[0];
      const filas: Array<{ etiqueta: string; texto: string }> = [
        { etiqueta: "Tarea", texto: `#${t}` },
      ];
      if (a.inicio) {
        filas.push({
          etiqueta: "Fecha",
          texto: `${fechaHora(a.inicio)}${a.fin ? `  a  ${fechaHora(a.fin)}` : ""}`,
        });
      }
      if (a.operarios.length || a.supervisores.length) {
        filas.push({
          etiqueta: "Responsables",
          texto: [
            a.supervisores.length ? `Supervisor: ${a.supervisores.join(", ")}` : "",
            a.operarios.length ? `Operarios: ${listaCorta(a.operarios, 5)}` : "",
          ]
            .filter(Boolean)
            .join("  |  "),
        });
      }
      caja(filas);
    } else {
      const filas: Array<{ etiqueta: string; texto: string }> = [];
      if (a.inicio && a.fin) {
        filas.push({
          etiqueta: "Periodo",
          texto: `${fechaCorta(a.inicio)} al ${fechaCorta(a.fin)}`,
        });
      }
      if (a.operarios.length || a.supervisores.length) {
        filas.push({
          etiqueta: "Responsables",
          texto: [
            a.supervisores.length ? `Supervisor: ${a.supervisores.join(", ")}` : "",
            a.operarios.length ? `Operarios: ${listaCorta(a.operarios, 5)}` : "",
          ]
            .filter(Boolean)
            .join("  |  "),
        });
      }
      if (a.ids.length > 0 && a.ids.length <= 6) {
        filas.push({
          etiqueta: "Tareas",
          texto: a.ids.map((id) => `#${id}`).join(", "),
        });
      } else if (a.ids.length > 6) {
        filas.push({ etiqueta: "Tareas", texto: `${a.ids.length} registros` });
      }
      if (filas.length) caja(filas);
    }

    const recursos: Array<{ etiqueta: string; texto: string }> = [];
    if (a.recursos.insumos) recursos.push({ etiqueta: "Insumos", texto: a.recursos.insumos });
    if (a.recursos.maquinaria) recursos.push({ etiqueta: "Maquinaria", texto: a.recursos.maquinaria });
    if (a.recursos.herramientas) recursos.push({ etiqueta: "Herramientas", texto: a.recursos.herramientas });
    if (recursos.length) caja(recursos);

    if (a.observaciones.length) {
      caja(
        a.observaciones.map((o) => ({
          etiqueta: "Observación",
          texto: recortar(o, 260),
        })),
      );
    }

    if (a.tipo === "CORRECTIVA" && a.reemplazaA.length > 0) {
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

    if (a.tipo === "PREVENTIVA" && a.reemplazadas.length > 0) {
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
  const altoMinimoActividad = (a: ActividadInforme): number =>
    medir(() => cabeceraActividad(a, 1)) +
    (a.fotos.length > 0 ? layoutFotos(a.fotos.length).filaH : 38) +
    8;

  const dibujarActividad = (a: ActividadInforme, numero: number) => {
    // La cabecera y la primera fila de fotos nunca se separan entre paginas.
    asegurar(altoMinimoActividad(a));
    cabeceraActividad(a, numero);
    dibujarFotos(a, numero);
    y += 8;
  };

  /* ------------------------------- secciones ----------------------------- */

  barraSeccion("TAREAS PREVENTIVAS", informe.preventivas.length, informe.preventivas[0]);
  if (informe.preventivas.length === 0) {
    notaVacia("No hay tareas preventivas para el periodo seleccionado.");
  }
  informe.preventivas.forEach((a, i) => dibujarActividad(a, i + 1));

  y += 4;
  barraSeccion("TAREAS CORRECTIVAS", informe.correctivas.length, informe.correctivas[0]);
  if (informe.correctivas.length === 0) {
    notaVacia("No se registraron tareas correctivas en el periodo.");
  }
  informe.correctivas.forEach((a, i) => dibujarActividad(a, i + 1));

  y += 4;
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
      `#${rep.tareaId}  ${recortar(rep.descripcion, 150)}`,
      MARGIN_X + 26,
      y + 1,
      CONTENT_W - 26,
      { size: 12, font: F_BOLD },
    );
    y += Math.max(h + 2, 18) + 4;
    caja(lineas, RED);
    y += 6;
  });

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
      "CONTROL S.A.S.  |  Informe mensual de actividades",
      MARGIN_X,
      PAGE_H - 36,
      320,
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
