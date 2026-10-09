import fs from "fs";
import os from "os";
import path from "path";

const mockList = jest.fn();
const mockCreate = jest.fn();

jest.mock("googleapis", () => ({
  google: {
    auth: { GoogleAuth: jest.fn() },
    drive: jest.fn(() => ({ files: { list: mockList, create: mockCreate } })),
  },
}));

import { uploadEvidenciaToDrive } from "../../src/utils/drive_evidencias";

describe("uploadEvidenciaToDrive: caché de carpetas", () => {
  let dir: string;
  let archivo: string;
  let contador = 0;

  beforeAll(async () => {
    process.env.GOOGLE_CREDENTIALS = JSON.stringify({ private_key: "x" });
    process.env.DRIVE_EVIDENCIAS_ROOT_ID = "raiz";
    dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "drive-cache-"));
    archivo = path.join(dir, "foto.jpg");
    await fs.promises.writeFile(archivo, "jpg");
  });
  afterAll(async () => {
    await fs.promises.rm(dir, { recursive: true, force: true });
  });
  beforeEach(() => {
    mockList.mockReset();
    mockCreate.mockReset();
    mockList.mockImplementation(async ({ q }: { q: string }) => ({
      data: { files: [{ id: `carpeta-${q.match(/name='([^']+)'/)?.[1]}` }] },
    }));
    mockCreate.mockImplementation(async () => ({ data: { id: `archivo-${++contador}` } }));
  });

  function subir(conjuntoNit: string) {
    return uploadEvidenciaToDrive({
      filePath: archivo,
      fileName: "foto.jpg",
      mimeType: "image/jpeg",
      conjuntoNit,
      fecha: new Date("2026-10-08T15:00:00"),
    });
  }

  it("las fotos de un cierre comparten la búsqueda de carpetas aunque suban a la vez", async () => {
    const urls = await Promise.all([subir("900"), subir("900"), subir("900")]);

    expect(new Set(urls).size).toBe(3);
    // Antes: 2 búsquedas por foto (6). Ahora: conjunto + mes, una sola vez.
    expect(mockList).toHaveBeenCalledTimes(2);
    expect(mockCreate).toHaveBeenCalledTimes(3);

    await subir("900");
    expect(mockList).toHaveBeenCalledTimes(2);
  });

  it("si la carpeta guardada ya no existe en Drive, la vuelve a buscar una vez", async () => {
    await subir("901");
    expect(mockList).toHaveBeenCalledTimes(2);

    mockCreate.mockRejectedValueOnce(Object.assign(new Error("File not found"), { code: 404 }));
    const url = await subir("901");

    expect(url).toMatch(/^https:\/\/drive\.google\.com\/file\/d\/archivo-/);
    expect(mockList).toHaveBeenCalledTimes(4);
  });
});
