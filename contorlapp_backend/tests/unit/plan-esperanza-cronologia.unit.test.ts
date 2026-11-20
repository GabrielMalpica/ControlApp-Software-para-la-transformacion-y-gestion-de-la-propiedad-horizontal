import {
  construirRangosContrato,
  contarMesesContrato,
  programarFasesPlanEsperanza,
} from "../../src/utils/planEsperanzaCronologia";

const fecha = (valor: string) => new Date(`${valor}T00:00:00.000Z`);

describe("cronología contractual del Plan Esperanza", () => {
  test("programa hitos trimestrales y el cierre en un contrato anual", () => {
    const fases = programarFasesPlanEsperanza(fecha("2026-09-01"), fecha("2027-08-31"));

    expect(fases.map((fase) => fase.mesObjetivo)).toEqual([1, 3, 6, 9, 11, 12]);
    expect(fases.map((fase) => fase.fechaProgramada.toISOString().slice(0, 7))).toEqual([
      "2026-09", "2026-11", "2027-02", "2027-05", "2027-07", "2027-08",
    ]);
  });

  test("usa la duración contractual real cuando el contrato dura once meses", () => {
    const inicio = fecha("2026-02-16");
    const fin = fecha("2026-12-15");

    expect(contarMesesContrato(inicio, fin)).toBe(11);
    expect(programarFasesPlanEsperanza(inicio, fin).map((fase) => fase.mesObjetivo)).toEqual([
      1, 3, 6, 9, 10, 11,
    ]);
  });

  test("mantiene el orden cuando seis fases deben caber en un contrato corto", () => {
    const fases = programarFasesPlanEsperanza(fecha("2026-01-01"), fecha("2026-05-31"));
    const meses = fases.map((fase) => fase.mesObjetivo);

    expect(meses).toEqual([1, 3, 5, 5, 5, 5]);
    expect(meses).toEqual([...meses].sort((a, b) => a - b));
  });

  test("crea rangos anuales hasta el ciclo actual y limita el último al fin del contrato", () => {
    const rangos = construirRangosContrato(
      fecha("2024-02-16"),
      fecha("2026-12-15"),
      fecha("2026-11-20"),
    );

    expect(rangos.map((rango) => rango.inicio.toISOString().slice(0, 10))).toEqual([
      "2024-02-16", "2025-02-16", "2026-02-16",
    ]);
    expect(rangos[rangos.length - 1]?.fin.toISOString().slice(0, 10)).toBe("2026-12-15");
  });
});
