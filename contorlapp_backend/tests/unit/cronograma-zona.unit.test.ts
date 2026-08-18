import {
  normalizarNombreZona,
  politicaZonaPredeterminada,
  resolverConfiguracionZona,
} from "../../src/utils/cronogramaZona";
import { DefinicionTareaPreventivaService } from "../../src/services/DefinicionTareaPreventivaService";

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

  test("ordena por zona y ubica primero los equipos mas dificiles", () => {
    const service = new DefinicionTareaPreventivaService({} as any) as any;
    const humeda = { id: 10, nombre: "Zonas humedas", padre: null };
    const verde = { id: 20, nombre: "Zonas verdes", padre: null };
    const task = (
      id: number,
      descripcion: string,
      elemento: any,
      duracionMinutos: number,
      operarios: string[],
    ) => ({
      id,
      descripcion,
      elemento,
      elementoId: elemento.id,
      ubicacionId: 1,
      duracionMinutos,
      operarios: operarios.map((operatorId) => ({ id: operatorId })),
      fechaInicio: new Date(2026, 8, 1, 7, id),
    });

    const ordered = service.ordenarTareasDiversasPorZona(
      [
        task(1, "Lavado", humeda, 20, ["op-1"]),
        task(4, "Corte", verde, 30, ["op-1"]),
        task(2, "Desinfeccion", humeda, 60, ["op-1", "op-2"]),
        task(3, "Lavado", humeda, 20, ["op-1"]),
      ],
      new Map(),
    );

    expect(ordered.map((item: any) => item.id)).toEqual([2, 1, 3, 4]);
  });

  test("una tarea P1 siempre va antes que P2/P3 aunque su zona vaya despues", () => {
    const service = new DefinicionTareaPreventivaService({} as any) as any;
    const humeda = { id: 10, nombre: "Zonas humedas", padre: null };
    const transito = { id: 30, nombre: "Zonas de transito", padre: null };
    const task = (
      id: number,
      elemento: any,
      prioridad: number,
    ) => ({
      id,
      descripcion: `Tarea ${id}`,
      elemento,
      elementoId: elemento.id,
      ubicacionId: 1,
      duracionMinutos: 20,
      prioridad,
      operarios: [{ id: "op-1" }],
      fechaInicio: new Date(2026, 8, 1, 7, id),
    });

    const ordered = service.ordenarTareasDiversasPorZona(
      [
        // P2 en zona humeda (orden 10): antes de la corrección, ganaba por
        // zona a pesar de haber una P1 esperando en zona de transito.
        task(1, humeda, 2),
        task(2, transito, 1),
        task(3, humeda, 3),
      ],
      new Map(),
    );

    expect(ordered.map((item: any) => item.id)).toEqual([2, 1, 3]);
  });
});
