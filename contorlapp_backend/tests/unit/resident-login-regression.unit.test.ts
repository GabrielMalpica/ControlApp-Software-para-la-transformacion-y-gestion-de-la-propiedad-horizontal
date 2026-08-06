import { Prisma, Rol } from "@prisma/client";
import { AuthService } from "../../src/services/authService";
import { CumpleanosService } from "../../src/services/CumpleanosService";

describe("regresiones de inicio de sesion residente", () => {
  test("la consulta de notificaciones no intenta generar cumpleanos de empresa", async () => {
    const db = {
      usuario: {
        findUnique: jest.fn().mockResolvedValue({
          id: "residente-1",
          rol: Rol.residente,
          nombre: "Residente Uno",
          activo: true,
          fechaNacimiento: new Date("1990-01-01"),
        }),
      },
      gerente: { findUnique: jest.fn() },
      $queryRaw: jest.fn(),
    };
    const service = new CumpleanosService(db as never);

    await expect(
      service.asegurarNotificacionesCumpleanosHoy("residente-1"),
    ).resolves.toBeUndefined();
    expect(db.gerente.findUnique).not.toHaveBeenCalled();
    expect(db.$queryRaw).not.toHaveBeenCalled();
  });

  test("perfil-resumen sigue disponible mientras se despliega la tabla de beneficios", async () => {
    const missingTable = new Prisma.PrismaClientKnownRequestError(
      "Tabla no disponible",
      { code: "P2021", clientVersion: "6.14.0" },
    );
    const db = {
      usuario: {
        findUnique: jest.fn().mockResolvedValue({
          id: "residente-1",
          nombre: "Residente Uno",
          correo: "residente@example.test",
          rol: Rol.residente,
          activo: true,
          requiereCambioContrasena: false,
          administrador: null,
          gerente: null,
          jefeOperaciones: null,
          residente: {
            tipoUnidad: "APARTAMENTO",
            sector: "Torre 1",
            unidad: "101",
            conjunto: { nit: "CJ-1", nombre: "Los Pinos" },
          },
        }),
      },
      pedidoApp: {
        aggregate: jest
          .fn()
          .mockResolvedValueOnce({ _count: { _all: 0 }, _sum: { total: null } })
          .mockResolvedValueOnce({ _sum: { total: null } }),
        count: jest.fn().mockResolvedValue(0),
      },
      movimientoPuntos: {
        aggregate: jest.fn().mockResolvedValue({ _sum: { puntos: null } }),
      },
      beneficioPuntos: {
        count: jest.fn().mockRejectedValue(missingTable),
      },
    };
    const service = new AuthService(db as never);

    const result = await service.obtenerResumenPerfil("residente-1");

    expect(result.user.rol).toBe(Rol.residente);
    expect(result.metricas.beneficiosActivos).toBe(0);
    expect(result.conjuntos).toEqual([{ nit: "CJ-1", nombre: "Los Pinos" }]);
  });
});
