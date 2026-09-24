import { Prisma } from "@prisma/client";

jest.mock("../../src/services/RedisService", () => ({
  cached: (_clave: string, _ttl: number, fn: () => unknown) => fn(),
}));

import {
  insumoDeclaradoCompleto,
  modoEfectivo,
  WooCommerceCatalogService,
  type WooInsumoConfig,
} from "../../src/services/WooCommerceCatalogService";
import { CommerceLifecycleService } from "../../src/services/CommerceLifecycleService";

const config = (overrides: Partial<WooInsumoConfig> = {}): WooInsumoConfig => ({
  modo: null,
  unidad: null,
  contenido: null,
  unidadContenido: null,
  categoria: null,
  umbralBajo: null,
  factorConversion: null,
  compartido: false,
  ...overrides,
});

describe("cuando Woo declara suficiente para crear el insumo", () => {
  test.each([
    ["por unidades con unidad", config({ modo: "unidad", unidad: "par" }), true],
    ["por empaques completo", config({ modo: "empaque", unidad: "tarro", contenido: 1.8, unidadContenido: "L" }), true],
    ["producto anterior al selector: solo unidad = por unidad", config({ unidad: "pastilla" }), true],
    ["nada declarado", config(), false],
    ["modo sin unidad", config({ modo: "unidad" }), false],
    ["empaque sin contenido", config({ modo: "empaque", unidad: "tarro", unidadContenido: "L" }), false],
    ["empaque con contenido 0", config({ modo: "empaque", unidad: "tarro", contenido: 0, unidadContenido: "L" }), false],
    ["empaque sin unidad de medida", config({ modo: "empaque", unidad: "tarro", contenido: 1.8 }), false],
    ["empaque sin nombre", config({ modo: "empaque", contenido: 1.8, unidadContenido: "L" }), false],
  ])("%s -> %s", (_nombre, cfg, esperado) => {
    expect(insumoDeclaradoCompleto(cfg)).toBe(esperado);
  });

  test("modoEfectivo respeta el declarado y cae a 'unidad' si solo hay unidad", () => {
    expect(modoEfectivo(config({ modo: "empaque", unidad: "caja" }))).toBe("empaque");
    expect(modoEfectivo(config({ unidad: "kit" }))).toBe("unidad");
    expect(modoEfectivo(config())).toBeNull();
  });
});

