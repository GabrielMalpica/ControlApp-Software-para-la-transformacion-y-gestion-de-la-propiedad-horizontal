import { AsistenciaService } from "../../src/services/AsistenciaService";
import {
  distanciaMetros,
  extraerCoordenadasDeTexto,
  resolverCoordenadasDesdeMaps,
  validarUbicacionEnConjunto,
} from "../../src/utils/ubicacionMaps";

describe("extraerCoordenadasDeTexto", () => {
  test("enlace de lugar: prioriza el punto marcado (!3d!4d) sobre el centro del mapa (@)", () => {
    const url =
      "https://www.google.com/maps/place/Conjunto/@4.7110,-74.0721,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d4.7200!4d-74.0500";
    expect(extraerCoordenadasDeTexto(url)).toEqual({ latitud: 4.72, longitud: -74.05 });
  });

  test("enlace con @lat,lng", () => {
    expect(extraerCoordenadasDeTexto("https://www.google.com/maps/@6.2442,-75.5812,15z")).toEqual({
      latitud: 6.2442,
      longitud: -75.5812,
    });
  });

  test("enlace con ?q=lat,lng y coordenadas a secas", () => {
    expect(extraerCoordenadasDeTexto("https://maps.google.com/?q=4.6097,-74.0817")).toEqual({
      latitud: 4.6097,
      longitud: -74.0817,
    });
    expect(extraerCoordenadasDeTexto("4.6097, -74.0817")).toEqual({ latitud: 4.6097, longitud: -74.0817 });
  });

  test("texto sin coordenadas o fuera de rango devuelve null", () => {
    expect(extraerCoordenadasDeTexto("https://www.google.com/maps/place/Algo")).toBeNull();
    expect(extraerCoordenadasDeTexto("95.0, -74.0")).toBeNull();
  });
});

describe("resolverCoordenadasDesdeMaps", () => {
  test("rechaza enlaces que no son de Google (no hace ninguna petición)", async () => {
    await expect(resolverCoordenadasDesdeMaps("https://ejemplo.com/mapa")).rejects.toMatchObject({
      status: 400,
    });
  });

  test("rechaza texto vacío o irreconocible", async () => {
    await expect(resolverCoordenadasDesdeMaps("   ")).rejects.toMatchObject({ status: 400 });
    await expect(resolverCoordenadasDesdeMaps("cerca del parque")).rejects.toMatchObject({ status: 400 });
  });
});

describe("distanciaMetros / validarUbicacionEnConjunto", () => {
  const conjunto = { nombre: "Serramonte", latitud: 4.7, longitud: -74.05, radioAsistenciaMetros: 150 };

  test("distancia entre dos puntos cercanos (~111 m por 0.001° de latitud)", () => {
    const d = distanciaMetros({ latitud: 4.7, longitud: -74.05 }, { latitud: 4.701, longitud: -74.05 });
    expect(d).toBeGreaterThan(105);
    expect(d).toBeLessThan(115);
  });

  test("dentro del radio pasa y devuelve la distancia", () => {
    const r = validarUbicacionEnConjunto({ conjunto, latitud: 4.7005, longitud: -74.05 });
    expect(r.verificada).toBe(true);
    expect(r.distanciaMetros).toBeLessThan(150);
  });

  test("fuera del radio se rechaza con 403 y dice a cuántos metros está", () => {
    expect(() => validarUbicacionEnConjunto({ conjunto, latitud: 4.71, longitud: -74.05 })).toThrow(
      /Estás a \d+ m de Serramonte/,
    );
    try {
      validarUbicacionEnConjunto({ conjunto, latitud: 4.71, longitud: -74.05 });
    } catch (e: any) {
      expect(e.status).toBe(403);
    }
  });

  test("sin ubicación del dispositivo se rechaza (no basta con no mandarla)", () => {
    expect(() => validarUbicacionEnConjunto({ conjunto, latitud: null, longitud: null })).toThrow(
      /Necesitamos tu ubicación/,
    );
  });

  test("la precisión del GPS amplía el radio hasta 100 m", () => {
    // ~200 m del conjunto: fuera de 150, pero con precisión 100 m entra (150+100=250).
    const lat = 4.7 + 0.0018;
    expect(() => validarUbicacionEnConjunto({ conjunto, latitud: lat, longitud: -74.05 })).toThrow();
    expect(
      validarUbicacionEnConjunto({ conjunto, latitud: lat, longitud: -74.05, precisionMetros: 100 }).verificada,
    ).toBe(true);
  });

  test("conjunto sin ubicación configurada no exige nada", () => {
    const r = validarUbicacionEnConjunto({
      conjunto: { nombre: "Sin ubicación", latitud: null, longitud: null, radioAsistenciaMetros: 150 },
      latitud: null,
      longitud: null,
    });
    expect(r).toEqual({ verificada: false, distanciaMetros: null });
  });
});

