import { AccionAuditoria, ModuloAuditoria } from "../../src/model/Auditoria";
import { GerenteService } from "../../src/services/GerenteServices";
import { mensajeValidacionAmigable } from "../../src/utils/errorFormat";

const EMPRESA = "EMP-1";
const OTRA_EMPRESA = "EMP-2";
const GERENTE = { id: "G-1", rol: "gerente", nombre: "Gina Gerente" };
const JEFE = { id: "J-1", rol: "jefe_operaciones", nombre: "Jaime Jefe" };

type UsuarioFake = {
  id: string;
  nombre: string;
  correo: string;
  rol: string;
  activo: boolean;
  telefono: bigint;
  fechaNacimiento: Date;
};

type ConjuntoFake = {
  nit: string;
  nombre: string;
  empresaId: string;
  administradorId: string | null;
};

function usuario(id: string, rol: string, extra: Partial<UsuarioFake> = {}): UsuarioFake {
  return {
    id,
    nombre: `Usuario ${id}`,
    correo: `${id.toLowerCase()}@test.com`,
    rol,
    activo: true,
    telefono: BigInt(3001234567),
    fechaNacimiento: new Date("1990-01-01T00:00:00.000Z"),
    ...extra,
  };
}

function conjunto(nit: string, empresaId: string, administradorId: string | null): ConjuntoFake {
  return { nit, nombre: `Conjunto ${nit}`, empresaId, administradorId };
}

/**
 * Prisma en memoria con lo justo para las ediciones rapidas y el reemplazo de
 * administradores. `perfilesAdmin` son los usuarios con fila en Administrador.
 */
function makePrisma(params: {
  usuarios: UsuarioFake[];
  conjuntos?: ConjuntoFake[];
  perfilesAdmin?: string[];
  supervisores?: { id: string; empresaId: string }[];
}) {
  const usuarios = new Map(params.usuarios.map((u) => [u.id, { ...u }]));
  const conjuntos = new Map((params.conjuntos ?? []).map((c) => [c.nit, { ...c }]));
  const perfilesAdmin = new Set(params.perfilesAdmin ?? []);
  const supervisores = new Map((params.supervisores ?? []).map((s) => [s.id, { ...s }]));
  const eventos: any[] = [];

  const prisma: any = {
    empresa: { findUnique: jest.fn().mockResolvedValue({ nit: EMPRESA }) },
    usuario: {
      findUnique: jest.fn(async ({ where }: any) => {
        const u = usuarios.get(where.id);
        return u ? { ...u, operario: { funciones: ["TODERO"] } } : null;
      }),
      findMany: jest.fn(async ({ where }: any) =>
        [...usuarios.values()]
          .filter((u) => where.id.in.includes(u.id))
          .map((u) => ({
            id: u.id,
            nombre: u.nombre,
            rol: u.rol,
            activo: u.activo,
            administrador: perfilesAdmin.has(u.id)
              ? {
                  conjuntos: [...conjuntos.values()]
                    .filter((c) => c.administradorId === u.id)
                    .map((c) => ({ empresaId: c.empresaId })),
                }
              : null,
          })),
      ),
      update: jest.fn(async ({ where, data }: any) => {
        const actual = usuarios.get(where.id);
        if (!actual) throw new Error("P2025");
        usuarios.set(where.id, { ...actual, ...data });
        return usuarios.get(where.id);
      }),
    },
    supervisor: {
      update: jest.fn(async ({ where, data }: any) => {
        supervisores.set(where.id, { ...supervisores.get(where.id)!, ...data });
        return supervisores.get(where.id);
      }),
    },
    operario: { update: jest.fn(async ({ where }: any) => ({ id: where.id })) },
    conjuntoNecesidadOperario: { findMany: jest.fn().mockResolvedValue([]) },
    conjunto: {
      findMany: jest.fn(async ({ where }: any) =>
        [...conjuntos.values()]
          .filter((c) => where.nit.in.includes(c.nit) && c.empresaId === where.empresaId)
          .map((c) => ({
            nit: c.nit,
            nombre: c.nombre,
            administradorId: c.administradorId,
            administrador: c.administradorId
              ? { usuario: { nombre: usuarios.get(c.administradorId)?.nombre ?? "" } }
              : null,
          })),
      ),
      update: jest.fn(async ({ where, data }: any) => {
        conjuntos.set(where.nit, { ...conjuntos.get(where.nit)!, ...data });
        return conjuntos.get(where.nit);
      }),
    },
    auditoriaEvento: {
      create: jest.fn(async ({ data }: any) => {
        eventos.push(data);
        return data;
      }),
    },
    $transaction: jest.fn(async (fn: any) => fn(prisma)),
  };

  return { prisma, usuarios, conjuntos, supervisores, eventos };
}