describe("lectura de lo que entrega WordPress", () => {
  const catalogo = new WooCommerceCatalogService();

  const productoStore = (clx: Record<string, unknown> | null) => ({
    id: 1993,
    name: "Detergente líquido",
    type: "simple",
    prices: { currency_code: "COP", currency_minor_unit: 0, price: "12000", regular_price: "12000", sale_price: "12000" },
    extensions: clx ? { clx_catalogo: clx } : {},
  });

  test("producto por empaques: modo, unidad, contenido y medida", () => {
    const p = (catalogo as any).normalizeProduct(
      productoStore({
        insumo_modo: "empaque",
        insumo_unidad: "tarro",
        insumo_contenido: 1.8,
        insumo_unidad_contenido: "L",
        insumo_categoria: "LIMPIEZA",
        insumo_umbral: 3,
        factor_inventario: null,
      }),
    );
    expect(p.insumoConfig).toEqual({
      modo: "empaque",
      unidad: "tarro",
      contenido: 1.8,
      unidadContenido: "L",
      categoria: "LIMPIEZA",
      umbralBajo: 3,
      factorConversion: null,
      compartido: false,
    });
  });

  test("producto por unidades con factor (caja de 12)", () => {
    const p = (catalogo as any).normalizeProduct(
      productoStore({ insumo_modo: "unidad", insumo_unidad: "unidad", factor_inventario: 12 }),
    );
    expect(p.insumoConfig).toMatchObject({ modo: "unidad", unidad: "unidad", factorConversion: 12, contenido: null });
  });

  test("sin extensions.clx_catalogo (el plugin no esta entregando datos) queda sin declarar", () => {
    const p = (catalogo as any).normalizeProduct(productoStore(null));
    expect(insumoDeclaradoCompleto(p.insumoConfig)).toBe(false);
  });

  test("valores basura se descartan: modo desconocido, contenido negativo o texto", () => {
    const p = (catalogo as any).normalizeProduct(
      productoStore({ insumo_modo: "caja-rara", insumo_unidad: " ", insumo_contenido: -3, insumo_unidad_contenido: "" }),
    );
    expect(p.insumoConfig).toMatchObject({ modo: null, unidad: null, contenido: null, unidadContenido: null });
  });

  describe("variaciones", () => {
    const variacion = (extra: Record<string, unknown>) =>
      (catalogo as any).normalizeVariation({ id: 5001, sku: "X", price: "1", regular_price: "1", ...extra }, "COP");

    const producto = (padre: Record<string, unknown>, variaciones: Array<Record<string, unknown>>) => {
      const svc = new WooCommerceCatalogService();
      jest.spyOn(svc as any, "ensureConfigured").mockReturnValue(undefined);
      jest
        .spyOn(svc as any, "fetchJson")
        .mockResolvedValue({ ...productoStore(padre), type: "variable" });
      jest.spyOn(svc, "getProductVariations").mockResolvedValue(variaciones.map(variacion) as never);
      return svc.getProduct(1993);
    };

    test("la variacion lee sus propios campos de la REST v3", () => {
      const v = variacion({
        clx_insumo_modo: "empaque",
        clx_insumo_unidad: "caja",
        clx_insumo_contenido: 6,
        clx_insumo_unidad_contenido: "kg",
      });
      expect(v.insumoConfig).toMatchObject({ modo: "empaque", unidad: "caja", contenido: 6, unidadContenido: "kg" });
    });

    test("una variacion sin datos hereda el modo, el contenido y la unidad del producto", async () => {
      const p = await producto(
        { insumo_modo: "empaque", insumo_unidad: "tarro", insumo_contenido: 1.8, insumo_unidad_contenido: "L" },
        [{}],
      );
      expect(p.variations[0].insumoConfig).toMatchObject({
        modo: "empaque",
        unidad: "tarro",
        contenido: 1.8,
        unidadContenido: "L",
      });
    });

    test("'todas las variaciones suman al mismo insumo' se lee del producto y lo heredan las variaciones", async () => {
      const p = await producto(
        { insumo_modo: "unidad", insumo_unidad: "pastilla", insumo_compartido: true },
        [{ clx_factor_inventario: 60 }, { clx_factor_inventario: 120 }],
      );
      expect(p.insumoConfig.compartido).toBe(true);
      expect(p.variations.map((v: any) => v.insumoConfig.compartido)).toEqual([true, true]);
      expect(p.variations.map((v: any) => v.insumoConfig.factorConversion)).toEqual([60, 120]);
    });

    test("sin marcarlo, cada variacion es su propio insumo", async () => {
      const p = await producto({ insumo_modo: "unidad", insumo_unidad: "pastilla" }, [{}]);
      expect(p.insumoConfig.compartido).toBe(false);
      expect(p.variations[0].insumoConfig.compartido).toBe(false);
    });

    test("una variacion con sus propios datos gana sobre el producto (x60 vs x120)", async () => {
      const p = await producto(
        { insumo_modo: "unidad", insumo_unidad: "pastilla", factor_inventario: 60 },
        [{ clx_factor_inventario: 120 }, {}],
      );
      expect(p.variations[0].insumoConfig).toMatchObject({ unidad: "pastilla", factorConversion: 120 });
      expect(p.variations[1].insumoConfig).toMatchObject({ unidad: "pastilla", factorConversion: 60 });
    });
  });
});

