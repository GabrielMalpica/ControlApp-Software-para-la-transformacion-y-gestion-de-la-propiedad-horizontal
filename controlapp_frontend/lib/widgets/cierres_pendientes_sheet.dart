import 'dart:async';

import 'package:flutter/material.dart';

import '../model/cierre_tarea_pendiente_model.dart';
import '../service/offline/cierre_tarea_offline_store.dart';
import '../service/offline/tarea_sync_engine.dart';

/// Lista los cierres de tarea guardados localmente por el operario mientras
/// no había conexión, con su estado de sincronización y acciones para
/// reintentar o descartar los que quedaron con error de negocio.
class CierresPendientesSheet extends StatefulWidget {
  final String usuarioId;

  const CierresPendientesSheet({super.key, required this.usuarioId});

  @override
  State<CierresPendientesSheet> createState() =>
      _CierresPendientesSheetState();
}

class _CierresPendientesSheetState extends State<CierresPendientesSheet> {
  List<CierreTareaPendiente> _cierres = [];
  bool _cargando = true;
  bool _sincronizando = false;
  StreamSubscription<void>? _sub;

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
    final lista = await CierreTareaOfflineStore.instance.listarCierres(
      usuarioId: widget.usuarioId,
    );
    lista.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    if (!mounted) return;
    setState(() {
      _cierres = lista;
      _cargando = false;
    });
  }

  Future<void> _sincronizarAhora() async {
    setState(() => _sincronizando = true);
    await TareaSyncEngine.instance.sincronizarAhora(
      usuarioId: widget.usuarioId,
    );
    if (!mounted) return;
    setState(() => _sincronizando = false);
  }

  Future<void> _reintentar(CierreTareaPendiente c) async {
    await TareaSyncEngine.instance.reintentarManual(
      usuarioId: widget.usuarioId,
      clienteCierreId: c.clienteCierreId,
    );
  }

  Future<void> _descartar(CierreTareaPendiente c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar cierre'),
        content: const Text(
          'Se perderán las evidencias, insumos y observaciones guardadas '
          'de este cierre. Esta acción no se puede deshacer. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await TareaSyncEngine.instance.descartar(c.clienteCierreId);
    }
  }

  static String _estadoTexto(CierreSyncEstado e) {
    switch (e) {
      case CierreSyncEstado.pendiente:
        return 'Pendiente de enviar';
      case CierreSyncEstado.sincronizando:
        return 'Enviando...';
      case CierreSyncEstado.sincronizado:
        return 'Sincronizado';
      case CierreSyncEstado.error:
        return 'Con error, requiere revisión';
    }
  }

  static Color _estadoColor(CierreSyncEstado e) {
    switch (e) {
      case CierreSyncEstado.pendiente:
        return Colors.orange.shade800;
      case CierreSyncEstado.sincronizando:
        return Colors.blue;
      case CierreSyncEstado.sincronizado:
        return Colors.green;
      case CierreSyncEstado.error:
        return Colors.red;
    }
  }

  static String _fmt(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.75;

    return SizedBox(
      height: alto,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cierres pendientes de sincronizar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _sincronizando ? null : _sincronizarAhora,
                icon: _sincronizando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  _sincronizando ? 'Sincronizando...' : 'Sincronizar ahora',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : (_cierres.isEmpty
                        ? const Center(
                            child: Text('No tienes cierres pendientes.'),
                          )
                        : ListView.separated(
                            itemCount: _cierres.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final c = _cierres[i];
                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Tarea #${c.tareaId}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _estadoTexto(c.estadoSync),
                                            style: TextStyle(
                                              color: _estadoColor(
                                                c.estadoSync,
                                              ),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${c.evidencias.length} evidencia(s) · cerrada ${_fmt(c.fechaCierreLocal)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      if (c.ultimoError != null &&
                                          c.ultimoError!.trim().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          c.ultimoError!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                      if (c.estadoSync ==
                                          CierreSyncEstado.error) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            TextButton(
                                              onPressed: () => _reintentar(c),
                                              child: const Text('Reintentar'),
                                            ),
                                            TextButton(
                                              onPressed: () => _descartar(c),
                                              child: const Text('Descartar'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          )),
            ),
          ],
        ),
      ),
    );
  }
}
