import { PassThrough } from "stream";
import { Rol, TipoPedidoApp } from "@prisma/client";

const mockGetEvidenciaStream = jest.fn();
const mockEmpresaIdAutenticada = jest.fn();

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));
jest.mock("../../src/utils/drive_evidencias", () => ({
  getEvidenciaStream: (fileId: string) => mockGetEvidenciaStream(fileId),
}));
jest.mock("../../src/middlewares/tenant.middleware", () => ({
  empresaIdAutenticada: (req: unknown) => mockEmpresaIdAutenticada(req),
}));

import { EvidenciaController } from "../../src/controller/EvidenciaController";
import {
  EvidenciaAccesoService,
  MENSAJE_EVIDENCIA_NO_DISPONIBLE,
  idsDriveEnTexto,
  type ActorEvidencia,
} from "../../src/services/EvidenciaAccesoService";
import { CommerceAccessService } from "../../src/services/CommerceAccessService";
import { PermissionService } from "../../src/services/PermissionService";

// Ids con la forma de Drive (alfanuméricos, "-" y "_", 33 caracteres).
const ID_TAREA = "1Tarea_Operario_A_conjunto1_xxxxx";
const ID_TAREA_VIEJA = "1TareaVieja-uc-id-conjunto1-yyyyy";
const ID_TAREA_C2 = "1Tarea_conjunto2_admin_otro_zzzzz";
const ID_TAREA_OTRA_EMPRESA = "1Tarea_otra_empresa_____________w";
const ID_DIAGNOSTICO = "1Diagnostico_plan_conjunto1_aaaaa";
const ID_COMPROBANTE = "1Comprobante_residente_r1_bbbbbbb";
const ID_POSTULACION = "1Postulacion_web_cedula_ccccccccc";

const drive = (id: string) => `https://drive.google.com/file/d/${id}/view`;

type FakeTarea = { id: number; conjuntoId: string | null; evidencias: string[]; operarios: string[] };

