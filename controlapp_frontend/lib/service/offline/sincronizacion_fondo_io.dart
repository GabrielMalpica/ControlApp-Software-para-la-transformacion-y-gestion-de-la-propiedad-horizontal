import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../app_info.dart';
import '../http/cliente_http_bridge.dart';
import 'cierre_tarea_offline_store.dart';
import 'tarea_sync_engine.dart';

const _trabajoUnico = 'controlapp.enviar-pendientes';
const _trabajoRespaldo = 'controlapp.enviar-pendientes-respaldo';
const _nombreTarea = 'enviarPendientes';

/// Mientras la app está en primer plano escribe aquí "hasta cuándo" (latido):
/// el proceso de segundo plano no abre la base mientras la app la usa.
const _kPrimerPlanoHasta = 'sync_fondo_primer_plano_hasta';

/// Candado del proceso de segundo plano (dos trabajos no envían a la vez).
const _kCandadoHasta = 'sync_fondo_candado_hasta';

const Duration _vigenciaLatido = Duration(minutes: 3);
const Duration _vigenciaCandado = Duration(minutes: 6);

bool get _soportado =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Punto de entrada de WorkManager (otro isolate, con la app cerrada).
@pragma('vm:entry-point')
void callbackDispatcherSincronizacion() {
  Workmanager().executeTask((tarea, datos) async {
    DartPluginRegistrant.ensureInitialized();
    return SincronizacionFondo.ejecutarEnvio();
  });
}

/// Envío de lo guardado sin señal aunque la app esté cerrada:
///
/// - un trabajo único con restricción de red: Android lo corre apenas vuelve
///   internet, y lo reintenta con backoff si el servidor falla;
/// - uno periódico cada 15 min de respaldo, que se cancela cuando la cola
///   queda vacía.
class SincronizacionFondo {
  SincronizacionFondo._();

  static Future<void> inicializar() async {
    if (!_soportado) return;
    try {
      await Workmanager().initialize(callbackDispatcherSincronizacion);
      TareaSyncEngine.programarEnFondo = programar;
      TareaSyncEngine.alQuedarSinPendientes = cancelarRespaldo;
    } catch (_) {
      // Sin WorkManager la cola se envía igual mientras la app esté abierta.
    }
  }

  static Future<void> programar() async {
    if (!_soportado) return;
    final conRed = Constraints(networkType: NetworkType.connected);
    await Workmanager().registerOneOffTask(
      _trabajoUnico,
      _nombreTarea,
      constraints: conRed,
      // Si ya hay uno esperando la red, ese mismo envía todo lo nuevo.
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
    await Workmanager().registerPeriodicTask(
      _trabajoRespaldo,
      _nombreTarea,
      frequency: const Duration(minutes: 15),
      constraints: conRed,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancelarRespaldo() async {
    if (!_soportado) return;
    try {
      await Workmanager().cancelByUniqueName(_trabajoRespaldo);
    } catch (_) {}
  }

  /// La app abierta avisa que está en primer plano (y lo renueva cada
  /// minuto); con false lo quita al irse a segundo plano.
  static Future<void> marcarPrimerPlano(bool activo) async {
    if (!_soportado) return;
    final prefs = SharedPreferencesAsync();
    if (activo) {
      await prefs.setInt(
        _kPrimerPlanoHasta,
        DateTime.now().add(_vigenciaLatido).millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_kPrimerPlanoHasta);
    }
  }

  /// true si el proceso de segundo plano está enviando ahora mismo.
  static Future<bool> otroProcesoEnviando() async {
    if (!_soportado) return false;
    final hasta = await SharedPreferencesAsync().getInt(_kCandadoHasta) ?? 0;
    return hasta > DateTime.now().millisecondsSinceEpoch;
  }

  /// Lo que hace el trabajo de WorkManager. true = terminado; false = que
  /// Android lo reintente más tarde (con backoff).
  static Future<bool> ejecutarEnvio() async {
    // WorkManager puede correr el trabajo dentro de la app abierta: ahí ya
    // está todo inicializado y la base es la misma.
    if (TareaSyncEngine.esProcesoPrincipal) {
      final r = await TareaSyncEngine.instance.sincronizarAhora(
        ignorarEspera: true,
      );
      return _terminado(r);
    }

    final prefs = SharedPreferencesAsync();
    final ahora = DateTime.now().millisecondsSinceEpoch;
    final primerPlano = await prefs.getInt(_kPrimerPlanoHasta) ?? 0;
    // La app está abierta y enviando por su cuenta.
    if (primerPlano > ahora) return true;
    final candado = await prefs.getInt(_kCandadoHasta) ?? 0;
    if (candado > ahora) return false;
    await prefs.setInt(
      _kCandadoHasta,
      DateTime.now().add(_vigenciaCandado).millisecondsSinceEpoch,
    );

    try {
      await AppInfo.cargar();
      final r = await ejecutarConClienteApp(
        () => TareaSyncEngine.instance.sincronizarAhora(ignorarEspera: true),
      );
      return _terminado(r);
    } catch (_) {
      return false;
    } finally {
      await CierreTareaOfflineStore.instance.cerrar();
      await prefs.remove(_kCandadoHasta);
    }
  }

  static bool _terminado(ResumenSincronizacion r) =>
      r.pendientes == 0 || r.sesionExpirada || r.appDesactualizada;
}
