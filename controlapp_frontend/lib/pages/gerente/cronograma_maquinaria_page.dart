import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/cronograma_maquinaria_api.dart';
import '../../model/maquinaria_model.dart';
import '../../model/necesidad_maquinaria_model.dart';
import '../../service/app_error.dart';
import '../../service/app_feedback.dart';
import '../../service/theme.dart';
import '../../widgets/maquinaria_conflict_dialog.dart';

/// Cronograma general de maquinaria de la empresa.
///
/// Las preventivas solo declaran QUÉ TIPO de máquina necesitan. Aquí se ven, mes a
/// mes y con todos los conjuntos a la vez, cuántas máquinas de cada tipo hacen
/// falta cada día y se asignan las máquinas reales.
class CronogramaMaquinariaPage extends StatefulWidget {
  final String empresaNit;

  const CronogramaMaquinariaPage({super.key, required this.empresaNit});

  @override
  State<CronogramaMaquinariaPage> createState() =>
      _CronogramaMaquinariaPageState();
}

class _CronogramaMaquinariaPageState extends State<CronogramaMaquinariaPage> {
  final _api = CronogramaMaquinariaApi();

  late int _anio;
  late int _mes;

  bool _cargando = true;
  bool _procesando = false;
  String? _error;
  bool _soloPendientes = false;
  TipoMaquinariaFlutter? _filtroTipo;