function servicio(prisma: any, actor: { id: string; rol: string; nombre?: string } = GERENTE) {
  return new GerenteService(prisma, EMPRESA, actor);
}

/** ZodError con un issue propio (code custom) en ese campo: el manejador central lo vuelve 400. */
function campoRechazado(campo: string, mensaje: RegExp) {
  return expect.objectContaining({
    name: "ZodError",
    issues: expect.arrayContaining([
      expect.objectContaining({ code: "custom", path: [campo], message: expect.stringMatching(mensaje) }),
    ]),
  });
}

describe("editarSupervisor: la empresa no viene del body", () => {
  test("rechaza empresaId y no mueve al supervisor de empresa", async () => {
    const { prisma, supervisores, eventos } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("2", "supervisor")],
      supervisores: [{ id: "2", empresaId: EMPRESA }],
    });

    await expect(
      servicio(prisma).editarSupervisor(2 as any, { nombre: "Sara", empresaId: OTRA_EMPRESA }),
    ).rejects.toEqual(campoRechazado("empresaId", /siempre es la de tu sesión/));

    expect(prisma.supervisor.update).not.toHaveBeenCalled();
    expect(prisma.usuario.update).not.toHaveBeenCalled();
    expect(supervisores.get("2")?.empresaId).toBe(EMPRESA);
    expect(eventos).toHaveLength(0);
  });

  test("el mensaje del rechazo llega tal cual al cliente", () => {
    expect(
      mensajeValidacionAmigable({
        code: "custom",
        message: "La empresa no se puede cambiar: siempre es la de tu sesión.",
      }),
    ).toBe("La empresa no se puede cambiar: siempre es la de tu sesión.");
  });

  test("rechaza también rol, activo y contraseña", async () => {
    const { prisma } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("2", "supervisor")],
    });
    const service = servicio(prisma);

    await expect(service.editarSupervisor(2 as any, { rol: "gerente" })).rejects.toEqual(
      campoRechazado("rol", /edición completa del usuario/),
    );
    await expect(service.editarSupervisor(2 as any, { activo: false })).rejects.toEqual(
      campoRechazado("activo", /edición completa del usuario/),
    );
    await expect(
      service.editarSupervisor(2 as any, { contrasena: "OtraClave123" }),
    ).rejects.toEqual(campoRechazado("contrasena", /edición completa del usuario/));
    expect(prisma.usuario.update).not.toHaveBeenCalled();
  });

  test("nombre y correo: OK, solo toca Usuario y queda auditado", async () => {
    const { prisma, usuarios, eventos } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("2", "supervisor")],
      supervisores: [{ id: "2", empresaId: EMPRESA }],
    });

    await servicio(prisma).editarSupervisor(2 as any, {
      nombre: "Sara Supervisora",
      correo: "SARA@Empresa.com",
    });

    expect(prisma.usuario.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "2" },
        data: { nombre: "Sara Supervisora", correo: "sara@empresa.com" },
      }),
    );
    expect(usuarios.get("2")).toMatchObject({ nombre: "Sara Supervisora", rol: "supervisor" });
    expect(prisma.supervisor.update).not.toHaveBeenCalled();
    expect(eventos).toEqual([
      expect.objectContaining({
        modulo: ModuloAuditoria.PERSONAL,
        accion: AccionAuditoria.EDITAR,
        actorId: "G-1",
      }),
    ]);
  });
});

describe("editarAdministrador: el rol no cambia por la edición rápida", () => {
  test("rechaza rol sin tocar el usuario ni su perfil", async () => {
    const { prisma, usuarios, eventos } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("7", "administrador")],
      perfilesAdmin: ["7"],
    });

    await expect(
      servicio(prisma).editarAdministrador(7, { nombre: "Ana", rol: "supervisor" }),
    ).rejects.toEqual(campoRechazado("rol", /edición completa del usuario/));

    expect(prisma.usuario.update).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(usuarios.get("7")).toMatchObject({ rol: "administrador", nombre: "Usuario 7" });
    expect(eventos).toHaveLength(0);
  });

  test("rechaza activo, contraseña y empresaId", async () => {
    const { prisma } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("7", "administrador")],
    });
    const service = servicio(prisma);

    await expect(service.editarAdministrador(7, { activo: false })).rejects.toEqual(
      campoRechazado("activo", /edición completa del usuario/),
    );
    await expect(
      service.editarAdministrador(7, { contrasena: "OtraClave123" }),
    ).rejects.toEqual(campoRechazado("contrasena", /edición completa del usuario/));
    await expect(
      service.editarAdministrador(7, { empresaId: OTRA_EMPRESA }),
    ).rejects.toEqual(campoRechazado("empresaId", /siempre es la de tu sesión/));
    expect(prisma.usuario.update).not.toHaveBeenCalled();
  });

  test("datos personales: OK, sin cambio de rol y sin campos ajenos a Usuario", async () => {
    const { prisma, usuarios, eventos } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("7", "administrador")],
      perfilesAdmin: ["7"],
    });

    await servicio(prisma).editarAdministrador(7, {
      nombre: "Ana Administradora",
      telefono: "3105556677",
      // Antes llegaban a Prisma y rompían la edición; ahora se descartan.
      conjuntoId: "C-1",
      disponibilidadPeriodos: [],
    });

    const { data } = prisma.usuario.update.mock.calls[0][0];
    expect(data).toEqual({ nombre: "Ana Administradora", telefono: BigInt(3105556677) });
    expect(usuarios.get("7")).toMatchObject({ rol: "administrador", nombre: "Ana Administradora" });
    expect(eventos.map((e) => e.accion)).toEqual([AccionAuditoria.EDITAR]);
  });
});

