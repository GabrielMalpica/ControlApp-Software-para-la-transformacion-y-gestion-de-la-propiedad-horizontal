import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/asistencia_api.dart';
import '../model/asistencia_model.dart';
import '../service/app_error.dart';
import '../service/app_feedback.dart';
import '../service/theme.dart';

class AsistenciaCheckinPage extends StatefulWidget {
  const AsistenciaCheckinPage({super.key});

  @override
  State<AsistenciaCheckinPage> createState() => _AsistenciaCheckinPageState();
}

class _AsistenciaCheckinPageState extends State<AsistenciaCheckinPage> {
  final AsistenciaApi _api = AsistenciaApi();

  bool _escaneando = false;
  bool _procesando = false;
  AsistenciaCheckinResultado? _ultimoResultado;
  String? _error;
  DateTime? _ultimoIntento;

  static const String _qrPrefix = 'CTRLAPP-ASISTENCIA|';
  static const Duration _pausaEntreIntentos = Duration(seconds: 2);

  Future<Position?> _obtenerUbicacion() async {
    try {
      final habilitado = await Geolocator.isLocationServiceEnabled();
      if (!habilitado) return null;

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _procesarCodigo(String raw) async {
    if (_procesando) return;

    final ahora = DateTime.now();
    if (_ultimoIntento != null && ahora.difference(_ultimoIntento!) < _pausaEntreIntentos) {
      return;
    }
    _ultimoIntento = ahora;

    final valor = raw.trim();
    if (!valor.startsWith(_qrPrefix)) {
      setState(() {
        _escaneando = false;
        _error = 'Este codigo QR no es de asistencia. Escanea el QR del conjunto.';
      });
      return;
    }

    final partes = valor.split('|');
    if (partes.length < 3) {
      setState(() {
        _escaneando = false;
        _error = 'El codigo QR esta incompleto o dañado.';
      });
      return;
    }
    final conjuntoId = partes[1];

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      final posicion = await _obtenerUbicacion();

      final resultado = await _api.checkin(
        conjuntoId: conjuntoId,
        qrPayload: valor,
        latitud: posicion?.latitude,
        longitud: posicion?.longitude,
      );
      if (!mounted) return;
      setState(() {
        _ultimoResultado = resultado;
        _escaneando = false;
      });
      final texto = resultado.tipo == 'ENTRADA'
          ? 'Entrada registrada en ${resultado.conjuntoNombre}'
          : 'Salida registrada en ${resultado.conjuntoNombre}';
      AppFeedback.showInfo(
        context,
        message: posicion == null ? '$texto. No se pudo verificar tu ubicacion.' : texto,
      );
    } catch (e) {
      if (!mounted) return;
      final msg = AppError.messageOf(e, fallback: 'No se pudo registrar la asistencia.');
      setState(() {
        // Si detecta un error se detiene el escaneo en vez de seguir
        // reintentando en bucle mientras la camara siga viendo el mismo QR.
        _escaneando = false;
        _error = msg;
      });
      AppFeedback.showError(context, message: msg);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Widget _buildResultadoCard() {
    final resultado = _ultimoResultado;
    if (resultado == null) return const SizedBox.shrink();

    final registro = resultado.registro;
    final esEntrada = resultado.tipo == 'ENTRADA';
    final tieneUbicacion = esEntrada
        ? registro.ubicacionEntrada != null
        : registro.ubicacionSalida != null;

    return Card(
      elevation: 0,
      color: (esEntrada ? AppTheme.green : AppTheme.primary).withValues(
        alpha: 0.08,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: esEntrada ? AppTheme.green : AppTheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  esEntrada ? Icons.login_rounded : Icons.logout_rounded,
                  color: esEntrada ? AppTheme.green : AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  esEntrada ? 'Entrada registrada' : 'Salida registrada',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Conjunto: ${resultado.conjuntoNombre}'),
            if (registro.horaEntrada != null)
              Text('Hora entrada: ${_formatHora(registro.horaEntrada!)}'),
            if (registro.horaSalida != null)
              Text('Hora salida: ${_formatHora(registro.horaSalida!)}'),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    tieneUbicacion ? Icons.location_on : Icons.location_off,
                    size: 14,
                    color: tieneUbicacion ? Colors.black54 : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tieneUbicacion ? 'Ubicacion registrada' : 'Sin ubicacion',
                    style: TextStyle(
                      fontSize: 12,
                      color: tieneUbicacion ? Colors.black54 : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            if (registro.observacion != null && registro.observacion!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  registro.observacion!,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatHora(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Marcar asistencia', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_escaneando)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        onDetect: (capture) {
                          for (final barcode in capture.barcodes) {
                            final raw = barcode.rawValue;
                            if (raw != null && raw.isNotEmpty) {
                              _procesarCodigo(raw);
                              break;
                            }
                          }
                        },
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                          ),
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => setState(() => _escaneando = false),
                        ),
                      ),
                      if (_procesando)
                        const ColoredBox(
                          color: Colors.black45,
                          child: Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 24),
              Icon(Icons.qr_code_scanner_rounded, size: 96, color: AppTheme.primary),
              const SizedBox(height: 16),
              const Text(
                'Escanea el codigo QR pegado en el sitio para registrar tu entrada o salida del dia.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear QR'),
                onPressed: () => setState(() {
                  _escaneando = true;
                  _error = null;
                }),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              _buildResultadoCard(),
            ],
          ],
        ),
      ),
    );
  }
}
