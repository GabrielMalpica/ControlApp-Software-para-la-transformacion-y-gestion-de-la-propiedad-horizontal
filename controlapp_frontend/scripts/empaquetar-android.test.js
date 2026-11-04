// Pruebas de scripts/empaquetar-android.js con un APK falso (sin Flutter ni
// Android SDK). Desde controlapp_frontend:
//   node scripts/empaquetar-android.test.js

const assert = require("node:assert/strict");
const { execFile } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { after, test } = require("node:test");

const SCRIPT = path.join(__dirname, "empaquetar-android.js");
// Empieza como un zip ("PK\x03\x04"), que es lo que revisa el script.
const APK_FALSO = Buffer.concat([Buffer.from("PK\x03\x04", "latin1"), crypto.randomBytes(2048)]);

const temporales = [];
after(() => temporales.forEach((d) => fs.rmSync(d, { recursive: true, force: true })));

function proyecto({ version = "1.4.2+7", apk = APK_FALSO } = {}) {
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), "empaquetar-android-"));
  temporales.push(raiz);
  fs.writeFileSync(path.join(raiz, "pubspec.yaml"), `name: app\n\nversion: ${version}\n\nenvironment:\n  sdk: ^3.9.2\n`);
  fs.mkdirSync(path.join(raiz, "build/app/outputs/flutter-apk"), { recursive: true });
  if (apk) fs.writeFileSync(path.join(raiz, "build/app/outputs/flutter-apk/app-release.apk"), apk);
  fs.mkdirSync(path.join(raiz, "build/web"), { recursive: true });
  fs.writeFileSync(path.join(raiz, "build/web/index.html"), "<!doctype html>");
  return raiz;
}

function correr(raiz, args = [], env = {}) {
  return new Promise((resolve) => {
    execFile(
      process.execPath,
      [SCRIPT, "--raiz", raiz, ...args],
      { env: { ...process.env, GITHUB_OUTPUT: "", ...env } },
      (error, stdout, stderr) => resolve({ codigo: error ? error.code : 0, stdout, stderr }),
    );
  });
}

function leerJson(raiz) {
  return JSON.parse(fs.readFileSync(path.join(raiz, "build/web/descargas/android.json"), "utf8"));
}

// Servidor local que responde con lo que diga `rutas` (simula Hostinger).
async function servidor(rutas) {
  const server = http.createServer((req, res) => {
    const r = rutas[req.url] ?? { status: 404, body: "no" };
    res.writeHead(r.status, { "Content-Type": r.tipo ?? "application/json" });
    res.end(r.body);
  });
  await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
  return { url: `http://127.0.0.1:${server.address().port}`, cerrar: () => new Promise((ok) => server.close(ok)) };
}

test("copia el APK, calcula sha256 y escribe android.json con los campos exactos", async () => {
  const raiz = proyecto();
  const salida = path.join(raiz, "github-output.txt");
  const r = await correr(raiz, ["--base-url", "https://descargas.ejemplo.co/"], { GITHUB_OUTPUT: salida });
  assert.equal(r.codigo, 0, r.stderr);

  const descargas = path.join(raiz, "build/web/descargas");
  assert.deepEqual(fs.readFileSync(path.join(descargas, "controlapp-1.4.2+7.apk")), APK_FALSO);
  assert.deepEqual(fs.readFileSync(path.join(descargas, "controlapp.apk")), APK_FALSO);
  assert.match(fs.readFileSync(path.join(descargas, ".htaccess"), "utf8"), /no-cache/);

  const info = leerJson(raiz);
  assert.deepEqual(Object.keys(info), [
    "versionCode",
    "versionName",
    "url",
    "sha256",
    "tamanoBytes",
    "publicadaEn",
    "minimaVersionCode",
    "notas",
  ]);
  assert.equal(info.versionCode, 7);
  assert.equal(info.versionName, "1.4.2");
  assert.equal(info.url, "https://descargas.ejemplo.co/descargas/controlapp-1.4.2%2B7.apk");
  assert.equal(info.sha256, crypto.createHash("sha256").update(APK_FALSO).digest("hex"));
  assert.equal(info.tamanoBytes, APK_FALSO.length);
  assert.equal(new Date(info.publicadaEn).toISOString(), info.publicadaEn);
  assert.equal(info.minimaVersionCode, 1);
  assert.equal(info.notas, "");

  const outputs = fs.readFileSync(salida, "utf8");
  assert.match(outputs, /^version_name=1\.4\.2$/m);
  assert.match(outputs, /^version_code=7$/m);
});

test("--minima y --notas llegan a android.json", async () => {
  const raiz = proyecto();
  const r = await correr(raiz, ["--minima", "5", "--notas", "Cierre sin señal"]);
  assert.equal(r.codigo, 0, r.stderr);
  const info = leerJson(raiz);
  assert.equal(info.minimaVersionCode, 5);
  assert.equal(info.notas, "Cierre sin señal");
  assert.equal(info.url, "https://controlapp.controlsas.com.co/descargas/controlapp-1.4.2%2B7.apk");
});

