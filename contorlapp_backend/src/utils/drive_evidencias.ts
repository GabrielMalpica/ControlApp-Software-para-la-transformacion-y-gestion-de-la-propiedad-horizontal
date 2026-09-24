import fs from "fs";
import path from "path";
import dotenv from "dotenv";
import { google } from "googleapis";

dotenv.config();

type DriveFile = {
  id?: string;
};

function monthNameEs(monthIndex0: number) {
  const m = [
    "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
    "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
  ];
  return m[monthIndex0] ?? "Mes";
}

function monthFolderLabel(date: Date) {
  const mm = monthNameEs(date.getMonth());
  const yyyy = date.getFullYear();
  return `Evidencias ${mm} ${yyyy}`;
}

function safeName(s: string) {
  return s.replace(/[\\/:*?"<>|]/g, "-").trim();
}

function fechaDDMMYYYY(d: Date) {
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = d.getFullYear();
  return `${dd}-${mm}-${yyyy}`;
}

/** Nombre del archivo tal como se ve en Drive: quién lo subió, su rol y la fecha (sin hora). */
export function buildEvidenciaFileName(params: {
  subidoPor: string;
  rol: string;
  fecha: Date;
  originalName: string;
  indice?: number;
}) {
  const ext = path.extname(params.originalName || "") || "";
  const sufijo = params.indice && params.indice > 1 ? `_${params.indice}` : "";
  return safeName(
    `${params.subidoPor}_${params.rol}_${fechaDDMMYYYY(params.fecha)}${sufijo}${ext}`,
  );
}

let driveClient: ReturnType<typeof google.drive> | null = null;
let driveClientCredentials: string | null = null;

function getDrive() {
  if (!process.env.GOOGLE_CREDENTIALS) {
    throw new Error("GOOGLE_CREDENTIALS no está definida");
  }
  // Se reutiliza el cliente mientras las credenciales no cambien: crear uno
  // por archivo obligaba a renegociar el token para cada foto de un informe.
  if (driveClient && driveClientCredentials === process.env.GOOGLE_CREDENTIALS) {
    return driveClient;
  }
  const credentials = JSON.parse(process.env.GOOGLE_CREDENTIALS);

  const auth = new google.auth.GoogleAuth({
    credentials: {
      ...credentials,
      private_key: (credentials.private_key || "").replace(/\\n/g, "\n"),
    },
    scopes: ["https://www.googleapis.com/auth/drive.file"],
  });

  driveClient = google.drive({ version: "v3", auth });
  driveClientCredentials = process.env.GOOGLE_CREDENTIALS;
  return driveClient;
}

async function findFolderByName(drive: any, parentId: string, name: string) {
  const q =
    `mimeType='application/vnd.google-apps.folder' and ` +
    `name='${name.replace(/'/g, "\\'")}' and ` +
    `'${parentId}' in parents and trashed=false`;

  const res = await drive.files.list({
    q,
    fields: "files(id, name)",
    pageSize: 10,
  });

  const files = res.data.files ?? [];
  return files.length ? (files[0].id as string) : null;
}

async function createFolder(drive: any, parentId: string, name: string) {
  const res = await drive.files.create({
    requestBody: {
      name,
      mimeType: "application/vnd.google-apps.folder",
      parents: [parentId],
    },
    fields: "id",
  });

  return res.data.id as string;
}

async function getOrCreateFolder(drive: any, parentId: string, name: string) {
  const existing = await findFolderByName(drive, parentId, name);
  if (existing) return existing;
  return createFolder(drive, parentId, name);
}

export async function uploadEvidenciaToDrive(params: {
  filePath: string;
  fileName: string;
  mimeType: string;
  conjuntoNit: string;
  conjuntoNombre?: string;
  fecha: Date; // para carpeta mensual
  /**
   * Carpeta fija dentro de la carpeta del conjunto (p. ej. "comprobantes-pago").
   * Si se indica, el archivo va ahi directamente y no en la carpeta mensual de
   * evidencias.
   */
  subcarpeta?: string;
}) {
  const rootId = process.env.DRIVE_EVIDENCIAS_ROOT_ID;
  if (!rootId) throw new Error("DRIVE_EVIDENCIAS_ROOT_ID no está definida");

  const drive = getDrive();

  const carpetaConjunto = safeName(
    `Conjunto ${params.conjuntoNit}${params.conjuntoNombre ? " - " + params.conjuntoNombre : ""}`
  );

  const conjuntoFolderId = await getOrCreateFolder(drive, rootId, carpetaConjunto);
  const destinoFolderId = await getOrCreateFolder(
    drive,
    conjuntoFolderId,
    params.subcarpeta ? safeName(params.subcarpeta) : monthFolderLabel(params.fecha),
  );

  const media = {
    mimeType: params.mimeType,
    body: fs.createReadStream(params.filePath),
  };

  const res = await drive.files.create({
    requestBody: {
      name: safeName(params.fileName),
      parents: [destinoFolderId],
    },
    media,
    fields: "id",
  });

  const file = res.data as DriveFile;
  if (!file.id) throw new Error("No se pudo obtener id del archivo en Drive");

  return `https://drive.google.com/file/d/${file.id}/view`;
}

/**
 * Descarga el binario de una evidencia directamente desde Drive usando la
 * cuenta de servicio. El scope es "drive.file", así que la cuenta solo puede
 * leer archivos que ella misma creó (las evidencias) — no hay riesgo de
 * exponer otros archivos de Drive aunque alguien adivine un fileId ajeno.
 *
 * Esto reemplaza el hotlink directo a drive.google.com: los enlaces de Drive
 * (thumbnail/uc/googleusercontent) no traen cabecera Access-Control-Allow-Origin,
 * así que el navegador los bloquea por CORS al intentar cargarlos desde la app.
 * Sirviéndolos desde nuestro propio backend evitamos ese problema.
 */
export async function getEvidenciaStream(fileId: string) {
  const drive = getDrive();

  const meta = await drive.files.get({
    fileId,
    fields: "id, name, mimeType",
  });

  const media = await drive.files.get(
    { fileId, alt: "media" },
    { responseType: "stream" },
  );

  return {
    stream: media.data as NodeJS.ReadableStream,
    mimeType: (meta.data.mimeType as string) || "application/octet-stream",
    name: (meta.data.name as string) || fileId,
  };
}

/**
 * Descarga una evidencia completa en memoria. A diferencia de
 * `getEvidenciaStream` no consulta los metadatos (una llamada menos por foto)
 * y corta con timeout: los informes piden muchas fotos y una sola colgada no
 * debe frenar todo el PDF.
 */
export async function getEvidenciaBuffer(
  fileId: string,
  timeoutMs = 20_000,
): Promise<Buffer> {
  const drive = getDrive();
  const res = await drive.files.get(
    { fileId, alt: "media" },
    { responseType: "arraybuffer", timeout: timeoutMs },
  );
  return Buffer.from(res.data as ArrayBuffer);
}

/**
 * Id de archivo de Drive dentro de un enlace (`/d/ID`, `?id=ID`), de la ruta
 * del proxy `/evidencias/ID` o un id suelto. Null si no parece de Drive.
 */
export function extraerDriveId(raw: string): string | null {
  const v = String(raw ?? "").trim().replace(/^["']|["']$/g, "");
  if (!v) return null;
  if (/^[a-zA-Z0-9_-]{20,}$/.test(v)) return v;
  const patrones = [
    /\/d\/([a-zA-Z0-9_-]{20,})/,
    /[?&]id=([a-zA-Z0-9_-]{20,})/,
    /\/evidencias\/([a-zA-Z0-9_-]{10,})/,
  ];
  for (const p of patrones) {
    const m = v.match(p);
    if (m) return m[1];
  }
  return null;
}

/**
 * Borra una evidencia de Drive. El scope "drive.file" solo permite tocar
 * archivos que la cuenta de servicio creo (las evidencias). Si el archivo ya
 * no existe se considera hecho.
 */
export async function eliminarEvidenciaDeDrive(fileId: string): Promise<void> {
  const drive = getDrive();
  try {
    await drive.files.delete({ fileId, supportsAllDrives: true });
  } catch (err: any) {
    const status = err?.code ?? err?.response?.status;
    if (status === 404) return;
    throw err;
  }
}
