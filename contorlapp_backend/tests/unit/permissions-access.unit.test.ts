import { Rol } from "@prisma/client";

import { CompromisoConjuntoService } from "../../src/services/CompromisoConjuntoService";
import { PermissionService } from "../../src/services/PermissionService";

describe("Permisos efectivos por modulo", () => {
  test("un permiso de accion concede la lectura minima del modulo", () => {
    expect(
      PermissionService.hasAnyPermission(
        new Set(["compromisos.gestionar"]),
        ["compromisos.ver"],
      ),
    ).toBe(true);
    expect(
      PermissionService.hasAnyPermission(
        new Set(["solicitudes.crear"]),
        ["solicitudes.ver"],
      ),
    ).toBe(true);
    expect(
      PermissionService.hasAnyPermission(
        new Set(["mapa_areas.gestionar"]),
        ["mapa_areas.ver"],
      ),
    ).toBe(true);
  });

  test("un permiso de lectura no concede acciones de escritura", () => {
    expect(
      PermissionService.hasAnyPermission(
        new Set(["compromisos.ver"]),
        ["compromisos.gestionar"],
      ),
    ).toBe(false);
    expect(
      PermissionService.hasAnyPermission(
        new Set(["solicitudes.ver"]),
        ["solicitudes.gestionar"],
      ),
    ).toBe(false);
  });

  test("los perfiles operativos reciben permisos separados para solicitudes", () => {
    const jefe = PermissionService.defaultPermissionsForRole(
      Rol.jefe_operaciones,
    );
    const supervisor = PermissionService.defaultPermissionsForRole(
      Rol.supervisor,
    );
    const operario = PermissionService.defaultPermissionsForRole(Rol.operario);

    expect(jefe.has("solicitudes.crear")).toBe(true);
    expect(jefe.has("solicitudes.gestionar")).toBe(true);
    expect(supervisor.has("solicitudes.crear")).toBe(true);
    expect(supervisor.has("solicitudes.gestionar")).toBe(false);
    expect(operario.has("solicitudes.crear")).toBe(true);
    expect(operario.has("solicitudes.gestionar")).toBe(false);
  });

  test("inventario físico separa registro administrativo y aprobación", () => {
    const gerente = PermissionService.defaultPermissionsForRole(Rol.gerente);
    const jefe = PermissionService.defaultPermissionsForRole(
      Rol.jefe_operaciones,
    );
    const administrador = PermissionService.defaultPermissionsForRole(
      Rol.administrador,
    );

    expect(gerente.has("maquinaria.aprobar")).toBe(true);
    expect(gerente.has("herramientas.aprobar")).toBe(true);
    expect(jefe.has("maquinaria.aprobar")).toBe(true);
    expect(jefe.has("herramientas.aprobar")).toBe(true);
    expect(administrador.has("maquinaria.crear")).toBe(true);
    expect(administrador.has("herramientas.crear")).toBe(true);
    expect(administrador.has("maquinaria.aprobar")).toBe(false);
    expect(administrador.has("herramientas.aprobar")).toBe(false);
    expect(administrador.has("maquinaria.gestionar_estado")).toBe(false);
    expect(administrador.has("herramientas.prestar")).toBe(false);
    expect(jefe.has("maquinaria.gestionar_estado")).toBe(true);
    expect(jefe.has("herramientas.prestar")).toBe(true);
  });
});

describe("Aislamiento de compromisos globales", () => {
  test("filtra los compromisos por la empresa autenticada", async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const prisma = { compromisoConjunto: { findMany } } as any;
    const service = new CompromisoConjuntoService(prisma);

    await service.listarGlobal("EMP-1");

    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { conjunto: { empresaId: "EMP-1" } },
      }),
    );
  });

  test("rechaza una consulta global sin empresa", async () => {
    const service = new CompromisoConjuntoService({} as any);

    await expect(service.listarGlobal("  ")).rejects.toMatchObject({
      status: 401,
    });
  });
});
