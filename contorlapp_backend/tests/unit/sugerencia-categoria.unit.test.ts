import { CATEGORIAS_POR_DEFECTO } from "../../src/services/CatalogoOperativoService";
import { sugerirCategoriaPorTexto } from "../../src/utils/sugerenciaCategoria";

const categorias = CATEGORIAS_POR_DEFECTO.map((c, i) => ({
  id: i + 1,
  nombre: c.nombre,
  ordenProgramacion: i + 1,
  palabrasClave: c.palabrasClave,
}));

const nombre = (texto: string, contexto = "") =>
  sugerirCategoriaPorTexto(texto, categorias, contexto)?.categoriaNombre ?? null;

describe("sugerirCategoriaPorTexto (descripciones reales)", () => {
  it.each([
    ["Limpieza de vidrios de encerramiento de la piscina", "Mantenimiento de piscinas"],
    ["Choque quimico de la piscina", "Mantenimiento de piscinas"],
    ["Aspirado de piscina (Martes por desagüe y resto de días por filtración)", "Mantenimiento de piscinas"],
    ["Lavado de mobiliario de piscina", "Mantenimiento de piscinas"],
    ["Mantenimiento general de piscina", "Mantenimiento de piscinas"],
    ["Poda Cesped", "Poda"],
    ["Poda de arboles del parque", "Poda"],
    ["Deshoje de palmas del parque", "Poda"],
    ["Aplicación fertilizantes a raíz triple 18", "Jardinería"],
    ["Aplicación herbicida", "Jardinería"],
    ["Barrido y Trapeado del salon social lunes, miercoles y viernes", "Aseo"],
    ["Limpieza, desinfeccion y lavado del shut de basura", "Aseo"],
    ["Inspeccion y verificacion extintor del bbq", "Mantenimientos básicos"],
    ["Turno salvavidas", "Salvamento acuático"],
  ])("'%s' → %s", (texto, esperada) => {
    expect(nombre(texto)).toBe(esperada);
  });

  // Descripciones tal como están cargadas en Bosques de Morelia (verbo en
  // infinitivo) más el nombre del elemento como contexto.
  it.each([
    ["Aspirar por filtro", "Piscina", "Mantenimiento de piscinas"],
    ["Aspirar por Deshague", "Piscina", "Mantenimiento de piscinas"],
    ["Cepillar paredes y fondo", "Piscina", "Mantenimiento de piscinas"],
    ["Tomar parámetros", "Piscina", "Mantenimiento de piscinas"],
    ["Choke quimico", "Piscina", "Mantenimiento de piscinas"],
    ["Barrer, lavar, cepillar y desinfectar pisos, rejillas y bordes.", "Playa de la piscina", "Aseo"],
    ["Barrer, lavar, retirar tierra, maleza y residuos acumulados.", "Sardineles", "Aseo"],
    ["Lavar y desinfectar sanitarios, lavamanos, espejos, puertas, pisos y canecas.", "Baños", "Aseo"],
    ["Vaciar, lavar, desinfectar y organizar las canecas.", "Canecas", "Aseo"],
    ["Limpiar vidrios,marcos y retirar manchas", "Ventanas", "Aseo"],
  ])("'%s' (%s) → %s", (texto, contexto, esperada) => {
    expect(nombre(texto, contexto)).toBe(esperada);
  });

  it("la descripción pesa más que el contexto", () => {
    // 'barr' (aseo) en la descripción gana a 'piscin' (piscinas) solo en el elemento.
    expect(nombre("Barrer pisos", "Piscina")).toBe("Aseo");
    // Sin pistas en la descripción, el elemento decide.
    expect(nombre("Revisión visual del estado", "Piscina")).not.toBeNull();
  });

  it("devuelve null cuando nada coincide", () => {
    expect(nombre("Reunión con la administración")).toBeNull();
  });

  it("ignora tildes y mayúsculas, y exige inicio de palabra", () => {
    expect(nombre("PODA DE ÁRBOLES")).toBe("Poda");
    expect(nombre("Capodastro")).toBeNull(); // 'poda' no empieza una palabra
  });

  it("ante empate gana la de menor orden de programación (determinista)", () => {
    const cats = [
      { id: 7, nombre: "B", ordenProgramacion: 2, palabrasClave: ["x"] },
      { id: 3, nombre: "A", ordenProgramacion: 1, palabrasClave: ["x"] },
    ];
    expect(sugerirCategoriaPorTexto("tarea x", cats)?.categoriaId).toBe(3);
    expect(sugerirCategoriaPorTexto("tarea x", [...cats].reverse())?.categoriaId).toBe(3);
  });

  it("gana la categoría con más coincidencias", () => {
    const r = sugerirCategoriaPorTexto("Limpieza de vidrios de encerramiento de la piscina", categorias);
    expect(r?.coincidencias.length).toBeGreaterThanOrEqual(2);
  });
});
