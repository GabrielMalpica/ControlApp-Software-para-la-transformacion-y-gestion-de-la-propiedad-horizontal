import {
  compararOrdenProgramacion,
  ordenarPorProgramacion,
  type DatosOrdenProgramacion,
} from "../../src/utils/ordenProgramacion";

function t(
  id: number,
  extra: Partial<DatosOrdenProgramacion> = {},
): DatosOrdenProgramacion {
  return {
    categoriaOrden: null,
    categoriaId: null,
    ordenEnCategoria: null,
    prioridad: 2,
    definicionId: id,
    fechaInicioMs: id,
    id,
    ...extra,
  };
}

const PISCINAS = { categoriaOrden: 1, categoriaId: 10 };
const PODA = { categoriaOrden: 2, categoriaId: 11 };
const JARDIN = { categoriaOrden: 3, categoriaId: 12 };
const ASEO = { categoriaOrden: 4, categoriaId: 13 };
const BASICO = { categoriaOrden: 5, categoriaId: 14 };

const ids = (lista: DatosOrdenProgramacion[]) =>
  ordenarPorProgramacion(lista, (x) => x).map((x) => x.id);

function permutaciones<T>(base: T[], n: number): T[][] {
  // Barajado determinista (LCG) para no depender de Math.random.
  let seed = 12345;
  const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
  return Array.from({ length: n }, () => {
    const copia = [...base];
    for (let i = copia.length - 1; i > 0; i--) {
      const j = Math.floor(rnd() * (i + 1));
      [copia[i], copia[j]] = [copia[j], copia[i]];
    }
    return copia;
  });
}

describe("compararOrdenProgramacion", () => {
  it("ordena por categoría y luego por orden interno (piscinas: shock, aspirado, vidrio, mobiliario)", () => {
    const lista = [
      t(4, { ...PISCINAS, ordenEnCategoria: 4 }),
      t(2, { ...PISCINAS, ordenEnCategoria: 2 }),
      t(1, { ...PISCINAS, ordenEnCategoria: 1 }),
      t(3, { ...PISCINAS, ordenEnCategoria: 3 }),
    ];
    expect(ids(lista)).toEqual([1, 2, 3, 4]);
  });

  it("la categoría manda sobre el orden interno y sobre la prioridad de selección", () => {
    const lista = [
      t(1, { ...BASICO, ordenEnCategoria: 1, prioridad: 1 }),
      t(2, { ...ASEO, ordenEnCategoria: 9, prioridad: 3 }),
      t(3, { ...JARDIN, prioridad: 3 }),
      t(4, { ...PODA, prioridad: 3 }),
      t(5, { ...PISCINAS, ordenEnCategoria: 7, prioridad: 3 }),
    ];
    expect(ids(lista)).toEqual([5, 4, 3, 2, 1]);
  });

  it("la prioridad de selección solo desempata dentro del mismo orden interno", () => {
    const lista = [
      t(1, { ...PODA, ordenEnCategoria: 1, prioridad: 3 }),
      t(2, { ...PODA, ordenEnCategoria: 1, prioridad: 1 }),
      t(3, { ...PODA, ordenEnCategoria: 1, prioridad: 2 }),
    ];
    expect(ids(lista)).toEqual([2, 3, 1]);
  });

  it("Poda A (orden 1) va antes que Poda B (orden 2) aunque B tenga id menor", () => {
    const lista = [
      t(1, { ...PODA, ordenEnCategoria: 2 }),
      t(9, { ...PODA, ordenEnCategoria: 1 }),
    ];
    expect(ids(lista)).toEqual([9, 1]);
  });

  it("dentro de una categoría, sin orden interno va después de las que lo tienen", () => {
    const lista = [
      t(1, { ...PODA, ordenEnCategoria: null }),
      t(2, { ...PODA, ordenEnCategoria: 5 }),
    ];
    expect(ids(lista)).toEqual([2, 1]);
  });

  it("las tareas sin categoría van al final y su orden interno se ignora", () => {
    const lista = [
      t(1, { categoriaOrden: null, ordenEnCategoria: 1, prioridad: 3 }),
      t(2, { categoriaOrden: null, ordenEnCategoria: 99, prioridad: 1 }),
      t(3, { ...BASICO }),
    ];
    // Sin categoría: prioridad -> definición; las categorizadas primero.
    expect(ids(lista)).toEqual([3, 2, 1]);
  });

  it("categorías con el mismo orden se desempatan por id de categoría (estable)", () => {
    const lista = [
      t(1, { categoriaOrden: 2, categoriaId: 30 }),
      t(2, { categoriaOrden: 2, categoriaId: 20 }),
    ];
    expect(ids(lista)).toEqual([2, 1]);
  });

  it("empate total de prioridad interna: definición, luego horario previo, luego id", () => {
    const base = { ...PODA, ordenEnCategoria: 1, prioridad: 2 };
    const lista = [
      t(5, { ...base, definicionId: 7, fechaInicioMs: 50 }),
      t(6, { ...base, definicionId: 7, fechaInicioMs: 10 }),
      t(4, { ...base, definicionId: 3, fechaInicioMs: 99 }),
      t(3, { ...base, definicionId: 7, fechaInicioMs: 10 }),
    ];
    expect(ids(lista)).toEqual([4, 3, 6, 5]);
  });

  it("cambiar el orden de una categoría reordena el día sin tocar las tareas", () => {
    const lista = [
      t(1, { ...PODA }),
      t(2, { ...PISCINAS }),
    ];
    expect(ids(lista)).toEqual([2, 1]);
    // El administrador mueve Poda antes de Piscinas.
    const reordenada = [
      t(1, { categoriaOrden: 1, categoriaId: PODA.categoriaId }),
      t(2, { categoriaOrden: 2, categoriaId: PISCINAS.categoriaId }),
    ];
    expect(ids(reordenada)).toEqual([1, 2]);
  });

  it("es determinista: 50 permutaciones de entrada dan el mismo resultado", () => {
    const base = [
      t(1, { ...PODA, ordenEnCategoria: 2 }),
      t(2, { ...PODA, ordenEnCategoria: 1 }),
      t(3, { ...PISCINAS, ordenEnCategoria: 1 }),
      t(4, { ...JARDIN }),
      t(5, { ...JARDIN }),
      t(6),
      t(7, { prioridad: 1 }),
      t(8, { ...ASEO, ordenEnCategoria: 1, prioridad: 3 }),
      t(9, { ...ASEO, ordenEnCategoria: 1, prioridad: 1 }),
    ];
    const esperado = ids(base);
    expect(esperado).toEqual([3, 2, 1, 4, 5, 9, 8, 7, 6]);
    for (const p of permutaciones(base, 50)) {
      expect(ids(p)).toEqual(esperado);
    }
  });

  it("es un orden total y antisimétrico", () => {
    const a = t(1, { ...PODA, ordenEnCategoria: 1 });
    const b = t(2, { ...PODA, ordenEnCategoria: 1 });
    expect(Math.sign(compararOrdenProgramacion(a, b))).toBe(
      -Math.sign(compararOrdenProgramacion(b, a)),
    );
    expect(compararOrdenProgramacion(a, a)).toBe(0);
  });
});