  CronogramaMaquinariaResponse? _data;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _anio = ahora.year;
    _mes = ahora.month;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final data = await _api.listarNecesidades(
        empresaNit: widget.empresaNit,
        anio: _anio,
        mes: _mes,
        tipo: _filtroTipo?.backendValue,
        soloPendientes: _soloPendientes,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(e);
        _cargando = false;
      });
    }
  }

  void _cambiarMes(int delta) {
    final base = DateTime(_anio, _mes + delta, 1);
    setState(() {
      _anio = base.year;
      _mes = base.month;
    });
    _cargar();
  }

  List<NecesidadMaquinaria> get _necesidades => _data?.necesidades ?? const [];

  /// Necesidades agrupadas por tipo, para pintarlas por bloques.
  Map<String, List<NecesidadMaquinaria>> get _porTipo {
    final salida = <String, List<NecesidadMaquinaria>>{};
    for (final item in _necesidades) {
      (salida[item.tipoLabel] ??= []).add(item);
    }
    return salida;
  }

  Future<void> _abrirNecesidad(NecesidadMaquinaria necesidad) async {
    final candidatas =
        _data?.maquinariasPorTipo[necesidad.tipoRaw] ??
        const <MaquinaCandidata>[];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${necesidad.tipoLabel} · ${necesidad.conjuntoNombre}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('EEEE d MMMM', 'es').format(necesidad.fecha)} · '
                '${necesidad.asignaciones.length}/${necesidad.cantidadRequerida} asignada(s)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),

              const Text(
                'Tareas que la requieren',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              ...necesidad.tareas.map(
                (tarea) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• ${tarea.descripcion} '
                    '(${DateFormat('HH:mm').format(tarea.fechaInicio)}-'
                    '${DateFormat('HH:mm').format(tarea.fechaFin)})'
                    '${tarea.operariosNombres.isEmpty ? '' : ' · ${tarea.operariosNombres.join(', ')}'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),

              if (necesidad.asignaciones.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Máquinas asignadas',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                ...necesidad.asignaciones.map(
                  (asignacion) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.precision_manufacturing),
                    title: Text(
                      '${asignacion.maquinariaNombre} · ${asignacion.marca}',
                    ),
                    subtitle: Text(
                      'Entrega ${DateFormat('dd/MM').format(asignacion.entrega)} · '
                      'Recogida ${DateFormat('dd/MM').format(asignacion.recogida)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off, color: Colors.red),
                      tooltip: 'Liberar',
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _liberar(asignacion.usoId);
                      },
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              Text(
                necesidad.pendientes > 0
                    ? 'Asignar máquina (faltan ${necesidad.pendientes})'
                    : 'Asignar otra máquina',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              if (candidatas.isEmpty)
                Text(
                  'No hay máquinas operativas de este tipo en la empresa.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: candidatas.map((maquina) {
                      final sugerida =
                          maquina.id == necesidad.maquinariaSugeridaId;
                      final yaAsignada = necesidad.asignaciones.any(
                        (item) => item.maquinariaId == maquina.id,
                      );
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          sugerida ? Icons.star : Icons.precision_manufacturing,
                          color: sugerida ? Colors.amber.shade800 : null,
                        ),
                        title: Text(maquina.etiqueta),
                        subtitle: sugerida
                            ? const Text('Sugerida por la preventiva')
                            : null,
                        enabled: !yaAsignada,
                        onTap: yaAsignada
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                _asignar(necesidad, maquina);
                              },
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _asignar(
    NecesidadMaquinaria necesidad,
    MaquinaCandidata maquina,
  ) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await _api.asignarMaquinaria(
        empresaNit: widget.empresaNit,
        tareaIds: necesidad.tareas.map((tarea) => tarea.tareaId).toList(),
        maquinariaId: maquina.id,
      );
      await _cargar();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('${maquina.nombre} asignada.')),
      );
    } catch (e) {
      if (!mounted) return;
      if (hasMaquinariaConflictDetails(e)) {
        await showMaquinariaConflictDialog(
          context,
          e,
          fallbackTitle: 'La máquina no está disponible',
        );
      } else {
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(content: Text(AppError.messageOf(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _liberar(int usoId) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await _api.liberarAsignacion(empresaNit: widget.empresaNit, usoId: usoId);
      await _cargar();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Maquinaria liberada.')),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesLabel = DateFormat(
      'MMMM yyyy',
      'es',
    ).format(DateTime(_anio, _mes)).toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Cronograma de maquinaria',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBarraFiltros(mesLabel),
          if (_procesando) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildError()
                : _buildLista(),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraFiltros(String mesLabel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _cargando ? null : () => _cambiarMes(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  mesLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: _cargando ? null : () => _cambiarMes(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TipoMaquinariaFlutter?>(
                  isExpanded: true,
                  initialValue: _filtroTipo,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<TipoMaquinariaFlutter?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ...TipoMaquinariaFlutter.values.map(
                      (tipo) => DropdownMenuItem<TipoMaquinariaFlutter?>(
                        value: tipo,
                        child: Text(tipo.label),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _filtroTipo = value);
                    _cargar();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _soloPendientes,
                label: const Text('Solo pendientes'),
                onSelected: (value) {
                  setState(() => _soloPendientes = value);
                  _cargar();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista() {
    final grupos = _porTipo;
    if (grupos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay necesidades de maquinaria en el cronograma publicado de este mes.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final tipos = grupos.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: tipos.length,
      itemBuilder: (_, index) {
        final tipo = tipos[index];
        final items = grupos[tipo]!;
        final pendientes = items.fold<int>(
          0,
          (acc, item) => acc + item.pendientes,
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            initiallyExpanded: pendientes > 0,
            leading: Icon(
              Icons.precision_manufacturing,
              color: pendientes > 0
                  ? Colors.orange.shade800
                  : Colors.green.shade700,
            ),
            title: Text(
              tipo,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              pendientes > 0
                  ? '$pendientes necesidad(es) sin asignar'
                  : 'Todo asignado',
              style: TextStyle(
                fontSize: 12,
                color: pendientes > 0
                    ? Colors.orange.shade900
                    : Colors.green.shade800,
              ),
            ),
            children: items.map(_buildFilaNecesidad).toList(),
          ),
        );
      },
    );
  }

  Widget _buildFilaNecesidad(NecesidadMaquinaria necesidad) {
    final cubierta = necesidad.cubierta;

    return ListTile(
      onTap: _procesando ? null : () => _abrirNecesidad(necesidad),
      leading: CircleAvatar(
        backgroundColor: cubierta
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.18),
        child: Text(
          '${necesidad.asignaciones.length}/${necesidad.cantidadRequerida}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: cubierta ? Colors.green.shade900 : Colors.orange.shade900,
          ),
        ),
      ),
      title: Text(necesidad.conjuntoNombre),
      subtitle: Text(
        '${DateFormat('EEE d MMM', 'es').format(necesidad.fecha)} · '
        '${necesidad.tareas.length} tarea(s)',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Icon(
        cubierta ? Icons.check_circle : Icons.add_circle_outline,
        color: cubierta ? Colors.green.shade700 : Colors.orange.shade800,
      ),
    );
  }
}
