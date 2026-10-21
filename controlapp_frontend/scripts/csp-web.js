#!/usr/bin/env node
// Pone al día los hashes de la Content-Security-Policy de la web (ver
// docs/actualizacion-web.md, "Content-Security-Policy").
//
// El arranque (web/flutter_bootstrap.js) va incrustado en index.html y la CSP
// solo deja correr ese <script> si su sha256 está en `script-src`. Flutter le
// mete flutter.js y la configuración del build, así que el hash cambia al
// actualizar Flutter o al editar el arranque: si queda viejo, el navegador no
// ejecuta el arranque y la app queda en blanco.
//
// Uso, desde controlapp_frontend, después de cada `flutter build web`:
//   node scripts/csp-web.js --api https://api.controlsas.com.co
//
// Calcula el hash del index.html compilado y lo escribe en build/web/.htaccess
// (lo que se sube) y en web/.htaccess (la fuente, para que quede en git).
// Con --api, además revisa que `connect-src` permita esa API.
// Opciones: --build <carpeta> si se compiló con -o en otra carpeta.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

// Scripts que la app inyecta en línea por su cuenta. printing (Printing.layoutPdf
// en un navegador de escritorio) agrega esta función para imprimir el PDF; si
// la CSP la bloquea, el PDF se abre en una pestaña en vez de imprimirse.
// Si una versión nueva de printing cambia el texto, actualizarlo aquí.
const SCRIPTS_EN_LINEA_DE_PAQUETES = [
  "function __net_nfet_printing___print(){var f=document.getElementById('__net_nfet_printing__');f.focus();f.contentWindow.print();}",
];

const raiz = path.resolve(__dirname, "..");

function opcion(nombre) {
  const i = process.argv.indexOf(nombre);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function hash(texto) {
  return `'sha256-${crypto.createHash("sha256").update(texto, "utf8").digest("base64")}'`;
}

function fallar(mensaje) {
  console.error(`[csp-web] ${mensaje}`);
  process.exit(1);
}

const build = path.resolve(raiz, opcion("--build") ?? "build/web");
const indexHtml = path.join(build, "index.html");
if (!fs.existsSync(indexHtml)) fallar(`No existe ${indexHtml}: primero flutter build web.`);

const enLinea = [...fs.readFileSync(indexHtml, "utf8").matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(
  (m) => m[1],
);
if (enLinea.length === 0) fallar(`${indexHtml} no tiene el arranque en línea.`);
const hashes = [...enLinea, ...SCRIPTS_EN_LINEA_DE_PAQUETES].map(hash);

// Reemplaza los 'sha256-…' de cada `script-src` por los calculados.
function actualizar(archivo) {
  const antes = fs.readFileSync(archivo, "utf8");
  if (!/script-src/.test(antes)) fallar(`${archivo} no tiene una CSP con script-src.`);
  const despues = antes.replace(/script-src([^;"]*)/g, (_, fuentes) => {
    const resto = fuentes.split(/\s+/).filter((f) => f && !/^'sha256-/.test(f));
    const palabras = resto.filter((f) => f.startsWith("'"));
    const hosts = resto.filter((f) => !f.startsWith("'"));
    return `script-src ${[...palabras, ...hashes, ...hosts].join(" ")}`;
  });
  if (despues !== antes) fs.writeFileSync(archivo, despues);
  console.log(`[csp-web] ${path.relative(raiz, archivo)}: ${despues !== antes ? "actualizado" : "sin cambios"}`);
  return despues;
}

const htaccessBuild = path.join(build, ".htaccess");
if (!fs.existsSync(htaccessBuild)) fallar(`No existe ${htaccessBuild}: Flutter lo copia desde web/.htaccess.`);
const politica = actualizar(htaccessBuild);
actualizar(path.join(raiz, "web/.htaccess"));
console.log(`[csp-web] Arranque: ${hashes[0]}`);

const api = opcion("--api");
if (api) {
  const origen = new URL(api).origin;
  const conexiones = [...politica.matchAll(/connect-src([^;"]*)/g)].map((m) => m[1].split(/\s+/));
  if (conexiones.length === 0 || conexiones.some((fuentes) => !fuentes.includes(origen))) {
    fallar(`connect-src no permite ${origen}: agrégalo en web/.htaccess y vuelve a compilar.`);
  }
  console.log(`[csp-web] connect-src permite ${origen}`);
}
