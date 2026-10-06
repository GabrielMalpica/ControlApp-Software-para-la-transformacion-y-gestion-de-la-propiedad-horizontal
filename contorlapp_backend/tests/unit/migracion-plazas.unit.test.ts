import { planificarMigracionPlazas } from "../../src/utils/migracionPlazas";

const op = (id: string, funciones: string[]) => ({ id, funciones });
const def = (id: number, ...operariosIds: string[]) => ({ id, descripcion: `Tarea ${id}`, operariosIds });

describe("planificarMigracionPlazas", () => {
  it("crea plaza solo a quien no tiene y vincula las preventivas completas", () => {
    const plan = planificarMigracionPlazas({
      operarios: [op("a", ["TODERO"]), op("b", ["TODERO", "SALVAVIDAS"]), op("c", ["ASEO"])],
      plazas: [{ operarioId: "a" }, { operarioId: null }],
      defs: [def(1, "a"), def(2, "b"), def(3, "a", "c")],
    });
    expect(plan.plazasACrear).toEqual([
      { operarioId: "b", roles: ["TODERO", "SALVAVIDAS"] },
      { operarioId: "c", roles: ["ASEO"] },
    ]);
    expect(plan.defsVincular).toEqual([1, 2, 3]);
    expect(plan.defsSaltadas).toEqual([]);
  });

  it("una cuadrilla se vincula solo si TODOS sus operarios tendrán plaza", () => {
    const plan = planificarMigracionPlazas({
      operarios: [op("a", ["TODERO"]), op("sinRol", [])],
      plazas: [],
      defs: [def(1, "a", "sinRol"), def(2, "a")],
    });
    expect(plan.defsVincular).toEqual([2]);
    expect(plan.defsSaltadas).toHaveLength(1);
    expect(plan.defsSaltadas[0]).toMatchObject({ id: 1 });
    expect(plan.defsSaltadas[0].motivo).toMatch(/no tiene funciones/);
    expect(plan.plazasACrear).toEqual([{ operarioId: "a", roles: ["TODERO"] }]);
  });

  it("un operario de la preventiva que no pertenece al conjunto se reporta", () => {
    const plan = planificarMigracionPlazas({
      operarios: [op("a", ["TODERO"])],
      plazas: [],
      defs: [def(1, "ajeno")],
    });
    expect(plan.defsVincular).toEqual([]);
    expect(plan.defsSaltadas[0].motivo).toMatch(/no pertenece al conjunto/);
  });

  it("es idempotente: con todo ya migrado no hay nada que hacer", () => {
    const plan = planificarMigracionPlazas({
      operarios: [op("a", ["TODERO"])],
      plazas: [{ operarioId: "a" }],
      defs: [],
    });
    expect(plan).toEqual({ plazasACrear: [], defsVincular: [], defsSaltadas: [] });
  });
});
