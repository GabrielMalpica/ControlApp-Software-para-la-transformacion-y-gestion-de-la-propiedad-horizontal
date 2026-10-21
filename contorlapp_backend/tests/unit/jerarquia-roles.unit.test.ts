jest.mock("../../src/services/RedisService", () => ({
  cached: (_key: string, _ttl: number, loader: () => Promise<unknown>) => loader(),
  cacheDelete: jest.fn().mockResolvedValue(undefined),
}));

import { Rol } from "@prisma/client";

import { AccionAuditoria, ModuloAuditoria } from "../../src/model/Auditoria";
import { GerenteService } from "../../src/services/GerenteServices";
import { PermissionService } from "../../src/services/PermissionService";
import { motivoRechazoGestionUsuario } from "../../src/utils/jerarquiaRoles";

const EMPRESA = "EMP-1";
const GERENTE = { id: "G-1", rol: "gerente", nombre: "Gina Gerente" };
const JEFE = { id: "J-1", rol: "jefe_operaciones", nombre: "Jaime Jefe" };
const SUPERVISOR = { id: "S-1", rol: "supervisor", nombre: "Sara Supervisora" };

type UsuarioFake = {
  id: string;
  nombre: string;
  correo: string;
  rol: string;
  activo: boolean;
  telefono: bigint;
  fechaNacimiento: Date;
  contrasena?: string;
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

/** Prisma en memoria con lo justo para gestionar usuarios, perfiles y traslados. */
function makePrisma(iniciales: UsuarioFake[]) {
  const usuarios = new Map(iniciales.map((u) => [u.id, { ...u }]));
  const eventos: any[] = [];
  const sinContrasena = (u: UsuarioFake | undefined) => {
    if (!u) return null;
    const { contrasena: _omitida, ...resto } = u;
    return resto;
  };

  const prisma: any = {
    usuario: {
      findUnique: jest.fn(async ({ where }: any) => {
        if (where.id != null) return sinContrasena(usuarios.get(where.id));
        return sinContrasena([...usuarios.values()].find((u) => u.correo === where.correo));
      }),
      create: jest.fn(async ({ data }: any) => {
        usuarios.set(data.id, { ...data });
        return sinContrasena(usuarios.get(data.id));
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const actual = usuarios.get(where.id);
        if (!actual) throw new Error("P2025");
        usuarios.set(where.id, { ...actual, ...data });
        return sinContrasena(usuarios.get(where.id));
      }),
      delete: jest.fn(async ({ where }: any) => {
        const actual = usuarios.get(where.id);
        usuarios.delete(where.id);
        return actual;
      }),
    },
    empresa: { findUnique: jest.fn().mockResolvedValue({ nit: EMPRESA }) },
    gerente: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn(async ({ data }: any) => data),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    jefeOperaciones: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn(async ({ data }: any) => data),
      deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    supervisor: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn(async ({ data }: any) => data),
      deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    operario: {
      findUnique: jest.fn().mockResolvedValue(null),
      findFirst: jest.fn().mockResolvedValue({
        id: "OP-1",
        conjuntos: [{ nit: "C-ORIGEN" }, { nit: "C-OTRO" }],
      }),
      create: jest.fn(async ({ data }: any) => ({ id: data.id })),
      update: jest.fn(async ({ where }: any) => ({ id: where.id })),
      deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    conjunto: { findFirst: jest.fn().mockResolvedValue({ nit: "C-DESTINO" }) },
    tarea: {
      count: jest.fn().mockResolvedValue(0),
      findMany: jest.fn().mockResolvedValue([]),
    },
    definicionTareaPreventiva: { findMany: jest.fn().mockResolvedValue([]) },
    conjuntoNecesidadOperario: {
      findMany: jest.fn().mockResolvedValue([
        { id: 501, conjuntoId: "C-ORIGEN", etiqueta: "Todero #1" },
      ]),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    auditoriaEvento: {
      create: jest.fn(async ({ data }: any) => {
        eventos.push(data);
        return data;
      }),
    },
    $transaction: jest.fn(async (fn: any) => fn(prisma)),
  };

  return { prisma, usuarios, eventos };
}

function servicio(prisma: any, actor?: { id: string; rol: string; nombre?: string }) {
  return new GerenteService(prisma, EMPRESA, actor);
}

const nuevoUsuario = (id: string, rol: string) => ({
  id,
  nombre: `Nuevo ${id}`,
  correo: `${id.toLowerCase()}@nuevo.com`,
  contrasena: "Secreta123",
  rol,
  telefono: "3009998877",
  fechaNacimiento: "1995-05-05",
});

describe("motivoRechazoGestionUsuario (regla pura)", () => {
  test("solo un gerente toca usuarios con rol gerente", () => {
    expect(
      motivoRechazoGestionUsuario({ actor: JEFE, objetivoId: "X", rolActual: "operario", rolNuevo: "gerente" }),
    ).toMatch(/Solo un gerente/);
    expect(
      motivoRechazoGestionUsuario({ actor: JEFE, objetivoId: "G-2", rolActual: "gerente" }),
    ).toMatch(/Solo un gerente/);
    expect(
      motivoRechazoGestionUsuario({ actor: GERENTE, objetivoId: "G-2", rolActual: "gerente" }),
    ).toBeNull();
  });

  test("un no gerente solo gestiona roles estrictamente inferiores", () => {
    expect(motivoRechazoGestionUsuario({ actor: JEFE, rolNuevo: "supervisor" })).toBeNull();
    expect(motivoRechazoGestionUsuario({ actor: JEFE, rolNuevo: "jefe_operaciones" })).toMatch(
      /no puedes asignar el rol jefe de operaciones/,
    );
    expect(
      motivoRechazoGestionUsuario({ actor: SUPERVISOR, objetivoId: "J-2", rolActual: "jefe_operaciones" }),
    ).toMatch(/roles inferiores/);
    expect(
      motivoRechazoGestionUsuario({ actor: SUPERVISOR, objetivoId: "OP-1", rolActual: "operario", rolNuevo: "supervisor" }),
    ).toMatch(/no puedes asignar el rol supervisor/);
    // Administrador u operario con el permiso delegado no gestionan a nadie.
    expect(
      motivoRechazoGestionUsuario({ actor: { id: "A-1", rol: "administrador" }, objetivoId: "OP-1", rolActual: "operario" }),
    ).toMatch(/roles inferiores/);
  });

  test("nadie cambia su propio rol, su activo ni se elimina", () => {
    expect(
      motivoRechazoGestionUsuario({ actor: GERENTE, objetivoId: "G-1", rolActual: "gerente", rolNuevo: "jefe_operaciones" }),
    ).toMatch(/tu propio rol/);
    expect(
      motivoRechazoGestionUsuario({ actor: GERENTE, objetivoId: "G-1", rolActual: "gerente", cambiaActivo: true }),
    ).toMatch(/propia cuenta/);
    expect(
      motivoRechazoGestionUsuario({ actor: GERENTE, objetivoId: "G-1", rolActual: "gerente", elimina: true }),
    ).toMatch(/eliminar tu propia cuenta/);
    // Reenviar el mismo rol o el mismo estado no es un cambio.
    expect(
      motivoRechazoGestionUsuario({ actor: GERENTE, objetivoId: "G-1", rolActual: "gerente", rolNuevo: "gerente" }),
    ).toBeNull();
  });

  test("un rol desconocido no se presume inferior", () => {
    expect(
      motivoRechazoGestionUsuario({ actor: JEFE, objetivoId: "Z-1", rolActual: "superadmin" }),
    ).toMatch(/roles inferiores/);
    expect(motivoRechazoGestionUsuario({ actor: { id: "Z-2", rol: "superadmin" }, rolNuevo: "operario" })).toMatch(
      /Tu rol no permite/,
    );
  });
});

describe("GerenteService: jerarquía de roles al gestionar usuarios", () => {
  test("jefe con usuarios.gestionar no puede ponerse rol gerente a sí mismo", async () => {
    const { prisma, usuarios, eventos } = makePrisma([usuario("J-1", "jefe_operaciones")]);

    await expect(
      servicio(prisma, JEFE).editarUsuario("J-1", { rol: "gerente" }),
    ).rejects.toMatchObject({ status: 403 });

    expect(usuarios.get("J-1")?.rol).toBe("jefe_operaciones");
    expect(prisma.gerente.create).not.toHaveBeenCalled();
    expect(prisma.$transaction).not.toHaveBeenCalled();
    // El intento queda registrado.
    expect(eventos).toEqual([
      expect.objectContaining({
        modulo: ModuloAuditoria.SEGURIDAD,
        accion: AccionAuditoria.GESTION_DENEGADA,
        entidadId: "J-1",
        actorId: "J-1",
      }),
    ]);
  });

  test("jefe con usuarios.gestionar no puede promover a otro a gerente", async () => {
    const { prisma, usuarios } = makePrisma([
      usuario("J-1", "jefe_operaciones"),
      usuario("OP-1", "operario"),
    ]);

    const intento = servicio(prisma, JEFE).editarUsuario("OP-1", { rol: "gerente" });
    await expect(intento).rejects.toMatchObject({ status: 403 });
    await expect(intento).rejects.toThrow(/Solo un gerente/);
    expect(usuarios.get("OP-1")?.rol).toBe("operario");
  });

  test("jefe no puede crear un gerente ni asignar el perfil de gerente", async () => {
    const { prisma, usuarios } = makePrisma([
      usuario("J-1", "jefe_operaciones"),
      usuario("G-2", "gerente"),
    ]);
    const service = servicio(prisma, JEFE);

    await expect(service.crearUsuario(nuevoUsuario("NUEVO-1", "gerente"))).rejects.toMatchObject({
      status: 403,
    });
    expect(usuarios.has("NUEVO-1")).toBe(false);

    await expect(
      service.asignarGerente({ Id: "G-2", empresaId: EMPRESA }),
    ).rejects.toMatchObject({ status: 403 });
    expect(prisma.gerente.create).not.toHaveBeenCalled();
  });

  test("jefe no puede editar ni la contraseña de un gerente ni eliminarlo", async () => {
    const { prisma, usuarios } = makePrisma([
      usuario("J-1", "jefe_operaciones"),
      usuario("G-2", "gerente"),
    ]);
    const service = servicio(prisma, JEFE);

    await expect(
      service.editarUsuario("G-2", { contrasena: "OtraClave123" }),
    ).rejects.toMatchObject({ status: 403 });
    await expect(service.eliminarUsuario("G-2")).rejects.toMatchObject({ status: 403 });
    expect(usuarios.has("G-2")).toBe(true);
  });

  test("jefe crea un operario: OK y queda auditado sin contraseña", async () => {
    const { prisma, usuarios, eventos } = makePrisma([usuario("J-1", "jefe_operaciones")]);

    const creado: any = await servicio(prisma, JEFE).crearUsuario(nuevoUsuario("OP-900", "operario"));

    expect(creado.id).toBe("OP-900");
    expect(usuarios.get("OP-900")?.rol).toBe("operario");
    expect(eventos).toHaveLength(1);
    expect(eventos[0]).toMatchObject({
      modulo: ModuloAuditoria.PERSONAL,
      entidad: "Usuario",
      entidadId: "OP-900",
      accion: AccionAuditoria.CREAR,
      empresaId: EMPRESA,
      actorId: "J-1",
      actorRol: "jefe_operaciones",
    });
    expect(eventos[0].datosDespues).toMatchObject({ rol: "operario", telefono: "3009998877" });
    expect(JSON.stringify(eventos[0])).not.toMatch(/contrasena|Secreta123/);
  });

  test("jefe no puede crear otro jefe; supervisor no puede crear supervisor", async () => {
    const { prisma } = makePrisma([
      usuario("J-1", "jefe_operaciones"),
      usuario("S-1", "supervisor"),
    ]);

    await expect(
      servicio(prisma, JEFE).crearUsuario(nuevoUsuario("J-900", "jefe_operaciones")),
    ).rejects.toMatchObject({ status: 403 });
    await expect(
      servicio(prisma, SUPERVISOR).crearUsuario(nuevoUsuario("S-900", "supervisor")),
    ).rejects.toMatchObject({ status: 403 });
  });

  test("gerente promueve a gerente: OK, crea el perfil y audita el cambio de rol", async () => {
    const { prisma, usuarios, eventos } = makePrisma([
      usuario("G-1", "gerente"),
      usuario("J-2", "jefe_operaciones"),
    ]);

    await servicio(prisma, GERENTE).editarUsuario("J-2", { rol: "gerente" });

    expect(usuarios.get("J-2")?.rol).toBe("gerente");
    expect(prisma.jefeOperaciones.deleteMany).toHaveBeenCalledWith({ where: { id: "J-2" } });
    expect(prisma.gerente.create).toHaveBeenCalledWith({
      data: { id: "J-2", empresaId: EMPRESA },
    });

    const cambioRol = eventos.find((e) => e.accion === AccionAuditoria.CAMBIAR_ROL);
    expect(cambioRol).toMatchObject({
      modulo: ModuloAuditoria.SEGURIDAD,
      entidadId: "J-2",
      actorId: "G-1",
      actorNombre: "Gina Gerente",
      datosAntes: { rol: "jefe_operaciones" },
      datosDespues: { rol: "gerente" },
    });
    expect(cambioRol.descripcion).toMatch(/de jefe de operaciones a gerente/);
  });

  test("nadie cambia su propio rol ni su propio activo, ni siquiera el gerente", async () => {
    const { prisma, usuarios } = makePrisma([usuario("G-1", "gerente"), usuario("S-1", "supervisor")]);

    await expect(
      servicio(prisma, GERENTE).editarUsuario("G-1", { rol: "jefe_operaciones" }),
    ).rejects.toThrow(/tu propio rol/);
    await expect(
      servicio(prisma, GERENTE).editarUsuario("G-1", { activo: false }),
    ).rejects.toMatchObject({ status: 403 });
    await expect(
      servicio(prisma, SUPERVISOR).editarUsuario("S-1", { rol: "operario" }),
    ).rejects.toMatchObject({ status: 403 });
    expect(usuarios.get("G-1")).toMatchObject({ rol: "gerente", activo: true });
    expect(usuarios.get("S-1")?.rol).toBe("supervisor");
  });

  test("gerente edita sus propios datos sin tocar rol ni activo", async () => {
    const { prisma, usuarios, eventos } = makePrisma([usuario("G-1", "gerente")]);

    await servicio(prisma, GERENTE).editarUsuario("G-1", {
      nombre: "Gina G.",
      rol: "gerente",
      activo: true,
      contrasena: "NuevaClave123",
    });

    expect(usuarios.get("G-1")?.nombre).toBe("Gina G.");
    expect(eventos).toHaveLength(1);
    expect(eventos[0]).toMatchObject({
      accion: AccionAuditoria.EDITAR,
      datosAntes: { nombre: "Usuario G-1" },
      datosDespues: { nombre: "Gina G." },
      metadataJson: { campos: ["nombre"], contrasenaCambiada: true },
    });
    expect(JSON.stringify(eventos[0])).not.toMatch(/NuevaClave123|\$2[aby]\$/);
  });

  test("gerente desactiva a un supervisor: evento DESACTIVAR", async () => {
    const { prisma, eventos } = makePrisma([usuario("G-1", "gerente"), usuario("S-2", "supervisor")]);

    await servicio(prisma, GERENTE).editarUsuario("S-2", { activo: false });

    expect(eventos).toEqual([
      expect.objectContaining({
        accion: AccionAuditoria.DESACTIVAR,
        entidadId: "S-2",
        datosAntes: { activo: true },
        datosDespues: { activo: false },
      }),
    ]);
  });

  test("sin actor identificado no se gestiona ningún usuario", async () => {
    const { prisma, usuarios } = makePrisma([usuario("OP-1", "operario")]);

    await expect(
      servicio(prisma).editarUsuario("OP-1", { nombre: "Otro" }),
    ).rejects.toMatchObject({ status: 403 });
    expect(usuarios.get("OP-1")?.nombre).toBe("Usuario OP-1");
  });

  test("un actor desactivado no gestiona usuarios aunque su token diga gerente", async () => {
    const { prisma } = makePrisma([
      usuario("G-1", "gerente", { activo: false }),
      usuario("OP-1", "operario"),
    ]);

    await expect(
      servicio(prisma, GERENTE).editarUsuario("OP-1", { nombre: "Otro" }),
    ).rejects.toMatchObject({ status: 403 });
  });

  test("el rol del actor se lee de la base, no del token", async () => {
    // El token aún dice gerente, pero en la base ya es jefe de operaciones.
    const { prisma } = makePrisma([
      usuario("G-1", "jefe_operaciones"),
      usuario("OP-1", "operario"),
    ]);

    await expect(
      servicio(prisma, GERENTE).editarUsuario("OP-1", { rol: "gerente" }),
    ).rejects.toThrow(/Solo un gerente/);
  });

  test("nadie elimina su propia cuenta", async () => {
    const { prisma, usuarios } = makePrisma([usuario("G-1", "gerente")]);

    await expect(servicio(prisma, GERENTE).eliminarUsuario("G-1")).rejects.toThrow(
      /eliminar tu propia cuenta/,
    );
    expect(usuarios.has("G-1")).toBe(true);
  });

  test("gerente elimina un supervisor: evento ELIMINAR con sus datos, sin contraseña", async () => {
    const { prisma, usuarios, eventos } = makePrisma([
      usuario("G-1", "gerente"),
      usuario("S-2", "supervisor", { contrasena: "$2b$10$hash" }),
    ]);

    await servicio(prisma, GERENTE).eliminarUsuario("S-2");

    expect(usuarios.has("S-2")).toBe(false);
    expect(eventos).toEqual([
      expect.objectContaining({
        modulo: ModuloAuditoria.PERSONAL,
        accion: AccionAuditoria.ELIMINAR,
        entidadId: "S-2",
        datosAntes: expect.objectContaining({ rol: "supervisor", correo: "s-2@test.com" }),
      }),
    ]);
    expect(JSON.stringify(eventos[0])).not.toMatch(/contrasena|\$2b\$/);
  });

  test("supervisor asigna el perfil de operario: OK y auditado", async () => {
    const { prisma, eventos } = makePrisma([usuario("S-1", "supervisor"), usuario("OP-5", "operario")]);

    await servicio(prisma, SUPERVISOR).asignarOperario({
      Id: "OP-5",
      funciones: ["TODERO"],
      cursoSalvamentoAcuatico: false,
      cursoAlturas: false,
      examenIngreso: false,
      fechaIngreso: "2026-01-01",
    });

    expect(prisma.operario.create).toHaveBeenCalledTimes(1);
    expect(eventos).toEqual([
      expect.objectContaining({
        accion: AccionAuditoria.ASIGNAR_PERFIL,
        entidadId: "OP-5",
        datosDespues: { perfil: Rol.operario },
        actorId: "S-1",
      }),
    ]);
  });

  test("el traslado de un operario deja un evento de auditoría", async () => {
    const { prisma, eventos } = makePrisma([usuario("G-1", "gerente"), usuario("OP-1", "operario")]);

    const result = await servicio(prisma, GERENTE).trasladarOperario("OP-1", {
      conjuntoId: "C-DESTINO",
    });

    expect(result).toEqual({ ok: true });
    expect(eventos).toEqual([
      expect.objectContaining({
        modulo: ModuloAuditoria.PERSONAL,
        entidad: "Operario",
        entidadId: "OP-1",
        accion: AccionAuditoria.TRASLADAR,
        conjuntoId: "C-DESTINO",
        actorId: "G-1",
        datosAntes: { conjuntos: ["C-ORIGEN", "C-OTRO"] },
        datosDespues: { conjuntos: ["C-DESTINO"] },
        metadataJson: {
          plazasLiberadas: [{ id: 501, conjuntoId: "C-ORIGEN", etiqueta: "Todero #1" }],
        },
      }),
    ]);
  });
});

describe("PermissionService.replacePermissionMatrix: auditoría", () => {
  function prismaPermisos(overridesGuardados: any[] = []) {
    const eventos: any[] = [];
    const prisma: any = {
      permisoRol: {
        findMany: jest.fn(async ({ where }: any) =>
          overridesGuardados.filter((o) =>
            where.rol?.in ? where.rol.in.includes(o.rol) : o.rol === where.rol,
          ),
        ),
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        createMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      auditoriaEvento: {
        create: jest.fn(async ({ data }: any) => {
          eventos.push(data);
          return data;
        }),
      },
      $transaction: jest.fn(async (fn: any) => fn(prisma)),
    };
    return { prisma, eventos };
  }

  test("registra qué permisos se otorgaron y revocaron, y quién lo hizo", async () => {
    const { prisma, eventos } = prismaPermisos();
    const defaultsJefe = PermissionService.defaultPermissionsForRole(Rol.jefe_operaciones);
    const revocable = [...defaultsJefe][0];

    await new PermissionService(prisma).replacePermissionMatrix(
      EMPRESA,
      { jefe_operaciones: { "usuarios.gestionar": true, [revocable]: false } },
      GERENTE,
    );

    expect(eventos).toHaveLength(1);
    expect(eventos[0]).toMatchObject({
      modulo: ModuloAuditoria.SEGURIDAD,
      entidad: "PermisoRol",
      entidadId: EMPRESA,
      accion: AccionAuditoria.ACTUALIZAR_PERMISOS,
      actorId: "G-1",
      datosAntes: { jefe_operaciones: { "usuarios.gestionar": false, [revocable]: true } },
      datosDespues: { jefe_operaciones: { "usuarios.gestionar": true, [revocable]: false } },
      metadataJson: {
        otorgados: ["jefe_operaciones:usuarios.gestionar"],
        revocados: [`jefe_operaciones:${revocable}`],
      },
    });
  });

  test("guardar la misma matriz no deja evento", async () => {
    const { prisma, eventos } = prismaPermisos([
      { rol: "jefe_operaciones", permiso: "usuarios.gestionar", permitido: true },
    ]);

    await new PermissionService(prisma).replacePermissionMatrix(
      EMPRESA,
      { jefe_operaciones: { "usuarios.gestionar": true } },
      GERENTE,
    );

    expect(eventos).toHaveLength(0);
  });
});
