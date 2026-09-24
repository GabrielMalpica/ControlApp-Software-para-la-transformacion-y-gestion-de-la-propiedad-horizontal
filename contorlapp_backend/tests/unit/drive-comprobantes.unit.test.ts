// Carpetas de Drive: los comprobantes de pago van a "comprobantes-pago" DENTRO
// de la carpeta del conjunto, y las evidencias de tareas siguen en su carpeta
// mensual.
type Carpeta = { id: string; name: string; parent: string };

const carpetas: Carpeta[] = [];
const archivos: Array<{ name: string; parents: string[] }> = [];
const creadas: Carpeta[] = [];

const fakeDrive = {
  files: {
    list: jest.fn(async ({ q }: { q: string }) => {
      const nombre = /name='((?:[^'\\]|\\.)*)'/.exec(q)?.[1]?.replace(/\\'/g, "'");
      const padre = /'([^']+)' in parents/.exec(q)?.[1];
      const found = carpetas.filter((c) => c.name === nombre && c.parent === padre);
      return { data: { files: found.map((c) => ({ id: c.id, name: c.name })) } };
    }),
    create: jest.fn(async ({ requestBody, media }: { requestBody: any; media?: any }) => {
      if (requestBody.mimeType === "application/vnd.google-apps.folder") {
        const carpeta = {
          id: `id-${carpetas.length + 1}`,
          name: requestBody.name,
          parent: requestBody.parents[0],
        };
        carpetas.push(carpeta);
        creadas.push(carpeta);
        return { data: { id: carpeta.id } };
      }
      // Como Drive, consume el archivo completo antes de responder.
      await new Promise<void>((resolve, reject) => {
        media.body.on("error", reject).on("end", resolve).resume();
      });
      archivos.push({ name: requestBody.name, parents: requestBody.parents });
      return { data: { id: "archivo-1" } };
    }),
  },
};

jest.mock("googleapis", () => ({
  google: {
    auth: { GoogleAuth: jest.fn() },
    drive: jest.fn(() => fakeDrive),
  },
}));

import fs from "fs";
import os from "os";
import path from "path";
import { uploadEvidenciaToDrive } from "../../src/utils/drive_evidencias";

let archivo: string;

beforeAll(async () => {
  process.env.GOOGLE_CREDENTIALS = JSON.stringify({ private_key: "clave" });
  process.env.DRIVE_EVIDENCIAS_ROOT_ID = "RAIZ";
  archivo = path.join(os.tmpdir(), `drive_test_${Date.now()}.png`);
  await fs.promises.writeFile(archivo, "contenido");
});

afterAll(async () => {
  await fs.promises.unlink(archivo).catch(() => undefined);
});

beforeEach(() => {
  carpetas.length = 0;
  archivos.length = 0;
  creadas.length = 0;
});

const base = () => ({
  filePath: archivo,
  fileName: "Ana_gerente_24-09-2026.png",
  mimeType: "image/png",
  conjuntoNit: "9001234",
  conjuntoNombre: "Los Pinos",
  fecha: new Date("2026-09-24T15:00:00Z"),
});

describe("uploadEvidenciaToDrive con subcarpeta", () => {
  test("crea comprobantes-pago dentro de la carpeta del conjunto y deja ahi el archivo", async () => {
    const url = await uploadEvidenciaToDrive({ ...base(), subcarpeta: "comprobantes-pago" });

    expect(url).toBe("https://drive.google.com/file/d/archivo-1/view");
    const conjunto = carpetas.find((c) => c.name === "Conjunto 9001234 - Los Pinos");
    const comprobantes = carpetas.find((c) => c.name === "comprobantes-pago");
    expect(conjunto?.parent).toBe("RAIZ");
    expect(comprobantes?.parent).toBe(conjunto?.id);
    expect(archivos).toEqual([
      { name: "Ana_gerente_24-09-2026.png", parents: [comprobantes!.id] },
    ]);
  });

  test("no crea la carpeta mensual de evidencias para los comprobantes", async () => {
    await uploadEvidenciaToDrive({ ...base(), subcarpeta: "comprobantes-pago" });
    expect(carpetas.some((c) => c.name.startsWith("Evidencias"))).toBe(false);
  });

  test("si comprobantes-pago ya existe la reutiliza (no la duplica)", async () => {
    await uploadEvidenciaToDrive({ ...base(), subcarpeta: "comprobantes-pago" });
    creadas.length = 0;

    await uploadEvidenciaToDrive({ ...base(), fileName: "Ana_gerente_25-09-2026.png", subcarpeta: "comprobantes-pago" });

    expect(creadas).toEqual([]);
    expect(carpetas.filter((c) => c.name === "comprobantes-pago")).toHaveLength(1);
    expect(archivos).toHaveLength(2);
    expect(archivos[0].parents).toEqual(archivos[1].parents);
  });

  test("cada conjunto tiene su propia carpeta comprobantes-pago", async () => {
    await uploadEvidenciaToDrive({ ...base(), subcarpeta: "comprobantes-pago" });
    await uploadEvidenciaToDrive({
      ...base(),
      conjuntoNit: "8005555",
      conjuntoNombre: "Quintas de Morelia",
      subcarpeta: "comprobantes-pago",
    });

    const conjuntos = carpetas.filter((c) => c.name.startsWith("Conjunto "));
    const comprobantes = carpetas.filter((c) => c.name === "comprobantes-pago");
    expect(conjuntos).toHaveLength(2);
    expect(comprobantes.map((c) => c.parent).sort()).toEqual(conjuntos.map((c) => c.id).sort());
  });
});

describe("uploadEvidenciaToDrive sin subcarpeta (evidencias de tareas)", () => {
  test("sigue usando la carpeta mensual de evidencias", async () => {
    await uploadEvidenciaToDrive(base());

    const mensual = carpetas.find((c) => c.name === "Evidencias Septiembre 2026");
    expect(mensual).toBeDefined();
    expect(archivos[0].parents).toEqual([mensual!.id]);
    expect(carpetas.some((c) => c.name === "comprobantes-pago")).toBe(false);
  });
});
