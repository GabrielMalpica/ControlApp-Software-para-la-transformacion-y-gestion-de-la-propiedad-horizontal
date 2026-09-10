import {
  CrearHerramientasInventarioBody,
  CrearMaquinariaInventarioBody,
  ListaHerramientasQuery,
  ListaMaquinariaQuery,
} from "../../src/model/InventarioActivo";
import { InventarioActivoService } from "../../src/services/InventarioActivoService";
import { normalizarNombreCatalogo } from "../../src/utils/catalogoInventario";
import { matchesDeclaredType } from "../../src/middlewares/upload_evidencias";

describe("Inventario físico de activos", () => {
  test.each([
    ["Cortasetos", "cortasetos"],
    ["Corta setos", "cortasetos"],
    ["CORTA-SÉTOS", "cortasetos"],
    ["  Guadaña eléctrica ", "guadanaelectrica"],
  ])("normaliza %s a una clave canónica estable", (value, expected) => {
    expect(normalizarNombreCatalogo(value)).toBe(expected);
  });

  test("exige catálogo existente o propuesta, pero no ambos", () => {
    expect(() =>
      CrearMaquinariaInventarioBody.parse({
        marca: "Stihl",
      }),
    ).toThrow();
    expect(() =>
      CrearMaquinariaInventarioBody.parse({
        tipoCatalogoId: 10,
        tipoPropuesto: { nombre: "Cortasetos" },
        marca: "Stihl",
      }),
    ).toThrow();
    expect(
      CrearMaquinariaInventarioBody.parse({
        tipoCatalogoId: 10,
        marca: "Stihl",
      }).tipoCatalogoId,
    ).toBe(10);
  });

  test("cada lote es individualizable y no acepta un serial compartido", () => {
    expect(() =>
      CrearHerramientasInventarioBody.parse({
        herramientaId: 20,
        cantidad: 3,
        serial: "SERIAL-COMPARTIDO",
      }),
    ).toThrow(/serial/i);
    expect(
      CrearHerramientasInventarioBody.parse({
        herramientaId: 20,
        cantidad: 3,
      }).cantidad,
    ).toBe(3);
  });

  test("valida la firma real de las fotografías y rechaza extensiones simuladas", () => {
    const jpeg = {
      originalname: "equipo.jpg",
      mimetype: "image/jpeg",
    } as Express.Multer.File;
    const png = {
      originalname: "equipo.png",
      mimetype: "image/png",
    } as Express.Multer.File;

    expect(
      matchesDeclaredType(jpeg, Buffer.from([0xff, 0xd8, 0xff, 0x00])),
    ).toBe(true);
    expect(
      matchesDeclaredType(
        png,
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      ),
    ).toBe(true);
    expect(matchesDeclaredType(jpeg, Buffer.from("<script>"))).toBe(false);
    expect(
      matchesDeclaredType(
        { ...jpeg, originalname: "equipo.png" },
        Buffer.from([0xff, 0xd8, 0xff]),
      ),
    ).toBe(false);
  });

  test("cada listado acepta únicamente estados de su clase de activo", () => {
    expect(() => ListaMaquinariaQuery.parse({ estado: "BAJA" })).toThrow();
    expect(() =>
      ListaHerramientasQuery.parse({ estado: "EN_REPARACION" }),
    ).toThrow();
    expect(ListaMaquinariaQuery.parse({ estado: "OPERATIVA" }).page).toBe(1);
  });
});

