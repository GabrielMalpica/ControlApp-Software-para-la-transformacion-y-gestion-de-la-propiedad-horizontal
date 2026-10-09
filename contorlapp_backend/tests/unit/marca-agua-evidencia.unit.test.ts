import fs from "fs";
import os from "os";
import path from "path";
import sharp from "sharp";

jest.mock("../../src/utils/direccion_gps", () => ({
  direccionGpsSinDemora: jest.fn(),
}));

import { direccionGpsSinDemora } from "../../src/utils/direccion_gps";
import {
  estamparMarcaAgua,
  formatearFechaMarcaAgua,
  lineasMarcaAgua,
  parsearCapturasEvidencias,
  subirEvidenciasConMarca,
} from "../../src/utils/marca_agua_evidencia";

const direccionMock = direccionGpsSinDemora as jest.MockedFunction<typeof direccionGpsSinDemora>;

const AHORA = new Date("2026-10-08T20:00:00.000Z"); // 3:00 p. m. en Bogotá
const PDF = "%PDF-1.4 acta";

async function fotoNegra(ancho: number, alto: number, orientacion?: number) {
  let img = sharp({
    create: { width: ancho, height: alto, channels: 3, background: { r: 0, g: 0, b: 0 } },
  });
  if (orientacion) img = img.withMetadata({ orientation: orientacion });
  return img.jpeg().toBuffer();
}

/** Brillo promedio (0-255) de una región de la imagen ya orientada. */
async function brillo(
  imagen: Buffer,
  region: { left: number; top: number; width: number; height: number },
) {
  const { data } = await sharp(imagen).rotate().extract(region).greyscale().raw().toBuffer({
    resolveWithObject: true,
  });
  let total = 0;
  for (const v of data) total += v;
  return total / data.length;
}

describe("formatearFechaMarcaAgua", () => {
  it("usa la hora de Colombia con el formato de las cámaras con fecha", () => {
    expect(formatearFechaMarcaAgua(new Date("2026-10-03T00:39:09.000Z"))).toBe(
      "2 oct 2026 7:39:09 p. m.",
    );
    expect(formatearFechaMarcaAgua(new Date("2026-09-15T05:00:00.000Z"))).toBe(
      "15 sept 2026 12:00:00 a. m.",
    );
    expect(formatearFechaMarcaAgua(new Date("2026-01-05T14:05:07.000Z"))).toBe(
      "5 ene 2026 9:05:07 a. m.",
    );
  });
});

describe("parsearCapturasEvidencias", () => {
  it("alinea cada captura con su archivo y tolera huecos", () => {
    const raw = JSON.stringify([
      { tomadaEn: "2026-10-08T19:58:00.000Z", latitud: 4.14, longitud: -73.62 },
      null,
    ]);
    const capturas = parsearCapturasEvidencias(raw, 3, AHORA);
    expect(capturas).toHaveLength(3);
    expect(capturas[0]).toEqual({
      tomadaEn: new Date("2026-10-08T19:58:00.000Z"),
      latitud: 4.14,
      longitud: -73.62,
    });
    expect(capturas[1]).toBeNull();
    expect(capturas[2]).toBeNull();
  });

  it("ignora metadatos mal formados sin hacer fallar el cierre", () => {
    expect(parsearCapturasEvidencias("no-es-json", 2, AHORA)).toEqual([null, null]);
    expect(parsearCapturasEvidencias('{"a":1}', 1, AHORA)).toEqual([null]);
    expect(parsearCapturasEvidencias(undefined, 1, AHORA)).toEqual([null]);
    expect(parsearCapturasEvidencias('[{"latitud":"x"}]', 1, AHORA)).toEqual([null]);
  });

  it("descarta horas del futuro o demasiado viejas (reloj del celular mal)", () => {
    const raw = JSON.stringify([
      { tomadaEn: "2026-10-08T21:00:00.000Z" },
      { tomadaEn: "2026-06-01T12:00:00.000Z", latitud: 4.1, longitud: -73.6 },
      { tomadaEn: "2026-10-05T12:00:00.000Z" },
    ]);
    const [futura, vieja, sinSenal] = parsearCapturasEvidencias(raw, 3, AHORA);
    expect(futura).toBeNull();
    expect(vieja).toEqual({ tomadaEn: null, latitud: 4.1, longitud: -73.6 });
    expect(sinSenal?.tomadaEn).toEqual(new Date("2026-10-05T12:00:00.000Z"));
  });

  it("solo toma el GPS si vienen latitud y longitud", () => {
    const raw = JSON.stringify([{ tomadaEn: "2026-10-08T19:59:00.000Z", latitud: 4.1 }]);
    expect(parsearCapturasEvidencias(raw, 1, AHORA)[0]).toEqual({
      tomadaEn: new Date("2026-10-08T19:59:00.000Z"),
      latitud: null,
      longitud: null,
    });
  });
});

