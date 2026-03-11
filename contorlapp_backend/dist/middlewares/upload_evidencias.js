"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.uploadEvidencias = void 0;
const multer_1 = __importDefault(require("multer"));
const path_1 = __importDefault(require("path"));
const os_1 = __importDefault(require("os"));
const crypto_1 = __importDefault(require("crypto"));
const storage = multer_1.default.diskStorage({
    destination: (_req, _file, cb) => cb(null, os_1.default.tmpdir()),
    filename: (_req, file, cb) => {
        const ext = path_1.default.extname(file.originalname || "") || ".jpg";
        const name = `evi_${Date.now()}_${crypto_1.default.randomBytes(6).toString("hex")}${ext}`;
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
function fileFilter(_req, file, cb) {
    const mime = String(file.mimetype ?? "").toLowerCase();
    const ext = path_1.default.extname(file.originalname || "").toLowerCase();
    const mimeAllowed = mime.startsWith("image/") || mime === "application/pdf";
    const extAllowed = allowedExtensions.has(ext);
    if (!mimeAllowed && !extAllowed) {
        return cb(new Error("Solo se permiten imagenes o PDF."));
    }
    cb(null, true);
}
exports.uploadEvidencias = (0, multer_1.default)({
    storage,
    fileFilter,
    limits: { fileSize: 10 * 1024 * 1024, files: 10 },
});
