import {
  CATEGORIA_ASEO,
  CATEGORIA_BASICOS,
  CATEGORIA_JARDINERIA,
  CATEGORIA_PISCINAS,
  CATEGORIA_SALVAMENTO,
  clasificarCategoriaPreventiva,
} from "../../src/utils/clasificarPreventiva";

// [descripción, elemento, categoría esperada]; descripciones reales de la base.
const CASOS: Array<[string, string, string | null]> = [
  // Piscinas
  ["Aspirar por filtro", "Piscina", CATEGORIA_PISCINAS],
  ["Aspirar por Deshague", "Piscina", CATEGORIA_PISCINAS],
  ["Aspirado de la piscina por filtro", "Cuerpo de agua", CATEGORIA_PISCINAS],
  ["aspirado por filtro jueves", "Cuerpo de agua", CATEGORIA_PISCINAS],
  ["Aspirado por desague", "Piscina Cuerpo de agua", CATEGORIA_PISCINAS],
  ["Shock clorox piscina", "Píscina", CATEGORIA_PISCINAS],
  ["Shoke quimico", "Cuerpo de agua", CATEGORIA_PISCINAS],
  ["Choke quimico y toma de parámetro", "Piscina", CATEGORIA_PISCINAS],
  ["Aplicación de alguicida y clarificante", "piscina 1", CATEGORIA_PISCINAS],
  ["Medición de cloro y pH", "piscina 1", CATEGORIA_PISCINAS],
  ["Control de parametros", "Piscina", CATEGORIA_PISCINAS],
  ["Retrolavado de filtros", "piscina 1", CATEGORIA_PISCINAS],
  ["Refregado de la boquilla", "Piscina", CATEGORIA_PISCINAS],
  ["Cepillar paredes y fondo", "Piscina", CATEGORIA_PISCINAS],
  ["Registro de bitácora de piscina", "piscina 1", CATEGORIA_PISCINAS],
  ["Limpieza de vidrios de encerramiento de la piscina", "Encerramiento", CATEGORIA_PISCINAS],
  ["Lavado de mobiliario de piscina", "Mobiliario (sillas, mesas, s", CATEGORIA_PISCINAS],
  ["Mantenimiento general de piscina", "Piscina cuerpo de agua", CATEGORIA_PISCINAS],
  ["Clorar el piso anden exterior de la piscina", "Piso anden exterior", CATEGORIA_PISCINAS],
  // lo que el equipo ya categorizó a mano: la playa de la piscina va en piscinas aunque se barra
  ["Barrer, lavar, cepillar y desinfectar pisos, rejillas y bordes.", "Playa de la piscina", CATEGORIA_PISCINAS],
  ["Limpiar la superficie", "Piscina", CATEGORIA_PISCINAS],
  ["Lavado de ducha", "Piscina", CATEGORIA_PISCINAS],
  // Jardinería (la poda y la guadaña incluidas)
  ["Podar, nivelar, deshierbar y retirar material vegetal", "Jardines", CATEGORIA_JARDINERIA],
  ["Poda de arboles", "Arboles", CATEGORIA_JARDINERIA],
  ["Poda Cesped", "Cesped", CATEGORIA_JARDINERIA],
  ["Guadañada de bordes", "Prados", CATEGORIA_JARDINERIA],
  ["Deshoje de palmas", "Palmas", CATEGORIA_JARDINERIA],
  ["Realizar deshoje, retirar hojas secas y recoger residuos vegetales.", "Palmas", CATEGORIA_JARDINERIA],
  ["Corte de césped en prados", "Prados", CATEGORIA_JARDINERIA],
  ["Aplicación de fertilizante", "Cesped", CATEGORIA_JARDINERIA],
  ["Aplicación herbicida", "Cesped", CATEGORIA_JARDINERIA],
  ["Control de maleza con bomba de espalda", "Áreas comunes exteriores", CATEGORIA_JARDINERIA],
  ["Control de plagas en jardines", "Jardineras y setos", CATEGORIA_JARDINERIA],
  ["Riego de jardineras", "Jardineras y setos", CATEGORIA_JARDINERIA],
  ["Poda swinglea", "duchas", CATEGORIA_JARDINERIA],
  ["Riego, poda y control de plagas de materas del salon social", "Materas", CATEGORIA_JARDINERIA],
  ["Mantenimiento general, poda y limpieza de jardines de ubicacion l", "Cesped", CATEGORIA_JARDINERIA],
  ["Realizar limpieza, deshierbe, poda y retiro de residuos vegetales.", "Jardín", CATEGORIA_JARDINERIA],
  ["Fumigación de zonas verdes", "Prados", CATEGORIA_JARDINERIA],
  // Mantenimientos básicos
  ["Inspeccion y verificacion extintor del bbq", "Extintor", CATEGORIA_BASICOS],
  ["Inspección de bombas", "duchas y accesorios visibles", CATEGORIA_BASICOS],
  ["Ajuste de tornillos", "Áreas comunes exteriores", CATEGORIA_BASICOS],
  ["Pintura de bordillos", "Bordillos", CATEGORIA_BASICOS],
  ["Demarcación de parqueaderos", "Parqueadero visitantes", CATEGORIA_BASICOS],
  ["Mantenimiento de juegos infantiles", "Juegos infantiles", CATEGORIA_BASICOS],
  ["Revisión mensual de cancha", "Cancha", CATEGORIA_BASICOS],
  ["Limpieza de telarañas", "Luminarias", CATEGORIA_BASICOS],
  ["Limpiar externamente, retirar polvo, suciedad, insectos y telarañas.", "Luminarias", CATEGORIA_BASICOS],
  // Salvamento
  ["Ronda de vigilancia y control de aforo", "piscina 1", CATEGORIA_SALVAMENTO],
  ["Revisión de equipos de emergencia", "piscina 1", CATEGORIA_SALVAMENTO],
  ["Ordenamiento de implementos de salvamento", "piscina 1", CATEGORIA_SALVAMENTO],
  // Aseo
  ["Barrer y trapear pisos; limpiar puertas y paredes; retirar polvo y telarañas", "Pisos,paredes,puertas y tech", CATEGORIA_ASEO],
  ["Barrer, lavar, retirar tierra, maleza y residuos acumulados.", "Sardineles", CATEGORIA_ASEO],
  ["Lavado y desinfección de baños", "Baños", CATEGORIA_ASEO],
  ["Limpiar vidrios, marcos y retirar manchas.", "Ventanas y vidrios", CATEGORIA_ASEO],
  ["Lavado shut jueves", "Canecas", CATEGORIA_ASEO],
  ["Aspirado de tapetes y sillas", "Piso salón", CATEGORIA_ASEO],
  ["Aspirado y desempolvado de escaleras", "Escaleras", CATEGORIA_ASEO],
  ["Clorado de andenes", "Calles", CATEGORIA_ASEO],
  ["Clorada", "Caminos y corredores", CATEGORIA_ASEO],
  ["Aseo general baños de la piscina", "Baños", CATEGORIA_PISCINAS],
  ["Barrido y trapeado de pasillos salón social y alrededores de la piscina", "Pasillos", CATEGORIA_ASEO],
  ["Barrido de zonas verdes", "Zonas verdes", CATEGORIA_ASEO],
  ["Recolección de basuras del parque", "Canecas parque", CATEGORIA_ASEO],
  ["Limpieza profunda del BBQ", "Area de bbq", CATEGORIA_ASEO],
  ["Hidrolavado de cancha", "Cancha de futbol", CATEGORIA_ASEO],
  ["Aseo parque infantil", "Cesped Sintético", CATEGORIA_ASEO],
  ["Barrer, cepillar, retirar residuos y realizar lavado .", "Césped sintético", CATEGORIA_ASEO],
  ["Limpiar, organizar y verificar visualmente el estado de las herramientas.", "Herramientas", CATEGORIA_ASEO],
  ["Limipeza general", "Pisos,paredes,ventanas y pue", CATEGORIA_ASEO], // tipeo real
  // Sin regla: se deja sin categoría para decidirlo a mano
  ["Reunión con la administración", "Oficina", null],
];

describe("clasificarCategoriaPreventiva (descripciones reales)", () => {
  it.each(CASOS)("'%s' (%s) → %s", (descripcion, elemento, esperada) => {
    expect(clasificarCategoriaPreventiva(descripcion, elemento)).toBe(esperada);
  });

  it("ignora tildes y mayúsculas", () => {
    expect(clasificarCategoriaPreventiva("PODA DE ÁRBOLES", "ÁRBOLES")).toBe(CATEGORIA_JARDINERIA);
  });

  it("es determinista", () => {
    for (const [d, e] of CASOS) {
      expect(clasificarCategoriaPreventiva(d, e)).toBe(clasificarCategoriaPreventiva(d, e));
    }
  });
});