function prismaCreacionMaquinaria() {
  const catalog = {
    id: 7,
    nombre: "Cortasetos",
    tipoLegacy: "CORTASETOS_MANO",
    activo: true,
    estadoAprobacion: "APROBADA",
  };
  const created = {
    id: 31,
    nombre: catalog.nombre,
    marca: "Stihl",
    tipo: catalog.tipoLegacy,
    estado: "OPERATIVA",
    propietarioTipo: "CONJUNTO",
    empresaId: "EMP-1",
    conjuntoPropietarioId: "CONJ-1",
    creadoPorId: "admin-1",
  };
  let persisted = created;
  const tx: any = {
    tipoMaquinariaCatalogo: {
      findFirst: jest.fn().mockResolvedValue(catalog),
    },
    maquinaria: {
      create: jest.fn(({ data }: any) => {
        persisted = { ...created, ...data };
        return Promise.resolve(persisted);
      }),
      update: jest.fn(({ data }: any) =>
        Promise.resolve({
          ...persisted,
          ...data,
          tipoCatalogo: catalog,
          conjuntoPropietario: { nit: "CONJ-1", nombre: "Conjunto 1" },
        }),
      ),
    },
    auditoriaEvento: { create: jest.fn().mockResolvedValue({}) },
  };
  const prisma: any = {
    conjunto: {
      findFirst: jest
        .fn()
        .mockResolvedValue({ nit: "CONJ-1", nombre: "Conjunto 1" }),
    },
    $transaction: jest.fn((callback: any) => callback(tx)),
  };
  return { prisma, tx };
}

describe("Flujo de aprobación de activos", () => {
  test("el administrador no puede registrar activos como propiedad de empresa", async () => {
    const service = new InventarioActivoService({} as any, "EMP-1", {
      id: "admin-1",
      rol: "administrador",
      nombre: "Admin",
    });

    await expect(
      service.crearMaquinaria(
        { tipoCatalogoId: 7, marca: "Stihl", estado: "OPERATIVA" },
        { propietarioTipo: "EMPRESA" as any, conjuntoId: null },
      ),
    ).rejects.toMatchObject({ status: 403 });
  });

  test("el administrador no edita por ID un activo de un conjunto que ya no administra", async () => {
    const prisma: any = {
      maquinaria: {
        findFirst: jest.fn().mockResolvedValue({
          id: 44,
          empresaId: "EMP-1",
          conjuntoPropietarioId: "CONJ-AJENO",
          estadoAprobacion: "PENDIENTE",
          creadoPorId: "admin-1",
        }),
      },
      conjunto: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    const service = new InventarioActivoService(prisma, "EMP-1", {
      id: "admin-1",
      rol: "administrador",
    });

    await expect(
      service.editar("maquinaria", 44, { alias: "Intento" }),
    ).rejects.toMatchObject({ status: 404 });
    expect(prisma.conjunto.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          nit: "CONJ-AJENO",
          administradorId: "admin-1",
        }),
      }),
    );
  });

  test("el administrador crea pendiente y queda acotado a su conjunto", async () => {
    const { prisma, tx } = prismaCreacionMaquinaria();
    const service = new InventarioActivoService(prisma, "EMP-1", {
      id: "admin-1",
      rol: "administrador",
      nombre: "Admin",
    });

    const result: any = await service.crearMaquinaria(
      { tipoCatalogoId: 7, marca: "Stihl", estado: "OPERATIVA" },
      { propietarioTipo: "CONJUNTO" as any, conjuntoId: "CONJ-1" },
    );

    expect(prisma.conjunto.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          nit: "CONJ-1",
          empresaId: "EMP-1",
          administradorId: "admin-1",
        }),
      }),
    );
    expect(tx.maquinaria.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          estadoAprobacion: "PENDIENTE",
          creadoPorId: "admin-1",
        }),
      }),
    );
    expect(result.estadoAprobacion).toBe("PENDIENTE");
  });

  test("gerente crea aprobado y activo sin autoaprobar al administrador", async () => {
    const { prisma, tx } = prismaCreacionMaquinaria();
    const service = new InventarioActivoService(prisma, "EMP-1", {
      id: "ger-1",
      rol: "gerente",
      nombre: "Gerente",
    });
    await service.crearMaquinaria(
      { tipoCatalogoId: 7, marca: "Stihl", estado: "OPERATIVA" },
      { propietarioTipo: "EMPRESA" as any, conjuntoId: null },
    );
    expect(tx.maquinaria.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          estadoAprobacion: "APROBADA",
          aprobadoPorId: "ger-1",
        }),
      }),
    );

    const adminService = new InventarioActivoService(prisma, "EMP-1", {
      id: "admin-1",
      rol: "administrador",
    });
    await expect(adminService.aprobar("maquinaria", 31)).rejects.toMatchObject({
      status: 403,
    });
  });
});
