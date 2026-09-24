import os from "os";
import path from "path";
import sharp from "sharp";
import type { Worker } from "tesseract.js";
import {
  evaluarComprobante,
  extraerDatosComprobante,
  verificacionIlegible,
  type ContextoPedido,
  type VerificacionComprobante,
} from "../utils/comprobanteParser";

// Motor: Tesseract (WebAssembly, corre dentro del propio proceso de Node -no
// hay servicio aparte ni dependencias del sistema-. El worker se crea al
// primer comprobante y se apaga solo tras un rato sin uso, para que el
// backend no cargue ~150-250 MB de RAM mientras nadie sube comprobantes.
const IDLE_MS = Number(process.env.COMPROBANTE_OCR_IDLE_MS ?? 60_000);
const TIMEOUT_MS = Number(process.env.COMPROBANTE_OCR_TIMEOUT_MS ?? 60_000);
const ANCHO_MAXIMO_PX = 1600;

let workerPromise: Promise<Worker> | null = null;
let idleTimer: NodeJS.Timeout | null = null;

function langPath() {
  if (process.env.TESSERACT_LANG_PATH) return process.env.TESSERACT_LANG_PATH;
  // Modelo de espanol incluido en node_modules: no se descarga nada en runtime.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const spa = require("@tesseract.js-data/spa") as { langPath: string };
  return spa.langPath;
}

async function getWorker(): Promise<Worker> {
  if (!workerPromise) {
    workerPromise = (async () => {
      const { createWorker } = await import("tesseract.js");
      return createWorker("spa", 1, {
        langPath: langPath(),
        gzip: true,
        cachePath: path.join(os.tmpdir(), "tesseract-cache"),
      });
    })().catch((error) => {
      workerPromise = null;
      throw error;
    });
  }
  return workerPromise;
}

export async function apagarWorkerOcr() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = null;
  const pendiente = workerPromise;
  workerPromise = null;
  if (!pendiente) return;
  try {
    await (await pendiente).terminate();
  } catch {
    // Best-effort: si ya estaba caido no hay nada que liberar.
  }
}

function programarApagado() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => void apagarWorkerOcr(), IDLE_MS);
  idleTimer.unref?.();
}

async function reconocer(imagen: Buffer): Promise<string> {
  const worker = await getWorker();
  const { data } = await worker.recognize(imagen);
  return data.text ?? "";
}

async function conTimeout<T>(promesa: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promesa,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("OCR_TIMEOUT")), ms);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

// Capturas de pantalla de celular: texto claro sobre fondos de color (Nequi) o
// muy grandes. Se pasa a grises, se reescala y se normaliza el contraste; si la
// primera lectura no encuentra un valor se reintenta con los colores
// invertidos (texto blanco sobre fondo oscuro).
async function textoDeImagen(buffer: Buffer): Promise<string[]> {
  const base = sharp(buffer, { failOn: "none", limitInputPixels: 100_000_000 })
    .rotate()
    .resize({ width: ANCHO_MAXIMO_PX, withoutEnlargement: true })
    .grayscale()
    .normalise();

  const normal = await base.clone().png().toBuffer();
  const primero = await reconocer(normal);
  if (extraerDatosComprobante(primero).monto != null) return [primero];

  const invertida = await base.clone().negate().png().toBuffer();
  const segundo = await reconocer(invertida);
  return [primero, segundo];
}

async function textoDePdf(buffer: Buffer): Promise<string> {
  const { PDFParse } = await import("pdf-parse");
  const parser = new PDFParse({ data: new Uint8Array(buffer) });
  try {
    const resultado = await parser.getText();
    return resultado.text ?? "";
  } finally {
    await parser.destroy().catch(() => undefined);
  }
}

// Un comprobante a la vez: el OCR es CPU/RAM intensivo y varias subidas
// simultaneas en un contenedor pequeno lo dejarian sin memoria.
let cola: Promise<unknown> = Promise.resolve();

function enCola<T>(tarea: () => Promise<T>): Promise<T> {
  const resultado = cola.then(tarea, tarea);
  cola = resultado.catch(() => undefined);
  return resultado;
}

export interface EntradaAnalisis {
  buffer: Buffer;
  mimeType: string;
  contexto: ContextoPedido;
}

/**
 * Lee el comprobante y lo compara con el pedido. Nunca lanza: cualquier fallo
 * (archivo danado, OCR sin memoria, timeout) devuelve un veredicto ILEGIBLE
 * para que el revisor lo mire a mano.
 */
export function analizarComprobante(entrada: EntradaAnalisis): Promise<VerificacionComprobante> {
  return enCola(async () => {
    try {
      let textos: string[];
      let motor: VerificacionComprobante["motor"];

      if (entrada.mimeType === "application/pdf") {
        textos = [await conTimeout(textoDePdf(entrada.buffer), TIMEOUT_MS)];
        motor = "pdf-texto";
        // Un PDF escaneado no trae texto: sin OCR de PDF, queda para revision.
        if (textos[0].replace(/\s/g, "").length < 20) {
          return verificacionIlegible(
            "El PDF no tiene texto legible (parece una imagen escaneada); revisalo manualmente",
          );
        }
      } else {
        textos = await conTimeout(textoDeImagen(entrada.buffer), TIMEOUT_MS);
        motor = "ocr";
      }

      // Se queda con la lectura que mas datos logro extraer.
      const candidatos = textos.map((texto) => {
        const extraido = extraerDatosComprobante(texto);
        const puntos =
          (extraido.monto != null ? 2 : 0) +
          (extraido.referencia ? 1 : 0) +
          (extraido.fecha ? 1 : 0) +
          (extraido.metodos.length ? 1 : 0);
        return { texto, extraido, puntos };
      });
      const mejor = candidatos.reduce((a, b) => (b.puntos > a.puntos ? b : a));

      return evaluarComprobante(mejor.texto, mejor.extraido, entrada.contexto, motor);
    } catch (error) {
      if (error instanceof Error && error.message === "OCR_TIMEOUT") {
        // El worker pudo quedar colgado: se descarta para crear uno limpio.
        await apagarWorkerOcr();
        return verificacionIlegible("La lectura automatica tardo demasiado; revisalo manualmente");
      }
      console.error("[comprobante-ocr] fallo el analisis", {
        name: error instanceof Error ? error.name : "Error",
        ...(process.env.NODE_ENV !== "production" && error instanceof Error
          ? { message: error.message }
          : {}),
      });
      return verificacionIlegible("No se pudo leer el archivo automaticamente; revisalo manualmente");
    } finally {
      programarApagado();
    }
  });
}
