import { CanalPago, EstadoCobro } from "@prisma/client";
import { crearFakePagosPrisma } from "../helpers/fakePagosPrisma";

const crearCobroFactus = jest.fn();
const consultarCobroFactus = jest.fn();

jest.mock("../../src/services/pagos/FactusPayClient", () => ({
  crearCobroFactus: (...args: unknown[]) => crearCobroFactus(...args),
  consultarCobroFactus: (...args: unknown[]) => consultarCobroFactus(...args),
  isFactusPayConfigured: () => true,
  FACTUS_MONTO_MIN_COP: 1_000,
  FACTUS_MONTO_MAX_COP: 12_100_000,
}));

import { PagoService } from "../../src/services/pagos/PagoService";

const HORA = 3_600_000;

function coleccion(overrides: Partial<Record<string, unknown>> = {}) {
  return { reference_code: "CA-x", amount: 50_000, status: "ready", qr: "x", ...overrides };
}

async function armar(remotoAlCrear: Record<string, unknown> = {}) {
  crearCobroFactus.mockResolvedValue(coleccion(remotoAlCrear));
  const prisma = crearFakePagosPrisma();
  const service = new PagoService(prisma);
  const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
  return { prisma, service, cobro };
}

beforeEach(() => {
  crearCobroFactus.mockReset();
  consultarCobroFactus.mockReset();
});

describe("vigencia del QR alineada con Factus", () => {
  test("sin qr_expires_at, la app lo da por vigente 24 h (la vigencia por defecto de Factus)", async () => {
    const { cobro } = await armar();
    const horas = (cobro.expiraLocalEn!.getTime() - cobro.creadoEn.getTime()) / HORA;
    expect(horas).toBeCloseTo(24, 1);
  });

  test("con qr_expires_at, manda el vencimiento real de Factus", async () => {
    const { cobro } = await armar({ qr_expires_at: "2026-10-15T15:20:00Z" });
    expect(cobro.expiraLocalEn?.toISOString()).toBe("2026-10-15T15:20:00.000Z");
    expect(cobro.qrExpiraEn?.toISOString()).toBe("2026-10-15T15:20:00.000Z");
  });

  test("mientras el QR esta vigente, pedir el cobro otra vez devuelve el mismo (un solo QR vivo por pedido)", async () => {
    const { service, cobro } = await armar();
    crearCobroFactus.mockClear();

    const otra = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    expect(otra.id).toBe(cobro.id);
    expect(crearCobroFactus).not.toHaveBeenCalled();
  });

  test("acepta montos desde 1.000 COP (limite actual de la doc de Factus)", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ amount: 1_000 }));
    const service = new PagoService(crearFakePagosPrisma());
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 1_000, pedidoAppId: 9 });
    expect(cobro.estado).toBe(EstadoCobro.PENDIENTE);
  });
});

describe("calendario de reconsulta", () => {
  test("PagoService usa el calendario registrado (p. ej. el disperso del modo webhook)", async () => {
    const { service, cobro } = await armar();
    service.registrarCalendario(() => 15 * 60_000);
    consultarCobroFactus.mockResolvedValue(coleccion());

    const antes = Date.now();
    const actualizado = await service.verificarCobro(cobro.id);

    const espera = actualizado.proximaVerificacion!.getTime() - antes;
    expect(espera).toBeGreaterThanOrEqual(15 * 60_000 - 1_000);
    expect(espera).toBeLessThanOrEqual(15 * 60_000 + 1_000);
  });

  test("si el calendario dice que ya no hay mas consultas, el cobro se abandona", async () => {
    const { service, cobro } = await armar();
    service.registrarCalendario(() => null);
    consultarCobroFactus.mockResolvedValue(coleccion());

    const actualizado = await service.verificarCobro(cobro.id);

    expect(actualizado.estado).toBe(EstadoCobro.ABANDONADO);
    expect(actualizado.proximaVerificacion).toBeNull();
  });
});

describe("cerrarVencido", () => {
  test("cierra un cobro pendiente y deja el motivo en la bitacora; no toca uno ya pagado", async () => {
    const { prisma, service, cobro } = await armar();

    expect(await service.cerrarVencido(cobro.id, "conciliacion: el QR vencio sin pago")).toBe(true);
    const cerrado = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(cerrado.estado).toBe(EstadoCobro.ABANDONADO);
    expect(prisma._debug.eventos().some((e: any) => e.payload?.motivo?.includes("vencio"))).toBe(true);

    await prisma.pagoCobro.update({ where: { id: cobro.id }, data: { estado: EstadoCobro.PAGADO } });
    expect(await service.cerrarVencido(cobro.id, "x")).toBe(false);
    expect((await prisma.pagoCobro.findUnique({ where: { id: cobro.id } })).estado).toBe(EstadoCobro.PAGADO);
  });
});
