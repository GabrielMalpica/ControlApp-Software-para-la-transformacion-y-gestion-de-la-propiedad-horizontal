import multer from "multer";
import path from "path";
import os from "os";
import crypto from "crypto";

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
  ".jfif",
  ".png",
  ".webp",
  ".gif",
  ".bmp",
  ".heic",
  ".heif",
  ".pdf",
]);

function fileFilter(
  _req: any,
  file: Express.Multer.File,
  cb: multer.FileFilterCallback,
) {
  const mime = String(file.mimetype ?? "").toLowerCase();
  const ext = path.extname(file.originalname || "").toLowerCase();

  const mimeAllowed = mime.startsWith("image/") || mime === "application/pdf";
  const extAllowed = allowedExtensions.has(ext);

  if (!mimeAllowed && !extAllowed) {
    return cb(new Error("Solo se permiten imagenes o PDF."));
  }

  cb(null, true);
}

export const uploadEvidencias = multer({
  storage,
  fileFilter,
  limits: { fileSize: 10 * 1024 * 1024, files: 10 },
});