const QR = "CTRLAPP-ASISTENCIA|C-1|tok-1";

function construirPrisma(opts: { conLat?: boolean } = {}) {
  const conLat = opts.conLat ?? true;
  const visitas: any[] = [];
  let seq = 0;
  const prisma: any = {
    visitas,
    conjunto: {
      findUnique: jest.fn().mockResolvedValue({
        nit: "C-1",
        nombre: "Conjunto Uno",
        qrAsistenciaToken: "tok-1",
        latitud: conLat ? "4.7000000" : null,
        longitud: conLat ? "-74.0500000" : null,
        radioAsistenciaMetros: 150,
      }),
    },
    supervisor: { findUnique: jest.fn().mockResolvedValue({ id: "sup-1" }) },
    visitaSupervisor: {
      findFirst: jest.fn(async ({ where }: any) =>
        [...visitas].reverse().find(
          (v) => v.supervisorId === where.supervisorId && v.conjuntoId === where.conjuntoId && v.horaSalida == null,
        ) ?? null,
      ),
      create: jest.fn(async ({ data }: any) => {
        const v = { id: ++seq, horaSalida: null, latitudSalida: null, longitudSalida: null, ...data };
        visitas.push(v);
        return v;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const v = visitas.find((x) => x.id === where.id);
        Object.assign(v, data);
        return v;
      }),
    },
  };
  return prisma;
}

describe("AsistenciaService.checkinSupervisor", () => {
  const base = { supervisorId: "sup-1", conjuntoId: "C-1", qrPayload: QR };

  test("en el sitio: el primer escaneo abre la visita (entrada) y el siguiente la cierra (salida)", async () => {
    const prisma = construirPrisma();
    const service = new AsistenciaService(prisma);

    const entrada = await service.checkinSupervisor({ ...base, latitud: 4.7002, longitud: -74.05 });
    expect(entrada.tipo).toBe("ENTRADA");
    expect(prisma.visitas).toHaveLength(1);

    const salida = await service.checkinSupervisor({ ...base, latitud: 4.7002, longitud: -74.05 });
    expect(salida.tipo).toBe("SALIDA");
    expect(prisma.visitas).toHaveLength(1);
    expect(prisma.visitas[0].horaSalida).toBeInstanceOf(Date);
  });

  test("puede volver el mismo día: tras cerrar una visita, el siguiente escaneo abre otra", async () => {
    const prisma = construirPrisma();
    const service = new AsistenciaService(prisma);
    const ubic = { latitud: 4.7002, longitud: -74.05 };

    await service.checkinSupervisor({ ...base, ...ubic });
    await service.checkinSupervisor({ ...base, ...ubic });
    const tercera = await service.checkinSupervisor({ ...base, ...ubic });

    expect(tercera.tipo).toBe("ENTRADA");
    expect(prisma.visitas).toHaveLength(2);
  });

  test("lejos del conjunto no registra nada", async () => {
    const prisma = construirPrisma();
    const service = new AsistenciaService(prisma);

    await expect(
      service.checkinSupervisor({ ...base, latitud: 4.8, longitud: -74.05 }),
    ).rejects.toMatchObject({ status: 403 });
    expect(prisma.visitas).toHaveLength(0);
  });

  test("sin ubicación del dispositivo no registra nada (el conjunto tiene ubicación)", async () => {
    const prisma = construirPrisma();
    const service = new AsistenciaService(prisma);

    await expect(service.checkinSupervisor({ ...base })).rejects.toMatchObject({ status: 400 });
    expect(prisma.visitas).toHaveLength(0);
  });

  test("QR incorrecto se rechaza", async () => {
    const prisma = construirPrisma();
    const service = new AsistenciaService(prisma);

    await expect(
      service.checkinSupervisor({ ...base, qrPayload: "CTRLAPP-ASISTENCIA|C-1|otro", latitud: 4.7, longitud: -74.05 }),
    ).rejects.toMatchObject({ status: 400 });
  });
});

describe("AsistenciaService.checkin (operario) - ubicación", () => {
  const base = { operarioId: "op-1", conjuntoId: "C-1", qrPayload: QR };

  test("lejos del conjunto no lo deja registrar la asistencia", async () => {
    const service = new AsistenciaService(construirPrisma());
    await expect(service.checkin({ ...base, latitud: 4.75, longitud: -74.05 })).rejects.toMatchObject({
      status: 403,
    });
  });

  test("sin ubicación no lo deja registrar cuando el conjunto tiene ubicación", async () => {
    const service = new AsistenciaService(construirPrisma());
    await expect(service.checkin({ ...base })).rejects.toMatchObject({ status: 400 });
  });
});
