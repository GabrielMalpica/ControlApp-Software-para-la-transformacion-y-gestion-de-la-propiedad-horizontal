// Marca de agua de auditoría para las evidencias de cierre de tareas: abajo a
// la derecha, como las apps de "cámara con fecha", pero estampada por el
// servidor antes de subir a Drive. Muestra cuándo se tomó la foto (hora del
// celular al tomarla dentro de la app), cuándo se subió si fue mucho después
// (cierres guardados sin señal), el conjunto, la dirección donde se tomó y a
// qué distancia del conjunto.
//
// El texto se dibuja como trazos vectoriales a partir de la fuente Roboto que
// viaja con el backend (assets/fonts): no depende de que el servidor tenga
// fuentes instaladas, que en contenedores mínimos suele no ser así.
import fs from "fs";
import path from "path";
import sharp from "sharp";
import { z } from "zod";
import { direccionGpsSinDemora, type DireccionGps } from "./direccion_gps";
import { distanciaMetros } from "./ubicacionMaps";

type TrazoGlifo = {
  scale(sx: number, sy?: number): TrazoGlifo;
  translate(x: number, y: number): TrazoGlifo;
  toSVG(): string;
};

type FuenteVectorial = {
  unitsPerEm: number;
  ascent: number;
  descent: number;
  layout(texto: string): {
    glyphs: Array<{ path: TrazoGlifo }>;
    positions: Array<{ xAdvance: number; xOffset: number; yOffset: number }>;
    advanceWidth: number;
  };
};

const RUTA_FUENTE = path.resolve(__dirname, "../../assets/fonts/Roboto-Bold.ttf");

let fuente: FuenteVectorial | null = null;

function cargarFuente(): FuenteVectorial {
  if (fuente) return fuente;
  // fontkit no publica tipos: solo usamos lo declarado arriba.
  const fontkit = require("fontkit") as { create(buffer: Buffer): FuenteVectorial };
  fuente = fontkit.create(fs.readFileSync(RUTA_FUENTE));
  return fuente;
}

/** Una foto tomada dentro de la app después de esta tolerancia en el futuro
 * (reloj del celular adelantado) no se toma como hora válida. */
const TOLERANCIA_FUTURO_MS = 10 * 60 * 1000;
/** Cierres guardados sin señal pueden subirse días después, pero no meses. */
const ANTIGUEDAD_MAXIMA_MS = 45 * 24 * 60 * 60 * 1000;
/** Si la foto se subió más de esto después de tomarla, se agrega la hora de subida. */
const DIFERENCIA_PARA_MOSTRAR_SUBIDA_MS = 10 * 60 * 1000;
/** Lo máximo que el cierre espera por la dirección. Normalmente ya está en
 * caché porque la app la pidió apenas se tomó la foto. */
const ESPERA_MAXIMA_DIRECCION_MS = 700;

export type CapturaEvidencia = {
  tomadaEn: Date | null;
  latitud: number | null;
  longitud: number | null;
};

export type ConjuntoMarcaAgua = {
  nombre?: string | null;
  direccion?: string | null;
  latitud?: unknown; // Decimal | number | string | null
  longitud?: unknown;
} | null;

const CapturaSchema = z
  .object({
    tomadaEn: z.string().nullish(),
    latitud: z.number().min(-90).max(90).nullish(),
    longitud: z.number().min(-180).max(180).nullish(),
  })
  .nullish();

/**
 * Datos de captura que manda la app por cada archivo (campo multipart
 * `evidenciasCaptura`, JSON alineado con el orden de `files`). Es metadato de
 * apoyo: si viene mal formado se ignora y la foto queda marcada solo con la
 * hora de subida; nunca hace fallar el cierre.
 */
export function parsearCapturasEvidencias(
  raw: unknown,
  cantidad: number,
  ahora: Date = new Date(),
): Array<CapturaEvidencia | null> {
  const vacias = Array.from({ length: cantidad }, () => null);
  if (typeof raw !== "string" || !raw.trim()) return vacias;

  let lista: unknown;
  try {
    lista = JSON.parse(raw);
  } catch {
    return vacias;
  }
  if (!Array.isArray(lista)) return vacias;

  return vacias.map((_, i) => {
    const item = CapturaSchema.safeParse(lista[i]);
    if (!item.success || !item.data) return null;

    let tomadaEn: Date | null = null;
    if (item.data.tomadaEn) {
      const fecha = new Date(item.data.tomadaEn);
      const t = fecha.getTime();
      const valida =
        Number.isFinite(t) &&
        t <= ahora.getTime() + TOLERANCIA_FUTURO_MS &&
        t >= ahora.getTime() - ANTIGUEDAD_MAXIMA_MS;
      if (valida) tomadaEn = fecha;
    }

    const conGps = item.data.latitud != null && item.data.longitud != null;
    const captura: CapturaEvidencia = {
      tomadaEn,
      latitud: conGps ? item.data.latitud! : null,
      longitud: conGps ? item.data.longitud! : null,
    };
    return captura.tomadaEn || conGps ? captura : null;
  });
}