describe("creacion automatica del insumo al confirmar la recepcion", () => {
  const item = (overrides: Record<string, unknown> = {}) => ({
    id: 7,
    pedidoId: 41,
    wooProductId: 1993,
    wooVariationId: null,
    nombreProducto: "Detergente líquido",
    sku: "DET-1",
    cantidad: new Prisma.Decimal(2),
    wooFactorInventario: null,
    insumo: null,
    ...overrides,
  });

  const pedido = (items: unknown[]) => ({
    id: 41,
    conjunto: { nombre: "Los Pinos", empresaId: "EMP-1" },
    items,
  });

  function servicio(cfg: WooInsumoConfig | Error, variaciones: Array<{ id: number; insumoConfig: WooInsumoConfig }> = []) {
    const create = jest.fn(async ({ data }: any) => ({
      id: 99,
      nombre: data.nombre,
      unidad: data.unidad,
      wooFactorConversion: data.wooFactorConversion,
    }));
    const update = jest.fn(async ({ where, data }: any) => ({
      id: where.id,
      nombre: "Sanitabs (5)",
      unidad: "par",
      wooFactorConversion: new Prisma.Decimal(1),
      ...data,
    }));
    const client = { insumo: { findFirst: jest.fn().mockResolvedValue(null), create, update } };
    const service = new CommerceLifecycleService({} as never);
    (service as any).catalog = {
      getProduct: cfg instanceof Error
        ? jest.fn().mockRejectedValue(cfg)
        : jest.fn().mockResolvedValue({ name: "Sanitabs", insumoConfig: cfg, variations: variaciones }),
    };
    return { service, client, create, update };
  }

  const resolver = (s: ReturnType<typeof servicio>, items: unknown[]) =>
    (s.service as any).resolveMappings(s.client, pedido(items), true);

  test("por unidades: crea el insumo sin contenido y NO pide mapeo", async () => {
    const s = servicio(config({ modo: "unidad", unidad: "par", categoria: "OTROS", factorConversion: 6 }));

    const [mapeo] = await resolver(s, [item()]);

    expect(mapeo.origen).toBe("AUTO_WOO");
    expect(mapeo.insumo).not.toBeNull();
    expect(s.create.mock.calls[0][0].data).toMatchObject({
      nombre: "Detergente líquido",
      unidad: "par",
      wooFactorConversion: 6,
      contenidoPorUnidad: null,
      unidadContenido: null,
      wooProductId: 1993,
    });
  });

  test("por empaques: crea el insumo con su contenido (1,8 L por tarro)", async () => {
    const s = servicio(
      config({ modo: "empaque", unidad: "tarro", contenido: 1.8, unidadContenido: "L", categoria: "LIMPIEZA", umbralBajo: 3 }),
    );

    const [mapeo] = await resolver(s, [item()]);

    expect(mapeo.origen).toBe("AUTO_WOO");
    expect(s.create.mock.calls[0][0].data).toMatchObject({
      unidad: "tarro",
      categoria: "LIMPIEZA",
      umbralBajo: 3,
      wooFactorConversion: 1,
      contenidoPorUnidad: 1.8,
      unidadContenido: "L",
    });
  });

  test("producto anterior al selector (solo unidad) se sigue creando por unidades", async () => {
    const s = servicio(config({ unidad: "pastilla" }));
    const [mapeo] = await resolver(s, [item()]);
    expect(mapeo.origen).toBe("AUTO_WOO");
    expect(s.create.mock.calls[0][0].data).toMatchObject({ unidad: "pastilla", contenidoPorUnidad: null });
  });

  test.each([
    ["nada declarado en Woo", config()],
    ["empaque sin contenido", config({ modo: "empaque", unidad: "tarro", unidadContenido: "L" })],
    ["empaque sin unidad de medida", config({ modo: "empaque", unidad: "tarro", contenido: 1.8 })],
  ])("%s -> pide mapeo manual y no inventa datos", async (_nombre, cfg) => {
    const s = servicio(cfg);
    const [mapeo] = await resolver(s, [item()]);
    expect(mapeo.origen).toBe("SIN_MAPEO");
    expect(s.create).not.toHaveBeenCalled();
  });

  test("si la tienda no responde, cae a mapeo manual sin romper la recepcion", async () => {
    const s = servicio(new Error("La tienda tardo demasiado"));
    const [mapeo] = await resolver(s, [item()]);
    expect(mapeo.origen).toBe("SIN_MAPEO");
  });

  test("una variacion usa la configuracion de su propia variacion", async () => {
    const s = servicio(config({ modo: "unidad", unidad: "und" }), [
      { id: 5001, insumoConfig: config({ modo: "empaque", unidad: "caja", contenido: 6, unidadContenido: "kg" }) },
    ]);

    const [mapeo] = await resolver(s, [item({ wooVariationId: 5001 })]);

    expect(mapeo.origen).toBe("AUTO_WOO");
    expect(s.create.mock.calls[0][0].data).toMatchObject({
      unidad: "caja",
      contenidoPorUnidad: 6,
      unidadContenido: "kg",
      wooProductId: 5001,
    });
  });

  describe("producto variable: todas las variaciones suman al mismo insumo", () => {
    const compartida = () =>
      config({ modo: "unidad", unidad: "pastilla", compartido: true, categoria: "PISCINA", umbralBajo: 5 });

    const variacion = (id: number, factor: number) => ({
      id,
      insumoConfig: config({ ...compartida(), factorConversion: factor }),
    });

    test("la primera variacion que se compra crea UN insumo con el nombre del producto (no el de la variacion)", async () => {
      const s = servicio(compartida(), [variacion(224, 60)]);

      const [mapeo] = await resolver(s, [
        item({ nombreProducto: "Sanitabs (60)", wooProductId: 220, wooVariationId: 224, wooFactorInventario: new Prisma.Decimal(60) }),
      ]);

      expect(mapeo.origen).toBe("AUTO_WOO");
      expect(s.create.mock.calls[0][0].data).toMatchObject({
        nombre: "Sanitabs",
        unidad: "pastilla",
        categoria: "PISCINA",
        umbralBajo: 5,
        wooProductId: 224,
        // El factor real viaja en cada compra; el del insumo es solo respaldo.
        wooFactorConversion: 1,
        contenidoPorUnidad: null,
      });
    });

    test("otra variacion (120) reutiliza ese mismo insumo aunque este vinculado a la de 60", async () => {
      const s = servicio(compartida(), [variacion(224, 60), variacion(225, 120)]);
      // por producto de Woo (225): nada; por SKU: nada; por nombre+unidad: el insumo "Sanitabs".
      s.client.insumo.findFirst
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce({
          id: 7,
          nombre: "Sanitabs",
          unidad: "pastilla",
          wooFactorConversion: new Prisma.Decimal(1),
          wooProductId: 224,
          wooSku: "S60",
        });

      const [mapeo] = await resolver(s, [
        item({ nombreProducto: "Sanitabs (120)", wooProductId: 220, wooVariationId: 225 }),
      ]);

      expect(mapeo.origen).toBe("AUTO_WOO");
      expect(mapeo.insumo).toMatchObject({ id: 7, nombre: "Sanitabs", unidad: "pastilla" });
      expect(s.create).not.toHaveBeenCalled();
      // No se le pisa el vinculo a la primera variacion.
      expect(s.update).not.toHaveBeenCalled();
      // Se busco por el nombre del producto, no por el de la variacion.
      expect(s.client.insumo.findFirst.mock.calls[2][0].where).toMatchObject({ nombre: "Sanitabs", unidad: "pastilla" });
    });

    test("cada compra aporta el factor de SU variacion (60 y 120), sobre el mismo insumo", async () => {
      const insumo = { id: 7, nombre: "Sanitabs", unidad: "pastilla", wooFactorConversion: new Prisma.Decimal(1) };
      const s = servicio(compartida(), [variacion(224, 60), variacion(225, 120)]);
      s.client.insumo.findFirst.mockResolvedValue({ ...insumo, wooProductId: 224, wooSku: null });

      const mapeos = await resolver(s, [
        item({ id: 1, nombreProducto: "Sanitabs (60)", wooVariationId: 224, wooFactorInventario: new Prisma.Decimal(60), cantidad: new Prisma.Decimal(2) }),
        item({ id: 2, nombreProducto: "Sanitabs (120)", wooVariationId: 225, wooFactorInventario: new Prisma.Decimal(120), cantidad: new Prisma.Decimal(1) }),
      ]);

      expect(mapeos.map((m: any) => m.insumo.id)).toEqual([7, 7]);
      // El mismo insumo recibe 2x60 y 1x120 = 240 pastillas.
      const total = mapeos.reduce(
        (suma: number, m: any) => suma + Number(m.item.cantidad) * Number(m.item.wooFactorInventario),
        0,
      );
      expect(total).toBe(240);
    });

    test("sin marcar 'mismo insumo', cada variacion crea el suyo con su propio nombre", async () => {
      const s = servicio(config({ modo: "unidad", unidad: "pastilla" }), [
        { id: 224, insumoConfig: config({ modo: "unidad", unidad: "pastilla", factorConversion: 60 }) },
      ]);

      await resolver(s, [item({ nombreProducto: "Sanitabs (60)", wooVariationId: 224 })]);

      expect(s.create.mock.calls[0][0].data).toMatchObject({ nombre: "Sanitabs (60)", wooFactorConversion: 60 });
    });

    test("por empaques nunca se comparte: cada tamano tiene su propio contenido", async () => {
      const cfg = config({ modo: "empaque", unidad: "tarro", contenido: 3.8, unidadContenido: "L", compartido: true });
      const s = servicio(cfg, [{ id: 224, insumoConfig: cfg }]);

      await resolver(s, [item({ nombreProducto: "Detergente (3,8 L)", wooVariationId: 224 })]);

      expect(s.create.mock.calls[0][0].data).toMatchObject({
        nombre: "Detergente (3,8 L)",
        contenidoPorUnidad: 3.8,
      });
    });

    test("un producto simple ignora la marca y usa su propio nombre", async () => {
      const s = servicio(compartida());
      await resolver(s, [item({ nombreProducto: "Sanitabs", wooVariationId: null })]);
      expect(s.create.mock.calls[0][0].data).toMatchObject({ nombre: "Sanitabs", wooFactorConversion: 1 });
    });
  });

  test("un insumo ya existente para el producto no se vuelve a crear", async () => {
    const s = servicio(config({ modo: "unidad", unidad: "par" }));
    s.client.insumo.findFirst.mockResolvedValueOnce({ id: 3, nombre: "X", unidad: "par", wooFactorConversion: new Prisma.Decimal(1) });

    const [mapeo] = await resolver(s, [item()]);

    expect(mapeo.origen).toBe("WOO_PRODUCT_ID");
    expect(s.create).not.toHaveBeenCalled();
  });

  describe("cuando el catalogo ya tiene un insumo con ese nombre y unidad", () => {
    // Busquedas en orden: por producto de Woo, por SKU y por nombre+unidad.
    const sinVincularPorProductoNiSku = (s: ReturnType<typeof servicio>, existente: unknown) =>
      s.client.insumo.findFirst
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(existente);

    test("sin vincular a la tienda: lo reutiliza (no choca con la restriccion de unicidad)", async () => {
      const s = servicio(config({ modo: "unidad", unidad: "par" }));
      sinVincularPorProductoNiSku(s, {
        id: 2,
        nombre: "Detergente líquido",
        unidad: "par",
        wooFactorConversion: new Prisma.Decimal(1),
        wooProductId: null,
        wooSku: null,
      });

      const [mapeo] = await resolver(s, [item()]);

      expect(mapeo.origen).toBe("AUTO_WOO");
      expect(s.create).not.toHaveBeenCalled();
      expect(s.update).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 2 }, data: { wooProductId: 1993, wooSku: "DET-1" } }),
      );
    });

    test("ya vinculado a OTRO producto de la tienda: no adivina, pide mapeo manual", async () => {
      const s = servicio(config({ modo: "unidad", unidad: "par" }));
      sinVincularPorProductoNiSku(s, {
        id: 2,
        nombre: "Detergente líquido",
        unidad: "par",
        wooFactorConversion: new Prisma.Decimal(1),
        wooProductId: 555,
        wooSku: null,
      });

      const [mapeo] = await resolver(s, [item()]);

      expect(mapeo.origen).toBe("SIN_MAPEO");
      expect(s.create).not.toHaveBeenCalled();
      expect(s.update).not.toHaveBeenCalled();
    });

    test("si otro proceso lo crea justo ahora (P2002), cae a mapeo manual en vez de romper", async () => {
      const s = servicio(config({ modo: "unidad", unidad: "par" }));
      s.create.mockRejectedValue(
        new Prisma.PrismaClientKnownRequestError("Unique constraint failed", {
          code: "P2002",
          clientVersion: "test",
        }),
      );

      const [mapeo] = await resolver(s, [item()]);

      expect(mapeo.origen).toBe("SIN_MAPEO");
    });

    test("cualquier otro error de base de datos si se propaga", async () => {
      const s = servicio(config({ modo: "unidad", unidad: "par" }));
      s.create.mockRejectedValue(new Error("conexion perdida"));

      await expect(resolver(s, [item()])).rejects.toThrow("conexion perdida");
    });
  });
});

