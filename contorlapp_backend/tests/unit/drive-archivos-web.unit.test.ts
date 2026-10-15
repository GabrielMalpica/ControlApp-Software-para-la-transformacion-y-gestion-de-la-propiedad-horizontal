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

import { uploadArchivoWebToDrive, vaciarCacheCarpetasDrive } from "../../src/utils/drive_evidencias";

describe("uploadArchivoWebToDrive", () => {
  let dir: string;
  let archivo: string;
  const creadas: Array<{ name: string; parents: string[]; mimeType?: string }> = [];

  beforeAll(async () => {
    process.env.GOOGLE_CREDENTIALS = JSON.stringify({ private_key: "x" });
    process.env.DRIVE_EVIDENCIAS_ROOT_ID = "raiz-evidencias";
    dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "drive-web-"));
    archivo = path.join(dir, "rut.pdf");
    await fs.promises.writeFile(archivo, "%PDF-1.4");
  });
  afterAll(async () => {
    delete process.env.DRIVE_REGISTROS_ROOT_ID;
    await fs.promises.rm(dir, { recursive: true, force: true });
  });
  beforeEach(() => {
    vaciarCacheCarpetasDrive();
    creadas.length = 0;
    mockList.mockReset();
    mockCreate.mockReset();
    // Ninguna carpeta existe todavia: se crean todas.
    mockList.mockResolvedValue({ data: { files: [] } });
    mockCreate.mockImplementation(async ({ requestBody }: { requestBody: any }) => {
      creadas.push(requestBody);
      return { data: { id: `id-${requestBody.name}` } };
    });
  });

  it("crea Página web / {caso} / {carpeta} y sube el archivo ahi", async () => {
    const res = await uploadArchivoWebToDrive({
      filePath: archivo,
      fileName: "RUT.pdf",
      mimeType: "application/pdf",
      caso: "conjunto",
      carpeta: "900123/4 - Torres: del Llano",
    });

    expect(creadas.map((c) => c.name)).toEqual([
      "Página web",
      "Conjuntos registrados",
      "900123-4 - Torres- del Llano",
      "RUT.pdf",
    ]);
    expect(creadas[0].parents).toEqual(["raiz-evidencias"]);
    expect(creadas[1].parents).toEqual(["id-Página web"]);
    expect(creadas[3].parents).toEqual(["id-900123-4 - Torres- del Llano"]);
    expect(res).toEqual({ fileId: "id-RUT.pdf" });
  });

  it("las postulaciones van a su propia carpeta y respeta DRIVE_REGISTROS_ROOT_ID", async () => {
    process.env.DRIVE_REGISTROS_ROOT_ID = "raiz-registros";
    await uploadArchivoWebToDrive({
      filePath: archivo,
      fileName: "cedula.pdf",
      mimeType: "application/pdf",
      caso: "trabajador",
      carpeta: "Ana Ruiz - #7",
    });
    delete process.env.DRIVE_REGISTROS_ROOT_ID;

    expect(creadas[0]).toMatchObject({ name: "Página web", parents: ["raiz-registros"] });
    expect(creadas[1].name).toBe("Postulaciones de trabajadores");
    expect(creadas[2].name).toBe("Ana Ruiz - #7");
  });
});
