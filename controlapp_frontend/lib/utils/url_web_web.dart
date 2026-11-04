import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Rutas como /login en vez de /#/login (el .htaccess las lleva a index.html).
void configurarUrlsWeb() {
  usePathUrlStrategy();
}
