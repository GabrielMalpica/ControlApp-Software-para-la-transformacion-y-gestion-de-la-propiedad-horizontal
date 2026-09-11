import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'service/offline/tarea_sync_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  unawaited(initializeDateFormatting('es', null));
  // Arranca el detector de conectividad y el drenado de cierres de tarea
  // pendientes (cola offline del operario). Vive toda la sesión de la app;
  // si no hay sesión iniciada o no hay pendientes, no hace nada.
  TareaSyncEngine.instance.iniciar();
  runApp(const MyApp());
}
