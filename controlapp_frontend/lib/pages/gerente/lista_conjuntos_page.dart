import 'package:flutter/material.dart';

import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../service/theme.dart';
import 'crear_conjunto_page.dart';
import 'detalle_conjunto_page.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

const List<String> _diasSemana = <String>[
  'LUNES',
  'MARTES',
  'MIERCOLES',
  'JUEVES',
  'VIERNES',
  'SABADO',
  'DOMINGO',
];

const Map<String, String> _diaLabel = <String, String>{
  'LUNES': 'Lunes',
  'MARTES': 'Martes',
  'MIERCOLES': 'Miercoles',
  'JUEVES': 'Jueves',
  'VIERNES': 'Viernes',
  'SABADO': 'Sabado',
  'DOMINGO': 'Domingo',
};

class _HorarioEditable {
  TimeOfDay? apertura;
  TimeOfDay? cierre;
  TimeOfDay? descansoInicio;
  TimeOfDay? descansoFin;
}

class ListaConjuntosPage extends StatefulWidget {
  final String nit;

  const ListaConjuntosPage({super.key, required this.nit});

  @override
  State<ListaConjuntosPage> createState() => _ListaConjuntosPageState();
}

class _ListaConjuntosPageState extends State<ListaConjuntosPage> {
  final GerenteApi _api = GerenteApi();
  late Future<List<Conjunto>> _futureConjuntos;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadConjuntos();
  }

  void _loadConjuntos() {
    setState(() {
      _futureConjuntos = _api.listarConjuntos();
    });
  }

  Future<void> _refreshConjuntos() async {
    _loadConjuntos();
    await _futureConjuntos;
  }

  String _normalizarDia(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ü', 'U');
  }

  TimeOfDay? _parseHora(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatHora(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  int _diaOrden(String dia) {
    final idx = _diasSemana.indexOf(_normalizarDia(dia));
    return idx < 0 ? 999 : idx;
  }

  String _resumenHorarios(Conjunto c) {
    if (c.horarios.isEmpty) return 'Sin horario configurado';
    final ordenados = [...c.horarios]
      ..sort((a, b) => _diaOrden(a.dia).compareTo(_diaOrden(b.dia)));
    final top = ordenados.take(2).map((h) {
      final dia = _normalizarDia(h.dia);
      final label = _diaLabel[dia]?.substring(0, 3) ?? dia.substring(0, 3);
      return '$label ${h.horaApertura}-${h.horaCierre}';
    }).toList();
    if (ordenados.length > 2) top.add('+${ordenados.length - 2} mas');
    return top.join(' | ');
  }

  Color _estadoColor(bool activo) =>
      activo ? const Color(0xFF1F8F4D) : const Color(0xFFC0392B);

  String _valorMensual(double? valor) {
    if (valor == null) return 'Sin valor mensual';
    return '\$${valor.toStringAsFixed(0)} / mes';
  }

  Future<void> _confirmarEliminar(Conjunto c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar conjunto'),
        content: Text('Seguro que deseas eliminar "${c.nombre}" (${c.nit})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.eliminarConjunto(c.nit);
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('Conjunto eliminado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      _hasChanges = true;
      _loadConjuntos();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editarHorarios(Conjunto c) async {
    final byDay = <String, _HorarioEditable>{
      for (final d in _diasSemana) d: _HorarioEditable(),
    };

    for (final h in c.horarios) {
      final key = _normalizarDia(h.dia);
      final item = byDay[key];
      if (item == null) continue;
      item.apertura = _parseHora(h.horaApertura);
      item.cierre = _parseHora(h.horaCierre);
      item.descansoInicio = _parseHora(h.descansoInicio);
      item.descansoFin = _parseHora(h.descansoFin);
    }

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        bool saving = false;
        String? error;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickTime({
              required TimeOfDay? current,
              required void Function(TimeOfDay) onSelected,
            }) async {
              final picked = await showTimePicker(
                context: context,
                initialTime: current ?? const TimeOfDay(hour: 8, minute: 0),
              );
              if (picked == null) return;
              setModalState(() => onSelected(picked));
            }

            Future<void> guardar() async {
              final payload = <Map<String, String>>[];
              for (final dia in _diasSemana) {
                final h = byDay[dia]!;
                final aper = h.apertura;
                final cier = h.cierre;
                final dIni = h.descansoInicio;
                final dFin = h.descansoFin;

                if ((aper == null) != (cier == null)) {
                  setModalState(
                    () => error =
                        'Completa apertura y cierre en ${_diaLabel[dia]}.',
                  );
                  return;
                }
                if ((dIni == null) != (dFin == null)) {
                  setModalState(
                    () => error =
                        'Completa descanso inicio y fin en ${_diaLabel[dia]}.',
                  );
                  return;
                }
                if (aper == null && cier == null) {
                  if (dIni != null || dFin != null) {
                    setModalState(
                      () => error =
                          'No puedes definir descanso sin jornada en ${_diaLabel[dia]}.',
                    );
                    return;
                  }
                  continue;
                }
                if (_toMinutes(aper!) >= _toMinutes(cier!)) {
                  setModalState(
                    () => error =
                        'Apertura debe ser menor al cierre en ${_diaLabel[dia]}.',
                  );
                  return;
                }

                final item = <String, String>{
                  'dia': dia,
                  'horaApertura': _formatHora(aper),
                  'horaCierre': _formatHora(cier),
                };
                if (dIni != null && dFin != null) {
                  final a = _toMinutes(aper);
                  final ci = _toMinutes(cier);
                  final di = _toMinutes(dIni);
                  final df = _toMinutes(dFin);
                  if (!(a < di && di < df && df < ci)) {
                    setModalState(
                      () => error =
                          'El descanso de ${_diaLabel[dia]} debe estar dentro de la jornada.',
                    );
                    return;
                  }
                  item['descansoInicio'] = _formatHora(dIni);
                  item['descansoFin'] = _formatHora(dFin);
                }
                payload.add(item);
              }

              setModalState(() {
                saving = true;
                error = null;
              });
              try {
                await _api.actualizarConjunto(c.nit, horarios: payload);
                if (!mounted || !sheetContext.mounted) return;
                Navigator.of(sheetContext).pop(true);
                AppFeedback.showFromSnackBar(
                  this.context,
                  const SnackBar(
                    content: Text('Horarios actualizados'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                setModalState(() {
                  saving = false;
                  error = 'No fue posible guardar: $e';
                });
              }
            }

            return SafeArea(
              child: Container(
                margin: const EdgeInsets.only(top: 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Editar horario - ${c.nombre}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Configura apertura, cierre y descanso por dia.',
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: _diasSemana.length,
                        itemBuilder: (_, i) {
                          final dia = _diasSemana[i];
                          final h = byDay[dia]!;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _diaLabel[dia]!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: saving
                                            ? null
                                            : () => setModalState(
                                                () => byDay[dia] =
                                                    _HorarioEditable(),
                                              ),
                                        child: const Text('Limpiar'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _timeBox(
                                        label: 'Apertura',
                                        value: h.apertura == null
                                            ? '--:--'
                                            : _formatHora(h.apertura!),
                                        onTap: saving
                                            ? null
                                            : () => pickTime(
                                                current: h.apertura,
                                                onSelected: (v) =>
                                                    h.apertura = v,
                                              ),
                                      ),
                                      _timeBox(
                                        label: 'Cierre',
                                        value: h.cierre == null
                                            ? '--:--'
                                            : _formatHora(h.cierre!),
                                        onTap: saving
                                            ? null
                                            : () => pickTime(
                                                current: h.cierre,
                                                onSelected: (v) => h.cierre = v,
                                              ),
                                      ),
                                      _timeBox(
                                        label: 'Desc. ini',
                                        value: h.descansoInicio == null
                                            ? '--:--'
                                            : _formatHora(h.descansoInicio!),
                                        onTap: saving
                                            ? null
                                            : () => pickTime(
                                                current: h.descansoInicio,
                                                onSelected: (v) =>
                                                    h.descansoInicio = v,
                                              ),
                                      ),
                                      _timeBox(
                                        label: 'Desc. fin',
                                        value: h.descansoFin == null
                                            ? '--:--'
                                            : _formatHora(h.descansoFin!),
                                        onTap: saving
                                            ? null
                                            : () => pickTime(
                                                current: h.descansoFin,
                                                onSelected: (v) =>
                                                    h.descansoFin = v,
                                              ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(sheetContext, false),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: saving ? null : guardar,
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(saving ? 'Guardando...' : 'Guardar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (updated == true) {
      _loadConjuntos();
    }
  }

  Widget _timeBox({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: 152,
      child: OutlinedButton(
        onPressed: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, _hasChanges),
        ),
        title: const Text('Conjuntos', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Crear conjunto',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CrearConjuntoPage(nit: widget.nit),
                ),
              ).then((changed) {
                if (changed == true) {
                  _hasChanges = true;
                  _loadConjuntos();
                  if (!mounted) return;
                  AppFeedback.showFromSnackBar(
                    context,
                    const SnackBar(
                      content: Text('✅ Conjunto creado correctamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              });
            },
            icon: const Icon(Icons.add_business, color: Colors.white),
          ),
        ],
      ),
      body: FutureBuilder<List<Conjunto>>(
        future: _futureConjuntos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 42),
                  const SizedBox(height: 8),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadConjuntos,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final conjuntos = [...(snapshot.data ?? [])]
            ..sort(
              (a, b) =>
                  a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
            );

          if (conjuntos.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshConjuntos,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 130),
                  Icon(Icons.apartment_outlined, size: 58, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    'No hay conjuntos registrados.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final activos = conjuntos.where((c) => c.activo).length;
          final conHorario = conjuntos
              .where((c) => c.horarios.isNotEmpty)
              .length;

          return RefreshIndicator(
            onRefresh: _refreshConjuntos,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.96),
                        const Color(0xFF118550),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resumen de conjuntos',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _stat('Total', '${conjuntos.length}'),
                          const SizedBox(width: 8),
                          _stat('Activos', '$activos'),
                          const SizedBox(width: 8),
                          _stat('Con horario', '$conHorario'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...conjuntos.map(
                  (c) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.nombre,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _estadoColor(
                                    c.activo,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  c.activo ? 'Activo' : 'Inactivo',
                                  style: TextStyle(
                                    color: _estadoColor(c.activo),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('NIT: ${c.nit}'),
                          const SizedBox(height: 3),
                          Text(c.direccion),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill(
                                _valorMensual(c.valorMensual),
                                Icons.payments_outlined,
                              ),
                              _pill(
                                '${c.operarios.length} operarios',
                                Icons.groups_2_outlined,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F7F4),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 16,
                                  color: Color(0xFF365D49),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _resumenHorarios(c),
                                    style: const TextStyle(
                                      color: Color(0xFF2D5641),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DetalleConjuntoPage(
                                          conjuntoNit: c.nit,
                                          modoEdicionBasico: true,
                                        ),
                                      ),
                                    ).then((_) => _loadConjuntos());
                                  },
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Editar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _editarHorarios(c),
                                  icon: const Icon(Icons.access_time, size: 18),
                                  label: const Text('Horario'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Eliminar',
                                onPressed: () => _confirmarEliminar(c),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Detalle',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DetalleConjuntoPage(
                                        conjuntoNit: c.nit,
                                      ),
                                    ),
                                  ).then((_) => _loadConjuntos());
                                },
                                icon: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5F1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF3E6653)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF355845),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