describe("lineasMarcaAgua", () => {
  const conjunto = {
    nombre: "Torres del Barzal",
    direccion: "Calle 33a # 39-37",
    latitud: "4.1418000",
    longitud: "-73.6265000",
  };
  const direccionGps = { calle: "Carrera 24B", barrio: "San Francisco", ciudad: "Villavicencio" };

  it("foto tomada en la app: hora, conjunto, calle, barrio, ciudad y distancia", () => {
    const lineas = lineasMarcaAgua({
      captura: {
        tomadaEn: new Date("2026-10-08T19:58:30.000Z"),
        latitud: 4.142013,
        longitud: -73.626641,
      },
      subidaEn: AHORA,
      conjunto,
      direccionGps,
    });
    expect(lineas).toEqual([
      "8 oct 2026 2:58:30 p. m.",
      "Torres del Barzal",
      "Carrera 24B",
      "San Francisco",
      "Villavicencio",
      "a 28 m del conjunto",
    ]);
  });

  it("sin dirección del GPS usa la dirección registrada del conjunto", () => {
    const lineas = lineasMarcaAgua({
      captura: { tomadaEn: new Date("2026-10-08T19:58:30.000Z"), latitud: 4.142013, longitud: -73.626641 },
      subidaEn: AHORA,
      conjunto,
      direccionGps: null,
    });
    expect(lineas).toEqual([
      "8 oct 2026 2:58:30 p. m.",
      "Torres del Barzal",
      "Calle 33a # 39-37",
      "a 28 m del conjunto",
    ]);
  });

  it("omite los datos de dirección que no vengan", () => {
    const lineas = lineasMarcaAgua({
      captura: { tomadaEn: AHORA, latitud: 4.142013, longitud: -73.626641 },
      subidaEn: AHORA,
      conjunto: { nombre: "Torres del Barzal" },
      direccionGps: { calle: "Carrera 24B", barrio: null, ciudad: "Villavicencio" },
    });
    expect(lineas).toEqual([
      "8 oct 2026 3:00:00 p. m.",
      "Torres del Barzal",
      "Carrera 24B",
      "Villavicencio",
    ]);
  });

  it("cierre guardado sin señal: agrega cuándo se subió", () => {
    const lineas = lineasMarcaAgua({
      captura: { tomadaEn: new Date("2026-10-07T13:00:00.000Z"), latitud: null, longitud: null },
      subidaEn: AHORA,
      conjunto: { nombre: "Torres del Barzal" },
    });
    expect(lineas).toEqual([
      "7 oct 2026 8:00:00 a. m.",
      "Subida 8 oct 2026 3:00:00 p. m.",
      "Torres del Barzal",
    ]);
  });

  it("archivo adjuntado (sin hora de captura): solo afirma la hora de subida", () => {
    const lineas = lineasMarcaAgua({ captura: null, subidaEn: AHORA, conjunto: null });
    expect(lineas).toEqual(["Subida 8 oct 2026 3:00:00 p. m."]);
  });

  it("muestra la distancia en km cuando la foto está lejos del conjunto", () => {
    const lineas = lineasMarcaAgua({
      captura: { tomadaEn: AHORA, latitud: 4.16, longitud: -73.6265 },
      subidaEn: AHORA,
      conjunto,
    });
    expect(lineas).toContain("a 2,0 km del conjunto");
  });
});