test("--minima vacía usa 1; mayor que el versionCode nuevo falla", async () => {
  const vacia = proyecto();
  assert.equal((await correr(vacia, ["--minima", ""])).codigo, 0);
  assert.equal(leerJson(vacia).minimaVersionCode, 1);

  const raiz = proyecto();
  const r = await correr(raiz, ["--minima", "8"]);
  assert.notEqual(r.codigo, 0);
  assert.match(r.stderr, /--minima 8 es mayor que el versionCode nuevo \(7\)/);
});

test("--anterior (archivo) con versionCode igual o mayor falla y no escribe nada", async () => {
  for (const publicada of [7, 9]) {
    const raiz = proyecto();
    const anterior = path.join(raiz, "publicado.json");
    fs.writeFileSync(anterior, JSON.stringify({ versionCode: publicada }));
    const r = await correr(raiz, ["--anterior", anterior]);
    assert.notEqual(r.codigo, 0);
    assert.match(r.stderr, new RegExp(`Ya está publicado el versionCode ${publicada} y el nuevo es 7`));
    assert.match(r.stderr, new RegExp(`1\\.4\\.2\\+${publicada + 1}`));
    assert.equal(fs.existsSync(path.join(raiz, "build/web/descargas")), false);
  }
});

test("--anterior (archivo) menor o que no existe deja seguir", async () => {
  const raiz = proyecto();
  const anterior = path.join(raiz, "publicado.json");
  fs.writeFileSync(anterior, JSON.stringify({ versionCode: 6 }));
  assert.equal((await correr(raiz, ["--anterior", anterior])).codigo, 0);

  const primera = proyecto();
  const r = await correr(primera, ["--anterior", path.join(primera, "no-existe.json")]);
  assert.equal(r.codigo, 0, r.stderr);
  assert.match(r.stdout, /primera versión/);
});

test("--anterior (URL): JSON, 404, index.html de Hostinger y errores", async () => {
  const s = await servidor({
    "/mayor.json": { status: 200, body: JSON.stringify({ versionCode: 10 }) },
    "/menor.json": { status: 200, body: JSON.stringify({ versionCode: 3 }) },
    "/html.json": { status: 200, tipo: "text/html", body: "<!doctype html><html></html>" },
    "/roto.json": { status: 200, body: "{versionCode:" },
    "/sin-version.json": { status: 200, body: "{}" },
    "/caido.json": { status: 500, body: "error" },
  });
  try {
    const casos = [
      ["/mayor.json", false, /Ya está publicado el versionCode 10/],
      ["/menor.json", true, /Versión publicada hoy: 3; nueva: 7/],
      ["/no-esta.json", true, /primera versión/],
      ["/html.json", true, /primera versión/],
      ["/roto.json", false, /no es un JSON válido/],
      ["/sin-version.json", false, /versionCode de .* debe ser un número entero/],
      ["/caido.json", false, /respondió 500/],
    ];
    for (const [ruta, pasa, mensaje] of casos) {
      const r = await correr(proyecto(), ["--anterior", `${s.url}${ruta}`]);
      assert.equal(r.codigo === 0, pasa, `${ruta}: ${r.stderr}`);
      assert.match(pasa ? r.stdout : r.stderr, mensaje, ruta);
    }
  } finally {
    await s.cerrar();
  }
});

test("--solo-revisar revisa la versión sin APK ni build y no escribe nada", async () => {
  const raiz = proyecto({ apk: null });
  fs.rmSync(path.join(raiz, "build/web"), { recursive: true });
  const anterior = path.join(raiz, "publicado.json");

  fs.writeFileSync(anterior, JSON.stringify({ versionCode: 6 }));
  let r = await correr(raiz, ["--solo-revisar", "--anterior", anterior, "--minima", "2"]);
  assert.equal(r.codigo, 0, r.stderr);
  assert.match(r.stdout, /1\.4\.2\+7 lista para compilar \(mínima 2\)/);
  assert.equal(fs.existsSync(path.join(raiz, "build/web")), false);

  fs.writeFileSync(anterior, JSON.stringify({ versionCode: 7 }));
  r = await correr(raiz, ["--solo-revisar", "--anterior", anterior]);
  assert.notEqual(r.codigo, 0);
  assert.match(r.stderr, /Ya está publicado el versionCode 7/);
});

test("pubspec sin versionCode, sin APK o con un archivo que no es APK falla", async () => {
  let r = await correr(proyecto({ version: "1.4.2" }));
  assert.notEqual(r.codigo, 0);
  assert.match(r.stderr, /debe tener "version: X\.Y\.Z\+N"/);

  r = await correr(proyecto({ apk: null }));
  assert.notEqual(r.codigo, 0);
  assert.match(r.stderr, /primero flutter build apk --release/);

  r = await correr(proyecto({ apk: Buffer.from("no soy un zip") }));
  assert.notEqual(r.codigo, 0);
  assert.match(r.stderr, /no parece un APK/);

  r = await correr(proyecto(), ["--base-url", "ftp://servidor"]);
  assert.notEqual(r.codigo, 0);
  assert.match(r.stderr, /--base-url debe ser http\(s\)/);
});
