#!/usr/bin/env node
// Deja el APK de Android listo para publicarse junto con la web (ver
// docs/app-android-sin-conexion.md, "Publicar una versión").
//
// La app de Android no está en Play Store: se descarga de la misma web
// (Hostinger) y, al abrirse, lee descargas/android.json para saber si hay una
// versión nueva. Este script, después de `flutter build web` y
// `flutter build apk --release`, pone en build/web/descargas/:
//   - controlapp-<versionName>+<versionCode>.apk  (el que apunta android.json)
//   - controlapp.apk                              (enlace fijo para compartir)
//   - android.json                                (versión, url, sha256…)
//   - .htaccess                                   (que el CDN no guarde viejos
//                                                  android.json ni controlapp.apk)
// Así se sube todo build/web de una vez y la app y la web quedan en la misma
// versión.
//
// Uso, desde controlapp_frontend:
//   node scripts/empaquetar-android.js --base-url https://controlapp.controlsas.com.co
// Opciones:
//   --base-url <url>   Dónde queda publicada la web (por defecto la de producción).
//   --minima <n>       versionCode mínimo que se deja seguir usando (por defecto 1).
//                      Con un número mayor, la app vieja obliga a actualizar.
//   --notas <texto>    Qué cambió, para mostrarlo al ofrecer la actualización.
//   --anterior <url|ruta>  android.json publicado hoy: falla si su versionCode
//                      es igual o mayor que el nuevo (los celulares no se
//                      actualizarían). Si aún no hay uno publicado, sigue.
//   --raiz <carpeta>   Carpeta del proyecto Flutter (por defecto la de este script).
//   --apk <ruta>       APK compilado (por defecto build/app/outputs/flutter-apk/app-release.apk).
//   --web <carpeta>    Build web (por defecto build/web).
//   --solo-revisar     Solo revisa versión, --minima y --anterior, sin APK ni
//                      build (el workflow lo corre antes de compilar).
// En GitHub Actions escribe version_name, version_code y apk en $GITHUB_OUTPUT.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const BASE_URL_POR_DEFECTO = "https://controlapp.controlsas.com.co";
// Android no acepta un versionCode mayor (developer.android.com, "versionCode").
const VERSION_CODE_MAXIMO = 2100000000;

const HTACCESS_DESCARGAS = `# Lo escribe scripts/empaquetar-android.js. android.json y controlapp.apk tienen
# el mismo nombre en cada versión: sin "no-cache" el CDN de Hostinger los
# guardaría 7 días y los celulares no verían la versión nueva. El APK con la
# versión en el nombre nunca cambia, así que puede guardarse.
AddType application/vnd.android.package-archive .apk

<FilesMatch "^(android\\.json|controlapp\\.apk)$">
  <IfModule mod_expires.c>
    ExpiresActive Off
  </IfModule>
  <IfModule mod_headers.c>
    Header set Cache-Control "no-cache"
    Header unset Expires
  </IfModule>
</FilesMatch>
`;

function opcion(nombre) {
  const i = process.argv.indexOf(nombre);
  if (i < 0) return undefined;
  const valor = process.argv[i + 1];
  if (valor === undefined || valor.startsWith("--")) fallar(`Falta el valor de ${nombre}.`);
  return valor;
}

function fallar(mensaje) {
  console.error(`[empaquetar-android] ${mensaje}`);
  process.exit(1);
}

function aviso(mensaje) {
  console.log(`[empaquetar-android] ${mensaje}`);
}

function entero(texto, nombre, { minimo = 1 } = {}) {
  if (!/^\d+$/.test(String(texto).trim())) fallar(`${nombre} debe ser un número entero, llegó "${texto}".`);
  const n = Number(texto);
  if (n < minimo || n > VERSION_CODE_MAXIMO) fallar(`${nombre} debe estar entre ${minimo} y ${VERSION_CODE_MAXIMO}, llegó ${n}.`);
  return n;
}