function crearDb() {
  const conjuntos = [
    { nit: "C1", empresaId: "E1", administradorId: "admin-1" },
    { nit: "C2", empresaId: "E1", administradorId: "admin-2" },
    { nit: "X1", empresaId: "E2", administradorId: "admin-x" },
  ];
  const tareas: FakeTarea[] = [
    { id: 1, conjuntoId: "C1", evidencias: [drive(ID_TAREA)], operarios: ["op-1"] },
    {
      id: 2,
      conjuntoId: "C1",
      evidencias: [`https://drive.google.com/uc?id=${ID_TAREA_VIEJA}`],
      operarios: ["op-2"],
    },
    { id: 3, conjuntoId: "C2", evidencias: [drive(ID_TAREA_C2)], operarios: ["op-3"] },
    { id: 4, conjuntoId: "X1", evidencias: [drive(ID_TAREA_OTRA_EMPRESA)], operarios: ["op-1"] },
  ];
  const diagnosticos = [
    { id: 10, urlFoto: drive(ID_DIAGNOSTICO), planEsperanza: { conjuntoId: "C1" } },
  ];
  const pedidos = [
    {
      id: 20,
      tipo: TipoPedidoApp.RESIDENTE,
      usuarioId: "res-1",
      conjuntoId: "C1",
      comprobanteUrl: drive(ID_COMPROBANTE),
    },
  ];
  const usuarios: Record<string, { rol: Rol; empresaId?: string; conjuntoId?: string }> = {
    "gerente-1": { rol: Rol.gerente, empresaId: "E1" },
    "jefe-1": { rol: Rol.jefe_operaciones, empresaId: "E1" },
    "admin-1": { rol: Rol.administrador },
    "admin-2": { rol: Rol.administrador },
    "res-1": { rol: Rol.residente, conjuntoId: "C1" },
    "res-2": { rol: Rol.residente, conjuntoId: "C1" },
    "op-1": { rol: Rol.operario },
  };

  const enLista = (valor: string | null, filtro?: { in: string[] }) =>
    !filtro || (valor != null && filtro.in.includes(valor));
  const conjuntoDe = (nit: string | null) => conjuntos.find((c) => c.nit === nit);

  const prisma = {
    // Emula el LIKE ANY sobre las evidencias unidas por espacio.
    $queryRaw: jest.fn(async (_sql: TemplateStringsArray, patrones: string[], limite: number) => {
      const textos = patrones.map((p) => p.slice(1, -1).replace(/\\(.)/g, "$1"));
      return tareas
        .filter((t) => textos.some((x) => t.evidencias.join(" ").includes(x)))
        .slice(0, limite)
        .map(({ id, conjuntoId, evidencias }) => ({ id, conjuntoId, evidencias }));
    }),
    diagnosticoArea: {
      findMany: jest.fn(async ({ where }: any) =>
        diagnosticos.filter((d) =>
          where.OR.some((o: any) => d.urlFoto?.includes(o.urlFoto.contains)),
        ),
      ),
    },
    pedidoApp: {
      findMany: jest.fn(async ({ where }: any) =>
        pedidos.filter((p) =>
          where.OR.some((o: any) => p.comprobanteUrl?.includes(o.comprobanteUrl.contains)),
        ),
      ),
    },
    tarea: {
      findFirst: jest.fn(async ({ where }: any) => {
        const t = tareas.find(
          (x) =>
            where.id.in.includes(x.id) &&
            conjuntoDe(x.conjuntoId)?.empresaId === where.conjunto.empresaId &&
            x.operarios.includes(where.operarios.some.id),
        );
        return t ? { id: t.id } : null;
      }),
    },
    conjunto: {
      findFirst: jest.fn(async ({ where }: any) => {
        const c = conjuntos.find(
          (x) =>
            enLista(x.nit, where.nit) &&
            x.empresaId === where.empresaId &&
            (where.administradorId === undefined || x.administradorId === where.administradorId),
        );
        return c ? { nit: c.nit } : null;
      }),
      // CommerceAccessService.getAuthorizedConjuntoIds
      findMany: jest.fn(async ({ where }: any) =>
        conjuntos
          .filter(
            (x) =>
              (where.administradorId === undefined || x.administradorId === where.administradorId) &&
              (where.empresaId === undefined || x.empresaId === where.empresaId),
          )
          .map((x) => ({ nit: x.nit })),
      ),
    },
    // CommerceAccessService.getActor
    usuario: {
      findUnique: jest.fn(async ({ where }: any) => {
        const u = usuarios[where.id];
        if (!u) return null;
        return {
          id: where.id,
          nombre: where.id,
          rol: u.rol,
          gerente: u.rol === Rol.gerente ? { empresaId: u.empresaId } : null,
          jefeOperaciones: u.rol === Rol.jefe_operaciones ? { empresaId: u.empresaId } : null,
          residente: u.conjuntoId ? { conjuntoId: u.conjuntoId } : null,
        };
      }),
    },
  };
  return prisma;
}

function cacheEnMemoria() {
  const datos = new Map<string, { valor: unknown; ttl: number }>();
  return {
    datos,
    get: async <T>(key: string) => (datos.get(key)?.valor as T | undefined) ?? null,
    set: async (key: string, valor: unknown, ttl: number) => {
      datos.set(key, { valor: JSON.parse(JSON.stringify(valor)), ttl });
    },
  };
}

function crearServicio(opciones: { permisos?: (rol: string) => Set<string> } = {}) {
  const db = crearDb();
  const cache = cacheEnMemoria();
  const service = new EvidenciaAccesoService(db as any, {
    // Permisos por defecto de cada rol, salvo que la prueba cambie la matriz.
    permisos: async (_empresaId, rol) =>
      opciones.permisos?.(rol) ?? PermissionService.defaultPermissionsForRole(rol as Rol),
    commerce: new CommerceAccessService(db as any),
    cache,
    ventanaLoteMs: 0,
  });
  return { db, cache, service };
}

const actor = (id: string, rol: Rol, empresaId = "E1"): ActorEvidencia => ({ id, rol, empresaId });

async function esperar404(promesa: Promise<unknown>) {
  await expect(promesa).rejects.toMatchObject({
    status: 404,
    message: MENSAJE_EVIDENCIA_NO_DISPONIBLE,
  });
}

