import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/plan_esperanza_api.dart';
import 'package:flutter_application_1/model/plan_esperanza_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/pickers/camera_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/file_pick_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';
import 'package:flutter_application_1/widgets/star_rating.dart';

class PlanEsperanzaPage extends StatefulWidget {
  final String nit;
  final String? nombreConjunto;

  const PlanEsperanzaPage({
    super.key,
    required this.nit,
    this.nombreConjunto,
  });

  @override
  State<PlanEsperanzaPage> createState() => _PlanEsperanzaPageState();
}

class _PlanEsperanzaPageState extends State<PlanEsperanzaPage>
    with SingleTickerProviderStateMixin {
  final PlanEsperanzaApi _api = PlanEsperanzaApi();
  late TabController _tabController;

  bool _loadingPlan = true;
  bool _saving = false;
  String? _error;

  PlanEsperanzaActivo? _planActivo;
  PlanEsperanzaConfig? _config;
  InformeResponse? _informe;
  HistoricoResponse? _historico;

  // Edits locales
  final Map<int, double> _editValoraciones = {};
  final Map<int, String> _editObservaciones = {};
  final Map<int, SelectedUploadFile?> _editFotos = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loadingPlan = true;
      _error = null;
    });
    try {
      final config = await _api.obtenerConfig(widget.nit);
      final planActivo = await _api.obtenerPlanActivo(widget.nit);
      if (!mounted) return;
      setState(() {
        _config = config;
        _planActivo = planActivo;
        _loadingPlan = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(e);
        _loadingPlan = false;
      });
    }
  }

  Future<void> _loadInforme(int planId) async {
    try {
      final informe = await _api.obtenerInforme(planId);
      if (!mounted) return;
      setState(() => _informe = informe);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context,
          message: AppError.messageOf(e,
              fallback: 'No se pudo cargar el informe.'));
    }
  }

  Future<void> _loadHistorico() async {
    try {
      final historico = await _api.obtenerHistorico(widget.nit);
      if (!mounted) return;
      setState(() => _historico = historico);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context,
          message: AppError.messageOf(e,
              fallback: 'No se pudo cargar el historico.'));
    }
  }

  Future<void> _onTabChanged() async {
    if (_tabController.index == 1 && _planActivo != null && _informe == null) {
      await _loadInforme(_planActivo!.id);
    } else if (_tabController.index == 2 && _historico == null) {
      await _loadHistorico();
    }
  }

  Future<void> _iniciarPlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Iniciar Plan Esperanza'),
        content: const Text(
          'Se iniciara un nuevo Plan Esperanza con todas las areas '
          'finales del conjunto. ¿Desea continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final plan = await _api.iniciarPlan(widget.nit);
      if (!mounted) return;
      _editValoraciones.clear();
      _editObservaciones.clear();
      _editFotos.clear();
      setState(() {
        _planActivo = plan;
        _informe = null;
        _historico = null;
        _saving = false;
      });
      _tabController.animateTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(context,
          message: AppError.messageOf(e,
              fallback: 'No se pudo iniciar el plan.'));
    }
  }

  Future<void> _finalizarPlan() async {
    if (_planActivo == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Plan Esperanza'),
        content: const Text(
          '¿Esta seguro de finalizar este plan? Ya no podra '
          'editar los diagnosticos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await _api.finalizarPlan(_planActivo!.id);
      if (!mounted) return;
      await _loadAll();
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(context,
          message: AppError.messageOf(e,
              fallback: 'No se pudo finalizar el plan.'));
    }
  }

  Future<void> _reiniciarPlan() async {
    final check = await _api.verificarZonasNuevas(widget.nit);

    final opcion = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final mensaje = check.hayZonasNuevas
            ? 'Se han agregado ${check.zonasActuales - check.zonasExistentes} '
                'zona(s) nueva(s). ¿Que desea hacer con las evidencias actuales?'
            : '¿Que desea hacer con las evidencias actuales?';

        return AlertDialog(
          title: const Text('Reiniciar Plan Esperanza'),
          content: Text(mensaje),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'mantener'),
              child: const Text('Mantener evidencias'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, 'nuevas'),
              child: const Text('Tomar nuevas evidencias'),
            ),
          ],
        );
      },
    );
    if (opcion == null || opcion == 'cancel') return;

    setState(() => _saving = true);
    try {
      final plan = await _api.reiniciarPlan(widget.nit,
          mantenerEvidencias: opcion == 'mantener');
      if (!mounted) return;
      _editValoraciones.clear();
      _editObservaciones.clear();
      _editFotos.clear();
      setState(() {
        _planActivo = plan;
        _informe = null;
        _historico = null;
        _saving = false;
      });
      _tabController.animateTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(context,
          message: AppError.messageOf(e,
              fallback: 'No se pudo reiniciar el plan.'));
    }
  }

  Future<void> _guardarDiagnostico(DiagnosticoAreaModel diag) async {
    final valoracion = _editValoraciones[diag.id];
    final observaciones = _editObservaciones[diag.id];
    final foto = _editFotos[diag.id];

    if (valoracion == null && observaciones == null && foto == null) {
      AppFeedback.showInfo(context, message: 'No hay cambios para guardar.');
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await _api.guardarDiagnostico(
        diag.id,
        valoracion: valoracion,
        observaciones: observaciones,
        foto: foto,
      );
      if (!mounted) return;
      setState(() {
        _editValoraciones.remove(diag.id);
        _editObservaciones.remove(diag.id);
        _editFotos.remove(diag.id);
        _planActivo = _planActivo!.copyWithDiagnostico(updated);
        _saving = false;
      });
      AppFeedback.showInfo(context, message: 'Diagnostico guardado.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(context,
          message: AppError.messageOf(e,
              fallback: 'No se pudo guardar el diagnostico.'));
    }
  }

  Future<void> _tomarFoto(DiagnosticoAreaModel diag) async {
    final source = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar foto'),
        content: const Text('¿Como desea agregar la foto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'camara'),
            child: const Text('Tomar foto'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'galeria'),
            child: const Text('Adjuntar'),
          ),
        ],
      ),
    );
    if (source == null) return;

    SelectedUploadFile? file;
    if (source == 'camara') {
      file = await CameraCapture.pickPhoto();
    } else {
      final files = await UniversalFilePick.pick(
        allowMultiple: false,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      file = files.isNotEmpty ? files.first : null;
    }

    if (file != null) {
      setState(() => _editFotos[diag.id] = file);
    }
  }

  Future<void> _showConfigDialog() async {
    final controller = TextEditingController(
      text: (_config?.intervaloMeses ?? 6).toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar Plan Esperanza'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Intervalo entre diagnosticos (en meses):'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Meses',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text);
              if (v == null || v < 1 || v > 60) {
                AppFeedback.showError(ctx,
                    message: 'Ingrese un valor entre 1 y 60.');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      try {
        final config =
            await _api.actualizarConfig(widget.nit, result);
        setState(() => _config = config);
        AppFeedback.showInfo(context,
            message: 'Configuracion actualizada.');
      } catch (e) {
        AppFeedback.showError(context,
            message: AppError.messageOf(e,
                fallback: 'No se pudo actualizar la configuracion.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombreConjunto ?? 'Plan Esperanza'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configurar periodicidad',
            onPressed: _showConfigDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => _onTabChanged(),
          tabs: const [
            Tab(icon: Icon(Icons.edit_note), text: 'Diagnostico'),
            Tab(icon: Icon(Icons.description), text: 'Informe'),
            Tab(icon: Icon(Icons.history), text: 'Historico'),
          ],
        ),
      ),
      body: _loadingPlan
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _loadAll,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDiagnosticoTab(),
                    _buildInformeTab(),
                    _buildHistoricoTab(),
                  ],
                ),
      floatingActionButton: _planActivo != null && !_planActivo!.completado
          ? FloatingActionButton.extended(
              onPressed: _finalizarPlan,
              icon: const Icon(Icons.check_circle),
              label: const Text('Finalizar Plan'),
              backgroundColor: AppTheme.green,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  // ──────────────────────────────────────────────
  // TAB: DIAGNÓSTICO
  // ──────────────────────────────────────────────

  Widget _buildDiagnosticoTab() {
    if (_planActivo == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.health_and_safety,
                size: 72, color: AppTheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No hay un Plan Esperanza activo.',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Inicie uno nuevo para comenzar los diagnosticos.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _iniciarPlan,
              icon: const Icon(Icons.play_arrow),
              label: Text(_saving ? 'Iniciando...' : 'Empezar Plan Esperanza'),
              style: AppTheme.saveButtonStyle,
            ),
          ],
        ),
      );
    }

    if (_planActivo!.completado) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            Text('Plan completado el ${_formatDate(_planActivo!.fechaFin)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _iniciarPlan,
              icon: const Icon(Icons.refresh),
              label: const Text('Iniciar nuevo plan'),
            ),
          ],
        ),
      );
    }

    final diagnosticos = _planActivo!.diagnosticos;
    final agrupado = _agruparDiagnosticos(diagnosticos);

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: Column(
        children: [
          // Header info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: AppTheme.surfaceSoft,
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Plan iniciado: ${_formatDate(_planActivo!.fechaInicio)} | '
                  '${diagnosticos.length} area(s)',
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _reiniciarPlan,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reiniciar', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          // Lista
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final ubic in agrupado.entries) ...[
                  _UbicacionHeader(ubic.key),
                  for (final subz in ubic.value.entries) ...[
                    _SubzonaHeader(subz.key),
                    for (final diag in subz.value)
                      _DiagnosticoCard(
                        diagnostico: diag,
                        editValoracion: _editValoraciones[diag.id],
                        editObservaciones: _editObservaciones[diag.id],
                        editFoto: _editFotos[diag.id],
                        saving: _saving,
                        onTomarFoto: () => _tomarFoto(diag),
                        onValoracionChanged: (v) =>
                            setState(() => _editValoraciones[diag.id] = v),
                        onObservacionesChanged: (v) =>
                            setState(() => _editObservaciones[diag.id] = v),
                        onGuardar: () => _guardarDiagnostico(diag),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Map<String, List<DiagnosticoAreaModel>>> _agruparDiagnosticos(
      List<DiagnosticoAreaModel> diagnosticos) {
    final map = <String, Map<String, List<DiagnosticoAreaModel>>>{};
    for (final d in diagnosticos) {
      final uName = d.ubicacionNombre;
      final sName = d.subzonaNombre ?? 'Sin subzona';
      map.putIfAbsent(uName, () => {});
      map[uName]!.putIfAbsent(sName, () => []);
      map[uName]![sName]!.add(d);
    }
    return map;
  }

  // ──────────────────────────────────────────────
  // TAB: INFORME
  // ──────────────────────────────────────────────

  Widget _buildInformeTab() {
    if (_planActivo == null) {
      return const Center(
        child: Text('No hay un plan activo para mostrar informe.'),
      );
    }

    if (_informe == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _loadInforme(_planActivo!.id),
              icon: const Icon(Icons.refresh),
              label: const Text('Cargar informe'),
            ),
          ],
        ),
      );
    }

    final informe = _informe!;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: AppTheme.surfaceSoft,
          child: Row(
            children: [
              Text(
                '${informe.conjuntoNombre} — '
                '${_formatDate(informe.fechaInicio)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Descargar PDF',
                onPressed: () {
                  AppFeedback.showInfo(context,
                      message: 'PDF disponible proximamente.');
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final ubic in informe.ubicaciones) ...[
                _UbicacionHeader(ubic.ubicacionNombre),
                for (final subz in ubic.subzonas) ...[
                  _SubzonaHeader(subz.subzonaNombre),
                  for (final area in subz.areas)
                    _AreaInformeCard(area: area),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // TAB: HISTÓRICO
  // ──────────────────────────────────────────────

  Widget _buildHistoricoTab() {
    if (_historico == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadHistorico,
              icon: const Icon(Icons.refresh),
              label: const Text('Cargar historico'),
            ),
          ],
        ),
      );
    }

    if (_historico!.planes.isEmpty) {
      return const Center(child: Text('Aun no hay planes registrados.'));
    }

    final historico = _historico!;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppTheme.surfaceSoft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Planes: ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                ...historico.planes.map((p) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text(
                          _formatDate(p.fechaInicio),
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: p.completado
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    )),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final ubic in historico.ubicaciones) ...[
                _UbicacionHeader(ubic.ubicacionNombre),
                for (final subz in ubic.subzonas) ...[
                  _SubzonaHeader(subz.subzonaNombre),
                  for (final area in subz.areas)
                    _AreaHistoricoCard(
                      area: area,
                      planes: historico.planes,
                    ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

// ──────────────────────────────────────────────
// WIDGETS AUXILIARES
// ──────────────────────────────────────────────

class _UbicacionHeader extends StatelessWidget {
  final String nombre;
  const _UbicacionHeader(this.nombre);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4, top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 4)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, size: 20, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(nombre,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }
}

class _SubzonaHeader extends StatelessWidget {
  final String nombre;
  const _SubzonaHeader(this.nombre);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right,
              size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(nombre,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _DiagnosticoCard extends StatelessWidget {
  final DiagnosticoAreaModel diagnostico;
  final double? editValoracion;
  final String? editObservaciones;
  final SelectedUploadFile? editFoto;
  final bool saving;
  final VoidCallback onTomarFoto;
  final ValueChanged<double> onValoracionChanged;
  final ValueChanged<String> onObservacionesChanged;
  final VoidCallback onGuardar;

  const _DiagnosticoCard({
    required this.diagnostico,
    this.editValoracion,
    this.editObservaciones,
    this.editFoto,
    required this.saving,
    required this.onTomarFoto,
    required this.onValoracionChanged,
    required this.onObservacionesChanged,
    required this.onGuardar,
  });

  @override
  Widget build(BuildContext context) {
    final tieneCambios = editValoracion != null ||
        editObservaciones != null ||
        editFoto != null;
    final fotoActual = editFoto ?? diagnostico.urlFoto;

    return Card(
      margin: const EdgeInsets.only(left: 32, bottom: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre del area
            Row(
              children: [
                Expanded(
                  child: Text(
                    diagnostico.elementoNombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                if (tieneCambios)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Sin guardar',
                        style: TextStyle(fontSize: 10, color: Colors.amber)),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Foto
            Row(
              children: [
                GestureDetector(
                  onTap: fotoActual != null ? () => _showFoto(context, fotoActual) : null,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                      image: fotoActual != null
                          ? DecorationImage(
                              image: _imageProvider(fotoActual),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: fotoActual == null
                        ? const Icon(Icons.add_a_photo,
                            size: 32, color: Colors.grey)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: saving ? null : onTomarFoto,
                      icon: Icon(Icons.camera_alt, size: 18),
                      label: Text(
                          fotoActual != null ? 'Reemplazar' : 'Agregar foto'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Valoración
            StarRatingInput(
              initialRating: diagnostico.valoracion ?? 0,
              onChanged: onValoracionChanged,
            ),
            const SizedBox(height: 8),

            // Observaciones
            TextField(
              decoration: InputDecoration(
                hintText: 'Observaciones...',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
              controller: TextEditingController(
                text: editObservaciones ?? diagnostico.observaciones ?? '',
              )..selection = TextSelection.fromPosition(
                  TextPosition(
                      offset:
                          (editObservaciones ?? diagnostico.observaciones ?? '')
                              .length)),
              onChanged: onObservacionesChanged,
            ),
            const SizedBox(height: 8),

            // Guardar
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed:
                    (saving || !tieneCambios) ? null : onGuardar,
                icon: Icon(Icons.save, size: 18),
                label: Text(saving ? 'Guardando...' : 'Guardar'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ImageProvider _imageProvider(dynamic foto) {
    if (foto is SelectedUploadFile) {
      if (foto.hasPath) return FileImage(File(foto.path!));
      if (foto.hasBytes) return MemoryImage(foto.bytes!);
    }
    if (foto is String && foto.isNotEmpty) return NetworkImage(foto);
    return const AssetImage('');
  }

  void _showFoto(BuildContext context, dynamic foto) {
    final provider = _imageProvider(foto);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: (provider is AssetImage)
            ? const Icon(Icons.image_not_supported, size: 64)
            : Image(image: provider, fit: BoxFit.contain),
      ),
    );
  }
}

class _AreaInformeCard extends StatelessWidget {
  final AreaInforme area;
  const _AreaInformeCard({required this.area});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(left: 32, bottom: 4),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (area.urlFoto != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  area.urlFoto!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, size: 24),
                  ),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.image_not_supported, size: 24),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(area.elementoNombre,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (area.valoracion != null)
                    StarRating(rating: area.valoracion!, starSize: 16),
                  if (area.observaciones != null && area.observaciones!.isNotEmpty)
                    Text(area.observaciones!,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaHistoricoCard extends StatelessWidget {
  final AreaHistorico area;
  final List<PlanResumen> planes;
  const _AreaHistoricoCard({required this.area, required this.planes});

  @override
  Widget build(BuildContext context) {
    final entradas = area.entradas;
    if (entradas.isEmpty) return const SizedBox.shrink();

    double? primeraVal;
    double? ultimaVal;
    if (entradas.isNotEmpty) {
      primeraVal = entradas.first.valoracion;
      ultimaVal = entradas.last.valoracion;
    }

    String tendencia = '➡️';
    Color tendenciaColor = Colors.grey;
    if (primeraVal != null && ultimaVal != null) {
      final diff = ultimaVal - primeraVal;
      if (diff > 0.2) {
        tendencia = '📈';
        tendenciaColor = Colors.green;
      } else if (diff < -0.2) {
        tendencia = '📉';
        tendenciaColor = Colors.red;
      }
    }

    return Card(
      margin: const EdgeInsets.only(left: 32, bottom: 4),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(area.elementoNombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                Text(tendencia,
                    style: TextStyle(color: tendenciaColor, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: entradas.map((e) {
                  return Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmtDate(e.fecha),
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        if (e.valoracion != null)
                          StarRating(rating: e.valoracion!, starSize: 14),
                        if (e.urlFoto != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              e.urlFoto!,
                              width: 120,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 120,
                                height: 60,
                                child: Icon(Icons.broken_image, size: 24),
                              ),
                            ),
                          ),
                        if (e.observaciones != null &&
                            e.observaciones!.isNotEmpty)
                          Text(e.observaciones!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

extension on PlanEsperanzaActivo {
  PlanEsperanzaActivo copyWithDiagnostico(DiagnosticoAreaModel updated) {
    return PlanEsperanzaActivo(
      id: id,
      conjuntoId: conjuntoId,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      completado: completado,
      diagnosticos: diagnosticos.map((d) {
        if (d.id == updated.id) return updated;
        return d;
      }).toList(),
    );
  }
}