// `version: 1.2.3+45` de pubspec.yaml → versionName 1.2.3, versionCode 45.
function leerVersion(pubspec) {
  const m = fs.readFileSync(pubspec, "utf8").match(/^version:[ \t]*["']?([^\s"'#+]+)\+(\d+)["']?[ \t]*(?:#.*)?$/m);
  if (!m) {
    fallar(`${pubspec} debe tener "version: X.Y.Z+N" (N es el versionCode de Android, súbelo en cada publicación).`);
  }
  // Va en el nombre del archivo y en la URL.
  if (!/^[0-9A-Za-z][0-9A-Za-z._-]*$/.test(m[1])) fallar(`versionName "${m[1]}" de ${pubspec} solo puede tener letras, números, punto, guion y _.`);
  return { versionName: m[1], versionCode: entero(m[2], "El versionCode de pubspec.yaml") };
}

function baseUrlValida(texto) {
  let url;
  try {
    url = new URL(texto);
  } catch {
    fallar(`--base-url no es una URL: "${texto}".`);
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") fallar(`--base-url debe ser http(s): "${texto}".`);
  if (url.search || url.hash) fallar(`--base-url no lleva ? ni #: "${texto}".`);
  return url.href.replace(/\/+$/, "");
}

// android.json publicado hoy, o null si todavía no hay ninguno.
async function leerAnterior(origen) {
  let texto;
  if (/^https?:\/\//i.test(origen)) {
    let respuesta;
    try {
      respuesta = await fetch(origen, { headers: { "Cache-Control": "no-cache" } });
    } catch (e) {
      fallar(`No se pudo consultar ${origen} (${e.cause?.code ?? e.message}). Revisa la URL o la conexión.`);
    }
    if (respuesta.status === 404) return null;
    if (!respuesta.ok) fallar(`${origen} respondió ${respuesta.status}: no se pudo revisar la versión publicada.`);
    texto = await respuesta.text();
  } else {
    const ruta = path.resolve(origen);
    if (!fs.existsSync(ruta)) return null;
    texto = fs.readFileSync(ruta, "utf8");
  }
  // En Hostinger, una ruta que no existe devuelve index.html (.htaccess de la
  // web): eso también quiere decir que aún no se ha publicado el APK.
  if (/^\s*</.test(texto)) return null;
  let json;
  try {
    json = JSON.parse(texto);
  } catch {
    fallar(`${origen} no es un JSON válido: revisa el android.json publicado.`);
  }
  return entero(json?.versionCode, `versionCode de ${origen}`);
}

function sha256(archivo) {
  return crypto.createHash("sha256").update(fs.readFileSync(archivo)).digest("hex");
}

async function main() {
  const raiz = path.resolve(opcion("--raiz") ?? path.join(__dirname, ".."));
  const apk = path.resolve(raiz, opcion("--apk") ?? "build/app/outputs/flutter-apk/app-release.apk");
  const web = path.resolve(raiz, opcion("--web") ?? "build/web");
  const baseUrl = baseUrlValida(opcion("--base-url") ?? BASE_URL_POR_DEFECTO);
  const notas = opcion("--notas") ?? "";

  const { versionName, versionCode } = leerVersion(path.join(raiz, "pubspec.yaml"));

  const minimaTexto = opcion("--minima");
  const minimaVersionCode = minimaTexto === undefined || minimaTexto.trim() === "" ? 1 : entero(minimaTexto, "--minima");
  if (minimaVersionCode > versionCode) {
    fallar(
      `--minima ${minimaVersionCode} es mayor que el versionCode nuevo (${versionCode}): ni la versión que se publica podría usarse.`,
    );
  }

  const soloRevisar = process.argv.includes("--solo-revisar");
  if (!soloRevisar) {
    if (!fs.existsSync(apk)) fallar(`No existe ${apk}: primero flutter build apk --release.`);
    const inicio = Buffer.alloc(4);
    const fd = fs.openSync(apk, "r");
    fs.readSync(fd, inicio, 0, 4, 0);
    fs.closeSync(fd);
    if (inicio.toString("latin1") !== "PK\x03\x04") fallar(`${apk} no parece un APK (no es un zip).`);
    if (!fs.existsSync(path.join(web, "index.html"))) fallar(`No existe ${path.join(web, "index.html")}: primero flutter build web.`);
  }

  const anterior = opcion("--anterior");
  if (anterior !== undefined) {
    const publicada = await leerAnterior(anterior);
    if (publicada === null) {
      aviso(`No hay android.json publicado en ${anterior}: es la primera versión.`);
    } else if (publicada >= versionCode) {
      fallar(
        `Ya está publicado el versionCode ${publicada} y el nuevo es ${versionCode}: los celulares no se actualizarían. ` +
          `Sube el número después del + en "version:" de pubspec.yaml (por ejemplo ${versionName}+${publicada + 1}).`,
      );
    } else {
      aviso(`Versión publicada hoy: ${publicada}; nueva: ${versionCode}.`);
    }
  }
  if (soloRevisar) {
    aviso(`Versión ${versionName}+${versionCode} lista para compilar (mínima ${minimaVersionCode}).`);
    return;
  }

  const descargas = path.join(web, "descargas");
  fs.mkdirSync(descargas, { recursive: true });
  const nombre = `controlapp-${versionName}+${versionCode}.apk`;
  fs.copyFileSync(apk, path.join(descargas, nombre));
  fs.copyFileSync(apk, path.join(descargas, "controlapp.apk"));

  const info = {
    versionCode,
    versionName,
    url: `${baseUrl}/descargas/${encodeURIComponent(nombre)}`,
    sha256: sha256(apk),
    tamanoBytes: fs.statSync(apk).size,
    publicadaEn: new Date().toISOString(),
    minimaVersionCode,
    notas,
  };
  fs.writeFileSync(path.join(descargas, "android.json"), `${JSON.stringify(info, null, 2)}\n`);
  fs.writeFileSync(path.join(descargas, ".htaccess"), HTACCESS_DESCARGAS);

  aviso(`${path.relative(raiz, path.join(descargas, nombre))} (${info.tamanoBytes} bytes, sha256 ${info.sha256})`);
  aviso(`android.json → ${info.url} (mínima ${minimaVersionCode})`);

  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(
      process.env.GITHUB_OUTPUT,
      `version_name=${versionName}\nversion_code=${versionCode}\napk=${path.join(descargas, nombre)}\n`,
    );
  }
}

main().catch((e) => fallar(e?.stack ?? String(e)));
