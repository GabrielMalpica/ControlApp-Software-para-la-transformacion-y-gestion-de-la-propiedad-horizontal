import {
  motivoRescatablePorCapacidad,
  ordenarCandidatasPorCarga,
  ordenarExcluidasParaRescate,
  plazasCandidatas,
  type PlazaRecurso,
} from "../../src/utils/capacidadCandidatos";

const PODA = 2;
const JARDINERIA = 3;
const MANTENIMIENTO = 5;
const SALVAMENTO = 6;

function plaza(
  id: number,
  categorias: number[],
  extra: Partial<PlazaRecurso> = {},
): PlazaRecurso {
  return {
    id,
    orden: id,
    operarioId: `op-${id}`,
    plazaActiva: true,
    perfilActivo: true,
    categoriasPermitidas: new Set(categorias),
    ...extra,
  };
}

describe("plazasCandidatas", () => {
  const todero = plaza(1, [1, PODA, JARDINERIA, 4, MANTENIMIENTO]);
  const toderoSalvavidas = plaza(2, [PODA, JARDINERIA, MANTENIMIENTO, SALVAMENTO]);

  it("excluye al dueño e incluye al perfil con la categoría habilitada", () => {
    const r = plazasCandidatas({
      categoriaId: PODA,
      plazasDuenasIds: [1],
      plazas: [todero, toderoSalvavidas],
    });
    expect(r.map((p) => p.id)).toEqual([2]);
  });

  it("nunca incluye un perfil sin permiso para la categoría (Todero no hace salvamento)", () => {
    const r = plazasCandidatas({
      categoriaId: SALVAMENTO,
      plazasDuenasIds: [2],
      plazas: [todero, toderoSalvavidas],
    });
    expect(r).toEqual([]);
  });

  it("un perfil sin capacidades configuradas nunca es candidato (no se infiere por nombre)", () => {
    const sinConfigurar = plaza(3, []);
    const r = plazasCandidatas({
      categoriaId: PODA,
      plazasDuenasIds: [1],
      plazas: [sinConfigurar],
    });
    expect(r).toEqual([]);
  });

  it("descarta plazas vacantes, plazas inactivas y perfiles inactivos", () => {
    const r = plazasCandidatas({
      categoriaId: PODA,
      plazasDuenasIds: [],
      plazas: [
        plaza(1, [PODA], { operarioId: null }),
        plaza(2, [PODA], { plazaActiva: false }),
        plaza(3, [PODA], { perfilActivo: false }),
        plaza(4, [PODA]),
      ],
    });
    expect(r.map((p) => p.id)).toEqual([4]);
  });

  it("una categoría nueva se habilita solo cuando se agrega al perfil", () => {
    const nueva = 99;
    const sin = plaza(5, [PODA]);
    const con = plaza(5, [PODA, nueva]);
    expect(
      plazasCandidatas({ categoriaId: nueva, plazasDuenasIds: [], plazas: [sin] }),
    ).toEqual([]);
    expect(
      plazasCandidatas({ categoriaId: nueva, plazasDuenasIds: [], plazas: [con] }).map(
        (p) => p.id,
      ),
    ).toEqual([5]);
  });

  it("el dueño con varias plazas (cuadrilla) las excluye a todas", () => {
    const r = plazasCandidatas({
      categoriaId: PODA,
      plazasDuenasIds: [1, 2],
      plazas: [todero, toderoSalvavidas, plaza(7, [PODA])],
    });
    expect(r.map((p) => p.id)).toEqual([7]);
  });
});

describe("ordenarCandidatasPorCarga", () => {
  it("dos perfiles compatibles: menos carga primero, luego orden y id", () => {
    const a = plaza(1, [PODA], { orden: 2 });
    const b = plaza(2, [PODA], { orden: 1 });
    const c = plaza(3, [PODA], { orden: 1 });
    const carga: Record<number, number> = { 1: 0, 2: 120, 3: 120 };
    expect(
      ordenarCandidatasPorCarga([c, b, a], (id) => carga[id]).map((p) => p.id),
    ).toEqual([1, 2, 3]);
  });
});

describe("ordenarExcluidasParaRescate / motivos", () => {
  const base = {
    id: 1,
    defId: 1,
    prioridad: 2,
    categoriaOrden: 2 as number | null,
    ordenEnCategoria: null as number | null,
    fechaObjetivoMs: 0,
  };

  it("prioridad de selección primero, luego categoría, luego orden interno", () => {
    const lista = [
      { ...base, id: 1, prioridad: 3, categoriaOrden: 1 },
      { ...base, id: 2, prioridad: 1, categoriaOrden: 5 },
      { ...base, id: 3, prioridad: 1, categoriaOrden: 2, ordenEnCategoria: 2 },
      { ...base, id: 4, prioridad: 1, categoriaOrden: 2, ordenEnCategoria: 1 },
    ];
    expect(ordenarExcluidasParaRescate(lista).map((x) => x.id)).toEqual([4, 3, 2, 1]);
  });

  it("es determinista ante empates totales (fecha, definición, id)", () => {
    const lista = [
      { ...base, id: 9, defId: 5, fechaObjetivoMs: 10 },
      { ...base, id: 8, defId: 5, fechaObjetivoMs: 10 },
      { ...base, id: 7, defId: 2, fechaObjetivoMs: 10 },
      { ...base, id: 6, defId: 9, fechaObjetivoMs: 1 },
    ];
    const esperado = [6, 7, 8, 9];
    expect(ordenarExcluidasParaRescate(lista).map((x) => x.id)).toEqual(esperado);
    expect(ordenarExcluidasParaRescate([...lista].reverse()).map((x) => x.id)).toEqual(
      esperado,
    );
  });

  it("solo los motivos por falta de cupo son rescatables", () => {
    for (const m of [
      "SIN_HUECO",
      "SIN_CANDIDATAS",
      "SIN_CAPACIDAD_P1",
      "NECESIDAD_SIN_OPERARIO",
      "REEMPLAZO_PRIORIDAD",
    ]) {
      expect(motivoRescatablePorCapacidad(m)).toBe(true);
    }
    for (const m of [
      "FESTIVO_OMITIDO",
      "DESCANSO_COMPENSATORIO",
      "MANUAL_ELIMINADA",
    ]) {
      expect(motivoRescatablePorCapacidad(m)).toBe(false);
    }
  });
});
