import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'service/actualizacion_app_service.dart';
import 'service/app_info.dart';
import 'service/http/cliente_http_bridge.dart';
import 'service/offline/ciclo_vida_sincronizacion.dart';
import 'service/offline/sincronizacion_fondo.dart';
import 'service/offline/tarea_sync_engine.dart';

Future<void> main() async {
  // En la app nativa todas las peticiones pasan por ClienteHttpApp
  // (cabeceras de versión, renovación de sesión, hora del servidor). La
  // vinculación de Flutter se inicializa dentro de la misma zona.
  await ejecutarConClienteApp(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (kIsWeb) {
      usePathUrlStrategy();
    }
    unawaited(initializeDateFormatting('es', null));
    unawaited(AppInfo.cargar());

    TareaSyncEngine.esProcesoPrincipal = true;
    ActualizacionAppService.instance.registrarAvisos();
    // WorkManager envía la cola con la app cerrada (solo Android).
    unawaited(SincronizacionFondo.inicializar());
    CicloVidaSincronizacion.instance.iniciar();
    // Arranca el detector de conectividad y el drenado de cierres y
    // asistencias pendientes (cola offline del operario). Vive toda la
    // sesión de la app; si no hay sesión iniciada o no hay pendientes, no
    // hace nada.
    TareaSyncEngine.instance.iniciar();
    runApp(const MyApp());
  });
}
