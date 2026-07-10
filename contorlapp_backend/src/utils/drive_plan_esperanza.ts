import fs from "fs";
import { google } from "googleapis";

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

async function findFolderByName(
  drive: any,
  parentId: string,
  name: string
) {
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

async function getOrCreateFolder(
  drive: any,
  parentId: string,
  name: string
) {
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

function safeName(s: string) {
  return s.replace(/[\\/:*?"<>|]/g, "-").trim();
}

export async function uploadPlanEsperanzaFoto(params: {
  filePath: string;
  fileName: string;
  mimeType: string;
  conjuntoNombre: string;
}) {
  const rootId = process.env.DRIVE_EVIDENCIAS_ROOT_ID;
  if (!rootId) throw new Error("DRIVE_EVIDENCIAS_ROOT_ID no está definida");

  const drive = getDrive();

  const carpetaRaiz = await getOrCreateFolder(drive, rootId, "PlanEsperanza");
  const carpetaConjunto = await getOrCreateFolder(
    drive,
    carpetaRaiz,
    safeName(params.conjuntoNombre)
  );

  const media = {
    mimeType: params.mimeType,
    body: fs.createReadStream(params.filePath),
  };

  const res = await drive.files.create({
    requestBody: {
      name: safeName(params.fileName),
      parents: [carpetaConjunto],
    },
    media,
    fields: "id",
  });

  const file = res.data as { id?: string };
  if (!file.id) throw new Error("No se pudo obtener id del archivo en Drive");

  await makePublic(drive, file.id);

  return `https://drive.google.com/uc?id=${file.id}`;
}
