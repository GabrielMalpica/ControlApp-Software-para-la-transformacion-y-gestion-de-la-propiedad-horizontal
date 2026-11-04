import 'dart:async';

import 'package:flutter/widgets.dart';

import 'cierre_tarea_offline_store.dart';
import 'sincronizacion_fondo.dart';
import 'tarea_sync_engine.dart';

/// Une la cola sin señal con el ciclo de vida de la app:
///
/// - en primer plano: avisa al proceso de segundo plano que la app manda
///   (latido cada minuto) y al volver envía lo pendiente sin esperar el
///   backoff;
/// - al irse a segundo plano: quita el latido, para el temporizador y cierra
///   la base (WorkManager la puede abrir desde otro proceso; dos procesos
///   escribiendo la misma base la dañarían). Al volver se reabre y se ve lo
///   que ese proceso haya enviado.
class CicloVidaSincronizacion with WidgetsBindingObserver {
  CicloVidaSincronizacion._();
  static final CicloVidaSincronizacion instance = CicloVidaSincronizacion._();

  bool _iniciado = false;
  bool _enPrimerPlano = true;
  Timer? _latido;

  void iniciar() {
    if (_iniciado) return;
    _iniciado = true;
    WidgetsBinding.instance.addObserver(this);
    _entrarPrimerPlano();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_enPrimerPlano) unawaited(_volverAPrimerPlano());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_enPrimerPlano) unawaited(_irASegundoPlano());
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _entrarPrimerPlano() {
    _enPrimerPlano = true;
    unawaited(SincronizacionFondo.marcarPrimerPlano(true));
    _latido?.cancel();
    _latido = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(SincronizacionFondo.marcarPrimerPlano(true));
    });
  }

  Future<void> _volverAPrimerPlano() async {
    _entrarPrimerPlano();
    // Si WorkManager está enviando justo ahora, se espera a que termine (máx.
    // 5 min) para no abrir la base a la vez.
    for (var i = 0; i < 60; i++) {
      if (!await SincronizacionFondo.otroProcesoEnviando()) break;
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!_enPrimerPlano) return;
    }
    if (!TareaSyncEngine.instance.sincronizando) {
      // Reabre la base para leer lo que haya escrito el otro proceso.
      await CierreTareaOfflineStore.instance.cerrar();
    }
    await TareaSyncEngine.instance.sincronizarAhora(ignorarEspera: true);
  }

  Future<void> _irASegundoPlano() async {
    _enPrimerPlano = false;
    _latido?.cancel();
    _latido = null;
    TareaSyncEngine.instance.pausarTemporizador();
    await SincronizacionFondo.marcarPrimerPlano(false);
    // Un envío en curso se deja terminar antes de cerrar la base.
    if (TareaSyncEngine.instance.sincronizando) {
      try {
        await TareaSyncEngine.instance.sincronizarAhora();
      } catch (_) {}
    }
    if (!_enPrimerPlano) {
      await CierreTareaOfflineStore.instance.cerrar();
    }
  }
}
