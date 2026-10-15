const mockWooFetch = jest.fn();
const mockCached = jest.fn(async (_key: string, _ttl: number, loader: () => Promise<unknown>) => loader());
const mockCacheGet = jest.fn(async (_key: string): Promise<unknown> => null);
const mockCacheSet = jest.fn(async (_key: string, _value: unknown, _ttl: number) => undefined);
const mockPapelera = jest.fn(async (_fileId: string) => undefined);

jest.mock("../../src/services/RedisService", () => ({
  cached: (key: string, ttl: number, loader: () => Promise<unknown>) => mockCached(key, ttl, loader),
  cacheGet: (key: string) => mockCacheGet(key),
  cacheSet: (key: string, value: unknown, ttl: number) => mockCacheSet(key, value, ttl),
}));
jest.mock("../../src/utils/drive_evidencias", () => ({
  enviarArchivoWebAPapelera: (fileId: string) => mockPapelera(fileId),
}));
jest.mock("../../src/db/prisma", () => ({ prisma: {} }));
jest.mock("../../src/services/wooFetch", () => {
  class WooFetchError extends Error {
    constructor(message: string, readonly status: number, readonly upstreamStatus?: number) {
      super(message);
    }
  }
  return {
    WooFetchError,
    // Igual que el real: los parametros vacios no viajan.
    buildWooUrl: jest.fn((ns: string, path: string, query: Record<string, unknown> = {}) => {
      const q = new URLSearchParams();
      for (const [k, v] of Object.entries(query)) if (v != null && v !== "") q.set(k, String(v));
      return `${ns}${path}?${q}`;
    }),
    wooFetch: (...args: unknown[]) => mockWooFetch(...args),
  };
});

import { WooFetchError } from "../../src/services/wooFetch";
import {
  normalizarPostulacion,
  normalizarRegistroConjunto,
  SolicitudesWebService,
  ultimos4,
} from "../../src/services/SolicitudesWebService";