const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"];

const formatoBogota = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/Bogota",
  year: "numeric",
  month: "numeric",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
  second: "2-digit",
  hour12: true,
});

/** "2 oct 2026 7:39:09 p. m." en hora de Colombia. */
export function formatearFechaMarcaAgua(fecha: Date): string {
  const partes: Record<string, string> = {};
  for (const p of formatoBogota.formatToParts(fecha)) partes[p.type] = p.value;
  const mes = MESES[Number(partes.month) - 1] ?? partes.month;
  const periodo = (partes.dayPeriod ?? "").toUpperCase() === "AM" ? "a. m." : "p. m.";
  return `${Number(partes.day)} ${mes} ${partes.year} ${Number(partes.hour)}:${partes.minute}:${partes.second} ${periodo}`;
}

function aNumero(valor: unknown): number | null {
  if (valor == null) return null;
  const n = Number((valor as any)?.toString?.() ?? valor);
  return Number.isFinite(n) ? n : null;
}

function formatearDistancia(metros: number): string {
  if (metros < 1000) return `${metros} m`;
  return `${(metros / 1000).toFixed(1).replace(".", ",")} km`;
}

/** Renglones de la marca de agua, de arriba hacia abajo. */
export function lineasMarcaAgua(params: {
  captura: CapturaEvidencia | null;
  subidaEn: Date;
  conjunto: ConjuntoMarcaAgua;
  /** Dirección donde se tomó la foto (según su GPS), si se pudo averiguar. */
  direccionGps?: DireccionGps | null;
}): string[] {
  const { captura, subidaEn, conjunto, direccionGps } = params;
  const lineas: string[] = [];

  if (captura?.tomadaEn) {
    lineas.push(formatearFechaMarcaAgua(captura.tomadaEn));
    if (subidaEn.getTime() - captura.tomadaEn.getTime() > DIFERENCIA_PARA_MOSTRAR_SUBIDA_MS) {
      lineas.push(`Subida ${formatearFechaMarcaAgua(subidaEn)}`);
    }
  } else {
    // Archivo adjuntado (galería, pegado) o sin hora confiable: solo se
    // puede afirmar cuándo llegó al sistema.
    lineas.push(`Subida ${formatearFechaMarcaAgua(subidaEn)}`);
  }

  const nombreConjunto = conjunto?.nombre?.trim();
  if (nombreConjunto) lineas.push(nombreConjunto);

  const lugar = [direccionGps?.calle, direccionGps?.barrio, direccionGps?.ciudad]
    .map((x) => x?.trim())
    .filter((x): x is string => !!x);
  if (lugar.length) {
    lineas.push(...lugar);
  } else {
    // Sin dirección del GPS (foto de galería, sin señal o servicio caído) se
    // muestra la dirección registrada del conjunto.
    const direccion = conjunto?.direccion?.trim();
    if (direccion) lineas.push(direccion);
  }

  if (captura?.latitud != null && captura.longitud != null) {
    const latConjunto = aNumero(conjunto?.latitud);
    const lngConjunto = aNumero(conjunto?.longitud);
    if (latConjunto != null && lngConjunto != null) {
      const d = distanciaMetros(
        { latitud: captura.latitud, longitud: captura.longitud },
        { latitud: latConjunto, longitud: lngConjunto },
      );
      lineas.push(`a ${formatearDistancia(d)} del conjunto`);
    }
  }

  return lineas;
}

function anchoTexto(f: FuenteVectorial, texto: string, escala: number): number {
  return f.layout(texto).advanceWidth * escala;
}

