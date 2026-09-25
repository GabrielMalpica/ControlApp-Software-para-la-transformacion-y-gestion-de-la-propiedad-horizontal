// src/utils/ubicacionMaps.ts
//
// Ubicación del conjunto para validar el QR de asistencia: extrae
// latitud/longitud de un enlace de Google Maps (o de "lat,lng" a secas) y
// calcula la distancia entre dos puntos.

export type Coordenadas = { latitud: number; longitud: number };

function httpError(status: number, message: string) {
  const err = new Error(message) as Error & { status: number };
  err.status = status;
  return err;
}

function coordenadasValidas(lat: number, lng: number): boolean {
  return (
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    Math.abs(lat) <= 90 &&
    Math.abs(lng) <= 180 &&
    !(lat === 0 && lng === 0)
  );
}

const NUM = "(-?\\d{1,3}(?:\\.\\d+)?)";

/**
 * Busca coordenadas dentro de un texto (URL de Google Maps ya expandida o
 * "lat,lng"). Prioriza el punto marcado (`!3d..!4d..`) sobre el centro del
 * mapa (`@lat,lng`), porque en un enlace de "lugar" el `@` es solo el centro
 * de la vista.
 */
export function extraerCoordenadasDeTexto(texto: string): Coordenadas | null {
  let decodificado = texto;
  try {
    decodificado = decodeURIComponent(texto);
  } catch {
    // se usa el texto tal cual
  }

  const patrones: RegExp[] = [
    new RegExp(`!3d${NUM}!4d${NUM}`),
    new RegExp(`[?&](?:q|query|ll|destination|center)=${NUM}\\s*,\\s*${NUM}`),
    new RegExp(`@${NUM},${NUM}`),
    new RegExp(`^\\s*${NUM}\\s*,\\s*${NUM}\\s*$`),
  ];

  for (const patron of patrones) {
    const m = patron.exec(decodificado);
    if (!m) continue;
    const latitud = Number(m[1]);
    const longitud = Number(m[2]);
    if (coordenadasValidas(latitud, longitud)) return { latitud, longitud };
  }
  return null;
}

const HOSTS_GOOGLE = new Set([
  "maps.app.goo.gl",
  "goo.gl",
  "g.co",
  "maps.google.com",
  "google.com",
  "www.google.com",
  "www.google.com.co",
  "google.com.co",
  "maps.google.com.co",
]);

function esHostGoogle(url: URL): boolean {
  return url.protocol === "https:" && HOSTS_GOOGLE.has(url.hostname.toLowerCase());
}

/** Sigue las redirecciones de un enlace corto de Google (solo hosts de Google). */
async function expandirEnlace(inicial: URL): Promise<string> {
  let actual = inicial;
  for (let salto = 0; salto < 6; salto++) {
    if (!esHostGoogle(actual)) {
      throw httpError(400, "El enlace debe ser de Google Maps.");
    }
    if (extraerCoordenadasDeTexto(actual.toString())) return actual.toString();

    const resp = await fetch(actual, {
      method: "GET",
      redirect: "manual",
      headers: { "User-Agent": "Mozilla/5.0 (compatible; ControlApp/1.0)" },
      signal: AbortSignal.timeout(8000),
    });
    const location = resp.headers.get("location");
    if (resp.status >= 300 && resp.status < 400 && location) {
      actual = new URL(location, actual);
      continue;
    }
    return actual.toString();
  }
  return actual.toString();
}

/**
 * Resuelve el enlace de Google Maps (largo o corto tipo maps.app.goo.gl) o un
 * "lat,lng" a coordenadas. Lanza un error 400 con mensaje claro si no se pudo.
 */
export async function resolverCoordenadasDesdeMaps(entrada: string): Promise<Coordenadas> {
  const texto = entrada.trim();
  if (!texto) throw httpError(400, "Pega el enlace de Google Maps del conjunto.");

  const directas = extraerCoordenadasDeTexto(texto);
  if (directas) return directas;

  let url: URL;
  try {
    url = new URL(texto);
  } catch {
    throw httpError(
      400,
      "No se reconoció la ubicación. Pega el enlace de Google Maps del conjunto (o las coordenadas 'lat,lng').",
    );
  }

  let finalUrl: string;
  try {
    finalUrl = await expandirEnlace(url);
  } catch (err: any) {
    if (err?.status) throw err;
    throw httpError(
      400,
      "No se pudo abrir el enlace de Google Maps. Revisa que sea correcto o pega el enlace largo del lugar.",
    );
  }

  const coords = extraerCoordenadasDeTexto(finalUrl);
  if (!coords) {
    throw httpError(
      400,
      "El enlace no trae una ubicación exacta. En Google Maps abre el lugar, toca Compartir y copia el enlace.",
    );
  }
  return coords;
}

/** Distancia en metros entre dos puntos (fórmula de haversine). */
export function distanciaMetros(a: Coordenadas, b: Coordenadas): number {
  const R = 6371000;
  const rad = (g: number) => (g * Math.PI) / 180;
  const dLat = rad(b.latitud - a.latitud);
  const dLng = rad(b.longitud - a.longitud);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.latitud)) * Math.cos(rad(b.latitud)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.min(1, Math.sqrt(h))));
}

export type UbicacionConjunto = {
  nombre: string;
  latitud: unknown; // Decimal | number | string | null
  longitud: unknown;
  radioAsistenciaMetros: number;
};

function aNumero(valor: unknown): number | null {
  if (valor == null) return null;
  const n = Number((valor as any)?.toString?.() ?? valor);
  return Number.isFinite(n) ? n : null;
}

/**
 * Valida que el dispositivo esté en el conjunto. Si el conjunto no tiene
 * ubicación configurada no se exige nada (`verificada: false`). Si la tiene y
 * el dispositivo no manda ubicación, o está lejos, lanza un error para que no
 * se registre la asistencia. La precisión reportada por el GPS amplía un poco
 * el radio (máx. 100 m) para no rechazar a quien sí está en el sitio.
 */
export function validarUbicacionEnConjunto(params: {
  conjunto: UbicacionConjunto;
  latitud?: number | null;
  longitud?: number | null;
  precisionMetros?: number | null;
}): { verificada: boolean; distanciaMetros: number | null } {
  const lat = aNumero(params.conjunto.latitud);
  const lng = aNumero(params.conjunto.longitud);
  if (lat == null || lng == null) return { verificada: false, distanciaMetros: null };

  if (params.latitud == null || params.longitud == null) {
    throw httpError(
      400,
      "Necesitamos tu ubicación para registrar la asistencia. Activa el GPS, da permiso de ubicación a la app e inténtalo de nuevo.",
    );
  }

  const distancia = distanciaMetros(
    { latitud: lat, longitud: lng },
    { latitud: params.latitud, longitud: params.longitud },
  );
  const holgura = Math.min(Math.max(params.precisionMetros ?? 0, 0), 100);
  const permitido = params.conjunto.radioAsistenciaMetros + holgura;
  if (distancia > permitido) {
    throw httpError(
      403,
      `Estás a ${distancia} m de ${params.conjunto.nombre}. Debes estar en el conjunto (máximo ${params.conjunto.radioAsistenciaMetros} m) para registrar la asistencia.`,
    );
  }
  return { verificada: true, distanciaMetros: distancia };
}
