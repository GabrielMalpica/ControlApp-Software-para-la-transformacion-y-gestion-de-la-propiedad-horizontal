import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/api/integraciones_ia_api.dart';
import 'package:flutter_application_1/model/integracion_ia_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:intl/intl.dart';

/// Configuración → Integraciones IA (solo gerentes). Conexiones de Claude o
/// ChatGPT a ControlApp por MCP: quién las autorizó, qué permisos tienen, su
/// actividad, aprobaciones pendientes de alto riesgo y revocación.
class IntegracionesIaPage extends StatefulWidget {
  const IntegracionesIaPage({super.key});

  @override
  State<IntegracionesIaPage> createState() => _IntegracionesIaPageState();
}

final _formatoFecha = DateFormat('dd/MM/yyyy · h:mm a');

String _fecha(DateTime? valor) =>
    valor == null ? 'Nunca' : _formatoFecha.format(valor);

class _IntegracionesIaPageState extends State<IntegracionesIaPage> {
  final _api = IntegracionesIaApi();

  bool _cargando = true;
  String? _error;
  ConfiguracionIntegracionesIa? _config;
  List<ConexionIa> _conexiones = const [];
  List<AprobacionIa> _aprobaciones = const [];

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
      final resultados = await Future.wait([
        _api.configuracion(),
        _api.conexiones(),
        _api.aprobaciones(),
      ]);
      if (!mounted) return;
      setState(() {
        _config = resultados[0] as ConfiguracionIntegracionesIa;
        _conexiones = resultados[1] as List<ConexionIa>;
        _aprobaciones = resultados[2] as List<AprobacionIa>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<bool> _confirmar(String titulo, String mensaje, String accion) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(accion),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _ejecutar(Future<void> Function() accion, String exito) async {
    try {
      await accion();
      if (!mounted) return;
      AppFeedback.showInfo(context, message: exito);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context, message: AppError.messageOf(e));
    }
  }

  Future<void> _revocar(ConexionIa conexion) async {
    final ok = await _confirmar(
      'Revocar ${conexion.cliente}',
      'Dejará de poder actuar en ControlApp en máximo 30 segundos. Para volver a usarla habrá que conectarla de nuevo desde el asistente.',
      'Revocar',
    );
    if (!ok) return;
    await _ejecutar(() => _api.revocar(conexion.id), 'Integración revocada.');
  }

  Future<void> _revocarTodas() async {
    final ok = await _confirmar(
      'Revocar todas mis integraciones',
      'Ningún asistente de IA conectado con tu cuenta podrá seguir usando ControlApp.',
      'Revocar todas',
    );
    if (!ok) return;
    await _ejecutar(() async {
      await _api.revocarTodas();
    }, 'Integraciones revocadas.');
  }

  Future<void> _decidir(AprobacionIa aprobacion, bool aprobar) async {
    if (aprobar) {
      final ok = await _confirmar(
        'Aprobar operación',
        '${aprobacion.cliente} pidió: ${aprobacion.resumen}\n\nSi la apruebas, el asistente podrá ejecutarla durante los próximos 15 minutos.',
        'Aprobar',
      );
      if (!ok) return;
    }
    await _ejecutar(
      () => _api.decidir(aprobacion.id, aprobar: aprobar),
      aprobar ? 'Operación aprobada.' : 'Operación rechazada.',
    );
  }

  Future<void> _editarPermisos(ConexionIa conexion) async {
    final config = _config;
    if (config == null) return;
    final seleccion = conexion.permisos.toSet();
    final nuevos = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Permisos de ${conexion.cliente}',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Aquí solo puedes quitar permisos. Para agregar, vuelve a conectar desde el asistente.',
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final scope in conexion.permisos)
                        CheckboxListTile(
                          value: seleccion.contains(scope),
                          title: Text(config.tituloPermiso(scope)),
                          onChanged: (v) => setSheet(() {
                            if (v == true) {
                              seleccion.add(scope);
                            } else {
                              seleccion.remove(scope);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: seleccion.isEmpty
                      ? null
                      : () => Navigator.pop(ctx, seleccion.toList()),
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (nuevos == null) return;
    await _ejecutar(
      () => _api.reducirPermisos(conexion.id, nuevos),
      'Permisos actualizados.',
    );
  }

  Future<void> _verActividad(ConexionIa conexion) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scroll) => FutureBuilder<List<ActividadIa>>(
          future: _api.actividad(conexion.id),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text(AppError.messageOf(snap.error!)));
            }
            final items = snap.data ?? const <ActividadIa>[];
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Actividad de ${conexion.cliente}',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (items.isEmpty) const Text('Todavía no ha hecho nada.'),
                for (final a in items)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      a.fallo
                          ? Icons.block_outlined
                          : Icons.check_circle_outline,
                      color: a.fallo ? Colors.redAccent : Colors.green,
                    ),
                    title: Text(a.herramientaLegible),
                    subtitle: Text(
                      [
                        _fecha(a.creadoEn),
                        a.resultado,
                        if (a.mensaje != null) a.mensaje!,
                      ].join(' · '),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Integraciones IA')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_cargando && _config == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _Aviso(
                icono: Icons.error_outline,
                color: Colors.redAccent,
                texto: _error!,
                accion: TextButton(
                  onPressed: _cargar,
                  child: const Text('Reintentar'),
                ),
              )
            else ...[
              _Cabecera(config: _config!),
              if (_aprobaciones.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Pendientes de tu aprobación',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final a in _aprobaciones)
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            a.cliente,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(a.resumen),
                          const SizedBox(height: 4),
                          Text(
                            'Vence: ${_fecha(a.expiraEn)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _decidir(a, false),
                                child: const Text('Rechazar'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _decidir(a, true),
                                child: const Text('Aprobar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'Asistentes conectados',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_conexiones.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Ningún asistente de IA está conectado.'),
                ),
              for (final c in _conexiones)
                _TarjetaConexion(
                  conexion: c,
                  config: _config!,
                  onRevocar: c.activa || c.suspendida
                      ? () => _revocar(c)
                      : null,
                  onPermisos: c.propia && c.activa
                      ? () => _editarPermisos(c)
                      : null,
                  onActividad: () => _verActividad(c),
                ),
              if (_conexiones.any((c) => c.propia && c.activa)) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _revocarTodas,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Revocar todas mis integraciones'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  final ConfiguracionIntegracionesIa config;

  const _Cabecera({required this.config});

  @override
  Widget build(BuildContext context) {
    final url = config.urlServidor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usa ControlApp desde Claude o ChatGPT',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Conecta tu asistente con la dirección de abajo. Iniciarás sesión en una página de ControlApp (nunca le des tu contraseña al asistente) y elegirás qué puede hacer. Lo que cambia datos te pedirá confirmación, y lo de alto riesgo, tu aprobación aquí.',
            ),
            const SizedBox(height: 12),
            if (!config.habilitadoParaMi)
              const _Aviso(
                icono: Icons.lock_outline,
                color: Colors.orange,
                texto:
                    'Tu cuenta aún no tiene habilitada la conexión con IA. Pídesela al equipo técnico de ControlApp.',
              )
            else if (url == null)
              const _Aviso(
                icono: Icons.info_outline,
                color: Colors.blueGrey,
                texto: 'El servidor de integraciones aún no está publicado.',
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      url,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar dirección',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!context.mounted) return;
                      AppFeedback.showInfo(
                        context,
                        message: 'Dirección copiada.',
                      );
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaConexion extends StatelessWidget {
  final ConexionIa conexion;
  final ConfiguracionIntegracionesIa config;
  final VoidCallback? onRevocar;
  final VoidCallback? onPermisos;
  final VoidCallback onActividad;

  const _TarjetaConexion({
    required this.conexion,
    required this.config,
    required this.onRevocar,
    required this.onPermisos,
    required this.onActividad,
  });

  @override
  Widget build(BuildContext context) {
    final color = conexion.activa
        ? Colors.green
        : conexion.suspendida
        ? Colors.orange
        : Colors.grey;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conexion.cliente,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(conexion.estadoLegible),
                  backgroundColor: color.withValues(alpha: 0.12),
                  side: BorderSide(color: color),
                ),
              ],
            ),
            if (!conexion.propia) Text('Autorizada por ${conexion.gerente}'),
            Text('Autorizada: ${_fecha(conexion.autorizadaEn)}'),
            Text('Último uso: ${_fecha(conexion.ultimoUsoEn)}'),
            if (conexion.motivoRevocacion != null && !conexion.activa)
              Text('Motivo: ${conexion.motivoRevocacion}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final scope in conexion.permisos)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(config.tituloPermiso(scope)),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onActividad,
                  child: const Text('Actividad'),
                ),
                if (onPermisos != null)
                  TextButton(
                    onPressed: onPermisos,
                    child: const Text('Permisos'),
                  ),
                if (onRevocar != null)
                  TextButton(
                    onPressed: onRevocar,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                    child: const Text('Revocar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String texto;
  final Widget? accion;

  const _Aviso({
    required this.icono,
    required this.color,
    required this.texto,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
          if (accion != null) accion!,
        ],
      ),
    );
  }
}
