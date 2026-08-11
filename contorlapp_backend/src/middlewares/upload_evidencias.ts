import multer from "multer";
import path from "path";
import os from "os";
import crypto from "crypto";
import fs from "fs";
import type { RequestHandler } from "express";

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, os.tmpdir()),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname || "") || ".jpg";
    const name = `evi_${Date.now()}_${crypto.randomBytes(6).toString("hex")}${ext}`;
    cb(null, name);
  },
});

const allowedExtensions = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".pdf",
]);
const allowedMimeTypes = new Set(["image/jpeg", "image/png", "application/pdf"]);

function fileFilter(
  _req: any,
  file: Express.Multer.File,
  cb: multer.FileFilterCallback,
) {
  const mime = String(file.mimetype ?? "").toLowerCase();
  const ext = path.extname(file.originalname || "").toLowerCase();

  const mimeAllowed = allowedMimeTypes.has(mime);
  const extAllowed = allowedExtensions.has(ext);

  if (!mimeAllowed || !extAllowed) {
    return cb(new Error("Solo se permiten archivos JPG, JPEG, PNG o PDF validos."));
  }

  cb(null, true);
}

const baseUpload = multer({
  storage,
  fileFilter,
  limits: { fileSize: 10 * 1024 * 1024, files: 10 },
});

function uploadedFiles(req: Express.Request): Express.Multer.File[] {
  if (req.file) return [req.file];
  if (Array.isArray(req.files)) return req.files;
  if (req.files && typeof req.files === "object") return Object.values(req.files).flat();
  return [];
}

async function hasValidMagic(file: Express.Multer.File): Promise<boolean> {
  const handle = await fs.promises.open(file.path, "r");
  try {
    const buffer = Buffer.alloc(8);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    const bytes = buffer.subarray(0, bytesRead);
    return matchesDeclaredType(file, bytes);
  } finally {
    await handle.close();
  }
}

const validateMagicBytes: RequestHandler = async (req, _res, next) => {
  const files = uploadedFiles(req);
  try {
    const valid = await Promise.all(files.map(hasValidMagic));
    if (valid.some((item) => !item)) {
      throw new Error("El contenido del archivo no coincide con un JPG, PNG o PDF valido.");
    }
    next();
  } catch (error) {
    await Promise.all(files.map((file) => fs.promises.unlink(file.path).catch(() => undefined)));
    next(error);
  }
};

function matchesDeclaredType(file: Express.Multer.File, bytes: Buffer): boolean {
  const isJpeg = bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng =
    bytes.length >= 8 &&
    bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const isPdf = bytes.length >= 5 && bytes.subarray(0, 5).toString("ascii") === "%PDF-";
  const ext = path.extname(file.originalname || "").toLowerCase();

  if (file.mimetype === "image/jpeg") return isJpeg && [".jpg", ".jpeg"].includes(ext);
  if (file.mimetype === "image/png") return isPng && ext === ".png";
  if (file.mimetype === "application/pdf") return isPdf && ext === ".pdf";
  return false;
}

const imageMemoryUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024, files: 1 },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname || "").toLowerCase();
    const valid =
      (file.mimetype === "image/jpeg" && [".jpg", ".jpeg"].includes(ext)) ||
      (file.mimetype === "image/png" && ext === ".png");
    if (!valid) {
      cb(new Error("Solo se permiten imagenes JPG, JPEG o PNG validas."));
      return;
    }
    cb(null, true);
  },
});

const validateImageBuffer: RequestHandler = (req, _res, next) => {
  const files = uploadedFiles(req);
  if (files.every((file) => matchesDeclaredType(file, file.buffer))) {
    next();
    return;
  }
  next(new Error("El contenido del mapa no coincide con una imagen JPG o PNG valida."));
};

export const uploadEvidencias = {
  single: (fieldName: string): RequestHandler[] => [
    baseUpload.single(fieldName),
    validateMagicBytes,
  ],
  array: (fieldName: string, maxCount?: number): RequestHandler[] => [
    baseUpload.array(fieldName, maxCount),
    validateMagicBytes,
  ],
};

export const uploadImagenMemoria = {
  single: (fieldName: string): RequestHandler[] => [
    imageMemoryUpload.single(fieldName),
    validateImageBuffer,
  ],
};