describe("EvidenciaAccesoService: evidencias de tareas", () => {
  test("el operario ve las evidencias de su propia tarea", async () => {
    const { service } = crearServicio();
    await expect(service.autorizar(ID_TAREA, actor("op-1", Rol.operario))).resolves.toBeUndefined();
  });

  test("operario: tarea ajena de su mismo conjunto -> 404", async () => {
    const { service } = crearServicio();
    await esperar404(service.autorizar(ID_TAREA, actor("op-2", Rol.operario)));
  });

  test("operario: tarea de otro conjunto -> 404", async () => {
    const { service } = crearServicio();
    await esperar404(service.autorizar(ID_TAREA_C2, actor("op-1", Rol.operario)));
  });

  test("operario: tarea suya pero de otra empresa (fuera de alcance) -> 404", async () => {
    const { service } = crearServicio();
    await esperar404(service.autorizar(ID_TAREA_OTRA_EMPRESA, actor("op-1", Rol.operario)));
  });

  test("residente -> 404", async () => {
    const { service } = crearServicio();
    await esperar404(service.autorizar(ID_TAREA, actor("res-1", Rol.residente)));
  });

  test("gerente, jefe de operaciones y supervisor ven cualquier tarea de su empresa", async () => {
    const { service } = crearServicio();
    await expect(service.autorizar(ID_TAREA, actor("gerente-1", Rol.gerente))).resolves.toBeUndefined();
    await expect(
      service.autorizar(ID_TAREA_C2, actor("jefe-1", Rol.jefe_operaciones)),
    ).resolves.toBeUndefined();
    await expect(
      service.autorizar(ID_TAREA_C2, actor("sup-1", Rol.supervisor)),
    ).resolves.toBeUndefined();
  });

  test("gerente de otra empresa -> 404", async () => {
    const { service } = crearServicio();
    await esperar404(service.autorizar(ID_TAREA, actor("gerente-x", Rol.gerente, "E2")));
  });

  test("administrador: su conjunto sí, otro conjunto -> 404", async () => {
    const { service } = crearServicio();
    await expect(
      service.autorizar(ID_TAREA, actor("admin-1", Rol.administrador)),
    ).resolves.toBeUndefined();
    await esperar404(service.autorizar(ID_TAREA_C2, actor("admin-1", Rol.administrador)));
  });

  test("sin permiso para ver tareas (matriz de permisos) -> 404", async () => {
    const { service } = crearServicio({ permisos: () => new Set<string>() });
    await esperar404(service.autorizar(ID_TAREA, actor("gerente-1", Rol.gerente)));
  });

  test("reconoce los enlaces viejos uc?id=", async () => {
    const { service } = crearServicio();
    await expect(
      service.autorizar(ID_TAREA_VIEJA, actor("op-2", Rol.operario)),
    ).resolves.toBeUndefined();
  });

  test("un pedazo de un id real no cuenta como ese archivo", async () => {
    const { service } = crearServicio();
    await esperar404(service.autorizar(ID_TAREA.slice(0, 20), actor("gerente-1", Rol.gerente)));
  });
});