function recortarAlAncho(f: FuenteVectorial, texto: string, escala: number, maximo: number): string {
  if (anchoTexto(f, texto, escala) <= maximo) return texto;
  let recortado = texto;
  while (recortado.length > 1 && anchoTexto(f, `${recortado}…`, escala) > maximo) {
    recortado = recortado.slice(0, -1);
  }
  return `${recortado.trimEnd()}…`;
}

function escaparAtributo(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
}

/**
 * SVG con el bloque de texto alineado a la derecha y su posición sobre una
 * imagen de `ancho` x `alto` (ya orientada).
 */
export function construirSvgMarcaAgua(
  lineas: string[],
  ancho: number,
  alto: number,
): { svg: Buffer; left: number; top: number } | null {
  if (!lineas.length || ancho < 64 || alto < 64) return null;
  const f = cargarFuente();

  const lado = Math.min(ancho, alto);
  const margen = Math.max(4, Math.round(lado * 0.02));
  const anchoDisponible = ancho - margen * 2;
  const tamanoMinimo = Math.max(9, lado * 0.018);
  let tamano = Math.max(tamanoMinimo, lado * 0.033);

  // Si el renglón más largo no cabe, se achica la letra (hasta un mínimo
  // legible) y lo que aún no quepa se recorta con "…".
  const masLargo = Math.max(...lineas.map((l) => anchoTexto(f, l, tamano / f.unitsPerEm)));
  if (masLargo > anchoDisponible) {
    tamano = Math.max(tamanoMinimo, (tamano * anchoDisponible) / masLargo);
  }
  const escala = tamano / f.unitsPerEm;
  const textos = lineas.map((l) => recortarAlAncho(f, l, escala, anchoDisponible));

  const anchos = textos.map((t) => anchoTexto(f, t, escala));
  const anchoBloque = Math.max(...anchos);
  const altoRenglon = (f.ascent - f.descent) * escala;
  const relleno = Math.ceil(tamano * 0.2); // espacio para el contorno y la sombra
  const anchoSvg = Math.ceil(anchoBloque + relleno * 2);
  const altoSvg = Math.ceil(altoRenglon * textos.length + relleno * 2);

  let d = "";
  textos.forEach((texto, i) => {
    const run = f.layout(texto);
    const linea = relleno + i * altoRenglon + f.ascent * escala;
    let x = relleno + (anchoBloque - anchos[i]);
    run.glyphs.forEach((glifo, j) => {
      const pos = run.positions[j];
      d += glifo.path
        .scale(escala, -escala)
        .translate(x + pos.xOffset * escala, linea - pos.yOffset * escala)
        .toSVG();
      x += pos.xAdvance * escala;
    });
  });

  // Contorno oscuro + sombra corrida, sin filtros de desenfoque: el blur
  // costaba casi la mitad del tiempo de toda la marca.
  const trazo = escaparAtributo(d);
  const desplazamiento = (tamano * 0.05).toFixed(2);
  const contorno = (tamano * 0.14).toFixed(2);
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="${anchoSvg}" height="${altoSvg}">` +
    `<path d="${trazo}" transform="translate(${desplazamiento},${desplazamiento})" ` +
    `fill="#000" fill-opacity="0.35" stroke="#000" stroke-opacity="0.35" ` +
    `stroke-width="${contorno}" stroke-linejoin="round"/>` +
    `<path d="${trazo}" fill="#fff" stroke="#000" stroke-opacity="0.45" ` +
    `stroke-width="${(tamano * 0.07).toFixed(2)}" stroke-linejoin="round" paint-order="stroke"/>` +
    `</svg>`;

  return {
    svg: Buffer.from(svg),
    left: Math.max(0, ancho - margen - anchoSvg + relleno),
    top: Math.max(0, alto - margen - altoSvg + relleno),
  };
}

/**
 * Estampa los renglones sobre la imagen (JPG o PNG), respetando la
 * orientación EXIF para que el texto quede abajo a la derecha tal como se ve
 * la foto. Conserva el formato y los metadatos EXIF originales.
 */
export async function estamparMarcaAgua(imagen: Buffer, lineas: string[]): Promise<Buffer> {
  const meta = await sharp(imagen, { failOn: "none" }).metadata();
  if (!meta.width || !meta.height) throw new Error("No se pudo leer el tamaño de la imagen.");
  const girada = (meta.orientation ?? 1) >= 5;
  const ancho = girada ? meta.height : meta.width;
  const alto = girada ? meta.width : meta.height;

  const marca = construirSvgMarcaAgua(lineas, ancho, alto);
  if (!marca) return imagen;

  const base = sharp(imagen, { failOn: "none" })
    .rotate()
    .composite([{ input: marca.svg, left: marca.left, top: marca.top }])
    .keepExif()
    .keepIccProfile();

  return meta.format === "png"
    ? base.png().toBuffer()
    : base.jpeg({ quality: 90 }).toBuffer();
}

const MIMES_ESTAMPABLES = new Set(["image/jpeg", "image/png"]);

export type ParametrosMarcaEvidencias = {
  files: Express.Multer.File[];
  /** Campo multipart `evidenciasCaptura` tal como llegó. */
  capturas: unknown;
  conjunto: ConjuntoMarcaAgua;
  subidaEn?: Date;
};

/**
 * Estampa la marca de agua en cada evidencia de imagen subida por multer
 * (archivo temporal en disco). Devuelve una promesa por archivo, alineada con
 * `files`, que se cumple cuando ese archivo ya quedó listo para subir. Las
 * fotos se procesan una a la vez y en orden (cada foto de cámara
 * descomprimida ocupa decenas de MB), empezando de inmediato.
 *
 * Es de mejor esfuerzo: las promesas nunca fallan. Si una imagen no se puede
 * procesar se sube tal cual y queda aviso en el log. Los PDF no se tocan.
 */
export function estamparEvidencias(params: ParametrosMarcaEvidencias): Promise<void>[] {
  const files = params.files ?? [];
  const subidaEn = params.subidaEn ?? new Date();
  const capturas = parsearCapturasEvidencias(params.capturas, files.length, subidaEn);

  // Una consulta por punto, todas a la vez y con espera acotada.
  const direcciones = capturas.map((c) =>
    c?.latitud != null && c.longitud != null
      ? direccionGpsSinDemora(c.latitud, c.longitud, ESPERA_MAXIMA_DIRECCION_MS)
      : Promise.resolve(null),
  );

  let anterior: Promise<void> = Promise.resolve();
  return files.map((f, i) => {
    anterior = anterior.then(async () => {
      if (!MIMES_ESTAMPABLES.has(String(f.mimetype ?? "").toLowerCase())) return;
      if (!f.path || !fs.existsSync(f.path)) return;
      try {
        const lineas = lineasMarcaAgua({
          captura: capturas[i],
          subidaEn,
          conjunto: params.conjunto,
          direccionGps: await direcciones[i],
        });
        const estampada = await estamparMarcaAgua(await fs.promises.readFile(f.path), lineas);
        await fs.promises.writeFile(f.path, estampada);
        f.size = estampada.length;
      } catch (err) {
        console.warn(
          `[marca-agua] No se pudo estampar la evidencia "${f.originalname}"; se sube sin marca.`,
          err instanceof Error ? err.message : err,
        );
      }
    });
    return anterior;
  });
}

/** Fotos subiendo a Drive al mismo tiempo dentro de un cierre. */
const SUBIDAS_SIMULTANEAS = 3;

/**
 * Sube las evidencias con `subir`, hasta 3 a la vez, estampando cada una
 * justo antes. Mientras unas fotos suben a Drive las siguientes ya se están
 * estampando, así que la marca casi no suma tiempo al cierre. Devuelve los
 * resultados en el orden de `files`.
 *
 * Si una subida falla deja de empezar otras, espera las que ya iban en
 * camino y el estampado en curso (para que quien llama pueda borrar los
 * temporales sin cortar nada a medias) y propaga el primer error.
 */
export async function subirEvidenciasConMarca<T>(
  params: ParametrosMarcaEvidencias,
  subir: (file: Express.Multer.File, indice: number) => Promise<T>,
): Promise<T[]> {
  const files = params.files ?? [];
  const listas = estamparEvidencias(params);
  const resultados = new Array<T>(files.length);
  let siguiente = 0;
  let fallo = null as { error: unknown } | null;

  const trabajador = async () => {
    while (!fallo && siguiente < files.length) {
      const i = siguiente++;
      await listas[i];
      if (fallo) return;
      try {
        resultados[i] = await subir(files[i], i + 1);
      } catch (error) {
        fallo ??= { error };
      }
    }
  };

  try {
    await Promise.all(
      Array.from({ length: Math.min(SUBIDAS_SIMULTANEAS, files.length) }, trabajador),
    );
  } finally {
    await Promise.all(listas);
  }
  if (fallo) throw fallo.error;
  return resultados;
}
