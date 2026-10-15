{{flutter_js}}
{{flutter_build_config}}

// Siempre la última versión publicada, sin Ctrl+F5 ni borrar la caché (ver
// docs/actualizacion-web.md). main.dart.js tiene el mismo nombre en cada
// compilación, así que el navegador puede seguir usando el viejo: se pregunta
// al servidor por su versión (ETag o fecha de modificación, sin descargarlo) y
// se pide como main.dart.js?v=<versión>, una URL nueva cada vez que se publica.
(function () {
  var CLAVE_VERSION = 'controlapp.versionWeb';

  function versionDe(respuesta) {
    if (!respuesta || !respuesta.ok) return null;
    return respuesta.headers.get('etag') || respuesta.headers.get('last-modified');
  }

  // `guardarFecha`: al abrir la app se guarda la fecha de publicación de la
  // versión cargada, que la app muestra como "Versión de la app" (login y
  // perfil) para saber qué versión tiene cada quien.
  function versionPublicada(guardarFecha) {
    return fetch('main.dart.js', { method: 'HEAD', cache: 'no-store' })
      .then(function (respuesta) {
        if (guardarFecha && respuesta && respuesta.ok) {
          window.controlappFechaVersionWeb = respuesta.headers.get('last-modified');
        }
        return versionDe(respuesta);
      })
      .catch(function () { return null; });
  }

  // Archivos que no cambian de nombre entre versiones: la fuente de íconos se
  // recorta en cada compilación (con la vieja salen íconos rotos) y los
  // manifiestos listan los recursos. `cache: 'reload'` los baja de nuevo y
  // reemplaza lo guardado.
  function refrescarRecursos() {
    var refrescar = function (url) {
      return fetch(url, { cache: 'reload' }).catch(function () { return null; });
    };
    var fuentes = refrescar('assets/FontManifest.json')
      .then(function (r) { return r && r.ok ? r.json() : []; })
      .then(function (familias) {
        var urls = [];
        (familias || []).forEach(function (familia) {
          (familia.fonts || []).forEach(function (f) {
            if (f && f.asset) urls.push('assets/' + f.asset);
          });
        });
        return Promise.all(urls.map(refrescar));
      })
      .catch(function () { return null; });
    return Promise.all([
      fuentes,
      refrescar('assets/AssetManifest.bin.json'),
      refrescar('assets/AssetManifest.bin'),
      refrescar('manifest.json'),
      refrescar(location.href.split('#')[0]),
      refrescar(document.baseURI),
    ]);
  }

  function guardarVersion(version) {
    try { localStorage.setItem(CLAVE_VERSION, version); } catch (_) {}
  }

  function versionAnterior() {
    try { return localStorage.getItem(CLAVE_VERSION); } catch (_) { return null; }
  }

  // Service workers de versiones viejas de Flutter servían todo desde su
  // propia caché; hoy no se usa ninguno.
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations()
      .then(function (registros) {
        registros.forEach(function (r) { r.unregister(); });
      })
      .catch(function () {});
  }

  // Usado por la app (lib/service/actualizacion_web*.dart) al volver a
  // primer plano: true si se publicó otra versión desde que se abrió.
  window.controlappHayVersionNueva = function () {
    var actual = window.controlappVersionWeb;
    if (!actual) return Promise.resolve(false);
    return versionPublicada().then(function (v) { return !!v && v !== actual; });
  };

  window.controlappActualizar = function () {
    return refrescarRecursos().then(function () { location.reload(); });
  };

  var compilacion = (_flutter.buildConfig.builds || []).filter(function (b) {
    return b && b.compileTarget === 'dart2js';
  })[0];

  // `flutter run` (desarrollo) no compila con dart2js: no hay nada que versionar.
  var lista = compilacion ? versionPublicada(true) : Promise.resolve(null);
  lista.then(function (version) {
    if (!version) return null;
    window.controlappVersionWeb = version;
    compilacion.mainJsPath =
      (compilacion.mainJsPath || 'main.dart.js') + '?v=' + version.replace(/[^A-Za-z0-9]/g, '');
    var anterior = versionAnterior();
    guardarVersion(version);
    if (anterior && anterior !== version) return refrescarRecursos();
    return null;
  }).catch(function () {
    return null;
  }).then(function () {
    _flutter.loader.load();
  });
})();