describe("solicitudes de la pagina web", () => {
  beforeEach(() => {
    mockWooFetch.mockReset();
    mockCached.mockClear();
    mockCacheGet.mockClear();
    mockCacheSet.mockClear();
    mockPapelera.mockReset();
    mockPapelera.mockResolvedValue(undefined);
  });

  test("la postulacion separa la foto, enmascara el documento y descarta ids invalidos", () => {
    const p = normalizarPostulacion({
      id: "7",
      nombres: " Ana ",
      apellidos: "Ruiz",
      correo: "ana@example.com",
      tipo_doc: "CC",
      num_doc_ultimos4: "1.023.456.789",
      habilidades: ["Aseo", "", null],
      zonas: ["Villavicencio"],
      estado: "en_revision",
      estado_etiqueta: "En revisión",
      documentos: [
        { tipo: "foto", etiqueta: "Tu foto", drive_file_id: "1AbCdEfGhIjKlMnOp", mime: "image/jpeg" },
        { tipo: "cedula_frontal", etiqueta: "Cédula (frente)", drive_file_id: "1QrStUvWxYz012345", mime: "image/png" },
        { tipo: "hoja_vida", drive_file_id: "../../etc", en_servidor: true },
      ],
    });

    expect(p.id).toBe(7);
    expect(p.nombres).toBe("Ana");
    expect(p.documentoUltimos4).toBe("6789");
    expect(p.habilidades).toEqual(["Aseo"]);
    expect(p.foto?.driveFileId).toBe("1AbCdEfGhIjKlMnOp");
    expect(p.documentos.map((d) => d.tipo)).toEqual(["cedula_frontal", "hoja_vida"]);
    expect(p.documentos[1]).toMatchObject({ driveFileId: null, enServidor: true, etiqueta: "hoja_vida" });
  });

  test("ultimos4 nunca devuelve mas de 4 digitos", () => {
    expect(ultimos4("CC 80.123.456")).toBe("3456");
    expect(ultimos4("")).toBeNull();
    expect(ultimos4(null)).toBeNull();
  });

  test("el registro de conjunto traduce el estado", () => {
    const c = normalizarRegistroConjunto({
      id: 3,
      nombre: "Torres",
      nit: "900",
      estado: "pending",
      documentos: [
        { tipo: "rut", etiqueta: "RUT", en_servidor: true, url_servidor: "https://tienda.test/wp-content/uploads/rut.pdf" },
        { tipo: "cedula", url_servidor: "javascript:alert(1)" },
      ],
    });
    expect(c.estadoEtiqueta).toBe("Pendiente de revisión");
    expect(c.documentos[0].urlServidor).toBe("https://tienda.test/wp-content/uploads/rut.pdf");
    expect(c.documentos[1].urlServidor).toBeNull();
    expect(normalizarRegistroConjunto({ estado: "approved" }).estadoEtiqueta).toBe("Aprobado");
  });

  test("consulta el REST del plugin con clave de WooCommerce y pagina el resultado", async () => {
    mockWooFetch.mockResolvedValue({ items: [{ id: 1, nombres: "Ana" }], total: 31, pagina: 2, por_pagina: 20 });
    const res = await new SolicitudesWebService().listarPostulaciones({ estado: "pendiente", pagina: 2 });

    expect(mockWooFetch).toHaveBeenCalledWith(
      "clmk/postulaciones?estado=pendiente&pagina=2",
      {},
      expect.objectContaining({ requireAuth: true }),
    );
    expect(res).toMatchObject({ total: 31, pagina: 2, porPagina: 20 });
    expect(res.items[0].nombres).toBe("Ana");
  });

  test("conjuntos usa el namespace clx", async () => {
    mockWooFetch.mockResolvedValue({ items: [] });
    await new SolicitudesWebService().listarConjuntos({});
    expect(mockWooFetch.mock.calls[0][0]).toMatch(/^clx\/registros-conjuntos/);
  });

  test("la marca de revision llega a la app solo si esta puesta", () => {
    const revisada = normalizarPostulacion({
      id: 4,
      revisada: true,
      revisada_en: "2026-10-14T20:00:00+00:00",
      revisada_por: " Laura Gerente ",
    });
    expect(revisada).toMatchObject({ revisada: true, revisadaEn: "2026-10-14T20:00:00+00:00", revisadaPor: "Laura Gerente" });
    expect(normalizarPostulacion({ id: 5, revisada: false, revisada_por: "x" })).toMatchObject({
      revisada: false,
      revisadaEn: null,
      revisadaPor: null,
    });
    expect(normalizarPostulacion({ id: 6 }).revisada).toBe(false);
  });

  describe("gestion desde la app", () => {
    const servicio = (nombre: string | null = "Laura Gerente") => {
      const findUnique = jest.fn(async () => (nombre == null ? null : { nombre }));
      return { service: new SolicitudesWebService({ usuario: { findUnique } } as never), findUnique };
    };

    test("filtra por revision y separa la cache por generacion", async () => {
      mockCacheGet.mockResolvedValueOnce(1792);
      mockWooFetch.mockResolvedValue({ items: [] });
      await new SolicitudesWebService().listarPostulaciones({ revision: "pendientes" });

      expect(mockWooFetch.mock.calls[0][0]).toBe("clmk/postulaciones?pagina=1&revision=pendientes");
      expect(mockCached.mock.calls[0][0]).toBe("web:postulaciones:v2:1792:pendientes::1");
    });

    test("marcar revisada guarda quien lo hizo e invalida el listado", async () => {
      const { service, findUnique } = servicio();
      mockWooFetch.mockResolvedValue({ id: 9, nombres: "Ana", revisada: true, revisada_por: "Laura Gerente" });

      const p = await service.marcarRevisionPostulacion(9, true, "u-1");

      expect(findUnique).toHaveBeenCalledWith({ where: { id: "u-1" }, select: { nombre: true } });
      const [url, init, opciones] = mockWooFetch.mock.calls[0];
      expect(url).toBe("clmk/postulaciones/9/revision?");
      expect(init).toMatchObject({ method: "POST" });
      expect(JSON.parse(init.body)).toEqual({ revisada: true, por: "Laura Gerente" });
      expect(opciones).toMatchObject({ requireAuth: true, mapConflict: true });
      expect(mockCacheSet).toHaveBeenCalledWith("web:postulaciones:generacion", expect.any(Number), expect.any(Number));
      expect(p).toMatchObject({ id: 9, revisada: true, revisadaPor: "Laura Gerente" });
    });

    test("sin nombre en ControlApp queda 'ControlApp' como responsable", async () => {
      const { service } = servicio(null);
      mockWooFetch.mockResolvedValue({ id: 9 });
      await service.marcarRevisionPostulacion(9, false, "u-x");
      expect(JSON.parse(mockWooFetch.mock.calls[0][1].body)).toEqual({ revisada: false, por: "ControlApp" });
    });

    test("borrar manda a la papelera de Drive solo ids validos y cuenta los que fallan", async () => {
      const { service } = servicio();
      mockWooFetch.mockResolvedValue({
        eliminado: true,
        drive_file_ids: ["1AbCdEfGhIjKlMnOp", "1QrStUvWxYz012345", "../../etc/passwd"],
      });
      mockPapelera.mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error("sin permiso"));
      const errores = jest.spyOn(console, "error").mockImplementation(() => undefined);

      const res = await service.eliminarPostulacion(12, "u-1");

      expect(mockWooFetch.mock.calls[0][0]).toBe("clmk/postulaciones/12?por=Laura+Gerente");
      expect(mockWooFetch.mock.calls[0][1]).toEqual({ method: "DELETE" });
      expect(mockPapelera.mock.calls.map(([id]) => id)).toEqual(["1AbCdEfGhIjKlMnOp", "1QrStUvWxYz012345"]);
      expect(res).toEqual({ eliminada: true, archivosEnPapelera: 1, archivosSinMover: 1 });
      expect(mockCacheSet).toHaveBeenCalled();
      errores.mockRestore();
    });

    test("si WordPress ya no la tiene, responde 404 claro y no toca Drive", async () => {
      const { service } = servicio();
      mockWooFetch.mockRejectedValue(new WooFetchError("No se pudo borrar", 502, 404));

      await expect(service.eliminarPostulacion(12, "u-1")).rejects.toMatchObject({
        status: 404,
        message: expect.stringContaining("ya no existe"),
      });
      expect(mockPapelera).not.toHaveBeenCalled();
      expect(mockCacheSet).not.toHaveBeenCalled();
    });

    test("si tiene servicios (409) el mensaje de WordPress llega tal cual", async () => {
      const { service } = servicio();
      const conflicto = new WooFetchError("Esta persona ya tiene servicios en la página.", 409, 409);
      mockWooFetch.mockRejectedValue(conflicto);
      await expect(service.eliminarPostulacion(3, "u-1")).rejects.toBe(conflicto);
    });
  });
});
