import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/asistencia_api.dart';
import '../model/asistencia_model.dart';
import '../service/app_error.dart';
import '../service/app_feedback.dart';
import '../service/chart_capture.dart';
import '../service/theme.dart';

class AsistenciaQrPage extends StatefulWidget {
  final String conjuntoId;
  final String conjuntoNombre;

  const AsistenciaQrPage({
    super.key,
    required this.conjuntoId,
    required this.conjuntoNombre,
  });

  @override
  State<AsistenciaQrPage> createState() => _AsistenciaQrPageState();
}

class _AsistenciaQrPageState extends State<AsistenciaQrPage> {
  final AsistenciaApi _api = AsistenciaApi();
  final GlobalKey _posterKey = GlobalKey();

  bool _cargando = true;
  bool _regenerando = false;
  bool _descargando = false;
  String? _error;
  AsistenciaQr? _qr;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final qr = await _api.obtenerQr(widget.conjuntoId);
      if (!mounted) return;
      setState(() => _qr = qr);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = AppError.messageOf(e, fallback: 'No se pudo cargar el QR.'),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _regenerar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Regenerar QR'),
        content: const Text(
          'El QR actual dejara de funcionar de inmediato. Debes imprimir y '
          'reemplazar el codigo pegado en el sitio. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _regenerando = true);
    try {
      final qr = await _api.regenerarQr(widget.conjuntoId);
      if (!mounted) return;
      setState(() => _qr = qr);
      AppFeedback.showInfo(context, message: 'QR regenerado correctamente.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo regenerar el QR.'),
      );
    } finally {
      if (mounted) setState(() => _regenerando = false);
    }
  }

  Future<void> _descargarQr() async {
    setState(() => _descargando = true);
    try {
      final bytes = await capturePngFromKey(_posterKey, pixelRatio: 3);
      await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar QR de asistencia',
        fileName: 'qr_asistencia_${widget.conjuntoId}.png',
        bytes: bytes,
      );
      if (!mounted) return;
      AppFeedback.showInfo(context, message: 'QR descargado correctamente.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo descargar el QR.'),
      );
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Widget _buildPoster() {
    return RepaintBoundary(
      key: _posterKey,
      child: Container(
        width: 320,
        color: Colors.white,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 64, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.conjuntoNombre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: QrImageView(
                      data: _qr?.payload ?? '',
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Escanea al llegar y al salir para marcar tu asistencia',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Image.asset(
                'assets/logo_cronograma.png',
                width: 72,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          'QR de asistencia · ${widget.conjuntoNombre}',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Imprime este codigo y pegalo en la entrada del conjunto. '
                    'Los operarios lo escanean para marcar entrada y salida.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Center(child: _buildPoster()),
                  if (_qr?.actualizadoEn != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Ultima actualizacion: ${_qr!.actualizadoEn!.toLocal()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _descargando ? null : _descargarQr,
                          icon: _descargando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.download, color: Colors.white),
                          label: const Text(
                            'Descargar QR',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _regenerando ? null : _regenerar,
                          icon: _regenerando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('Regenerar QR'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