describe("EvidenciaAccesoService: otros dueños y archivos sin dueño", () => {
  test("un documento de postulación web no se sirve por /evidencias -> 404 (ni al gerente)", async () => {
    const { service, db } = crearServicio();
    await esperar404(service.autorizar(ID_POSTULACION, actor("gerente-1", Rol.gerente)));
    await esperar404(service.autorizar(ID_POSTULACION, actor("jefe-1", Rol.jefe_operaciones)));
    // El segundo pedido usa el "sin dueño" en caché.
    expect(db.$queryRaw).toHaveBeenCalledTimes(1);
  });

  test("diagnóstico: con permiso del Plan Esperanza y el conjunto en alcance", async () => {
    const { service } = crearServicio();
    await expect(
      service.autorizar(ID_DIAGNOSTICO, actor("sup-1", Rol.supervisor)),
    ).resolves.toBeUndefined();
    await expect(
      service.autorizar(ID_DIAGNOSTICO, actor("gerente-1", Rol.gerente)),
    ).resolves.toBeUndefined();
    // Sin el permiso por defecto.
    await esperar404(service.autorizar(ID_DIAGNOSTICO, actor("op-1", Rol.operario)));
    await esperar404(service.autorizar(ID_DIAGNOSTICO, actor("res-1", Rol.residente)));
  });

  test("diagnóstico: administrador con el permiso, solo en sus conjuntos", async () => {
    const conPlan = (rol: string) =>
      new Set([...PermissionService.defaultPermissionsForRole(rol as Rol), "plan_esperanza.acceso"]);
    const { service } = crearServicio({ permisos: conPlan });
    await expect(
      service.autorizar(ID_DIAGNOSTICO, actor("admin-1", Rol.administrador)),
    ).resolves.toBeUndefined();
    await esperar404(service.autorizar(ID_DIAGNOSTICO, actor("admin-2", Rol.administrador)));
  });

  test("comprobante: el residente dueño y el administrador del conjunto; nadie más", async () => {
    const { service } = crearServicio();
    await expect(
      service.autorizar(ID_COMPROBANTE, actor("res-1", Rol.residente)),
    ).resolves.toBeUndefined();
    await expect(
      service.autorizar(ID_COMPROBANTE, actor("admin-1", Rol.administrador)),
    ).resolves.toBeUndefined();
    await expect(
      service.autorizar(ID_COMPROBANTE, actor("gerente-1", Rol.gerente)),
    ).resolves.toBeUndefined();
    await esperar404(service.autorizar(ID_COMPROBANTE, actor("res-2", Rol.residente)));
    await esperar404(service.autorizar(ID_COMPROBANTE, actor("admin-2", Rol.administrador)));
    await esperar404(service.autorizar(ID_COMPROBANTE, actor("op-1", Rol.operario)));
  });
});

describe("EvidenciaAccesoService: rendimiento", () => {
  test("las fotos pedidas a la vez se buscan en una sola consulta", async () => {
    const db = crearDb();
    const service = new EvidenciaAccesoService(db as any, {
      permisos: async (_e, rol) => PermissionService.defaultPermissionsForRole(rol as Rol),
      cache: cacheEnMemoria(),
      ventanaLoteMs: 5,
    });
    const gerente = actor("gerente-1", Rol.gerente);
    const resultados = await Promise.allSettled([
      service.autorizar(ID_TAREA, gerente),
      service.autorizar(ID_TAREA_C2, gerente),
      service.autorizar(ID_TAREA, gerente),
      service.autorizar(ID_POSTULACION, gerente),
    ]);
    expect(resultados.map((r) => r.status)).toEqual([
      "fulfilled",
      "fulfilled",
      "fulfilled",
      "rejected",
    ]);
    expect(db.$queryRaw).toHaveBeenCalledTimes(1);
    const patrones = db.$queryRaw.mock.calls[0][1] as string[];
    expect(patrones).toHaveLength(3);
    // "_" es comodín en LIKE: va escapado.
    expect(patrones).toContain(`%${ID_TAREA.replace(/_/g, "\\_")}%`);
  });

  test("los dueños quedan en caché: la segunda foto no vuelve a buscar", async () => {
    const { service, db, cache } = crearServicio();
    await service.autorizar(ID_TAREA, actor("gerente-1", Rol.gerente));
    await service.autorizar(ID_TAREA, actor("admin-1", Rol.administrador));
    expect(db.$queryRaw).toHaveBeenCalledTimes(1);
    expect(cache.datos.get(`evidencia:duenos:v1:${ID_TAREA}`)).toEqual({
      valor: { tareas: [{ id: 1, conjuntoId: "C1" }], diagnosticos: [], pedidos: [] },
      ttl: 600,
    });
    await esperar404(service.autorizar(ID_POSTULACION, actor("gerente-1", Rol.gerente)));
    expect(cache.datos.get(`evidencia:duenos:v1:${ID_POSTULACION}`)?.ttl).toBe(60);
  });

  test("si la búsqueda falla, el error llega a todos los que esperaban", async () => {
    const { service, db } = crearServicio();
    db.$queryRaw.mockRejectedValueOnce(new Error("db caida"));
    await expect(service.autorizar(ID_TAREA, actor("gerente-1", Rol.gerente))).rejects.toThrow(
      "db caida",
    );
  });
});