describe("editarOperario: solo nombre, correo y funciones", () => {
  test("rechaza empresaId y rol", async () => {
    const { prisma } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("1", "operario")],
    });
    const service = servicio(prisma);

    await expect(
      service.editarOperario(1 as any, { funciones: ["TODERO"], empresaId: OTRA_EMPRESA }),
    ).rejects.toEqual(campoRechazado("empresaId", /siempre es la de tu sesión/));
    await expect(service.editarOperario(1 as any, { rol: "supervisor" })).rejects.toEqual(
      campoRechazado("rol", /edición completa del usuario/),
    );
    expect(prisma.operario.update).not.toHaveBeenCalled();
    expect(prisma.usuario.update).not.toHaveBeenCalled();
  });

  test("el correo se valida antes de llegar a la base", async () => {
    const { prisma } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("1", "operario")],
    });

    await expect(
      servicio(prisma).editarOperario(1 as any, { correo: "no-es-correo" }),
    ).rejects.toMatchObject({ name: "ZodError" });
    expect(prisma.usuario.update).not.toHaveBeenCalled();
  });

  test("funciones y nombre (lo que manda la app): OK", async () => {
    const { prisma } = makePrisma({
      usuarios: [usuario("G-1", "gerente"), usuario("1", "operario")],
    });

    await servicio(prisma).editarOperario(1 as any, {
      funciones: ["TODERO", "SALVAVIDAS"],
      nombre: "Oscar Operario",
    });

    expect(prisma.operario.update).toHaveBeenCalledWith({
      where: { id: "1" },
      data: { funciones: ["TODERO", "SALVAVIDAS"] },
    });
    expect(prisma.usuario.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { nombre: "Oscar Operario" } }),
    );
  });
});

