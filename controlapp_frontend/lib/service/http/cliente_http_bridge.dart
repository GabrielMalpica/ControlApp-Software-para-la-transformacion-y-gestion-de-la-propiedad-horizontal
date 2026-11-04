// Instala `ClienteHttpApp` para todas las peticiones de la app nativa. En web
// no se instala nada: la web no manda cabeceras de versión y renueva su sesión
// con la cookie HttpOnly.
export 'cliente_http_io.dart'
    if (dart.library.js_interop) 'cliente_http_web.dart';
