// Dirección (calle, barrio, ciudad) del punto donde se tomó una foto de
// evidencia, para su marca de agua. Usa geocodificación inversa de
// OpenStreetMap (Nominatim): gratis y sin API key, a cambio de respetar su
// política de uso (máx. 1 consulta por segundo, User-Agent que identifique la
// app). Por eso todo pasa por la caché compartida y por una fila con turnos.
//
// Nunca bloquea un cierre: si el servicio tarda o falla, quien llama recibe
// null y la marca usa la dirección registrada del conjunto.
import { z } from "zod";
import { cached } from "../services/RedisService";

export type DireccionGps = {
  calle: string | null;
  barrio: string | null;
  ciudad: string | null;
};

const NOMINATIM_URL = (process.env.NOMINATIM_URL || "https://nominatim.openstreetmap.org").replace(/\/+$/, "");
const USER_AGENT = "ControlApp/1.0 (evidencias de tareas)";

/** Las calles no cambian: se guarda un mes. */
const TTL_CACHE_SEGUNDOS = 30 * 24 * 60 * 60;
const TIMEOUT_CONSULTA_MS = 4000;
const SEPARACION_CONSULTAS_MS = 1100;
/** Si hay más consultas esperando turno se descarta la nueva en vez de encolarla. */
const MAX_EN_COLA = 15;

const NominatimSchema = z.object({
  address: z.record(z.string(), z.unknown()).optional(),
});

function texto(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const limpio = valor.replace(/\s+/g, " ").trim();
  return limpio.length ? limpio.slice(0, 80) : null;
}

/** Convierte la respuesta de Nominatim (`format=jsonv2`) en calle, barrio y ciudad. */
export function parsearDireccionNominatim(json: unknown): DireccionGps {
  const parsed = NominatimSchema.safeParse(json);
  const a = parsed.success ? (parsed.data.address ?? {}) : {};

  const via = texto(a.road) ?? texto(a.pedestrian) ?? texto(a.footway);
  const placa = texto(a.house_number);
  const calle = via && placa ? `${via} # ${placa}` : via;

  const barrio =
    texto(a.neighbourhood) ?? texto(a.suburb) ?? texto(a.residential) ?? texto(a.quarter);

  // En Colombia OSM suele traer la ciudad como "Perímetro Urbano Villavicencio".
  const ciudadCruda =
    texto(a.city) ?? texto(a.town) ?? texto(a.village) ?? texto(a.municipality) ?? texto(a.county);
  const ciudad = ciudadCruda?.replace(/^per[ií]metro urbano\s+/i, "").trim() || null;

  return { calle, barrio, ciudad };
}

let siguienteTurno = 0;
let enCola = 0;

async function esperarTurno(): Promise<void> {
  if (enCola >= MAX_EN_COLA) throw new Error("Demasiadas consultas de dirección en espera.");
  enCola++;
  try {
    const ahora = Date.now();
    const turno = Math.max(ahora, siguienteTurno);
    siguienteTurno = turno + SEPARACION_CONSULTAS_MS;
    if (turno > ahora) await new Promise((r) => setTimeout(r, turno - ahora));
  } finally {
    enCola--;
  }
}

async function consultarNominatim(latitud: number, longitud: number): Promise<DireccionGps> {
  await esperarTurno();
  const params = new URLSearchParams({
    lat: latitud.toFixed(6),
    lon: longitud.toFixed(6),
    format: "jsonv2",
    zoom: "18",
    addressdetails: "1",
    "accept-language": "es",
  });
  if (process.env.NOMINATIM_EMAIL) params.set("email", process.env.NOMINATIM_EMAIL);

  const res = await fetch(`${NOMINATIM_URL}/reverse?${params}`, {
    headers: { "User-Agent": USER_AGENT, Accept: "application/json" },
    signal: AbortSignal.timeout(TIMEOUT_CONSULTA_MS),
  });
  if (!res.ok) throw new Error(`Nominatim respondió ${res.status}`);
  return parsearDireccionNominatim(await res.json());
}

/** ~11 m: fotos del mismo sitio comparten consulta y caché. */
function claveCache(latitud: number, longitud: number) {
  return `geo:direccion:v1:${latitud.toFixed(4)},${longitud.toFixed(4)}`;
}

/**
 * Dirección del punto, desde caché o consultando OpenStreetMap. Las consultas
 * simultáneas del mismo punto se reúnen en una sola. Null si no se pudo.
 */
export async function buscarDireccionGps(
  latitud: number,
  longitud: number,
): Promise<DireccionGps | null> {
  if (!Number.isFinite(latitud) || !Number.isFinite(longitud)) return null;
  try {
    return await cached(claveCache(latitud, longitud), TTL_CACHE_SEGUNDOS, () =>
      consultarNominatim(latitud, longitud),
    );
  } catch {
    return null;
  }
}

/**
 * Igual que `buscarDireccionGps`, pero sin esperar más de `esperaMaximaMs`:
 * si la respuesta no llega a tiempo devuelve null y la consulta sigue en
 * segundo plano llenando la caché para la próxima foto.
 */
export function direccionGpsSinDemora(
  latitud: number,
  longitud: number,
  esperaMaximaMs: number,
): Promise<DireccionGps | null> {
  let temporizador: NodeJS.Timeout | undefined;
  const limite = new Promise<null>((resolve) => {
    temporizador = setTimeout(() => resolve(null), esperaMaximaMs);
  });
  return Promise.race([buscarDireccionGps(latitud, longitud), limite]).finally(() =>
    clearTimeout(temporizador),
  );
}
