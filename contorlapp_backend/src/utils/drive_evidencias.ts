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

function getDrive() {
  if (!process.env.GOOGLE_CREDENTIALS) {
    throw new Error("GOOGLE_CREDENTIALS no está definida");
  }
  const credentials = JSON.parse(process.env.GOOGLE_CREDENTIALS);

  const auth = new google.auth.GoogleAuth({
    credentials: {
      ...credentials,
      private_key: (credentials.private_key || "").replace(/\\n/g, "\n"),
    },
    scopes: ["https://www.googleapis.com/auth/drive"],
  });

  return google.drive({ version: "v3", auth });
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

async function makePublic(drive: any, fileId: string) {
  await drive.permissions.create({
    fileId,
    requestBody: { role: "reader", type: "anyone" },
  });
}

export async function uploadEvidenciaToDrive(params: {
  filePath: string;
  fileName: string;
  mimeType: string;
  conjuntoNit: string;
  conjuntoNombre?: string;
  fecha: Date; // para carpeta mensual
}) {
  const rootId = process.env.DRIVE_EVIDENCIAS_ROOT_ID;
  if (!rootId) throw new Error("DRIVE_EVIDENCIAS_ROOT_ID no está definida");

  const drive = getDrive();

  const carpetaConjunto = safeName(
    `Conjunto ${params.conjuntoNit}${params.conjuntoNombre ? " - " + params.conjuntoNombre : ""}`
  );

  const conjuntoFolderId = await getOrCreateFolder(drive, rootId, carpetaConjunto);
  const mesFolderId = await getOrCreateFolder(drive, conjuntoFolderId, monthFolderLabel(params.fecha));

  const media = {
    mimeType: params.mimeType,
    body: fs.createReadStream(params.filePath),
  };

  const res = await drive.files.create({
    requestBody: {
      name: safeName(params.fileName),
      parents: [mesFolderId],
    },
    media,
    fields: "id",
  });

  const file = res.data as DriveFile;
  if (!file.id) throw new Error("No se pudo obtener id del archivo en Drive");

  await makePublic(drive, file.id);

  // URL pública tipo uc?id=
  return `https://drive.google.com/uc?id=${file.id}`;
}
