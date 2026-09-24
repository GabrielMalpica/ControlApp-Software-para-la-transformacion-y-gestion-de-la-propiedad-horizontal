import { execFileSync } from "child_process";
import path from "path";
import sharp from "sharp";
import {
  analizarComprobante,
  apagarWorkerOcr,
} from "../../src/services/ComprobanteOcrService";

// Estas pruebas corren el motor real (Tesseract + pdf-parse) sobre comprobantes
// generados en el momento, sin fixtures binarios en el repo.
jest.setTimeout(180_000);

type Linea = { t: string; size?: number; color?: string; bold?: boolean };

function capturaSvg(opts: {
  lineas: Linea[];
  fondo: string;
  encabezado: string;
}) {
  let y = 520;
  const cuerpo = opts.lineas
    .map((l) => {
      y += (l.size ?? 44) + 38;
      return `<text x="70" y="${y}" font-family="Arial, Helvetica, 'DejaVu Sans', sans-serif" font-size="${
        l.size ?? 44
      }" fill="${l.color ?? "#2a2a2a"}" font-weight="${l.bold ? "bold" : "normal"}">${l.t}</text>`;
    })
    .join("");
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="2000">` +
      `<rect width="100%" height="100%" fill="${opts.fondo}"/>` +
      `<rect width="100%" height="420" fill="${opts.encabezado}"/>${cuerpo}</svg>`,
  );
}

const png = (svg: Buffer) => sharp(svg).png().toBuffer();

const contexto = (metodoPago: string, monto: number) => ({
  metodoPago,
  montosEsperados: [monto],
  creadoEn: new Date("2026-09-24T14:00:00Z"),
  ahora: new Date("2026-09-24T16:00:00Z"),
  destinosConfigurados: ["3001234567"],
});

// PDF minimo valido con una pagina de texto (lo que descarga un banco).
function pdfConTexto(lineas: string[]) {
  const escapar = (s: string) => s.replace(/[\\()]/g, "\\$&");
  const contenido =
    "BT /F1 18 Tf 50 750 Td 24 TL " + lineas.map((l) => `(${escapar(l)}) Tj T*`).join(" ") + " ET";
  const objetos = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R /Resources << /Font << /F1 4 0 R >> >> >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    `<< /Length ${Buffer.byteLength(contenido)} >>\nstream\n${contenido}\nendstream`,
  ];
  let salida = "%PDF-1.4\n";
  const offsets: number[] = [];
  objetos.forEach((o, i) => {
    offsets.push(Buffer.byteLength(salida));
    salida += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = Buffer.byteLength(salida);
  salida += `xref\n0 ${objetos.length + 1}\n0000000000 65535 f \n`;
  offsets.forEach((o) => {
    salida += `${String(o).padStart(10, "0")} 00000 n \n`;
  });
  salida += `trailer\n<< /Size ${objetos.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return Buffer.from(salida, "latin1");
}

afterAll(async () => {
  await apagarWorkerOcr();
});

describe("analizarComprobante (motor real)", () => {
  test("captura tipo Nequi (fondo claro, encabezado de color) -> COINCIDE", async () => {
    const buffer = await png(
      capturaSvg({
        fondo: "#ffffff",
        encabezado: "#da0081",
        lineas: [
          { t: "¡Listo! Tu envío quedó", size: 52, bold: true },
          { t: "Para", color: "#777" },
          { t: "JUAN CARLOS PEREZ", bold: true },
          { t: "Cuánto", color: "#777" },
          { t: "$ 374.500", size: 56, bold: true },
          { t: "Fecha", color: "#777" },
          { t: "24 de septiembre de 2026 a las 10:15 a. m." },
          { t: "Referencia", color: "#777" },
          { t: "M4839201" },
          { t: "Disponible $ 1.250.000", color: "#777" },
          { t: "Nequi", color: "#777" },
        ],
      }),
    );

    const v = await analizarComprobante({
      buffer,
      mimeType: "image/png",
      contexto: contexto("nequi", 374500),
    });

    expect(v.montoDetectado).toBe(374500);
    expect(v.referencia).toBe("M4839201");
    expect(v.metodoDetectado).toBe("nequi");
    expect(v.veredicto).toBe("COINCIDE");
    expect(v.motor).toBe("ocr");
  });

  test("captura tipo Bre-B con la llave del negocio -> COINCIDE y valida el destino", async () => {
    const buffer = await png(
      capturaSvg({
        fondo: "#f4f4f4",
        encabezado: "#1d3f8f",
        lineas: [
          { t: "Transferencia exitosa", size: 52, bold: true },
          { t: "Bre-B", bold: true },
          { t: "Valor: $374.500,00" },
          { t: "Llave destino: 3001234567" },
          { t: "Fecha: 24/09/2026 10:20 AM" },
          { t: "Código de la transacción: 2026092410204512" },
        ],
      }),
    );

    const v = await analizarComprobante({
      buffer,
      mimeType: "image/png",
      contexto: contexto("bre_b", 374500),
    });

    expect(v.montoDetectado).toBe(374500);
    expect(v.referencia).toBe("2026092410204512");
    expect(v.checks.find((c) => c.clave === "destino")?.ok).toBe(true);
    expect(v.veredicto).toBe("COINCIDE");
  });

  test("texto claro sobre fondo oscuro se lee con la pasada invertida", async () => {
    const buffer = await png(
      capturaSvg({
        fondo: "#1b1b2f",
        encabezado: "#33334d",
        lineas: [
          { t: "Transferencia exitosa", size: 52, bold: true, color: "#ffffff" },
          { t: "Valor: $18.900", color: "#ffffff" },
          { t: "Fecha: 24/09/2026 09:00 AM", color: "#ffffff" },
          { t: "Referencia: M7788123", color: "#ffffff" },
          { t: "Nequi", color: "#ffffff" },
        ],
      }),
    );

    const v = await analizarComprobante({
      buffer,
      mimeType: "image/png",
      contexto: contexto("nequi", 18900),
    });

    expect(v.montoDetectado).toBe(18900);
    expect(v.referencia).toBe("M7788123");
    expect(v.veredicto).toBe("COINCIDE");
  });

  test("valor distinto al del pedido -> REVISAR", async () => {
    const buffer = await png(
      capturaSvg({
        fondo: "#ffffff",
        encabezado: "#da0081",
        lineas: [
          { t: "Transferencia exitosa", size: 52, bold: true },
          { t: "Valor: $10.000" },
          { t: "Fecha: 24/09/2026 10:20 AM" },
          { t: "Referencia: M1122334" },
          { t: "Nequi" },
        ],
      }),
    );

    const v = await analizarComprobante({
      buffer,
      mimeType: "image/png",
      contexto: contexto("nequi", 374500),
    });

    expect(v.montoDetectado).toBe(10000);
    expect(v.veredicto).toBe("REVISAR");
    expect(v.checks.find((c) => c.clave === "monto")?.ok).toBe(false);
  });

  test("PDF con texto (comprobante bancario) se lee sin OCR", () => {
    // Proceso hijo: ver tests/helpers/analizar-comprobante-cli.ts.
    const salida = execFileSync(
      process.execPath,
      [
        path.join(__dirname, "../../node_modules/tsx/dist/cli.mjs"),
        path.join(__dirname, "../helpers/analizar-comprobante-cli.ts"),
      ],
      {
        input: JSON.stringify({
          base64: pdfConTexto([
            "Comprobante de transferencia Bre-B",
            "Valor: $ 374.500",
            "Fecha: 24/09/2026 10:20 AM",
            "Codigo de la transaccion: 2026092410204512",
            "Llave destino: 3001234567",
          ]).toString("base64"),
          mimeType: "application/pdf",
          contexto: contexto("bre_b", 374500),
        }),
        encoding: "utf8",
        timeout: 120_000,
      },
    );
    const v = JSON.parse(salida.split("@@RESULTADO@@")[1]);

    expect(v.motor).toBe("pdf-texto");
    expect(v.montoDetectado).toBe(374500);
    expect(v.referencia).toBe("2026092410204512");
    expect(v.veredicto).toBe("COINCIDE");
  });

  test("archivo corrupto no lanza: devuelve ILEGIBLE para revision manual", async () => {
    const v = await analizarComprobante({
      buffer: Buffer.from("esto no es una imagen"),
      mimeType: "image/png",
      contexto: contexto("nequi", 1000),
    });
    expect(v.veredicto).toBe("ILEGIBLE");
  });

  test("imagen sin texto -> ILEGIBLE", async () => {
    const buffer = await sharp({
      create: { width: 600, height: 600, channels: 3, background: "#cccccc" },
    })
      .png()
      .toBuffer();
    const v = await analizarComprobante({
      buffer,
      mimeType: "image/png",
      contexto: contexto("nequi", 1000),
    });
    expect(v.veredicto).toBe("ILEGIBLE");
  });
});
