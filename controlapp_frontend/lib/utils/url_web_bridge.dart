// URLs sin "#" en la web. flutter_web_plugins solo compila para el navegador:
// en Android/iOS se usa la versión que no hace nada.
export 'url_web_io.dart' if (dart.library.js_interop) 'url_web_web.dart';
