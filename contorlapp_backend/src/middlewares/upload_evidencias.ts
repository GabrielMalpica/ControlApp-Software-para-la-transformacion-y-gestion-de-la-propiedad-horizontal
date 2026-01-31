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

function fileFilter(_req: any, file: Express.Multer.File, cb: multer.FileFilterCallback) {
  // solo imágenes por ahora
  if (!file.mimetype.startsWith("image/")) {
    return cb(new Error("Solo se permiten imágenes (image/*)"));
  }
  cb(null, true);
}

export const uploadEvidencias = multer({
  storage,
  fileFilter,
  limits: { fileSize: 10 * 1024 * 1024, files: 10 },
});