describe("estamparMarcaAgua", () => {
  it("escribe el texto abajo a la derecha y conserva tamaño y formato", async () => {
    const original = await fotoNegra(800, 600);
    const salida = await estamparMarcaAgua(original, ["8 oct 2026 3:00:00 p. m.", "Ana · Operario"]);
    const meta = await sharp(salida).metadata();
    expect(meta.format).toBe("jpeg");
    expect([meta.width, meta.height]).toEqual([800, 600]);
    expect(await brillo(salida, { left: 560, top: 540, width: 220, height: 50 })).toBeGreaterThan(20);
    expect(await brillo(salida, { left: 0, top: 0, width: 300, height: 300 })).toBeLessThan(2);
  });

  it("respeta la orientación EXIF para que la marca quede donde se ve la esquina", async () => {
    // Guardada acostada (800x600) pero se ve vertical (600x800).
    const original = await fotoNegra(800, 600, 6);
    const salida = await estamparMarcaAgua(original, ["8 oct 2026 3:00:00 p. m."]);
    const meta = await sharp(salida).metadata();
    expect([meta.width, meta.height]).toEqual([600, 800]);
    expect(meta.orientation ?? 1).toBe(1);
    expect(await brillo(salida, { left: 380, top: 740, width: 200, height: 40 })).toBeGreaterThan(20);
  });

  it("conserva PNG como PNG", async () => {
    const png = await sharp({
      create: { width: 400, height: 300, channels: 3, background: { r: 0, g: 0, b: 0 } },
    })
      .png()
      .toBuffer();
    const salida = await estamparMarcaAgua(png, ["Subida 8 oct 2026 3:00:00 p. m."]);
    expect((await sharp(salida).metadata()).format).toBe("png");
  });
});

