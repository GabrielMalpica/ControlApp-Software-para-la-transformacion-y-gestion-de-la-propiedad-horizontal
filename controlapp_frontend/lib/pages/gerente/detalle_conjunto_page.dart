import 'package:flutter/material.dart';

import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../model/usuario_model.dart';
import '../../service/theme.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

const Map<String, int> _dayOrder = <String, int>{
  'LUNES': 1,
  'MARTES': 2,
  'MIERCOLES': 3,
  'JUEVES': 4,
  'VIERNES': 5,
  'SABADO': 6,
  'DOMINGO': 7,
};

const Map<String, String> _dayLabel = <String, String>{
  'LUNES': 'Lunes',
  'MARTES': 'Martes',
  'MIERCOLES': 'Miercoles',
  'JUEVES': 'Jueves',
  'VIERNES': 'Viernes',
  'SABADO': 'Sabado',
  'DOMINGO': 'Domingo',
};

class DetalleConjuntoPage extends StatefulWidget {
  final String conjuntoNit;
  final bool modoEdicionBasico;

  const DetalleConjuntoPage({
    super.key,
    required this.conjuntoNit,
    this.modoEdicionBasico = false,
  });

  @override
  State<DetalleConjuntoPage> createState() => _DetalleConjuntoPageState();
}

class _DetalleConjuntoPageState extends State<DetalleConjuntoPage> {
  final GerenteApi _api = GerenteApi();

  late Future<Conjunto> _futureConjunto;

  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _direccionCtrl = TextEditingController();
  final TextEditingController _correoCtrl = TextEditingController();
  final TextEditingController _valorMensualCtrl = TextEditingController();

  List<Usuario> _adminsCatalogo = <Usuario>[];
  List<Usuario> _operariosCatalogo = <Usuario>[];
  bool _cargandoCatalogos = false;

  bool _editMode = false;
  bool _saving = false;
  bool _formInicializado = false;

