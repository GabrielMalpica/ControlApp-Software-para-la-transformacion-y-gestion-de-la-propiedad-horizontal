import { Rol } from "@prisma/client";
import * as XLSX from "xlsx";

import { ConjuntoExcelTemplateService } from "../../src/services/ConjuntoExcelTemplateService";
import { GerenteService } from "../../src/services/GerenteServices";

function makeFile(buffer: Buffer): Express.Multer.File {
  return {
    buffer,
    originalname: "plantilla_conjunto.xlsx",
    mimetype:
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  } as Express.Multer.File;
}

async function workbookBuffer(
  mutate?: (workbook: XLSX.WorkBook) => void,
): Promise<Buffer> {
  const base = await new ConjuntoExcelTemplateService().generar({
    insumos: [],
    herramientas: [],
    supervisores: [{ id: "1000000000", nombre: "Ana Supervisora" }],
  });
  const workbook = XLSX.read(base, { type: "buffer", cellDates: true });
  mutate?.(workbook);
  return XLSX.write(workbook, { type: "buffer", bookType: "xlsx" });
}

function removeDataRows(workbook: XLSX.WorkBook, sheetName: string): void {
  const matrix = XLSX.utils.sheet_to_json<unknown[]>(workbook.Sheets[sheetName], {
    header: 1,
    raw: true,
  });
  workbook.Sheets[sheetName] = XLSX.utils.aoa_to_sheet([matrix[0]]);
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
        activo: true,
        tipoServicio: ["ASEO", "PISCINA"],
        horarios: [],
      }),
      update: jest.fn().mockResolvedValue({}),
    },
    administrador: { findUnique: jest.fn() },
    usuario: {
      findMany: jest.fn().mockImplementation(({ where }: any) => {
        if (!existingOperario) return Promise.resolve([]);
        if (where.id?.in?.includes("1032456789")) {
          return Promise.resolve([
            {
              id: "1032456789",
              correo: "carlos.perez@example.com",
              rol: Rol.operario,
              operario: { id: "1032456789", empresaId: "EMP-1" },
            },
          ]);
        }
        if (where.correo?.in?.includes("carlos.perez@example.com")) {
          return Promise.resolve([
            { id: "1032456789", correo: "carlos.perez@example.com" },
          ]);
        }
        return Promise.resolve([]);
      }),
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
    supervisor: {
      findUnique: jest.fn().mockImplementation(({ where }: any) =>
        Promise.resolve(
          where.id === "1000000000"
            ? { id: "1000000000", empresaId: "EMP-1" }
            : null,
        ),
      ),
    },
    insumo: { findMany: jest.fn().mockResolvedValue([]) },
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
          ],
        },
        {
          id: 2,
          nombre: "Zona húmeda",
          elementos: [
            { id: 20, nombre: "Piscina", padreId: null },
            { id: 21, nombre: "Piscina principal", padreId: 20 },
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
  prisma.$transaction.mockImplementation(async (callback: any) => callback(prisma));
  return prisma;
}

describe("GerenteService.cargarConjuntoMasivo", () => {
  test("aborta antes de escribir cuando el NIT ya existe", async () => {
    const prisma = makePrisma();
    prisma.conjunto.findUnique.mockResolvedValueOnce({ nit: "900123456-7" });
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");

    await expect(
      service.cargarConjuntoMasivo(
        "gerente-1",
        makeFile(await workbookBuffer()),
      ),
    ).rejects.toThrow(/NIT/i);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  test("informa claramente cuando falta la hoja Conjunto", async () => {
    const service = new GerenteService(makePrisma());
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = await workbookBuffer((workbook) => {
      delete workbook.Sheets.Conjunto;
      workbook.SheetNames = workbook.SheetNames.filter(
        (name) => name !== "Conjunto",
      );
    });
    await expect(
      service.cargarConjuntoMasivo("gerente-1", makeFile(buffer)),
    ).rejects.toThrow(/hoja Conjunto/i);
  });

  test("rechaza cédula repetida sin ejecutar la transacción", async () => {
    const prisma = makePrisma(false);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = await workbookBuffer((workbook) => {
      const matrix = XLSX.utils.sheet_to_json<unknown[]>(
        workbook.Sheets.Operarios,
        { header: 1, raw: true },
      );
      const duplicate = [...matrix[1]];
      duplicate[1] = "Carlos duplicado";
      duplicate[2] = "otro@example.com";
      XLSX.utils.sheet_add_aoa(workbook.Sheets.Operarios, [duplicate], {
        origin: -1,
      });
    });
    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(buffer),
    );
    expect(result.creado).toBe(false);
    expect(result.errores).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          seccion: "Operarios",
          motivo: expect.stringMatching(/repetida/i),
        }),
      ]),
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  test("rechaza periodos de disponibilidad solapados", async () => {
    const prisma = makePrisma(false);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = await workbookBuffer((workbook) => {
      XLSX.utils.sheet_add_aoa(
        workbook.Sheets["Disponibilidad operarios"],
        [["1032456789", "2026-01-20", "", "No", "", "Solapado"]],
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
        expect.objectContaining({
          seccion: "Disponibilidad operarios",
          motivo: expect.stringMatching(/solapan/i),
        }),
      ]),
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  test("crea el usuario con datos laborales y expande una semanal multidía", async () => {
    const prisma = makePrisma(false);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(await workbookBuffer()),
    );

    expect(result.creado).toBe(true);
    expect(result.resumen).toMatchObject({
      horarios: 6,
      ubicaciones: 2,
      operariosCreados: 1,
      preventivasTotal: 2,
      preventivasCreadas: 2,
      definicionesCreadas: 3,
    });
    expect(prisma.usuario.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          estadoCivil: "SOLTERO",
          tipoContrato: "TERMINO_INDEFINIDO",
          direccion: "Calle 10 # 20-30",
        }),
      }),
    );
    expect(prisma.operario.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          observaciones: "Operario creado desde la plantilla",
          disponibilidadPeriodos: expect.any(Object),
        }),
      }),
    );
    expect(prisma.definicionTareaPreventiva.create).toHaveBeenCalledTimes(3);
  });

  test("reutiliza y vincula un operario sin sobrescribirlo", async () => {
    const prisma = makePrisma(true);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = await workbookBuffer((workbook) =>
      removeDataRows(workbook, "Disponibilidad operarios"),
    );
    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(buffer),
    );
    expect(result.creado).toBe(true);
    expect(result.resumen.operariosReutilizados).toBe(1);
    expect(prisma.usuario.create).not.toHaveBeenCalled();
    expect(prisma.operario.create).not.toHaveBeenCalled();
    expect(prisma.conjunto.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { operarios: { connect: [{ id: "1032456789" }] } },
      }),
    );
  });

  test("guarda planes de insumos, maquinaria y herramientas", async () => {
    const prisma = makePrisma(false);
    prisma.insumo.findMany.mockResolvedValue([
      { id: 1, nombre: "Cloro", unidad: "LITRO" },
    ]);
    prisma.herramienta.findMany.mockResolvedValue([
      { id: 2, nombre: "Escoba", unidad: "UNIDAD" },
    ]);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = await workbookBuffer((workbook) => {
      XLSX.utils.sheet_add_aoa(
        workbook.Sheets["Insumos preventivas"],
        [["PREV-001", "1 | Cloro | LITRO", "LITRO", 0.5]],
        { origin: -1 },
      );
      XLSX.utils.sheet_add_aoa(
        workbook.Sheets["Herramientas preventivas"],
        [["PREV-001", "2 | Escoba | UNIDAD", "UNIDAD", 2]],
        { origin: -1 },
      );
    });
    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(buffer),
    );
    expect(result.creado).toBe(true);
    expect(result.resumen).toMatchObject({
      insumosPreventivas: 1,
      maquinariaPreventivas: 1,
      herramientasPreventivas: 1,
    });
    expect(prisma.definicionTareaPreventiva.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          insumosPlanJson: [{ insumoId: 1, consumoPorUnidad: 0.5 }],
          maquinariaPlanJson: [
            expect.objectContaining({
              tipo: "HIDROLAVADORA_ELECTRICA",
              cantidad: 1,
            }),
          ],
          herramientasPlanJson: [{ herramientaId: 2, cantidad: 2 }],
        }),
      }),
    );
  });

  test("operario inexistente falla solo su preventiva", async () => {
    const prisma = makePrisma(true);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = await workbookBuffer((workbook) => {
      removeDataRows(workbook, "Disponibilidad operarios");
      workbook.Sheets.Preventivas.T2.v = "9999999999";
    });
    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(buffer),
    );
    expect(result.creado).toBe(true);
    expect(result.resumen.preventivasCreadas).toBe(1);
    expect(result.resumen.preventivasFallidas).toBe(1);
    expect(result.errores).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ seccion: "Preventivas", fila: 2 }),
      ]),
    );
  });

  test("QUINCENAL con varios días falla solo su fila", async () => {
    const prisma = makePrisma(true);
    const service = new GerenteService(prisma);
    (service as any).resolverEmpresaNit = jest.fn().mockResolvedValue("EMP-1");
    const buffer = await workbookBuffer((workbook) => {
      removeDataRows(workbook, "Disponibilidad operarios");
      workbook.Sheets.Preventivas.F2.v = "Quincenal";
      workbook.Sheets.Preventivas.G2.v = "Lunes, Miércoles";
    });

    const result = await service.cargarConjuntoMasivo(
      "gerente-1",
      makeFile(buffer),
    );

    expect(result.creado).toBe(true);
    expect(result.resumen.preventivasCreadas).toBe(1);
    expect(result.resumen.preventivasFallidas).toBe(1);
    expect(result.errores).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          seccion: "Preventivas",
          fila: 2,
          motivo: expect.stringMatching(/exactamente un día/i),
        }),
      ]),
    );
  });
});