describe("subirEvidenciasConMarca", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "marca-agua-"));
    direccionMock.mockResolvedValue({
      calle: "Carrera 24B",
      barrio: "San Francisco",
      ciudad: "Villavicencio",
    });
  });
  afterEach(async () => {
    await fs.promises.rm(dir, { recursive: true, force: true });
  });

  async function jpg(nombre: string) {
    const ruta = path.join(dir, nombre);
    const datos = await fotoNegra(640, 480);
    await fs.promises.writeFile(ruta, datos);
    return {
      file: { path: ruta, originalname: nombre, mimetype: "image/jpeg", size: datos.length } as Express.Multer.File,
      original: datos,
    };
  }

  it("sube cada imagen ya estampada, en orden, y deja intactos PDFs e inexistentes", async () => {
    const a = await jpg("a.jpg");
    const b = await jpg("b.jpg");
    const pdfPath = path.join(dir, "acta.pdf");
    await fs.promises.writeFile(pdfPath, PDF);
    const files = [
      a.file,
      { path: pdfPath, originalname: "acta.pdf", mimetype: "application/pdf", size: 9 },
      { path: path.join(dir, "no-existe.jpg"), originalname: "x.jpg", mimetype: "image/jpeg" },
      b.file,
    ] as Express.Multer.File[];

    const vistos: Array<{ nombre: string; indice: number; estampada: boolean }> = [];
    const urls = await subirEvidenciasConMarca(
      {
        files,
        capturas: JSON.stringify([
          { tomadaEn: "2026-10-08T19:59:00.000Z", latitud: 4.142, longitud: -73.6266 },
        ]),
        conjunto: { nombre: "Torres del Barzal" },
        subidaEn: AHORA,
      },
      async (f, indice) => {
        const estampada =
          f.mimetype === "image/jpeg" && fs.existsSync(f.path)
            ? !(await fs.promises.readFile(f.path)).equals(f === a.file ? a.original : b.original)
            : false;
        vistos.push({ nombre: f.originalname, indice, estampada });
        return `url-${indice}`;
      },
    );

    // Suben varias a la vez: el orden de llegada puede variar, el resultado no.
    expect(urls).toEqual(["url-1", "url-2", "url-3", "url-4"]);
    expect(vistos.sort((x, y) => x.indice - y.indice)).toEqual([
      { nombre: "a.jpg", indice: 1, estampada: true },
      { nombre: "acta.pdf", indice: 2, estampada: false },
      { nombre: "x.jpg", indice: 3, estampada: false },
      { nombre: "b.jpg", indice: 4, estampada: true },
    ]);
    // Solo se consulta dirección para la foto que trae GPS, con espera acotada.
    expect(direccionMock).toHaveBeenCalledTimes(1);
    expect(direccionMock).toHaveBeenCalledWith(4.142, -73.6266, 700);

    const estampada = await fs.promises.readFile(a.file.path);
    expect(a.file.size).toBe(estampada.length);
    expect(await brillo(estampada, { left: 400, top: 350, width: 220, height: 110 })).toBeGreaterThan(10);
    expect(await brillo(estampada, { left: 0, top: 0, width: 300, height: 300 })).toBeLessThan(2);
    expect(await fs.promises.readFile(pdfPath, "utf8")).toBe(PDF);
  });

  function pdfs(cantidad: number) {
    return Array.from({ length: cantidad }, (_, i) => ({
      path: path.join(dir, `no-existe-${i}.pdf`),
      originalname: `${i}.pdf`,
      mimetype: "application/pdf",
    })) as Express.Multer.File[];
  }
  const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));

  it("sube hasta 3 a la vez y devuelve los resultados en orden", async () => {
    let activas = 0;
    let maximo = 0;
    const inicio = Date.now();
    const urls = await subirEvidenciasConMarca(
      { files: pdfs(6), capturas: undefined, conjunto: null },
      async (_f, indice) => {
        activas++;
        maximo = Math.max(maximo, activas);
        await esperar(indice <= 3 ? 120 : 40); // las primeras tardan más
        activas--;
        return indice;
      },
    );
    expect(urls).toEqual([1, 2, 3, 4, 5, 6]);
    expect(maximo).toBe(3);
    // En serie serían ~480 ms; de a 3 son ~160 ms.
    expect(Date.now() - inicio).toBeLessThan(400);
  });

  it("si una subida falla no empieza las que faltan", async () => {
    const llamadas: number[] = [];
    await expect(
      subirEvidenciasConMarca(
        { files: pdfs(6), capturas: undefined, conjunto: null },
        async (_f, indice) => {
          llamadas.push(indice);
          await esperar(20);
          if (indice === 1) throw new Error("Drive caído");
          return indice;
        },
      ),
    ).rejects.toThrow("Drive caído");
    expect(llamadas.sort()).toEqual([1, 2, 3]);
  });

  it("si una subida falla, espera el estampado en curso antes de propagar el error", async () => {
    const a = await jpg("a.jpg");
    const b = await jpg("b.jpg");
    const promesa = subirEvidenciasConMarca(
      { files: [a.file, b.file], capturas: undefined, conjunto: null, subidaEn: AHORA },
      async () => {
        throw new Error("Drive caído");
      },
    );
    await expect(promesa).rejects.toThrow("Drive caído");
    // La segunda foto ya terminó de estamparse: borrar los temporales ahora
    // no deja archivos a medio escribir.
    expect((await fs.promises.readFile(b.file.path)).equals(b.original)).toBe(false);
  });
});
