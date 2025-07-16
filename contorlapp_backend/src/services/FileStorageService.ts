export class FileStorageService {
  async subirArchivo(_buffer: Buffer, nombreArchivo: string): Promise<string> {
    // Simulamos que subimos el archivo y devolvemos una URL falsa
    return `https://archivos.control-limpieza.com/fake-drive/${nombreArchivo}`;
  }
}
