import { repartirConsumoDiario } from "../../scripts/compensar-cierre-preventivas";

describe("reparto de consumo estimado de Compensar", () => {
  it("distribuye el total diario entre tareas compatibles sin multiplicarlo por ubicación", () => {
    const cantidades = repartirConsumoDiario(450, [
      { id: 1, cantidadOperarios: 1 },
      { id: 2, cantidadOperarios: 2 },
      { id: 3, cantidadOperarios: 1 },
    ]);

    expect([...cantidades.values()].reduce((total, value) => total + value, 0)).toBeCloseTo(450);
    expect(cantidades.get(1)).not.toBe(cantidades.get(3));
    expect(cantidades.get(2)!).toBeGreaterThan(cantidades.get(1)!);
  });

  it("no propone consumo si no hay tareas compatibles o la fila está en cero", () => {
    expect(repartirConsumoDiario(450, [])).toEqual(new Map());
    expect(repartirConsumoDiario(0, [{ id: 1, cantidadOperarios: 1 }])).toEqual(new Map());
  });

  it("conserva el total del Excel con redondeo a cuatro decimales", () => {
    const tareas = Array.from({ length: 19 }, (_, index) => ({
      id: index + 1,
      cantidadOperarios: index === 0 ? 2 : 1,
    }));
    const cantidades = repartirConsumoDiario(450, tareas);
    const repeticion = repartirConsumoDiario(450, tareas);

    expect([...cantidades.values()].reduce((total, value) => total + value, 0)).toBe(450);
    expect([...cantidades.values()].every((value) => value > 0)).toBe(true);
    expect(cantidades).toEqual(repeticion);
  });
});
