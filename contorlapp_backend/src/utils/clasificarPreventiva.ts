// Clasificación determinista de una preventiva en una categoría, con reglas
// explícitas basadas en cómo están redactadas las preventivas reales y en las
// categorías que ya asignó el equipo a mano. Sin Prisma. Devuelve el NOMBRE de
// la categoría (de las 7 por defecto) o null si ninguna regla aplica.
//
// Criterios (en orden; gana la primera que coincide):
//  1. Salvamento acuático: salvamento, salvavidas, rescate, aforo, vigilancia,
//     equipos de emergencia.
//  2. Jardinería: poda/podar, guadañar, deshierbe, desmaleza, deshoje, corte de
//     césped, fertilizar, herbicida, plagas, riego, setos... (la poda va en
//     Jardinería, como se vino categorizando).
//  3. Mantenimiento de piscinas: todo lo que nombra la piscina / cuerpo de agua
//     (en la descripción o en el elemento) y sus labores propias (aspirado de
//     piscina, shock/choque, cloro y pH, boquilla, retrolavado, filtros...).
//  4. Mantenimientos básicos: luminarias, e inspección, revisión,
//     mantenimiento, ajuste, pintura, demarcación y verificación al inicio.
//  5. Aseo: barrer, trapear, limpiar, lavar, desinfectar, recolectar, etc.
import { normalizarTexto } from "./perfilOperativo";

export const CATEGORIA_SALVAMENTO = "Salvamento acuático";
export const CATEGORIA_JARDINERIA = "Jardinería";
export const CATEGORIA_PISCINAS = "Mantenimiento de piscinas";
export const CATEGORIA_BASICOS = "Mantenimientos básicos";
export const CATEGORIA_ASEO = "Aseo";

const SALVAMENTO = /\b(salvamento|salvavidas|rescate|aforo|vigilancia|emergencia)/;

const JARDINERIA =
  /\b(poda|podar|guada|deshierb|desmalez|control de maleza|deshoj|corte de c|cesped(?! sintetico)|fertiliz|herbicida|plaga|fumigacion|riego|seto|swemglea|swinglea|swingla|ixora|jardin|hojarasca|arbustos|ronda de revision de zonas verdes)/;

// Labores propias de la piscina aunque la descripción no diga "piscina".
const PISCINA_LABOR =
  /(piscin|\bshock|\bshoke|choque|choke|clorox|alguicida|clarificante|boquilla|retrolavado|cloro y ph|parametros|bitacora|calidad del agua|motobomba|vaso y borde|cuerpo de agua|aspirado (por|de) (desagu|filtro|desahuegue)|aspirado por filtro|aspirar por (filtro|deshague|desague)|cepillar paredes y fondo|cepillado de paredes)/;
const PISCINA_ELEMENTO = /(piscina|cuerpo de agua|boquilla)/;
// "alrededores de la piscina" solo ubica la tarea de aseo, no es de la piscina.
const PISCINA_SOLO_UBICACION = /alrededores de la piscina/;

const BASICOS_INICIO =
  /^(ajuste|inspecc|revision|mantenimiento|pintura|demarcacion|verific|ronda de revision)/;
const BASICOS_ELEMENTO = /(luminaria)/;

const ASEO =
  /(aseo|barr|trape|limpi|limip|lav|desinfec|despapel|recoger|recolecc|descaneca|shut|hidrolav|cristaliz|encerado|pulida|brillo|desmanche|vaciar|aspirado|clorad|clorar|retiro de telara|telaranas|refreg|cepill)/;

export function clasificarCategoriaPreventiva(
  descripcion: string,
  elemento = "",
): string | null {
  const d = normalizarTexto(descripcion);
  const e = normalizarTexto(elemento);

  if (SALVAMENTO.test(d) || /rescate/.test(e)) return CATEGORIA_SALVAMENTO;
  if (JARDINERIA.test(d)) return CATEGORIA_JARDINERIA;

  const piscinaPorDescripcion =
    PISCINA_LABOR.test(d) && !PISCINA_SOLO_UBICACION.test(d);
  if (piscinaPorDescripcion || (PISCINA_ELEMENTO.test(e) && !PISCINA_SOLO_UBICACION.test(d))) {
    return CATEGORIA_PISCINAS;
  }

  if (BASICOS_ELEMENTO.test(e) || BASICOS_INICIO.test(d)) return CATEGORIA_BASICOS;
  if (ASEO.test(d)) return CATEGORIA_ASEO;
  return null;
}