describe("idsDriveEnTexto", () => {
  test("reconoce las formas guardadas y todos los enlaces de un texto", () => {
    expect(idsDriveEnTexto(drive(ID_TAREA))).toEqual([ID_TAREA]);
    expect(idsDriveEnTexto(`https://drive.google.com/uc?id=${ID_TAREA}`)).toEqual([ID_TAREA]);
    expect(idsDriveEnTexto(ID_TAREA)).toEqual([ID_TAREA]);
    expect(idsDriveEnTexto(`/evidencias/${ID_TAREA}`)).toEqual([ID_TAREA]);
    expect(
      idsDriveEnTexto(JSON.stringify([drive(ID_TAREA), drive(ID_TAREA_C2)])),
    ).toEqual([ID_TAREA, ID_TAREA_C2]);
    expect(idsDriveEnTexto("https:\\/\\/drive.google.com\\/file\\/d\\/" + ID_TAREA + "\\/view")).toEqual([
      ID_TAREA,
    ]);
    expect(idsDriveEnTexto("")).toEqual([]);
    expect(idsDriveEnTexto(null)).toEqual([]);
  });
});

describe("EvidenciaController.obtener", () => {
  function reqDe(fileId: string) {
    return { params: { fileId }, user: { sub: "op-2", rol: "operario" } } as any;
  }

  beforeEach(() => {
    mockEmpresaIdAutenticada.mockResolvedValue("E1");
    mockGetEvidenciaStream.mockReset();
  });

  test("sin acceso responde 404 y no descarga nada de Drive", async () => {
    const autorizar = jest
      .spyOn(EvidenciaAccesoService.prototype, "autorizar")
      .mockRejectedValueOnce(Object.assign(new Error(MENSAJE_EVIDENCIA_NO_DISPONIBLE), { status: 404 }));
    const next = jest.fn();
    await new EvidenciaController().obtener(reqDe(ID_TAREA), {} as any, next);

    expect(autorizar).toHaveBeenCalledWith(ID_TAREA, { id: "op-2", rol: "operario", empresaId: "E1" });
    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 404 }));
    expect(mockGetEvidenciaStream).not.toHaveBeenCalled();
  });

  test("con acceso transmite el archivo", async () => {
    jest.spyOn(EvidenciaAccesoService.prototype, "autorizar").mockResolvedValueOnce(undefined);
    const origen = new PassThrough();
    mockGetEvidenciaStream.mockResolvedValue({ stream: origen, mimeType: "image/jpeg" });
    const res = Object.assign(new PassThrough(), { setHeader: jest.fn(), headersSent: false });
    const next = jest.fn();

    await new EvidenciaController().obtener(reqDe(ID_TAREA), res as any, next);
    origen.end(Buffer.from("jpg"));

    expect(next).not.toHaveBeenCalled();
    expect(mockGetEvidenciaStream).toHaveBeenCalledWith(ID_TAREA);
    expect(res.setHeader).toHaveBeenCalledWith("Content-Type", "image/jpeg");
    expect(res.setHeader).toHaveBeenCalledWith("Cache-Control", "private, max-age=2592000, immutable");
    expect(res.setHeader).toHaveBeenCalledWith("ETag", `"ev-${ID_TAREA}"`);
  });

  test("si el navegador ya la tiene (If-None-Match), responde 304 sin bajarla de Drive", async () => {
    jest.spyOn(EvidenciaAccesoService.prototype, "autorizar").mockResolvedValueOnce(undefined);
    const end = jest.fn();
    const res = { setHeader: jest.fn(), status: jest.fn(() => ({ end })) };
    const next = jest.fn();
    const req = { ...reqDe(ID_TAREA), headers: { "if-none-match": `"ev-${ID_TAREA}"` } };

    await new EvidenciaController().obtener(req, res as any, next);

    expect(res.status).toHaveBeenCalledWith(304);
    expect(end).toHaveBeenCalled();
    expect(mockGetEvidenciaStream).not.toHaveBeenCalled();
  });
});
