import { Rol } from "@prisma/client";
import { CompromisoConjuntoService } from "../../src/services/CompromisoConjuntoService";
import { NotificacionService } from "../../src/services/NotificacionService";
import { PermissionService } from "../../src/services/PermissionService";

describe("Permiso de seguimiento de PQRS", () => {
  test("solo gerente y jefe de operaciones tienen seguimiento por defecto", () => {
    const permiso = "compromisos.seguimiento.gestionar";
    expect(PermissionService.defaultPermissionsForRole(Rol.gerente).has(permiso)).toBe(true);
    expect(PermissionService.defaultPermissionsForRole(Rol.jefe_operaciones).has(permiso)).toBe(true);
    expect(PermissionService.defaultPermissionsForRole(Rol.administrador).has(permiso)).toBe(false);
    expect(PermissionService.defaultPermissionsForRole(Rol.supervisor).has(permiso)).toBe(false);
  });
});

describe("NotificacionService PQRS", () => {
  test("notifica al administrador asignado del conjunto", async () => {
    const db = {
      usuario: { findUnique: jest.fn(async () => ({ nombre: "Jefe Uno" })) },
      conjunto: {
        findUnique: jest.fn(async () => ({ nombre: "Conjunto Uno", administradorId: "admin-1" })),
      },
      $executeRaw: jest.fn(async () => 1),
    };
    const service = new NotificacionService(db as any);

    await service.notificarActualizacionPqrs({
      compromisoId: 8,
      conjuntoId: "C1",
      titulo: "Luz dañada",
      estado: "EN_PROCESO",
      actorId: "jefe-1",
    });

    expect(db.conjunto.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({ where: { nit: "C1" } }),
    );
    expect(db.$executeRaw).toHaveBeenCalledTimes(1);
  });
});

describe("CompromisoConjuntoService seguimiento", () => {
  const now = new Date("2026-11-14T12:00:00.000Z");
  const base = {
    id: 8,
    conjuntoId: "C1",
    titulo: "Luz dañada",
    completado: false,
    estado: "EN_PROCESO",
    creadaEn: now,
    cerradaEn: null,
    actualizadaEn: now,
    creadoPorId: "admin-1",
    conjunto: {
      nit: "C1",
      nombre: "Conjunto Uno",
      direccion: null,
      latitud: null,
      longitud: null,
    },
    actualizaciones: [],
  };

  function setup(current = { ...base }) {
    const tx = {
      compromisoConjunto: {
        updateMany: jest.fn(async () => ({ count: 1 })),
        findUniqueOrThrow: jest.fn(async () => ({
          ...base,
          estado: "EN_PROCESO",
          actualizaciones: [
            {
              id: 44,
              estado: "EN_PROCESO",
              observacion: "Se programó la reparación",
              evidencias: [],
              actorId: "gerente-1",
              creadaEn: now,
              actor: { nombre: "Gerente Uno", rol: "gerente" },
            },
          ],
        })),
      },
      compromisoActualizacion: { create: jest.fn(async () => ({ id: 44 })) },
    };
    const prisma = {
      compromisoConjunto: { findUnique: jest.fn(async () => current) },
      usuario: { findUnique: jest.fn(async () => ({ nombre: "Gerente Uno", rol: "gerente" })) },
      conjunto: { findUnique: jest.fn(async () => null) },
      $transaction: jest.fn(async (callback: (value: typeof tx) => Promise<unknown>) => callback(tx)),
    };
    return { service: new CompromisoConjuntoService(prisma as any), prisma, tx };
  }

  test("acepta registrar varias veces el mismo estado y conserva cada evento", async () => {
    const { service, tx } = setup();
    for (let i = 0; i < 2; i++) {
      await service.agregarSeguimiento({
        id: 8,
        estado: "EN_PROCESO",
        observacion: `Avance ${i + 1}`,
        actorId: "gerente-1",
        files: [],
      });
    }

    expect(tx.compromisoActualizacion.create).toHaveBeenCalledTimes(2);
    expect(tx.compromisoConjunto.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ estado: "EN_PROCESO", completado: false }) }),
    );
  });

  test("una PQRS cerrada no puede recibir más actualizaciones", async () => {
    const { service, prisma } = setup({ ...base, estado: "CERRADO", completado: true });
    await expect(
      service.agregarSeguimiento({
        id: 8,
        estado: "EN_PROCESO",
        actorId: "gerente-1",
        files: [],
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });
});
