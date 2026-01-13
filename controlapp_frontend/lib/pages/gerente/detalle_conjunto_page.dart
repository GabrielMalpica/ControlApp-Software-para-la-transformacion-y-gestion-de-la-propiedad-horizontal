import 'package:flutter/material.dart';
import '../../service/theme.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../model/usuario_model.dart';

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

  // Catálogos para edición
  List<Usuario>? _adminsCatalogo;
  List<Usuario>? _operariosCatalogo;
  bool _cargandoCatalogos = false;

  // Controllers de formulario
  final _nombreCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _valorMensualCtrl = TextEditingController();

  bool _activo = true;
  DateTime? _fechaInicioContrato;
  DateTime? _fechaFinContrato;

  String? _adminSeleccionadoId;
  Set<String> _operariosSeleccionadosIds = {};

  bool _editMode = false;
  bool _saving = false;
  bool _formInicializado = false;
  List<Map<String, dynamic>> _ubicacionesEditables = [];

  @override
  void initState() {
    super.initState();
    _editMode = widget.modoEdicionBasico;
    _loadConjunto();
    _loadCatalogos();
  }

  void _loadConjunto() {
    _futureConjunto = _api.obtenerConjunto(widget.conjuntoNit);
  }

  Future<void> _loadCatalogos() async {
    setState(() => _cargandoCatalogos = true);
    try {
      final admins = await _api.listarUsuarios(rol: 'administrador');
      final operarios = await _api.listarUsuarios(rol: 'operario');

      setState(() {
        _adminsCatalogo = admins;
        _operariosCatalogo = operarios;
        _cargandoCatalogos = false;
      });
    } catch (_) {
      // Si falla el catálogo, igual mostramos el detalle del conjunto
      if (mounted) {
        setState(() {
          _cargandoCatalogos = false;
        });
      }
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
    _operariosSeleccionadosIds = c.operarios.map((o) => o.cedula).toSet();
    _ubicacionesEditables = c.ubicaciones
        .map<Map<String, dynamic>>(
          (u) => {
            'nombre': u.nombre,
            'elementos': u.elementos.map((e) => e.nombre).toList(),
          },
        )
        .toList();

    _formInicializado = true;
  }

  Future<void> _seleccionarFecha({
    required DateTime? actual,
    required ValueChanged<DateTime> onSelected,
    String? helpText,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: helpText,
    );
    if (picked != null) {
      onSelected(picked);
    }
  }

  Future<void> _guardarCambios(Conjunto c) async {
    setState(() => _saving = true);
    try {
      double? valor = _valorMensualCtrl.text.trim().isNotEmpty
          ? double.tryParse(_valorMensualCtrl.text.trim())
          : null;

      await _api.actualizarConjunto(
        c.nit,
        nombre: _nombreCtrl.text.trim(),
        direccion: _direccionCtrl.text.trim(),
        correo: _correoCtrl.text.trim(),
        activo: _activo,
        valorMensual: valor,
        fechaInicioContrato: _fechaInicioContrato,
        fechaFinContrato: _fechaFinContrato,
        administradorId: _adminSeleccionadoId,
        operariosIds: _operariosSeleccionadosIds.toList(),
        ubicaciones: _ubicacionesEditables,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Conjunto actualizado'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _editMode = false;
        _formInicializado = false;
        _loadConjunto();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al actualizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
        title: Text(
          'Conjunto ${widget.conjuntoNit}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _editMode ? Icons.close : Icons.edit,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _editMode = !_editMode;
              });
            },
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
              child: Text('Error cargando conjunto: ${snapshot.error}'),
            );
          }

          final c = snapshot.data!;
          if (_editMode) _inicializarForm(c);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _headerCard(c),
                const SizedBox(height: 16),
                _editMode ? _formEdicion(c) : _seccionResumenContrato(c),
                const SizedBox(height: 16),
                _seccionAdministrador(c),
                const SizedBox(height: 16),
                _seccionOperarios(c),
                const SizedBox(height: 16),
                if (c.horarios.isNotEmpty) _seccionHorarios(c),
                const SizedBox(height: 16),
                if (c.ubicaciones.isNotEmpty) _seccionUbicaciones(c),
                const SizedBox(height: 16),
                if (c.consignasEspeciales.isNotEmpty ||
                    c.valorAgregado.isNotEmpty)
                  _seccionTextos(c),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER "DASHBOARD" BONITO
  // ─────────────────────────────────────────────────────────────

  Widget _headerCard(Conjunto c) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.95),
            AppTheme.green.withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.apartment, color: Colors.white, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.activo
                      ? Colors.greenAccent
                      : Colors.redAccent.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      c.activo ? Icons.check_circle : Icons.block,
                      size: 16,
                      color: c.activo ? Colors.green[900] : Colors.red[900],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      c.activo ? "Activo" : "Inactivo",
                      style: TextStyle(
                        color: c.activo ? Colors.green[900] : Colors.red[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on, size: 18, color: Colors.white70),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  c.direccion,
                  style: const TextStyle(color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.email_outlined, size: 18, color: Colors.white70),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  c.correo,
                  style: const TextStyle(color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (c.valorMensual != null)
                _chipInfo(
                  "Valor mensual",
                  "\$${c.valorMensual!.toStringAsFixed(0)}",
                  Icons.attach_money,
                ),
              if (c.fechaInicioContrato != null)
                _chipInfo(
                  "Inicio",
                  "${c.fechaInicioContrato!.day}/${c.fechaInicioContrato!.month}/${c.fechaInicioContrato!.year}",
                  Icons.play_circle_outline,
                ),
              if (c.fechaFinContrato != null)
                _chipInfo(
                  "Fin",
                  "${c.fechaFinContrato!.day}/${c.fechaFinContrato!.month}/${c.fechaFinContrato!.year}",
                  Icons.stop_circle_outlined,
                ),
              _chipInfo(
                "Operarios",
                "${c.operarios.length}",
                Icons.groups_2_outlined,
              ),
              _chipInfo(
                "Ubicaciones",
                "${c.ubicaciones.length}",
                Icons.location_city_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(String label, String value, IconData icon) {
    return Chip(
      backgroundColor: Colors.white.withOpacity(0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      avatar: Icon(icon, size: 18, color: Colors.black),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SECCIÓN RESUMEN CONTRATO (solo lectura)
  // ─────────────────────────────────────────────────────────────

  Widget _seccionResumenContrato(Conjunto c) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titulo("Información de contrato"),
            const SizedBox(height: 12),
            _rowLabelValue("NIT", c.nit),
            const SizedBox(height: 8),
            if (c.fechaInicioContrato != null)
              _rowLabelValue(
                "Inicio contrato",
                "${c.fechaInicioContrato!.day}/${c.fechaInicioContrato!.month}/${c.fechaInicioContrato!.year}",
              ),
            if (c.fechaFinContrato != null) ...[
              const SizedBox(height: 8),
              _rowLabelValue(
                "Fin contrato",
                "${c.fechaFinContrato!.day}/${c.fechaFinContrato!.month}/${c.fechaFinContrato!.year}",
              ),
            ],
            const SizedBox(height: 8),
            _rowLabelValue("Estado", c.activo ? "Activo" : "Inactivo"),
          ],
        ),
      ),
    );
  }

  Widget _rowLabelValue(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FORMULARIO EDICIÓN GENERAL + ESTADO + ADMIN + OPERARIOS
  // ─────────────────────────────────────────────────────────────

  Widget _formEdicion(Conjunto c) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titulo("Editar información del conjunto"),
            const SizedBox(height: 12),
            _textField("Nombre", _nombreCtrl),
            const SizedBox(height: 12),
            _textField("Dirección", _direccionCtrl),
            const SizedBox(height: 12),
            _textField("Correo", _correoCtrl),
            const SizedBox(height: 12),
            _textField("Valor mensual", _valorMensualCtrl, number: true),
            const SizedBox(height: 16),

            // Estado y fechas
            SwitchListTile(
              title: const Text("Conjunto activo"),
              subtitle: const Text(
                "Si lo desactivas y no defines fecha de fin, se usará la fecha actual",
              ),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _cardFecha(
                    label: "Inicio contrato",
                    fecha: _fechaInicioContrato,
                    onTap: () => _seleccionarFecha(
                      actual: _fechaInicioContrato,
                      onSelected: (d) =>
                          setState(() => _fechaInicioContrato = d),
                      helpText: "Fecha de inicio del contrato",
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _cardFecha(
                    label: "Fin contrato",
                    fecha: _fechaFinContrato,
                    onTap: () => _seleccionarFecha(
                      actual: _fechaFinContrato,
                      onSelected: (d) => setState(() => _fechaFinContrato = d),
                      helpText: "Fecha de finalización del contrato",
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Administrador
            _tituloSecundario("Administrador"),
            const SizedBox(height: 8),
            _buildAdministradorDropdown(),

            const SizedBox(height: 18),

            // Operarios
            _tituloSecundario("Operarios asignados"),
            const SizedBox(height: 8),
            _buildOperariosChips(),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : () => _guardarCambios(c),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController ctrl, {
    bool number = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _cardFecha({
    required String label,
    required DateTime? fecha,
    required VoidCallback onTap,
  }) {
    final text = fecha == null
        ? "Seleccionar"
        : "${fecha.day}/${fecha.month}/${fecha.year}";
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.event, color: AppTheme.primary, size: 20),
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
                    text,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titulo(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
    );
  }

  Widget _tituloSecundario(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ADMINISTRADOR (LECTURA Y EDICIÓN)
  // ─────────────────────────────────────────────────────────────

  Widget _seccionAdministrador(Conjunto c) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titulo("Administrador"),
            const SizedBox(height: 12),
            if (!_editMode)
              Text(
                c.administradorNombre ?? "No asignado",
                style: const TextStyle(fontSize: 16),
              )
            else
              _buildAdministradorDropdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildAdministradorDropdown() {
    if (_cargandoCatalogos) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_adminsCatalogo == null || _adminsCatalogo!.isEmpty) {
      return const Text(
        "No hay administradores disponibles.",
        style: TextStyle(color: Colors.grey),
      );
    }

    return DropdownButtonFormField<String>(
      value: _adminSeleccionadoId,
      decoration: const InputDecoration(
        labelText: "Administrador asignado",
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text("Sin administrador")),
        ..._adminsCatalogo!.map(
          (u) => DropdownMenuItem(
            value: u.cedula,
            child: Text("${u.nombre} (${u.cedula})"),
          ),
        ),
      ],
      onChanged: (v) {
        setState(() {
          _adminSeleccionadoId = v;
        });
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // OPERARIOS (LECTURA Y EDICIÓN)
  // ─────────────────────────────────────────────────────────────

  Widget _seccionOperarios(Conjunto c) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titulo("Operarios"),
            const SizedBox(height: 12),
            if (!_editMode)
              c.operarios.isEmpty
                  ? const Text(
                      "No hay operarios asignados.",
                      style: TextStyle(color: Colors.grey),
                    )
                  : Column(
                      children: c.operarios
                          .map(
                            (o) => ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(o.nombre),
                              subtitle: Text("CC: ${o.cedula}"),
                            ),
                          )
                          .toList(),
                    )
            else
              _buildOperariosChips(),
          ],
        ),
      ),
    );
  }

  Widget _buildOperariosChips() {
    if (_cargandoCatalogos) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_operariosCatalogo == null || _operariosCatalogo!.isEmpty) {
      return const Text(
        "No hay operarios disponibles.",
        style: TextStyle(color: Colors.grey),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _operariosCatalogo!.map((o) {
        final selected = _operariosSeleccionadosIds.contains(o.cedula);
        return FilterChip(
          label: Text(o.nombre),
          selected: selected,
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

  // ─────────────────────────────────────────────────────────────
  // HORARIOS
  // ─────────────────────────────────────────────────────────────

  Widget _seccionHorarios(Conjunto c) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titulo("Horarios"),
            const SizedBox(height: 12),
            ...c.horarios.map(
              (h) => Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      h.dia,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${h.horaApertura} - ${h.horaCierre}"),
                        if (h.descansoInicio != null && h.descansoFin != null)
                          Text(
                            "Descanso: ${h.descansoInicio} - ${h.descansoFin}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // UBICACIONES + ELEMENTOS
  // ─────────────────────────────────────────────────────────────

  Widget _seccionUbicaciones(Conjunto c) {
    if (!_editMode) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titulo("Ubicaciones"),
              const SizedBox(height: 12),
              ...c.ubicaciones.map(
                (u) => ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 0),
                  childrenPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  title: Text(
                    u.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  children: u.elementos.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              "Sin elementos registrados.",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ]
                      : u.elementos
                            .map(
                              (e) => ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: Colors.grey,
                                ),
                                title: Text(e.nombre),
                              ),
                            )
                            .toList(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titulo("Ubicaciones (editable)"),
            const SizedBox(height: 12),
            ..._ubicacionesEditables.asMap().entries.map((entry) {
              final index = entry.key;
              final u = entry.value;
              final nombreCtrl = TextEditingController(
                text: u['nombre'] as String,
              );
              final List elementos = (u['elementos'] as List);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nombreCtrl,
                              decoration: const InputDecoration(
                                labelText: "Nombre ubicación",
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                _ubicacionesEditables[index]['nombre'] = v;
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _ubicacionesEditables.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Elementos",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...elementos.asMap().entries.map((eEntry) {
                        final eIndex = eEntry.key;
                        final String nombreElem = eEntry.value as String;
                        final elemCtrl = TextEditingController(
                          text: nombreElem,
                        );
                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: elemCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Nombre elemento",
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) {
                                  _ubicacionesEditables[index]['elementos'][eIndex] =
                                      v;
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.redAccent,
                              ),
                              onPressed: () {
                                setState(() {
                                  (_ubicacionesEditables[index]['elementos']
                                          as List)
                                      .removeAt(eIndex);
                                });
                              },
                            ),
                          ],
                        );
                      }).toList(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              (_ubicacionesEditables[index]['elementos']
                                      as List)
                                  .add("");
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text("Agregar elemento"),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _ubicacionesEditables.add({
                      'nombre': '',
                      'elementos': <String>[],
                    });
                  });
                },
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text("Agregar ubicación"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CONSIGNAS & VALOR AGREGADO
  // ─────────────────────────────────────────────────────────────

  Widget _seccionTextos(Conjunto c) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.consignasEspeciales.isNotEmpty) ...[
              _titulo("Consignas especiales"),
              const SizedBox(height: 8),
              ...c.consignasEspeciales.map(
                (txt) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("• "),
                      Expanded(child: Text(txt)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (c.valorAgregado.isNotEmpty) ...[
              _titulo("Valor agregado"),
              const SizedBox(height: 8),
              ...c.valorAgregado.map(
                (txt) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("• "),
                      Expanded(child: Text(txt)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
