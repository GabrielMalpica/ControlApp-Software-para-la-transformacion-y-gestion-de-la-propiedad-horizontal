"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FileStorageService = void 0;
class FileStorageService {
    async subirArchivo(_buffer, nombreArchivo) {
        // Simulamos que subimos el archivo y devolvemos una URL falsa
        return `https://archivos.control-limpieza.com/fake-drive/${nombreArchivo}`;
    }
}
exports.FileStorageService = FileStorageService;
