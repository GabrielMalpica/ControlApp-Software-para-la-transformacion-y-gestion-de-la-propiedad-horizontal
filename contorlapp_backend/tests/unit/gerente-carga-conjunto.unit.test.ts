import { Rol } from "@prisma/client";
import * as XLSX from "xlsx";

import { GerenteService } from "../../src/services/GerenteServices";

function makeFile(buffer: Buffer): Express.Multer.File {
  return {
    buffer,
    originalname: "plantilla_conjunto.xlsx",
    mimetype:
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  } as Express.Multer.File;
}

function workbookBuffer(
  mutate?: (workbook: XLSX.WorkBook) => void,
): Buffer {
  const base = new GerenteService({} as any).generarPlantillaConjunto();
  const workbook = XLSX.read(base, { type: "buffer", cellDates: true });
  mutate?.(workbook);
  return XLSX.write(workbook, { type: "buffer", bookType: "xlsx" });
}

function makePrisma(existingOperario = true) {
  let elementId = 100;
  const prisma: any = {
    $transaction: jest.fn(),
    conjunto: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockResolvedValue({
        nit: "900123456-7",
        nombre: "Conjunto Mirador del Parque",
        direccion: "Carrera 10 # 20-30",
        correo: "administracion@miradordelparque.com",
        administradorId: null,
        empresaId: "EMP-1",
        fechaInicioContrato: new Date("2026-01-15T00:00:00.000Z"),
        fechaFinContrato: null,
        activo: true,
        tipoServicio: ["ASEO", "PISCINA", "MANTENIMIENTOS_LOCATIVOS"],
        valorMensual: 8500000,
        consignasEspeciales: [],
        valorAgregado: [],
        horarios: [],
      }),
      update: jest.fn().mockResolvedValue({}),
    },
    administrador: { findUnique: jest.fn() },
    usuario: {
      findUnique: jest.fn().mockImplementation(({ where }: any) => {
        if (!existingOperario) return Promise.resolve(null);
        if (where.id === "1032456789") {
          return Promise.resolve({
            id: "1032456789",
            rol: Rol.operario,
            operario: { id: "1032456789", empresaId: "EMP-1" },
          });
        }
        if (where.correo === "carlos.perez@example.com") {
          return Promise.resolve({ id: "1032456789" });
        }
        return Promise.resolve(null);
      }),
      create: jest.fn().mockResolvedValue({}),
    },
    operario: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockResolvedValue({}),
    },
    supervisor: { findUnique: jest.fn().mockResolvedValue(null) },
    ubicacion: {
      findFirst: jest.fn().mockImplementation(({ where }: any) =>
        Promise.resolve({ id: where.nombre === "Torre 1" ? 1 : 2 }),
      ),
      findMany: jest.fn().mockResolvedValue([
        {
          id: 1,
          nombre: "Torre 1",
          elementos: [
            { id: 10, nombre: "Zonas comunes", padreId: null },
            { id: 11, nombre: "Lobby", padreId: 10 },
            { id: 12, nombre: "Escaleras", padreId: 10 },
          ],
        },
        {
          id: 2,
          nombre: "Zona húmeda",
          elementos: [
            { id: 20, nombre: "Piscina", padreId: null },
            { id: 21, nombre: "Piscina principal", padreId: 20 },
            { id: 22, nombre: "Cuarto de máquinas", padreId: 20 },
          ],
        },
      ]),
    },
    elemento: {
      create: jest.fn().mockImplementation(() => Promise.resolve({ id: elementId++ })),
    },
    herramienta: { findMany: jest.fn().mockResolvedValue([]) },
    conjuntoHerramientaStock: { createMany: jest.fn() },
    definicionTareaPreventiva: {
      create: jest.fn().mockImplementation(({ data }: any) =>
        Promise.resolve({ id: elementId++, ...data }),
      ),
    },
  };
  prisma.$transaction.mockImplementation(async (cb: any) => cb(prisma));
  return prisma;
}

describe("GerenteService.cargarConjuntoMasivo", () => {
  test("aborta antes de escribir cuando el NIT ya existe", async () => {
    const prisma = makePrisma();
    prisma.conjunto.findUnique.mockResolvedValueOnce({ nit: "900123456-7" });
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");

    await expect(
      service.cargarConjuntoMasivo("gerente-1", makeFile(workbookBuffer())),
    ).rejects.toThrow(/NIT/i);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  test("informa claramente cuando falta la hoja Conjunto", async () => {
    const service = new GerenteService(makePrisma());
    const buffer = workbookBuffer((workbook) => {
      delete workbook.Sheets.Conjunto;
      workbook.SheetNames = workbook.SheetNames.filter((name) => name !== "Conjunto");
    });

    await expect(
      service.cargarConjuntoMasivo("gerente-1", makeFile(buffer)),
    ).rejects.toThrow(/hoja Conjunto/i);
  });

  test("rechaza cédula repetida sin ejecutar la transacción", async () => {
    const prisma = makePrisma();
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = workbookBuffer((workbook) => {
      XLSX.utils.sheet_add_aoa(
        workbook.Sheets.Operarios,
        [
          [
            "1032456789",
            "Carlos duplicado",
            "otro@example.com",
            "3009999999",
            "1992-06-15",
            "ASEO",
            "2026-01-15",
            "COMPLETA",
            "",
            "NO",
            "NO",
            "SI",
            "NO",
            "",
            "1032456789",
          ],
        ],
        { origin: -1 },
      );
    });

    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(buffer),
    );

    expect(result.creado).toBe(false);
    expect(result.errores).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ seccion: "Operarios", motivo: expect.stringMatching(/repetida/i) }),
      ]),
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  test("reutiliza, vincula y crea preventivas válidas", async () => {
    const prisma = makePrisma(true);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");

    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(workbookBuffer()),
    );

    expect(result.creado).toBe(true);
    expect(result.resumen).toMatchObject({
      horarios: 6,
      ubicaciones: 2,
      operariosCreados: 0,
      operariosReutilizados: 1,
      preventivasTotal: 3,
      preventivasCreadas: 3,
      preventivasFallidas: 0,
    });
    expect(prisma.conjunto.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { operarios: { connect: [{ id: "1032456789" }] } },
      }),
    );
    expect(prisma.definicionTareaPreventiva.create).toHaveBeenCalledTimes(3);
  });

  test("operario inexistente falla solo su preventiva", async () => {
    const prisma = makePrisma(true);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = workbookBuffer((workbook) => {
      workbook.Sheets.Preventivas.K2.v = "9999999999";
    });

    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(buffer),
    );

    expect(result.creado).toBe(true);
    expect(result.resumen.preventivasCreadas).toBe(2);
    expect(result.resumen.preventivasFallidas).toBe(1);
    expect(result.errores[0]).toMatchObject({ seccion: "Preventivas", fila: 2 });
  });
});
