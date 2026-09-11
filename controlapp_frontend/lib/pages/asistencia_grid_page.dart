import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/asistencia_api.dart';
import '../model/asistencia_model.dart';
import '../service/app_error.dart';
import '../service/app_feedback.dart';
import '../service/permission_service.dart';
import '../service/theme.dart';

Color _colorFromHex(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF9E9E9E);
}

class AsistenciaGridPage extends StatefulWidget {
  /// Si es null se muestran los operarios de toda la empresa (vista gerencial),
  /// igual que las hojas mensuales del Excel.
  final String? conjuntoId;
  final String? conjuntoNombre;

  const AsistenciaGridPage({super.key, this.conjuntoId, this.conjuntoNombre});

  @override
  State<AsistenciaGridPage> createState() => _AsistenciaGridPageState();
}

class _AsistenciaGridPageState extends State<AsistenciaGridPage>
    with SingleTickerProviderStateMixin {
  final AsistenciaApi _api = AsistenciaApi();
  late final TabController _tabController;

  DateTime _periodo = DateTime(DateTime.now().year, DateTime.now().month, 1);

  bool _cargando = true;
  String? _error;
  AsistenciaGrid? _grid;
  AsistenciaResumen? _resumen;
  List<ConceptoAsistencia> _conceptos = [];

  bool get _puedeEditar => PermissionService.instance.can(
    'asistencia.registrar_manual',
  );

  bool get _puedeExportar => PermissionService.instance.can('asistencia.exportar');

  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listarConceptos(),
        _api.getGrid(
          conjuntoId: widget.conjuntoId,
          anio: _periodo.year,
          mes: _periodo.month,
        ),
        _api.getResumen(
          conjuntoId: widget.conjuntoId,
          anio: _periodo.year,
          mes: _periodo.month,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _conceptos = results[0] as List<ConceptoAsistencia>;
        _grid = results[1] as AsistenciaGrid;
        _resumen = results[2] as AsistenciaResumen;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = AppError.messageOf(
          e,
          fallback: 'No se pudo cargar la asistencia.',
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cambiarMes(int delta) {
    setState(() {
      _periodo = DateTime(_periodo.year, _periodo.month + delta, 1);
    });
    _cargar();
  }

  Future<void> _exportarExcel() async {
    setState(() => _exportando = true);
    try {
      final bytes = await _api.descargarExcel(
        conjuntoId: widget.conjuntoId,
        anio: _periodo.year,
        mes: _periodo.month,
      );
      final nombreArchivo =
          'asistencia_${_periodo.year}_${_periodo.month.toString().padLeft(2, '0')}.xlsx';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar reporte de asistencia',
        fileName: nombreArchivo,
        bytes: bytes,
      );
      if (!mounted) return;
      AppFeedback.showInfo(context, message: 'Reporte exportado correctamente.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo exportar el reporte.'),
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _onCeldaTap(
    AsistenciaOperarioFila fila,
    AsistenciaDiaCelda dia,
  ) async {
    if (dia.registro != null) {
      final editar = await _mostrarDetalleCelda(fila, dia);
      if (editar == true && _puedeEditar) {
        await _abrirEditor(fila, dia);
      }
      return;
    }

    if (!_puedeEditar) return;
    await _abrirEditor(fila, dia);
  }

  Future<void> _abrirEditor(
    AsistenciaOperarioFila fila,
    AsistenciaDiaCelda dia,
  ) async {
    final seleccionado = await showModalBottomSheet<_EdicionCelda>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditorCeldaSheet(
        fila: fila,
        dia: dia,
        conceptos: _conceptos,
      ),
    );
    if (seleccionado == null) return;

    try {
      await _api.upsertRegistro(
        operarioId: fila.operarioId,
        fecha: dia.fecha,
        conceptoId: seleccionado.conceptoId,
        conjuntoId: widget.conjuntoId,
        observacion: seleccionado.observacion,
      );
      if (!mounted) return;
      AppFeedback.showInfo(context, message: 'Dia actualizado.');
      _cargar();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo guardar.'),
      );
    }
  }

  Future<void> _abrirUbicacion(UbicacionAsistencia ubicacion) async {
    final uri = Uri.parse(ubicacion.googleMapsUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      AppFeedback.showError(context, message: 'No se pudo abrir el mapa.');
    }
  }

  String _formatHora(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _filaHoraUbicacion(
    String etiqueta,
    DateTime? hora,
    UbicacionAsistencia? ubicacion,
  ) {
    if (hora == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text('$etiqueta: ${_formatHora(hora)}')),
          if (ubicacion != null)
            TextButton.icon(
              onPressed: () => _abrirUbicacion(ubicacion),
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Ver mapa'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Sin ubicacion',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Future<bool?> _mostrarDetalleCelda(
    AsistenciaOperarioFila fila,
    AsistenciaDiaCelda dia,
  ) {
    final registro = dia.registro;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${fila.nombre} · ${dia.fecha}'),
        content: registro == null
            ? const Text('Sin marcar.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${registro.conceptoCodigo} · ${registro.conceptoNombre}'),
                  Text('Origen: ${registro.origen == 'QR' ? 'Check-in QR' : 'Manual'}'),
                  if (dia.incompleto)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Solo se registro la entrada, falta la salida. '
                        'Revisa y decide si cuenta como asistencia completa.',
                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                      ),
                    ),
                  _filaHoraUbicacion(
                    'Entrada',
                    registro.horaEntrada,
                    registro.ubicacionEntrada,
                  ),
                  _filaHoraUbicacion(
                    'Salida',
                    registro.horaSalida,
                    registro.ubicacionSalida,
                  ),
                  if (registro.observacion != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(registro.observacion!),
                    ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cerrar'),
          ),
          if (_puedeEditar)
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Editar'),
            ),
        ],
      ),
    );
  }

  Future<void> _abrirAsignacionMasiva() async {
    if (_grid == null) return;
    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AsignacionMasivaSheet(
        operarios: _grid!.operarios,
        conceptos: _conceptos,
        conjuntoId: widget.conjuntoId,
        api: _api,
      ),
    );
    if (resultado == true) _cargar();
  }

  Widget _buildLeyenda() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _conceptos
          .where((c) => c.activo)
          .map(
            (c) => Chip(
              backgroundColor: _colorFromHex(c.colorHex).withValues(alpha: 0.18),
              label: Text(
                '${c.codigo} · ${c.nombre}',
                style: TextStyle(
                  fontSize: 11,
                  color: _colorFromHex(c.colorHex),
                  fontWeight: FontWeight.w700,
                ),
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )
          .toList(),
    );
  }

  static const double _nameColWidth = 140;
  static const double _dayColWidth = 28;
  static const double _rowHeight = 30;

  Widget _buildGridTab() {
    final grid = _grid;
    if (grid == null) return const SizedBox.shrink();

    if (grid.operarios.isEmpty) {
      return const Center(child: Text('No hay operarios para este periodo.'));
    }

    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(_nameColWidth),
      for (var i = 1; i <= grid.totalDias; i++) i: const FixedColumnWidth(_dayColWidth),
    };

    final grupos = grid.gruposPorConjunto;
    final filas = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade100),
        children: [
          _headerCell('Operario', alignLeft: true),
          for (final dia in grid.operarios.first.dias)
            _headerCell(
              '${dia.dia}',
              color: dia.diaSemana == 0 ? Colors.red : null,
            ),
        ],
      ),
    ];

    if (grupos != null && grupos.isNotEmpty) {
      for (final grupo in grupos) {
        filas.add(_grupoHeaderRow(grupo.conjuntoNombre, grid.totalDias));
        for (final fila in grupo.operarios) {
          filas.add(_operarioRow(fila));
        }
      }
    } else {
      for (final fila in grid.operarios) {
        filas.add(_operarioRow(fila));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildLeyenda(),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Table(
                columnWidths: columnWidths,
                border: TableBorder.all(color: Colors.grey.shade300, width: 0.6),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: filas,
              ),
            ),
          ),
        ),
      ],
    );
  }

  TableRow _operarioRow(AsistenciaOperarioFila fila) {
    return TableRow(
      children: [
        _nameCell(fila.nombre),
        for (final dia in fila.dias)
          InkWell(
            onTap: () => _onCeldaTap(fila, dia),
            child: _buildCelda(dia),
          ),
      ],
    );
  }

  TableRow _grupoHeaderRow(String nombreConjunto, int totalDias) {
    final color = AppTheme.primary.withValues(alpha: 0.12);
    return TableRow(
      decoration: BoxDecoration(color: color),
      children: [
        Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          child: Text(
            nombreConjunto,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
        for (var i = 0; i < totalDias; i++) Container(height: _rowHeight),
      ],
    );
  }

  Widget _headerCell(String text, {bool alignLeft = false, Color? color}) {
    return Container(
      height: _rowHeight,
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      padding: alignLeft ? const EdgeInsets.symmetric(horizontal: 6) : EdgeInsets.zero,
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: color),
      ),
    );
  }

  Widget _nameCell(String nombre) {
    return Container(
      constraints: const BoxConstraints(minHeight: _rowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      alignment: Alignment.centerLeft,
      child: Text(
        nombre,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildCelda(AsistenciaDiaCelda dia) {
    final registro = dia.registro;
    if (registro == null) {
      return Container(
        height: _rowHeight,
        alignment: Alignment.center,
        color: dia.pendiente ? Colors.red.withValues(alpha: 0.08) : null,
        child: Text(
          dia.pendiente ? '?' : '',
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      );
    }

    final color = dia.incompleto ? Colors.orange.shade800 : _colorFromHex(registro.colorHex);
    return Container(
      height: _rowHeight,
      alignment: Alignment.center,
      color: color.withValues(alpha: 0.22),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            registro.conceptoCodigo,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (dia.incompleto)
            Positioned(
              top: 1,
              right: 1,
              child: Icon(
                Icons.warning_amber_rounded,
                size: 9,
                color: Colors.orange.shade800,
              ),
            ),
        ],
      ),
    );
  }

  Widget _resumenOperarioCard(AsistenciaResumenOperario op) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(op.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(op.cargo, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final entry in op.conteoPorConcepto.entries)
                  Text('${entry.key}: ${entry.value}'),
                if (op.pendientes > 0)
                  Text(
                    'Pendientes: ${op.pendientes}',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumenGrupoHeader(String nombreConjunto) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          nombreConjunto,
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryDark),
        ),
      ),
    );
  }

  Widget _buildResumenTab() {
    final resumen = _resumen;
    if (resumen == null) return const SizedBox.shrink();

    final grupos = resumen.gruposPorConjunto;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Resumen por operario', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        if (grupos != null && grupos.isNotEmpty)
          for (final grupo in grupos) ...[
            _resumenGrupoHeader(grupo.conjuntoNombre),
            for (final op in grupo.operarios) _resumenOperarioCard(op),
          ]
        else
          for (final op in resumen.operarios) _resumenOperarioCard(op),
        const SizedBox(height: 16),
        const Text('Turnos extra del mes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        if (resumen.turnosExtra.isEmpty) const Text('Sin turnos extra registrados.'),
        for (final t in resumen.turnosExtra)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('${t.operarioNombre} · ${t.fecha}'),
              subtitle: Text(
                [
                  t.tipo,
                  if (t.esReemplazo) 'Reemplazo de ${t.reemplazadoNombre ?? "?"}',
                  if (t.motivo != null) t.motivo!,
                ].join(' · '),
              ),
              trailing: t.valorNegociado != null
                  ? Text('\$${t.valorNegociado!.toStringAsFixed(0)}')
                  : null,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.conjuntoNombre != null
        ? 'Asistencia · ${widget.conjuntoNombre}'
        : 'Asistencia · Toda la empresa';
    final mesLabel = DateFormat.yMMMM('es').format(_periodo);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(titulo, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_puedeExportar)
            IconButton(
              tooltip: 'Exportar a Excel',
              icon: _exportando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_download_outlined, color: Colors.white),
              onPressed: _exportando ? null : _exportarExcel,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Grid mensual'),
            Tab(text: 'Resumen'),
          ],
        ),
      ),
      floatingActionButton: _puedeEditar
          ? FloatingActionButton.extended(
              onPressed: _abrirAsignacionMasiva,
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.event_repeat, color: Colors.white),
              label: const Text(
                'Asignar rango',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _cambiarMes(-1),
                ),
                Text(
                  mesLabel[0].toUpperCase() + mesLabel.substring(1),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _cambiarMes(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(
                    controller: _tabController,
                    children: [_buildGridTab(), _buildResumenTab()],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EdicionCelda {
  final int conceptoId;
  final String? observacion;
  _EdicionCelda(this.conceptoId, this.observacion);
}

class _EditorCeldaSheet extends StatefulWidget {
  final AsistenciaOperarioFila fila;
  final AsistenciaDiaCelda dia;
  final List<ConceptoAsistencia> conceptos;

  const _EditorCeldaSheet({
    required this.fila,
    required this.dia,
    required this.conceptos,
  });

  @override
  State<_EditorCeldaSheet> createState() => _EditorCeldaSheetState();
}

class _EditorCeldaSheetState extends State<_EditorCeldaSheet> {
  int? _conceptoId;
  final _observacionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _conceptoId = widget.dia.registro?.conceptoId;
    _observacionCtrl.text = widget.dia.registro?.observacion ?? '';
  }

  @override
  void dispose() {
    _observacionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.fila.nombre} · ${widget.dia.fecha}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (widget.dia.incompleto)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Solo se registro la entrada (sin salida). Confirma el '
                'concepto si cuenta como asistencia o corrigelo.',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.conceptos.where((c) => c.activo).map((c) {
              final seleccionado = c.id == _conceptoId;
              final color = _colorFromHex(c.colorHex);
              return ChoiceChip(
                label: Text('${c.codigo} · ${c.nombre}'),
                selected: seleccionado,
                selectedColor: color.withValues(alpha: 0.3),
                onSelected: (_) => setState(() => _conceptoId = c.id),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _observacionCtrl,
            decoration: const InputDecoration(
              labelText: 'Observacion (opcional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: _conceptoId == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      _EdicionCelda(
                        _conceptoId!,
                        _observacionCtrl.text.trim().isEmpty
                            ? null
                            : _observacionCtrl.text.trim(),
                      ),
                    ),
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AsignacionMasivaSheet extends StatefulWidget {
  final List<AsistenciaOperarioFila> operarios;
  final List<ConceptoAsistencia> conceptos;
  final String? conjuntoId;
  final AsistenciaApi api;

  const _AsignacionMasivaSheet({
    required this.operarios,
    required this.conceptos,
    required this.conjuntoId,
    required this.api,
  });

  @override
  State<_AsignacionMasivaSheet> createState() => _AsignacionMasivaSheetState();
}

class _AsignacionMasivaSheetState extends State<_AsignacionMasivaSheet> {
  final Set<String> _operarioIds = {};
  int? _conceptoId;
  DateTime? _inicio;
  DateTime? _fin;
  final _observacionCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _observacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha({required bool inicio}) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (fecha == null) return;
    setState(() {
      if (inicio) {
        _inicio = fecha;
      } else {
        _fin = fecha;
      }
    });
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _guardar() async {
    if (_operarioIds.isEmpty || _conceptoId == null || _inicio == null || _fin == null) {
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.api.bulkUpsertRegistro(
        operarioIds: _operarioIds.toList(),
        fechaInicio: _ymd(_inicio!),
        fechaFin: _ymd(_fin!),
        conceptoId: _conceptoId!,
        conjuntoId: widget.conjuntoId,
        observacion: _observacionCtrl.text.trim().isEmpty
            ? null
            : _observacionCtrl.text.trim(),
      );
      if (!mounted) return;
      AppFeedback.showInfo(context, message: 'Rango asignado correctamente.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo asignar el rango.'),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Asignar un concepto a varios dias (vacaciones, incapacidad, etc.)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text('Operarios', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(
              height: 160,
              child: ListView(
                children: widget.operarios.map((op) {
                  final checked = _operarioIds.contains(op.operarioId);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    title: Text(op.nombre),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _operarioIds.add(op.operarioId);
                        } else {
                          _operarioIds.remove(op.operarioId);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Concepto', style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.conceptos.where((c) => c.activo).map((c) {
                final seleccionado = c.id == _conceptoId;
                return ChoiceChip(
                  label: Text('${c.codigo} · ${c.nombre}'),
                  selected: seleccionado,
                  onSelected: (_) => setState(() => _conceptoId = c.id),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _seleccionarFecha(inicio: true),
                    child: Text(
                      _inicio == null ? 'Fecha inicio' : _ymd(_inicio!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _seleccionarFecha(inicio: false),
                    child: Text(_fin == null ? 'Fecha fin' : _ymd(_fin!)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacionCtrl,
              decoration: const InputDecoration(
                labelText: 'Observacion (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
