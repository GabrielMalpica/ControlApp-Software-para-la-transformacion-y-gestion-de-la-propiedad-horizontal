import fs from "fs";
import { google } from "googleapis";

function driveClient() {
  if (!process.env.GOOGLE_CREDENTIALS) {
    throw new Error("El almacenamiento de imágenes no está configurado.");
  }
  const credentials = JSON.parse(process.env.GOOGLE_CREDENTIALS);
  const auth = new google.auth.GoogleAuth({
    credentials: {
      ...credentials,
      private_key: String(credentials.private_key ?? "").replace(/\\n/g, "\n"),
    },
    scopes: ["https://www.googleapis.com/auth/drive.file"],
  });
  return google.drive({ version: "v3", auth });
}

function safeName(value: string) {
  return value.replace(/[\\/:*?"<>|]/g, "-").trim().slice(0, 120) || "archivo";
}

async function folder(drive: ReturnType<typeof driveClient>, parentId: string, name: string) {
  const escaped = name.replace(/'/g, "\\'");
  const found = await drive.files.list({
    q: `mimeType='application/vnd.google-apps.folder' and name='${escaped}' and '${parentId}' in parents and trashed=false`,
    fields: "files(id)",
    pageSize: 1,
  });
  const existing = found.data.files?.[0]?.id;
  if (existing) return existing;

  const created = await drive.files.create({
    requestBody: {
      name,
      mimeType: "application/vnd.google-apps.folder",
      parents: [parentId],
    },
    fields: "id",
  });
  if (!created.data.id) throw new Error("No fue posible crear la carpeta de inventario.");
  return created.data.id;
}

export async function subirFotoInventario(params: {
  filePath: string;
  fileName: string;
  mimeType: string;
  empresaId: string;
  clase: "maquinaria" | "herramientas";
}) {
  const rootId = process.env.DRIVE_EVIDENCIAS_ROOT_ID;
  if (!rootId) throw new Error("El almacenamiento de imágenes no está configurado.");

  const drive = driveClient();
  const inventoryFolder = await folder(drive, rootId, "Inventario");
  const companyFolder = await folder(drive, inventoryFolder, safeName(params.empresaId));
  const classFolder = await folder(drive, companyFolder, params.clase);

  const response = await drive.files.create({
    requestBody: { name: safeName(params.fileName), parents: [classFolder] },
    media: { mimeType: params.mimeType, body: fs.createReadStream(params.filePath) },
    fields: "id",
  });
  if (!response.data.id) throw new Error("No se pudo almacenar la fotografía.");
  return response.data.id;
}

export async function obtenerFotoInventario(fileId: string) {
  const drive = driveClient();
  const [meta, media] = await Promise.all([
    drive.files.get({ fileId, fields: "id,name,mimeType,size" }),
    drive.files.get({ fileId, alt: "media" }, { responseType: "stream" }),
  ]);
  return {
    stream: media.data as NodeJS.ReadableStream,
    nombre: meta.data.name ?? "foto-inventario",
    mimeType: meta.data.mimeType ?? "application/octet-stream",
    tamano: Number(meta.data.size ?? 0),
  };
}

export async function eliminarFotoInventario(fileId: string) {
  const drive = driveClient();
  await drive.files.delete({ fileId });
}
