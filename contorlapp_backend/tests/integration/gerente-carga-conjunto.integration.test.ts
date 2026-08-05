import express from "express";
import jwt from "jsonwebtoken";
import request from "supertest";
import * as XLSX from "xlsx";

const cargarConjuntoMasivoMock = jest.fn();
const generarPlantillaConjuntoMock = jest.fn();

jest.mock("../../src/services/GerenteServices", () => ({
  GerenteService: jest.fn().mockImplementation(() => ({
    cargarConjuntoMasivo: cargarConjuntoMasivoMock,
    generarPlantillaConjunto: generarPlantillaConjuntoMock,
  })),
}));
jest.mock("../../src/db/prisma", () => ({ prisma: {} }));

import gerenteRouter from "../../src/routes/Gerente";

function sampleBuffer(): Buffer {
  const workbook = XLSX.utils.book_new();
  for (const name of [
    "Conjunto",
    "Horarios",
    "Ubicaciones",
    "Operarios",
    "Disponibilidad operarios",
    "Preventivas",
    "Insumos preventivas",
    "Maquinaria preventivas",
    "Herramientas preventivas",
    "Opciones",
  ]) {
    XLSX.utils.book_append_sheet(
      workbook,
      XLSX.utils.aoa_to_sheet([["header"], ["ejemplo"]]),
      name,
    );
  }
  return XLSX.write(workbook, { type: "buffer", bookType: "xlsx" });
}

function makeApp() {
  const app = express();
  app.use(express.json());
  app.use("/gerente", gerenteRouter);
  app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    res.status(400).json({ message: err.message });
  });
  return app;
}

describe("Endpoints de carga masiva de conjunto", () => {
  const secret = "test-secret";
  let token: string;

  beforeAll(() => {
    process.env.JWT_SECRET = secret;
    token = jwt.sign(
      { sub: "gerente-1", rol: "gerente", correo: "gerente@test.com" },
      secret,
    );
  });

  test("POST recibe buffer multipart y devuelve resumen con errores", async () => {
    cargarConjuntoMasivoMock.mockResolvedValueOnce({
      creado: true,
      conjunto: { nit: "900-1", nombre: "Conjunto Uno" },
      resumen: {
        horarios: 6,
        ubicaciones: 2,
        operariosCreados: 1,
        operariosReutilizados: 0,
        preventivasTotal: 2,
        preventivasCreadas: 1,
        preventivasFallidas: 1,
        definicionesCreadas: 1,
        insumosPreventivas: 0,
        maquinariaPreventivas: 0,
        herramientasPreventivas: 0,
      },
      errores: [{ fila: 3, seccion: "Preventivas", motivo: "Operario inexistente" }],
      columnasEsperadas: {},
    });

    const response = await request(makeApp())
      .post("/gerente/conjuntos/carga-masiva")
      .set("Authorization", `Bearer ${token}`)
      .attach("file", sampleBuffer(), {
        filename: "plantilla_conjunto.xlsx",
        contentType:
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      });

    expect(response.status).toBe(201);
    expect(response.body.resumen.preventivasFallidas).toBe(1);
    expect(cargarConjuntoMasivoMock).toHaveBeenCalledWith(
      "gerente-1",
      expect.objectContaining({ originalname: "plantilla_conjunto.xlsx" }),
    );
  });

  test("GET devuelve un attachment XLSX válido", async () => {
    generarPlantillaConjuntoMock.mockResolvedValueOnce(sampleBuffer());

    const response = await request(makeApp())
      .get("/gerente/conjuntos/plantilla")
      .set("Authorization", `Bearer ${token}`)
      .buffer(true)
      .parse((res, callback) => {
        const chunks: Buffer[] = [];
        res.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
        res.on("end", () => callback(null, Buffer.concat(chunks)));
      });

    expect(response.status).toBe(200);
    expect(response.headers["content-disposition"]).toContain("plantilla_conjunto.xlsx");
    const workbook = XLSX.read(response.body as Buffer, { type: "buffer" });
    expect(workbook.SheetNames).toEqual([
      "Conjunto",
      "Horarios",
      "Ubicaciones",
      "Operarios",
      "Disponibilidad operarios",
      "Preventivas",
      "Insumos preventivas",
      "Maquinaria preventivas",
      "Herramientas preventivas",
      "Opciones",
    ]);
  });
});
