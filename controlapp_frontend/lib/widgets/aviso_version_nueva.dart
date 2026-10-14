import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_application_1/service/actualizacion_web/actualizacion_web_bridge.dart';
import 'package:flutter_application_1/service/theme.dart';

/// Envuelve toda la app (MaterialApp.builder). Al abrir la app el navegador
/// ya carga la última versión publicada (web/flutter_bootstrap.js); esto
/// cubre a quien la deja abierta días: al volver a ella revisa si se publicó
/// otra y ofrece actualizar con un toque.
///
/// No recarga sola: el operario puede estar a mitad de un cierre con fotos
/// (volver de la cámara también cuenta como volver a la app) y lo perdería.
class AvisoVersionNueva extends StatefulWidget {
  const AvisoVersionNueva({super.key, required this.child, this.revisar});

  final Widget child;

  /// Para pruebas; por defecto pregunta al servidor.
  final Future<bool> Function()? revisar;

  @override
  State<AvisoVersionNueva> createState() => _AvisoVersionNuevaState();
}

class _AvisoVersionNuevaState extends State<AvisoVersionNueva> {
  /// Es una petición HEAD de pocos bytes, pero cambiar de pestaña o de
  /// ventana también cuenta como volver: no más de una cada 5 minutos.
  static const Duration _entreRevisiones = Duration(minutes: 5);

  AppLifecycleListener? _ciclo;
  DateTime? _ultimaRevision;
  bool _hayVersionNueva = false;
  bool _actualizando = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || widget.revisar != null) {
      _ciclo = AppLifecycleListener(onResume: _revisar);
    }
  }

  @override
  void dispose() {
    _ciclo?.dispose();
    super.dispose();
  }

  Future<void> _revisar() async {
    if (_hayVersionNueva) return;
    final ahora = DateTime.now();
    final ultima = _ultimaRevision;
    if (ultima != null && ahora.difference(ultima) < _entreRevisiones) return;
    _ultimaRevision = ahora;

    final nueva = await (widget.revisar ?? ActualizacionWeb.hayVersionNueva)();
    if (!mounted || !nueva) return;
    setState(() => _hayVersionNueva = true);
  }

  Future<void> _actualizar() async {
    setState(() => _actualizando = true);
    await ActualizacionWeb.actualizar();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_hayVersionNueva)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    color: AppTheme.primaryDark,
                    elevation: 6,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.system_update_alt_rounded,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Hay una versión nueva de ControlApp. Termina lo que estás haciendo y toca Actualizar.',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          TextButton(
                            onPressed: _actualizando ? null : _actualizar,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.accent,
                            ),
                            child: Text(
                              _actualizando ? 'Actualizando...' : 'Actualizar',
                            ),
                          ),
                          // Sin tooltip: este aviso está por fuera del
                          // Navigator y no tiene Overlay donde mostrarlo.
                          IconButton(
                            onPressed: () =>
                                setState(() => _hayVersionNueva = false),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              semanticLabel: 'Ahora no',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