  bool _activo = true;
  DateTime? _fechaInicioContrato;
  DateTime? _fechaFinContrato;
  String? _adminSeleccionadoId;
  Set<String> _operariosSeleccionadosIds = <String>{};
  List<Map<String, dynamic>> _ubicacionesEditables = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _editMode = widget.modoEdicionBasico;
    _reloadConjunto();
    _cargarCatalogos();
  }

  void _reloadConjunto() {
    _futureConjunto = _api.obtenerConjunto(widget.conjuntoNit);
  }

  Future<void> _refreshConjunto() async {
    setState(_reloadConjunto);
    await _futureConjunto;
  }

  Future<void> _cargarCatalogos() async {
    setState(() => _cargandoCatalogos = true);
    try {
      final admins = await _api.listarUsuarios(rol: 'administrador');
      final operarios = await _api.listarUsuarios(rol: 'operario');
      if (!mounted) return;
      setState(() {
        _adminsCatalogo = admins;
        _operariosCatalogo = operarios;
        _cargandoCatalogos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoCatalogos = false);
    }
  }

  void _inicializarForm(Conjunto c) {
    if (_formInicializado) return;

    _nombreCtrl.text = c.nombre;
    _direccionCtrl.text = c.direccion;
    _correoCtrl.text = c.correo;
    _valorMensualCtrl.text = c.valorMensual?.toStringAsFixed(0) ?? '';

    _activo = c.activo;
    _fechaInicioContrato = c.fechaInicioContrato;
    _fechaFinContrato = c.fechaFinContrato;
    _adminSeleccionadoId = c.administradorId;
    _operariosSeleccionadosIds = c.operarios.map((e) => e.cedula).toSet();
    _ubicacionesEditables = c.ubicaciones
        .map<Map<String, dynamic>>(
          (u) => <String, dynamic>{
            'nombre': u.nombre,
            'elementos': u.elementos
                .map((e) => e.nombre)
                .toList(growable: true),
          },
        )
        .toList(growable: true);

    _formInicializado = true;
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      _formInicializado = false;
    });
  }

  String _normalizeDay(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll('\u00C1', 'A')
        .replaceAll('\u00C9', 'E')
        .replaceAll('\u00CD', 'I')
        .replaceAll('\u00D3', 'O')
        .replaceAll('\u00DA', 'U')
        .replaceAll('\u00DC', 'U');
  }

  int _sortDay(String raw) => _dayOrder[_normalizeDay(raw)] ?? 99;

  String _dayText(String raw) {
    final key = _normalizeDay(raw);
    return _dayLabel[key] ?? raw;
  }

  String _dateText(DateTime? value) {
    if (value == null) return 'Sin definir';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  String _valorMensualText(double? value) {
    if (value == null) return 'Sin valor';
    return '\$${value.toStringAsFixed(0)}';
  }

  void _showSnack(String text, {Color color = Colors.green}) {
    AppFeedback.showFromSnackBar(
      context,
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  Future<void> _seleccionarFecha({
    required DateTime? actual,
    required ValueChanged<DateTime> onSelected,
    required String helpText,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 8)),
      helpText: helpText,
    );
    if (picked != null) {
      onSelected(picked);
    }
  }

  List<Map<String, dynamic>> _ubicacionesPayload() {
    final payload = <Map<String, dynamic>>[];

    for (final item in _ubicacionesEditables) {
      final nombre = (item['nombre'] ?? '').toString().trim();
      if (nombre.isEmpty) continue;

      final rawElementos = (item['elementos'] as List?) ?? const [];
      final elementos = rawElementos
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();

      payload.add(<String, dynamic>{'nombre': nombre, 'elementos': elementos});
    }

    return payload;
  }

  Future<void> _guardarCambios(Conjunto c) async {
    final rawValor = _valorMensualCtrl.text.trim();
    double? valorMensual;
    if (rawValor.isNotEmpty) {
      valorMensual = double.tryParse(rawValor.replaceAll(',', '.'));
      if (valorMensual == null) {
        _showSnack('Valor mensual invalido.', color: Colors.red);
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await _api.actualizarConjunto(
        c.nit,
        nombre: _nombreCtrl.text.trim(),
        direccion: _direccionCtrl.text.trim(),
        correo: _correoCtrl.text.trim(),
        activo: _activo,
        valorMensual: valorMensual,
        fechaInicioContrato: _fechaInicioContrato,
        fechaFinContrato: _fechaFinContrato,
        administradorId: _adminSeleccionadoId,
        operariosIds: _operariosSeleccionadosIds.toList(),
        ubicaciones: _ubicacionesPayload(),
      );

      if (!mounted) return;
      _showSnack('Conjunto actualizado correctamente.');
      setState(() {
        _editMode = false;
        _formInicializado = false;
        _reloadConjunto();
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error al actualizar: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _correoCtrl.dispose();
    _valorMensualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Detalle del conjunto',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _refreshConjunto,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            tooltip: _editMode ? 'Cancelar edicion' : 'Editar',
            onPressed: _toggleEditMode,
            icon: Icon(
              _editMode ? Icons.close : Icons.edit_outlined,
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: FutureBuilder<Conjunto>(
        future: _futureConjunto,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 46,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No fue posible cargar el conjunto.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _refreshConjunto,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          final c = snapshot.data!;
          if (_editMode) _inicializarForm(c);

          return RefreshIndicator(
            onRefresh: _refreshConjunto,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _headerHero(c),
                const SizedBox(height: 12),
                _editMode ? _editBasicsCard() : _generalInfoCard(c),
                const SizedBox(height: 12),
                _administradorCard(c),
                const SizedBox(height: 12),
                _operariosCard(c),
                const SizedBox(height: 12),
                _horariosCard(c),
                const SizedBox(height: 12),
                _ubicacionesCard(c),
                if (c.consignasEspeciales.isNotEmpty ||
                    c.valorAgregado.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _textosCard(c),
                ],
                if (_editMode) ...[
                  const SizedBox(height: 12),
                  _editActionsCard(c),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _headerHero(Conjunto c) {
    final statusColor = c.activo
        ? const Color(0xFF2E9B57)
        : const Color(0xFFC73D37);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.97),
            const Color(0xFF10814D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.apartment, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'NIT: ${c.nit}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  c.activo ? 'Activo' : 'Inactivo',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.direccion,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.mail_outline, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.correo,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatPill(label: 'Operarios', value: '${c.operarios.length}'),
              _StatPill(label: 'Ubicaciones', value: '${c.ubicaciones.length}'),
              _StatPill(label: 'Horarios', value: '${c.horarios.length}'),
              _StatPill(
                label: 'Valor',
                value: _valorMensualText(c.valorMensual),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _generalInfoCard(Conjunto c) {
    return _SectionCard(
      icon: Icons.info_outline,
      title: 'Informacion general',
      subtitle: 'Contrato, servicio y estado',
      child: Column(
        children: [
          _infoRow('Inicio contrato', _dateText(c.fechaInicioContrato)),
          _infoRow('Fin contrato', _dateText(c.fechaFinContrato)),
          _infoRow('Valor mensual', _valorMensualText(c.valorMensual)),
          _infoRow('Estado', c.activo ? 'Activo' : 'Inactivo'),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tipo de servicio',
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (c.tipoServicio.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No definido',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: c.tipoServicio
                  .map(
                    (t) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6F2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          color: Color(0xFF295845),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _editBasicsCard() {
    return _SectionCard(
      icon: Icons.edit_note_outlined,
      title: 'Edicion basica',
      subtitle: 'Nombre, contacto, contrato y estado',
      child: Column(
        children: [
          _inputField(label: 'Nombre', controller: _nombreCtrl),
          const SizedBox(height: 10),
          _inputField(label: 'Direccion', controller: _direccionCtrl),
          const SizedBox(height: 10),
          _inputField(label: 'Correo', controller: _correoCtrl),
          const SizedBox(height: 10),
          _inputField(
            label: 'Valor mensual',
            controller: _valorMensualCtrl,
            number: true,
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _activo,
            title: const Text('Conjunto activo'),
            subtitle: const Text(
              'Cuando esta inactivo no se programa servicio nuevo.',
            ),
            onChanged: (value) => setState(() => _activo = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _dateTile(
                  label: 'Inicio contrato',
                  value: _fechaInicioContrato,
                  onTap: () => _seleccionarFecha(
                    actual: _fechaInicioContrato,
                    helpText: 'Fecha de inicio de contrato',
                    onSelected: (d) => setState(() => _fechaInicioContrato = d),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateTile(
                  label: 'Fin contrato',
                  value: _fechaFinContrato,
                  onTap: () => _seleccionarFecha(
                    actual: _fechaFinContrato,
                    helpText: 'Fecha de finalizacion de contrato',
                    onSelected: (d) => setState(() => _fechaFinContrato = d),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _administradorCard(Conjunto c) {
    return _SectionCard(
      icon: Icons.badge_outlined,
      title: 'Administrador',
      subtitle: _editMode ? 'Selecciona el administrador del conjunto' : null,
      child: !_editMode
          ? Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    c.administradorNombre ?? 'No asignado',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          : _administradorDropdown(),
    );
  }

  Widget _administradorDropdown() {
    if (_cargandoCatalogos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text('Sin administrador'),
      ),
      ..._adminsCatalogo.map(
        (u) => DropdownMenuItem<String>(
          value: u.cedula,
          child: Text('${u.nombre} (${u.cedula})'),
        ),
      ),
    ];

    if (_adminSeleccionadoId != null &&
        _adminSeleccionadoId!.isNotEmpty &&
        !items.any((i) => i.value == _adminSeleccionadoId)) {
      items.add(
        DropdownMenuItem<String>(
          value: _adminSeleccionadoId!,
          child: Text('Asignado actual (${_adminSeleccionadoId!})'),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: _adminSeleccionadoId ?? '',
      decoration: const InputDecoration(
        labelText: 'Administrador asignado',
        border: OutlineInputBorder(),
      ),
      items: items,
      onChanged: (value) {
        setState(() {
          _adminSeleccionadoId = (value == null || value.isEmpty)
              ? null
              : value;
        });
      },
    );
  }

  Widget _operariosCard(Conjunto c) {
    return _SectionCard(
      icon: Icons.groups_2_outlined,
      title: 'Operarios',
      subtitle: _editMode ? 'Selecciona operarios asignados al conjunto' : null,
      child: !_editMode ? _operariosReadOnly(c) : _operariosEditor(),
    );
  }

  Widget _operariosReadOnly(Conjunto c) {
    if (c.operarios.isEmpty) {
      return Text(
        'No hay operarios asignados.',
        style: TextStyle(color: Colors.grey.shade600),
      );
    }

    return Column(
      children: c.operarios
          .map(
            (o) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBF9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE6EEEA)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 17,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      o.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(o.cedula, style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _operariosEditor() {
    if (_cargandoCatalogos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_operariosCatalogo.isEmpty) {
      return Text(
        'No hay operarios disponibles.',
        style: TextStyle(color: Colors.grey.shade600),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _operariosCatalogo.map((o) {
        final selected = _operariosSeleccionadosIds.contains(o.cedula);
        return FilterChip(
          label: Text(o.nombre),
          selected: selected,
          avatar: Icon(
            selected ? Icons.check_circle : Icons.person_outline,
            size: 16,
          ),
          onSelected: (value) {
            setState(() {
              if (value) {
                _operariosSeleccionadosIds.add(o.cedula);
              } else {
                _operariosSeleccionadosIds.remove(o.cedula);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _horariosCard(Conjunto c) {
    final horarios = [...c.horarios]
      ..sort((a, b) => _sortDay(a.dia).compareTo(_sortDay(b.dia)));

    return _SectionCard(
      icon: Icons.schedule,
      title: 'Horarios',
      subtitle: 'Definicion de apertura, cierre y descansos',
      child: horarios.isEmpty
          ? Text(
              'No hay horarios configurados.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          : Column(
              children: horarios
                  .map(
                    (h) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAF8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE4ECE8)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 86,
                            child: Text(
                              _dayText(h.dia),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${h.horaApertura} - ${h.horaCierre}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (h.descansoInicio != null &&
                                    h.descansoFin != null)
                                  Text(
                                    'Descanso: ${h.descansoInicio} - ${h.descansoFin}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _ubicacionesCard(Conjunto c) {
    return _SectionCard(
      icon: Icons.location_city_outlined,
      title: 'Ubicaciones',
      subtitle: _editMode
          ? 'Puedes agregar, editar o eliminar ubicaciones'
          : null,
      child: !_editMode ? _ubicacionesReadOnly(c) : _ubicacionesEditor(),
    );
  }

  Widget _ubicacionesReadOnly(Conjunto c) {
    if (c.ubicaciones.isEmpty) {
      return Text(
        'No hay ubicaciones registradas.',
        style: TextStyle(color: Colors.grey.shade600),
      );
    }

    return Column(
      children: c.ubicaciones
          .map(
            (u) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FCFA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE3ECE7)),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Text(
                  u.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${u.elementos.length} elementos'),
                children: [
                  if (u.elementos.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Sin elementos.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: u.elementos
                          .map(
                            (e) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF5F1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                e.nombre,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _ubicacionesEditor() {
    return Column(
      children: [
        if (_ubicacionesEditables.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No hay ubicaciones. Agrega una nueva.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ..._ubicacionesEditables.asMap().entries.map((entry) {
          final index = entry.key;
          final raw = entry.value;
          final nombre = (raw['nombre'] ?? '').toString();
          final elementos = (raw['elementos'] as List).cast<String>();

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBF9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE3ECE7)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: nombre,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de ubicacion',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          _ubicacionesEditables[index]['nombre'] = value;
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() => _ubicacionesEditables.removeAt(index));
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Elementos',
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (elementos.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sin elementos.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ...elementos.asMap().entries.map((item) {
                  final i = item.key;
                  final text = item.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: text,
                            decoration: const InputDecoration(
                              labelText: 'Elemento',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              _ubicacionesEditables[index]['elementos'][i] =
                                  value;
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              (_ubicacionesEditables[index]['elementos']
                                      as List)
                                  .removeAt(i);
                            });
                          },
                          icon: const Icon(
                            Icons.close,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        (_ubicacionesEditables[index]['elementos'] as List).add(
                          '',
                        );
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar elemento'),
                  ),
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _ubicacionesEditables.add(<String, dynamic>{
                  'nombre': '',
                  'elementos': <String>[],
                });
              });
            },
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Agregar ubicacion'),
          ),
        ),
      ],
    );
  }

  Widget _textosCard(Conjunto c) {
    return _SectionCard(
      icon: Icons.article_outlined,
      title: 'Consignas y valor agregado',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.consignasEspeciales.isNotEmpty) ...[
            const Text(
              'Consignas especiales',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...c.consignasEspeciales.map(_bulletLine),
            const SizedBox(height: 12),
          ],
          if (c.valorAgregado.isNotEmpty) ...[
            const Text(
              'Valor agregado',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...c.valorAgregado.map(_bulletLine),
          ],
        ],
      ),
    );
  }

  Widget _editActionsCard(Conjunto c) {
    return _SectionCard(
      icon: Icons.save_outlined,
      title: 'Acciones de edicion',
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving
                  ? null
                  : () {
                      setState(() {
                        _editMode = false;
                        _formInicializado = false;
                      });
                    },
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _saving ? null : () => _guardarCambios(c),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE5E0)),
          color: const Color(0xFFF8FBF9),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dateText(value),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('- '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4ECE8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
