import 'dart:async';

import 'package:flutter/material.dart';

import '../model/cierre_tarea_pendiente_model.dart';
import '../service/offline/cierre_tarea_offline_store.dart';
import '../service/offline/tarea_sync_engine.dart';
import '../service/session_service.dart';
import 'cierres_pendientes_sheet.dart';

/// Resumen de lo guardado sin señal (cierres y asistencias) para el panel:
///
/// - rechazados por el servidor: "N cierres/asistencias no se pudieron
///   enviar" con el primer motivo y "Ver" (fotos guardadas y "Descartar");
/// - pendientes: "N guardados en el teléfono, se enviarán solos".
///
/// Sin nada guardado no muestra nada.
class PendientesEnvioBanner extends StatefulWidget {
  const PendientesEnvioBanner({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  State<PendientesEnvioBanner> createState() => _PendientesEnvioBannerState();
}

class _PendientesEnvioBannerState extends State<PendientesEnvioBanner> {
  StreamSubscription<void>? _sub;
  String? _usuarioId;
  int _pendientes = 0;
  int _rechazados = 0;
  String? _motivo;

  @override
  void initState() {
    super.initState();
    _cargar();
    _sub = TareaSyncEngine.instance.onCambios.listen((_) => _cargar());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final uid = _usuarioId ?? (await SessionService().getUserId())?.trim();
      if (uid == null || uid.isEmpty) return;
      final store = CierreTareaOfflineStore.instance;
      final cierres = await store.listarCierres(usuarioId: uid);
      final asistencias = await store.listarAsistencias(usuarioId: uid);
      final estados = [
        for (final c in cierres) (c.estadoSync, c.ultimoError),
        for (final a in asistencias) (a.estadoSync, a.ultimoError),
      ];
      final rechazos = estados
          .where((e) => e.$1 == CierreSyncEstado.error)
          .toList();
      if (!mounted) return;
      setState(() {
        _usuarioId = uid;
        _rechazados = rechazos.length;
        _pendientes = estados
            .where(
              (e) =>
                  e.$1 == CierreSyncEstado.pendiente ||
                  e.$1 == CierreSyncEstado.sincronizando,
            )
            .length;
        _motivo = rechazos.map((e) => e.$2).whereType<String>().firstOrNull;
      });
    } catch (_) {
      // El aviso es informativo: si la base no abre, no se muestra.
    }
  }

  Future<void> _ver() async {
    final uid = _usuarioId;
    if (uid == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CierresPendientesSheet(usuarioId: uid),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    if (_rechazados == 0 && _pendientes == 0) return const SizedBox.shrink();
    final rechazo = _rechazados > 0;
    final texto = rechazo
        ? '$_rechazados ${_rechazados == 1 ? 'cierre/asistencia no se pudo enviar' : 'cierres/asistencias no se pudieron enviar'}.'
              '${_motivo != null ? ' Motivo: $_motivo' : ''}'
        : '$_pendientes ${_pendientes == 1 ? 'registro guardado' : 'registros guardados'} en el teléfono. Se enviarán solos cuando haya señal.';
    return Padding(
      padding: widget.padding,
      child: Material(
        color: rechazo ? const Color(0xFFFDE8E8) : const Color(0xFFFDF0E1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _ver,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Icon(
                  rechazo ? Icons.error_outline : Icons.cloud_upload_outlined,
                  color: rechazo ? Colors.red.shade800 : Colors.orange.shade900,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(texto)),
                TextButton(onPressed: _ver, child: const Text('Ver')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
