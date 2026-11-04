import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../model/asistencia_pendiente_model.dart';
import '../model/cierre_tarea_pendiente_model.dart';
import '../service/offline/cierre_tarea_offline_store.dart';
import '../service/offline/tarea_sync_engine.dart';
import '../utils/uploader_preview/preview_bridge.dart';

/// Lista lo que el operario guardó en el teléfono sin señal (asistencias por
/// QR y cierres de tarea), con su estado de envío. Lo que el servidor rechazó
/// muestra el motivo, deja ver las fotos guardadas y ofrece "Reintentar" o
/// "Descartar". Nada se descarta solo.
class CierresPendientesSheet extends StatefulWidget {
  final String usuarioId;

  const CierresPendientesSheet({super.key, required this.usuarioId});

  @override
  State<CierresPendientesSheet> createState() => _CierresPendientesSheetState();
}

class _CierresPendientesSheetState extends State<CierresPendientesSheet> {
  List<CierreTareaPendiente> _cierres = [];
  List<AsistenciaPendiente> _asistencias = [];
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
    final store = CierreTareaOfflineStore.instance;
    final cierres = await store.listarCierres(usuarioId: widget.usuarioId);
    final asistencias = await store.listarAsistencias(
      usuarioId: widget.usuarioId,
    );
    // Primero lo rechazado (lo que pide atención), luego lo más reciente.
    int orden(CierreSyncEstado e) => e == CierreSyncEstado.error ? 0 : 1;
    cierres.sort((a, b) {
      final o = orden(a.estadoSync).compareTo(orden(b.estadoSync));
      return o != 0 ? o : b.creadoEn.compareTo(a.creadoEn);
    });
    asistencias.sort((a, b) {
      final o = orden(a.estadoSync).compareTo(orden(b.estadoSync));
      return o != 0 ? o : b.creadoEn.compareTo(a.creadoEn);
    });
    if (!mounted) return;
    setState(() {
      _cierres = cierres;
      _asistencias = asistencias;
      _cargando = false;
    });
  }

  Future<void> _sincronizarAhora() async {
    setState(() => _sincronizando = true);
    await TareaSyncEngine.instance.sincronizarAhora(
      usuarioId: widget.usuarioId,
      ignorarEspera: true,
    );
    if (!mounted) return;
    setState(() => _sincronizando = false);
  }

  Future<bool> _confirmarDescarte(String texto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Descartar?'),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _descartarCierre(CierreTareaPendiente c) async {
    if (await _confirmarDescarte(
      'Se borrarán del teléfono las fotos, insumos y observaciones de este '
      'cierre. No se puede deshacer.',
    )) {
      await TareaSyncEngine.instance.descartar(c.clienteCierreId);
    }
  }

  Future<void> _descartarAsistencia(AsistenciaPendiente a) async {
    if (await _confirmarDescarte(
      'Se borrará del teléfono esta marca de asistencia. Si la necesitas, '
      'pídele a tu supervisor que la registre a mano.',
    )) {
      await TareaSyncEngine.instance.descartarAsistencia(a.clienteRegistroId);
    }
  }

  void _verFotos(CierreTareaPendiente c) {
    showDialog<void>(
      context: context,
      builder: (_) => _FotosGuardadasDialog(cierre: c),
    );
  }

  static String _estadoTexto(CierreSyncEstado e) {
    switch (e) {
      case CierreSyncEstado.pendiente:
        return 'Pendiente de enviar';
      case CierreSyncEstado.sincronizando:
        return 'Enviando...';
      case CierreSyncEstado.sincronizado:
        return 'Enviado';
      case CierreSyncEstado.error:
        return 'No se pudo enviar';
    }
  }

  static Color _estadoColor(CierreSyncEstado e) {
    switch (e) {
      case CierreSyncEstado.pendiente:
        return Colors.orange.shade900;
      case CierreSyncEstado.sincronizando:
        return Colors.blue.shade800;
      case CierreSyncEstado.sincronizado:
        return Colors.green.shade800;
      case CierreSyncEstado.error:
        return Colors.red.shade800;
    }
  }

  static String _fmt(DateTime d) {
    final l = d.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mi = l.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mi';
  }

  Widget _tarjeta({
    required String titulo,
    required String detalle,
    required CierreSyncEstado estado,
    String? motivo,
    List<Widget> acciones = const [],
  }) {
    final rechazado = estado == CierreSyncEstado.error;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: rechazado
            ? BorderSide(color: Colors.red.shade300)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _estadoTexto(estado),
                  style: TextStyle(
                    color: _estadoColor(estado),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              detalle,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (motivo != null && motivo.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                rechazado ? 'Motivo: ${motivo.trim()}' : motivo.trim(),
                style: TextStyle(
                  fontSize: 13,
                  color: rechazado ? Colors.red.shade800 : Colors.black54,
                ),
              ),
            ],
            if (acciones.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 4, children: acciones),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _items() {
    final out = <Widget>[];
    if (_asistencias.isNotEmpty) {
      out.add(const _Titulo('Asistencias'));
      for (final a in _asistencias) {
        final tipo = a.tipoRegistrado == null
            ? 'Marca de asistencia'
            : (a.tipoRegistrado == 'SALIDA' ? 'Salida' : 'Entrada');
        out.add(
          _tarjeta(
            titulo:
                '$tipo${(a.conjuntoNombre ?? '').isNotEmpty ? ' · ${a.conjuntoNombre}' : ''}',
            detalle: 'Escaneada ${_fmt(a.registradaEn)}',
            estado: a.estadoSync,
            motivo: a.ultimoError,
            acciones: [
              if (a.estadoSync == CierreSyncEstado.error) ...[
                TextButton(
                  onPressed: () =>
                      TareaSyncEngine.instance.reintentarAsistencia(
                        usuarioId: widget.usuarioId,
                        clienteRegistroId: a.clienteRegistroId,
                      ),
                  child: const Text('Reintentar'),
                ),
                TextButton(
                  onPressed: () => _descartarAsistencia(a),
                  child: const Text('Descartar'),
                ),
              ],
            ],
          ),
        );
      }
    }
    if (_cierres.isNotEmpty) {
      out.add(const _Titulo('Cierres de actividades'));
      for (final c in _cierres) {
        final nombre = (c.descripcionTarea ?? '').trim();
        out.add(
          _tarjeta(
            titulo: nombre.isNotEmpty ? nombre : 'Actividad #${c.tareaId}',
            detalle:
                '${c.evidencias.length} foto(s) · cerrada ${_fmt(c.fechaCierreLocal)}',
            estado: c.estadoSync,
            motivo: c.ultimoError,
            acciones: [
              if (c.evidencias.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _verFotos(c),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Ver fotos'),
                ),
              if (c.estadoSync == CierreSyncEstado.error) ...[
                TextButton(
                  onPressed: () => TareaSyncEngine.instance.reintentarManual(
                    usuarioId: widget.usuarioId,
                    clienteCierreId: c.clienteCierreId,
                  ),
                  child: const Text('Reintentar'),
                ),
                TextButton(
                  onPressed: () => _descartarCierre(c),
                  child: const Text('Descartar'),
                ),
              ],
            ],
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.8;
    final items = _items();

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
                    'Guardado en el teléfono',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
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
                label: Text(_sincronizando ? 'Enviando...' : 'Enviar ahora'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : (items.isEmpty
                        ? const Center(
                            child: Text('No tienes nada pendiente de enviar.'),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) => items[i],
                          )),
            ),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        texto,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );
  }
}

/// Fotos de un cierre guardado (siguen en el teléfono hasta que se envíe o
/// el operario lo descarte).
class _FotosGuardadasDialog extends StatelessWidget {
  const _FotosGuardadasDialog({required this.cierre});
  final CierreTareaPendiente cierre;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fotos guardadas'),
      content: SizedBox(
        width: 480,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final e in cierre.evidencias)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _miniatura(e),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _miniatura(EvidenciaPendiente e) {
    final esPdf = e.nombre.toLowerCase().endsWith('.pdf');
    if (esPdf) {
      return const ColoredBox(
        color: Color(0xFFEEF1F5),
        child: Center(child: Icon(Icons.picture_as_pdf, size: 40)),
      );
    }
    final b64 = e.bytesBase64;
    if (b64 != null) {
      return Image.memory(
        Uint8List.fromList(base64Decode(b64)),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    }
    final path = e.path;
    if (path == null || path.isEmpty) {
      return const Icon(Icons.broken_image_outlined);
    }
    return PreviewHelper.previewXFile(XFile(path), size: 220);
  }
}