describe("reemplazarAdminEnVariosConjuntos: valida al administrador nuevo y audita", () => {
  function escenario() {
    return makePrisma({
      usuarios: [
        usuario("G-1", "gerente"),
        usuario("J-1", "jefe_operaciones"),
        usuario("10", "administrador", { nombre: "Ana Anterior" }),
        usuario("20", "administrador", { nombre: "Nora Nueva" }),
        usuario("30", "administrador", { nombre: "Ines Inactiva", activo: false }),
        usuario("40", "operario"),
        usuario("50", "administrador", { nombre: "Otra Empresa" }),
        usuario("60", "administrador", { nombre: "Sin Perfil" }),
        usuario("70", "administrador", { nombre: "Sin Conjuntos" }),
      ],
      perfilesAdmin: ["10", "20", "30", "50", "70"],
      conjuntos: [
        conjunto("C-1", EMPRESA, "10"),
        conjunto("C-2", EMPRESA, null),
        conjunto("C-3", EMPRESA, "20"),
        conjunto("C-AJENO", OTRA_EMPRESA, "50"),
      ],
    });
  }

  const sinCambios = (conjuntos: Map<string, ConjuntoFake>) => {
    expect(conjuntos.get("C-1")?.administradorId).toBe("10");
    expect(conjuntos.get("C-2")?.administradorId).toBeNull();
  };

  test.each([
    ["no existe", 99, 404],
    ["no tiene rol administrador", 40, 404],
    ["tiene conjuntos de otra empresa", 50, 404],
    ["no tiene perfil de administrador", 60, 404],
    ["está inactivo", 30, 400],
  ])("rechaza un administrador nuevo que %s", async (_caso, nuevoAdminId, status) => {
    const { prisma, conjuntos, eventos } = escenario();

    await expect(
      servicio(prisma).reemplazarAdminEnVariosConjuntos({
        reemplazos: [{ conjuntoId: "C-1", nuevoAdminId }],
      }),
    ).rejects.toMatchObject({ status });

    expect(prisma.conjunto.update).not.toHaveBeenCalled();
    sinCambios(conjuntos);
    expect(eventos).toHaveLength(0);
  });

  test("rechaza un conjunto de otra empresa", async () => {
    const { prisma, conjuntos } = escenario();

    const intento = servicio(prisma).reemplazarAdminEnVariosConjuntos({
      reemplazos: [{ conjuntoId: "C-AJENO", nuevoAdminId: 20 }],
    });
    await expect(intento).rejects.toMatchObject({ status: 404 });
    await expect(intento).rejects.toThrow(/C-AJENO no encontrado en la empresa/);
    expect(conjuntos.get("C-AJENO")?.administradorId).toBe("50");
  });

  test("o todos o ninguno: un reemplazo inválido frena los demás", async () => {
    const { prisma, conjuntos } = escenario();

    await expect(
      servicio(prisma).reemplazarAdminEnVariosConjuntos({
        reemplazos: [
          { conjuntoId: "C-1", nuevoAdminId: 20 },
          { conjuntoId: "C-2", nuevoAdminId: 30 },
        ],
      }),
    ).rejects.toMatchObject({ status: 400 });
    expect(prisma.conjunto.update).not.toHaveBeenCalled();
    sinCambios(conjuntos);
  });

  test("rechaza el mismo conjunto repetido en la lista", async () => {
    const { prisma } = escenario();

    await expect(
      servicio(prisma).reemplazarAdminEnVariosConjuntos({
        reemplazos: [
          { conjuntoId: "C-1", nuevoAdminId: 20 },
          { conjuntoId: "C-1", nuevoAdminId: 70 },
        ],
      }),
    ).rejects.toMatchObject({ name: "ZodError" });
    expect(prisma.conjunto.update).not.toHaveBeenCalled();
  });

  test("un actor sin jerarquía sobre administradores no reemplaza", async () => {
    const { prisma, conjuntos, eventos } = escenario();
    prisma.usuario.findUnique.mockImplementation(async ({ where }: any) =>
      where.id === "A-1" ? { id: "A-1", rol: "administrador", activo: true } : null,
    );

    await expect(
      servicio(prisma, { id: "A-1", rol: "administrador" }).reemplazarAdminEnVariosConjuntos({
        reemplazos: [{ conjuntoId: "C-1", nuevoAdminId: 20 }],
      }),
    ).rejects.toMatchObject({ status: 403 });
    sinCambios(conjuntos);
    expect(eventos).toEqual([
      expect.objectContaining({
        modulo: ModuloAuditoria.SEGURIDAD,
        accion: AccionAuditoria.GESTION_DENEGADA,
      }),
    ]);
  });

  test("reemplazo válido: cambia los conjuntos y audita cada cambio en PERSONAL", async () => {
    const { prisma, conjuntos, eventos } = escenario();

    await servicio(prisma, JEFE).reemplazarAdminEnVariosConjuntos({
      reemplazos: [
        { conjuntoId: "C-1", nuevoAdminId: 20 },
        { conjuntoId: "C-2", nuevoAdminId: 70 },
        // Ya es su administrador: no cambia nada ni deja evento.
        { conjuntoId: "C-3", nuevoAdminId: 20 },
      ],
    });

    expect(conjuntos.get("C-1")?.administradorId).toBe("20");
    expect(conjuntos.get("C-2")?.administradorId).toBe("70");
    expect(conjuntos.get("C-3")?.administradorId).toBe("20");
    expect(prisma.conjunto.update).toHaveBeenCalledTimes(2);
    expect(prisma.conjunto.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { nit: { in: ["C-1", "C-2", "C-3"] }, empresaId: EMPRESA },
      }),
    );

    expect(eventos).toEqual([
      expect.objectContaining({
        modulo: ModuloAuditoria.PERSONAL,
        entidad: "Usuario",
        entidadId: "20",
        accion: AccionAuditoria.REEMPLAZAR,
        conjuntoId: "C-1",
        empresaId: EMPRESA,
        actorId: "J-1",
        datosAntes: { administradorId: "10" },
        datosDespues: { administradorId: "20" },
      }),
      expect.objectContaining({
        entidadId: "70",
        conjuntoId: "C-2",
        datosAntes: { administradorId: null },
        datosDespues: { administradorId: "70" },
      }),
    ]);
    expect(eventos[0].descripcion).toMatch(
      /asignó a Nora Nueva \(20\) como administrador del conjunto Conjunto C-1 \(C-1\) en reemplazo de Ana Anterior \(10\)/,
    );
  });

  test("lista vacía: no hace nada", async () => {
    const { prisma } = escenario();

    await servicio(prisma).reemplazarAdminEnVariosConjuntos({ reemplazos: [] });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });
});
