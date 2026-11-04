import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_application_1/service/actualizacion_app_service.dart';
import 'package:flutter_application_1/service/theme.dart';

/// Envuelve toda la app nativa (MaterialApp.builder). Al abrir y al volver a
/// la app (máx. cada 30 min) revisa `descargas/android.json`:
///
/// - versión más nueva: aviso abajo con "Actualizar" (se puede dejar para
///   después; nunca se interrumpe un cierre);
/// - por debajo de la mínima o el servidor respondió 426: pantalla que obliga
///   a actualizar. Lo guardado sin señal se conserva y se envía con la
///   versión nueva.
///
/// En web no hace nada (la web usa `AvisoVersionNueva`).
class AvisoActualizacionApp extends StatefulWidget {
  const AvisoActualizacionApp({super.key, required this.child, this.servicio});

  final Widget child;

  /// Para pruebas.
  final ActualizacionAppService? servicio;

  @override
  State<AvisoActualizacionApp> createState() => _AvisoActualizacionAppState();
}

class _AvisoActualizacionAppState extends State<AvisoActualizacionApp> {
  ActualizacionAppService get _servicio =>
      widget.servicio ?? ActualizacionAppService.instance;

  AppLifecycleListener? _ciclo;
  bool _ocultoHastaProxima = false;
  ProgresoActualizacion? _progreso;
  StreamSubscription<ProgresoActualizacion>? _descarga;

  @override
  void initState() {
    super.initState();
    if (!ActualizacionAppService.soportada && widget.servicio == null) return;
    _servicio.estado.addListener(_cambio);
    _ciclo = AppLifecycleListener(onResume: () => _servicio.consultar());
    unawaited(_servicio.consultar());
  }

  @override
  void dispose() {
    _ciclo?.dispose();
    _descarga?.cancel();
    _servicio.estado.removeListener(_cambio);
    super.dispose();
  }

  void _cambio() {
    if (!mounted) return;
    setState(() => _ocultoHastaProxima = false);
  }

  void _actualizar() {
    _descarga?.cancel();
    setState(() => _progreso = const ProgresoActualizacion(porcentaje: 0));
    _descarga = _servicio.descargarEInstalar().listen((p) {
      if (!mounted) return;
      setState(() => _progreso = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final estado = _servicio.estado.value;
    return Stack(
      children: [
        widget.child,
        if (estado == EstadoActualizacion.obligatoria)
          Positioned.fill(child: _pantallaObligatoria())
        else if (estado == EstadoActualizacion.disponible &&
            !_ocultoHastaProxima)
          Positioned(left: 12, right: 12, bottom: 12, child: _aviso()),
      ],
    );
  }

  Widget _estadoDescarga({required Color color}) {
    final p = _progreso;
    if (p == null) return const SizedBox.shrink();
    if (p.error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          p.error!,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      );
    }
    if (p.instalando) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'Abriendo el instalador… toca "Actualizar" o "Instalar" en la ventana de Android.',
          style: TextStyle(color: color),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: (p.porcentaje ?? 0) / 100,
            semanticsLabel: 'Descargando actualización',
            semanticsValue: '${p.porcentaje ?? 0} %',
          ),
          const SizedBox(height: 6),
          Text(
            'Descargando… ${p.porcentaje ?? 0} %',
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }

  bool get _descargando {
    final p = _progreso;
    return p != null && p.error == null;
  }

  Widget _aviso() {
    final m = _servicio.manifiesto;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: AppTheme.primaryDark,
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.system_update_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Hay una versión nueva de ControlApp'
                          '${m != null && m.versionName.isNotEmpty ? ' (${m.versionName})' : ''}.',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: _descargando ? null : _actualizar,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.accent,
                        ),
                        child: const Text('Actualizar'),
                      ),
                      if (!_descargando)
                        IconButton(
                          tooltip: 'Después',
                          onPressed: () =>
                              setState(() => _ocultoHastaProxima = true),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                    ],
                  ),
                  _estadoDescarga(color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pantallaObligatoria() {
    final m = _servicio.manifiesto;
    return Material(
      color: AppTheme.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.system_update_rounded,
                    size: 72,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Actualiza ControlApp para seguir',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Esta versión ya no funciona con el servidor. Lo que guardaste sin señal sigue en el teléfono y se enviará con la versión nueva.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  if (m != null && m.notas.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(m.notas.trim(), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: _descargando
                        ? null
                        : (m == null
                              ? () => _servicio.consultar(forzar: true)
                              : _actualizar),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      m == null ? 'Buscar la versión nueva' : 'Actualizar',
                    ),
                  ),
                  _estadoDescarga(color: AppTheme.textMuted),
                  const SizedBox(height: 16),
                  const Text(
                    'Si Android lo pide, permite "Instalar apps desconocidas" para ControlApp y vuelve a tocar Actualizar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
