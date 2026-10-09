import {
  buscarDireccionGps,
  direccionGpsSinDemora,
  parsearDireccionNominatim,
} from "../../src/utils/direccion_gps";

// Respuesta real de Nominatim para un punto de Villavicencio (recortada).
const RESPUESTA_VILLAVICENCIO = {
  address: {
    road: "Carrera 24B",
    neighbourhood: "San Francisco",
    quarter: "Comuna 6",
    city: "Perímetro Urbano Villavicencio",
    county: "Villavicencio",
    state: "Meta",
    country: "Colombia",
  },
};

function respuesta(json: unknown, ok = true) {
  return { ok, status: ok ? 200 : 503, json: async () => json } as Response;
}

describe("parsearDireccionNominatim", () => {
  it("toma calle, barrio y ciudad limpiando el 'Perímetro Urbano'", () => {
    expect(parsearDireccionNominatim(RESPUESTA_VILLAVICENCIO)).toEqual({
      calle: "Carrera 24B",
      barrio: "San Francisco",
      ciudad: "Villavicencio",
    });
  });

  it("agrega la placa cuando OpenStreetMap la tiene", () => {
    expect(
      parsearDireccionNominatim({
        address: { road: "Calle 33A", house_number: "39-37", suburb: "El Barzal", city: "Bogotá" },
      }),
    ).toEqual({ calle: "Calle 33A # 39-37", barrio: "El Barzal", ciudad: "Bogotá" });
  });

  it("tolera respuestas sin dirección", () => {
    expect(parsearDireccionNominatim({ error: "Unable to geocode" })).toEqual({
      calle: null,
      barrio: null,
      ciudad: null,
    });
    expect(parsearDireccionNominatim(null)).toEqual({ calle: null, barrio: null, ciudad: null });
  });
});

describe("buscarDireccionGps", () => {
  const fetchOriginal = global.fetch;
  let fetchMock: jest.Mock;

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });
  afterAll(() => {
    global.fetch = fetchOriginal;
  });

  it("consulta una vez por punto y reutiliza la caché para fotos del mismo sitio", async () => {
    fetchMock.mockResolvedValue(respuesta(RESPUESTA_VILLAVICENCIO));

    const [a, b] = await Promise.all([
      buscarDireccionGps(4.142013, -73.626641),
      buscarDireccionGps(4.142013, -73.626641),
    ]);
    // A pocos metros: misma celda de caché.
    const c = await buscarDireccionGps(4.142031, -73.626629);

    expect(a?.calle).toBe("Carrera 24B");
    expect(b).toEqual(a);
    expect(c).toEqual(a);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(String(url)).toContain("/reverse?");
    expect(String(url)).toContain("lat=4.142013");
    expect(init.headers["User-Agent"]).toMatch(/ControlApp/);
  });

  it("devuelve null si el servicio falla, sin guardar el fallo", async () => {
    fetchMock.mockResolvedValueOnce(respuesta({}, false));
    expect(await buscarDireccionGps(5.5, -74.1)).toBeNull();

    fetchMock.mockResolvedValueOnce(respuesta(RESPUESTA_VILLAVICENCIO));
    expect((await buscarDireccionGps(5.5, -74.1))?.barrio).toBe("San Francisco");
  });

  it("direccionGpsSinDemora no espera más de lo indicado", async () => {
    fetchMock.mockImplementation(
      () => new Promise((resolve) => setTimeout(() => resolve(respuesta(RESPUESTA_VILLAVICENCIO)), 3000)),
    );
    const inicio = Date.now();
    expect(await direccionGpsSinDemora(6.2, -75.5, 150)).toBeNull();
    expect(Date.now() - inicio).toBeLessThan(1000);
  });
});
