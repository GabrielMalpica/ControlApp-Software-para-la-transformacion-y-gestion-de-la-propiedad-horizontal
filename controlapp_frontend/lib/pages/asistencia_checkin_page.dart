import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/asistencia_api.dart';
import '../model/asistencia_model.dart';
import '../service/app_error.dart';
import '../service/app_feedback.dart';
import '../service/theme.dart';
import '../service/ubicacion_service.dart';
import '../widgets/ayuda_ubicacion.dart';

class AsistenciaCheckinPage extends StatefulWidget {
  const AsistenciaCheckinPage({super.key});

  @override
  State<AsistenciaCheckinPage> createState() => _AsistenciaCheckinPageState();
}

class _AsistenciaCheckinPageState extends State<AsistenciaCheckinPage> {
  final AsistenciaApi _api = AsistenciaApi();

  bool _escaneando = false;
  bool _procesando = false;
  bool _buscandoUbicacion = false;
  AsistenciaCheckinResultado? _ultimoResultado;
  String? _error;
  DateTime? _ultimoIntento;

  /// Ubicación tomada al abrir el escáner. La asistencia no se registra sin
  /// ubicación: es la trazabilidad de dónde marcó el operario.
  Position? _posicion;
  FalloUbicacion? _falloUbicacion;

  static const String _qrPrefix = 'CTRLAPP-ASISTENCIA|';
  static const Duration _pausaEntreIntentos = Duration(seconds: 2);

  /// Una ubicación de hasta esta edad sirve al registrar (el operario sigue
  /// frente al QR); si es más vieja se pide otra.
  static const Duration _vigenciaUbicacion = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _revisarPermiso();
  }

  /// Si el permiso ya está negado se avisa desde el principio, antes de que
  /// el operario intente escanear.
  Future<void> _revisarPermiso() async {
    final permiso = await UbicacionDispositivo.permiso();
    if (!mounted || permiso != PermisoUbicacion.denegado) return;
    setState(() => _falloUbicacion = FalloUbicacion.permisoDenegado);
  }

  /// Primero la ubicación, después la cámara: sin permiso de ubicación no se
  /// abre el escáner.
  Future<void> _iniciarEscaneo() async {
    if (_buscandoUbicacion) return;
    setState(() {
      _buscandoUbicacion = true;
      _falloUbicacion = null;
      _error = null;
    });
    try {
      final posicion = await UbicacionDispositivo.obtener();
      if (!mounted) return;
      setState(() {
        _posicion = posicion;
        _escaneando = true;
      });
    } on UbicacionException catch (e) {
      if (!mounted) return;
      setState(() => _falloUbicacion = e.fallo);
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  Future<Position> _ubicacionParaRegistrar() async {
    final actual = _posicion;
    if (actual != null &&
        DateTime.now().difference(actual.timestamp) <= _vigenciaUbicacion) {
      return actual;
    }
    final nueva = await UbicacionDispositivo.obtener(
      espera: const Duration(seconds: 15),
    );
    _posicion = nueva;
    return nueva;
  }

  Future<void> _procesarCodigo(String raw) async {
    if (_procesando) return;

    final ahora = DateTime.now();
    if (_ultimoIntento != null &&
        ahora.difference(_ultimoIntento!) < _pausaEntreIntentos) {
      return;
    }
    _ultimoIntento = ahora;

    final valor = raw.trim();
    if (!valor.startsWith(_qrPrefix)) {
      setState(() {
        _escaneando = false;
        _error =
            'Este codigo QR no es de asistencia. Escanea el QR del conjunto.';
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
      final posicion = await _ubicacionParaRegistrar();

      final resultado = await _api.checkin(
        conjuntoId: conjuntoId,
        qrPayload: valor,
        latitud: posicion.latitude,
        longitud: posicion.longitude,
        precisionMetros: posicion.accuracy,
      );
      if (!mounted) return;
      setState(() {
        _ultimoResultado = resultado;
        _escaneando = false;
      });
      final texto = resultado.tipo == 'ENTRADA'
          ? 'Entrada registrada en ${resultado.conjuntoNombre}'
          : 'Salida registrada en ${resultado.conjuntoNombre}';
      AppFeedback.showInfo(context, message: texto);
    } on UbicacionException catch (e) {
      if (!mounted) return;
      setState(() {
        _escaneando = false;
        _falloUbicacion = e.fallo;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = AppError.messageOf(
        e,
        fallback: 'No se pudo registrar la asistencia.',
      );
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
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
            if (registro.observacion != null &&
                registro.observacion!.isNotEmpty)
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
        title: const Text(
          'Marcar asistencia',
          style: TextStyle(color: Colors.white),
        ),
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
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 24),
              Icon(
                Icons.qr_code_scanner_rounded,
                size: 96,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Escanea el código QR pegado en el sitio para registrar tu entrada o salida. Debes estar en el conjunto y permitir la ubicación: sin ella no se registra la asistencia.',
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
                icon: _buscandoUbicacion
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.qr_code_scanner),
                label: Text(
                  _buscandoUbicacion
                      ? 'Buscando tu ubicación...'
                      : 'Escanear QR',
                ),
                onPressed: _buscandoUbicacion ? null : _iniciarEscaneo,
              ),
              const SizedBox(height: 20),
              if (_falloUbicacion != null)
                _AvisoSinUbicacion(
                  fallo: _falloUbicacion!,
                  onReintentar: _iniciarEscaneo,
                ),
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

/// Por qué no se puede escanear todavía y cómo arreglarlo.
class _AvisoSinUbicacion extends StatelessWidget {
  const _AvisoSinUbicacion({required this.fallo, required this.onReintentar});

  final FalloUbicacion fallo;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_off_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Necesitamos tu ubicación',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(UbicacionException(fallo).mensaje),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (fallo != FalloUbicacion.sinSenal)
                OutlinedButton.icon(
                  onPressed: () => mostrarAyudaUbicacion(context),
                  icon: const Icon(Icons.help_outline_rounded),
                  label: const Text('Cómo activarla'),
                ),
              FilledButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Intentar de nuevo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
