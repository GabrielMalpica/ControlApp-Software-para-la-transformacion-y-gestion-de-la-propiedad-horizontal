import {
  normalizarNombreZona,
  politicaZonaPredeterminada,
  resolverConfiguracionZona,
} from "../../src/utils/cronogramaZona";

// El orden del dia ya no depende de la zona (ver orden-programacion.unit.test.ts);
// la zona solo conserva su color en el cronograma.
describe("configuracion de zonas del cronograma", () => {
  test("normaliza acentos y aplica los tres niveles predeterminados", () => {
    expect(normalizarNombreZona("Zonas de Tránsito")).toBe(
      "zonas de transito",
    );
    expect(politicaZonaPredeterminada("Zonas húmedas")).toMatchObject({
      orden: 10,
      colorHex: "#2196F3",
    });
    expect(politicaZonaPredeterminada("Zona verde").orden).toBe(20);
    expect(politicaZonaPredeterminada("Circulación vehicular").orden).toBe(
      30,
    );
  });

  test("resuelve la zona raiz y respeta una configuracion guardada", () => {
    const raiz = { id: 10, nombre: "Zonas verdes", padre: null };
    const hoja = {
      id: 12,
      nombre: "Cesped",
      padre: { id: 11, nombre: "Jardines", padre: raiz },
    };
    const result = resolverConfiguracionZona(
      hoja,
      new Map([
        [
          10,
          { elementoZonaId: 10, orden: 5, colorHex: "#ABCDEF" },
        ],
      ]),
    );

    expect(result).toEqual({
      elementoId: 10,
      nombre: "Zonas verdes",
      orden: 5,
      colorHex: "#ABCDEF",
      configurado: true,
    });
  });
});
