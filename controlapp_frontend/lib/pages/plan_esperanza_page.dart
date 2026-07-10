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
  List<PlanResumen> _allPlanes = [];
  int? _selectedPlanInfoId;

  final Map<int, double> _editValoraciones = {};
  final Map<int, String> _editObservaciones = {};
  final Map<int, SelectedUploadFile?> _editFotos = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
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
        _allPlanes = [];
        _informe = null;
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

  void _onTabChanged() {
    if (_tabController.index == 1 && _allPlanes.isEmpty) {
      _loadAllPlanes();
    } else if (_tabController.index == 2 && _historico == null) {
      _loadHistorico();
    }
  }

  Future<void> _loadAllPlanes() async {
    try {
      final planes = await _api.listarPlanes(widget.nit);
      if (!mounted) return;
      setState(() {
        _allPlanes = planes;
        if (planes.isNotEmpty && _selectedPlanInfoId == null) {
          _selectedPlanInfoId = planes.first.id;
          _loadInforme(planes.first.id);
        }
      });
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context,
          message: AppError.messageOf(e,
              fallback: 'No se pudieron cargar los planes.'));
    }
  }

  Future<void> _iniciarPlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.health_and_safety, color: AppTheme.primary, size: 28),
            const SizedBox(width: 10),
            const Text('Iniciar Plan Esperanza'),
          ],
        ),
        content: const Text(
          'Se iniciara un nuevo Plan Esperanza con todas las areas '
          'finales del conjunto. ¿Desea continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.green, size: 28),
            const SizedBox(width: 10),
            const Text('Finalizar Plan'),
          ],
        ),
        content: const Text(
          '¿Esta seguro de finalizar este plan? Ya no podra '
          'editar los diagnosticos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.refresh, color: Colors.orange, size: 28),
              const SizedBox(width: 10),
              const Text('Reiniciar Plan'),
            ],
          ),
          content: Text(mensaje),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'mantener'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Mantener evidencias'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, 'nuevas'),
              child: const Text('Tomar nuevas'),
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(context,
          message: AppError.messageOf(e,
              fallback: 'No se pudo guardar el diagnostico.'));
    }
  }

  Future<void> _tomarFoto(DiagnosticoAreaModel diag) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Agregar foto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Icon(Icons.camera_alt, color: AppTheme.primary),
                ),
                title: const Text('Tomar foto'),
                subtitle: const Text('Usa la camara del dispositivo'),
                onTap: () => Navigator.pop(ctx, 'camara'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                  child: const Icon(Icons.photo_library, color: Colors.orange),
                ),
                title: const Text('Adjuntar desde galeria'),
                subtitle: const Text('Selecciona una imagen existente'),
                onTap: () => Navigator.pop(ctx, 'galeria'),
              ),
            ],
          ),
        ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.settings, color: AppTheme.primary, size: 28),
            const SizedBox(width: 10),
            const Text('Configuracion'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cada cuantos meses se debe realizar el Plan Esperanza?'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Meses',
                suffixText: 'meses',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppTheme.surfaceSoft,
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
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      try {
        final config = await _api.actualizarConfig(widget.nit, result);
        setState(() => _config = config);
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
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.health_and_safety, size: 26),
            const SizedBox(width: 8),
            Text(widget.nombreConjunto ?? 'Plan Esperanza'),
          ],
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: 'Configurar periodicidad',
            onPressed: _showConfigDialog,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: AppTheme.primaryDark,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.edit_note, size: 22), text: 'Diagnostico'),
                Tab(icon: Icon(Icons.description, size: 22), text: 'Informe'),
                Tab(icon: Icon(Icons.history, size: 22), text: 'Historico'),
              ],
            ),
          ),
        ),
      ),
      body: _loadingPlan
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off,
                            size: 64, color: Colors.red.shade200),
                        const SizedBox(height: 16),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade700, fontSize: 15)),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loadAll,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
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
              onPressed: _saving ? null : _finalizarPlan,
              icon: const Icon(Icons.check_circle),
              label: const Text('Finalizar Plan'),
              backgroundColor: AppTheme.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.health_and_safety,
                    size: 64, color: AppTheme.primary.withValues(alpha: 0.4)),
              ),
              const SizedBox(height: 24),
              const Text('No hay un Plan Esperanza activo',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppTheme.text)),
              const SizedBox(height: 8),
              Text(
                'Inicie uno nuevo para comenzar los diagnosticos '
                'de todas las areas del conjunto.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _iniciarPlan,
                icon: const Icon(Icons.play_arrow, size: 22),
                label: Text(_saving ? 'Iniciando...' : 'Empezar Plan Esperanza',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_planActivo!.completado) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.check_circle, size: 64, color: AppTheme.green),
            ),
            const SizedBox(height: 24),
            Text('Plan completado',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_planActivo!.fechaFin != null
                ? 'Finalizado el ${_formatDate(_planActivo!.fechaFin)}'
                : ''),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _iniciarPlan,
              icon: const Icon(Icons.refresh),
              label: const Text('Iniciar nuevo plan'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    final diagnosticos = _planActivo!.diagnosticos;
    final agrupado = _agruparDiagnosticos(diagnosticos);
    final totalGuardados =
        diagnosticos.where((d) => d.valoracion != null).length;

    return Column(
      children: [
        _InfoBar(
          fechaInicio: _planActivo!.fechaInicio,
          totalAreas: diagnosticos.length,
          completadas: totalGuardados,
          onReiniciar: _reiniciarPlan,
        ),
        Expanded(
          child: diagnosticos.isEmpty
              ? const Center(
                  child: Text('No hay areas diagnosticadas en este plan.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  children: [
                    for (final ubic in agrupado.entries) ...[
                      _UbicacionHeader(
                        nombre: ubic.key,
                        total: _totalEnUbicacion(ubic.value),
                        completadas:
                            _completadasEnUbicacion(ubic.value),
                      ),
                      for (final subz in ubic.value.entries) ...[
                        _SubzonaHeader(nombre: subz.key),
                        for (final diag in subz.value)
                          _DiagnosticoCard(
                            diagnostico: diag,
                            editValoracion: _editValoraciones[diag.id],
                            editObservaciones: _editObservaciones[diag.id],
                            editFoto: _editFotos[diag.id],
                            saving: _saving,
                            onTomarFoto: () => _tomarFoto(diag),
                            onValoracionChanged: (v) => setState(
                                () => _editValoraciones[diag.id] = v),
                            onObservacionesChanged: (v) => setState(
                                () => _editObservaciones[diag.id] = v),
                            onGuardar: () => _guardarDiagnostico(diag),
                          ),
                      ],
                    ],
                  ],
                ),
        ),
      ],
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

  int _totalEnUbicacion(
      Map<String, List<DiagnosticoAreaModel>> subzonas) {
    return subzonas.values.fold(0, (s, l) => s + l.length);
  }

  int _completadasEnUbicacion(
      Map<String, List<DiagnosticoAreaModel>> subzonas) {
    return subzonas.values.fold(
        0, (s, l) => s + l.where((d) => d.valoracion != null).length);
  }

  // ──────────────────────────────────────────────
  // TAB: INFORME
  // ──────────────────────────────────────────────

  Widget _buildInformeTab() {
    if (_allPlanes.isEmpty && !_loadingPlan) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No hay planes registrados',
                style: TextStyle(
                    fontSize: 16, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text('Inicie un Plan Esperanza para ver informes.',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    if (_allPlanes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.description, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 6),
                  const Text('Seleccione un plan',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const Spacer(),
                  if (_informe != null)
                    IconButton(
                      icon: Icon(Icons.picture_as_pdf,
                          color: Colors.red.shade400, size: 22),
                      tooltip: 'Descargar PDF',
                      onPressed: () {
                        AppFeedback.showInfo(context,
                            message: 'PDF disponible proximamente.');
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _allPlanes.map((p) {
                    final selected = _selectedPlanInfoId == p.id;
                    final color = p.completado
                        ? AppTheme.green
                        : AppTheme.primary;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: selected,
                        label: Text(
                          _formatDate(p.fechaInicio),
                          style: TextStyle(
                            fontSize: 12,
                            color: selected ? Colors.white : color,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        avatar: Icon(Icons.circle,
                            size: 8,
                            color: selected ? Colors.white : color),
                        selectedColor: color,
                        checkmarkColor: Colors.white,
                        backgroundColor: color.withValues(alpha: 0.1),
                        side: BorderSide.none,
                        onSelected: (_) {
                          setState(() {
                            _selectedPlanInfoId = p.id;
                            _informe = null;
                          });
                          _loadInforme(p.id);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _informe == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2),
                      const SizedBox(height: 12),
                      Text('Cargando informe...',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : _informe!.ubicaciones.isEmpty
                  ? Center(
                      child: Text('No hay datos en este informe.',
                          style: TextStyle(color: Colors.grey.shade500)))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final ubic in _informe!.ubicaciones) ...[
                          _UbicacionHeader(
                            nombre: ubic.ubicacionNombre,
                            total: ubic.subzonas.fold<int>(
                                0, (s, sz) => s + sz.areas.length),
                            completadas: ubic.subzonas.fold<int>(0,
                                (s, sz) => s + sz.areas.where((a) => a.valoracion != null).length),
                          ),
                          for (final subz in ubic.subzonas) ...[
                            _SubzonaHeader(nombre: subz.subzonaNombre),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadHistorico,
              icon: const Icon(Icons.refresh),
              label: const Text('Cargar historico'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_historico!.planes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('Aun no hay planes registrados.',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    final historico = _historico!;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceSoft,
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 6),
                  const Text('Linea de tiempo',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.picture_as_pdf,
                        color: Colors.red.shade400, size: 22),
                    tooltip: 'Descargar PDF',
                    onPressed: () {
                      AppFeedback.showInfo(context,
                          message: 'PDF disponible proximamente.');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...historico.planes.map((p) {
                      final activo = _planActivo != null &&
                          _planActivo!.id == p.id;
                      final color = p.completado
                          ? AppTheme.green
                          : activo
                              ? AppTheme.primary
                              : Colors.orange;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          avatar: Icon(Icons.circle, size: 10, color: color),
                          label: Text(
                            _formatDate(p.fechaInicio),
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: color.withValues(alpha: 0.1),
                          side: BorderSide.none,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final ubic in historico.ubicaciones) ...[
                _UbicacionHeader(
                  nombre: ubic.ubicacionNombre,
                  total: ubic.subzonas.fold<int>(
                      0, (s, sz) => s + sz.areas.length),
                  completadas: ubic.subzonas.fold<int>(
                      0, (s, sz) => s + sz.areas.where((a) => a.entradas.any((e) => e.valoracion != null)).length),
                ),
                for (final subz in ubic.subzonas) ...[
                  _SubzonaHeader(nombre: subz.subzonaNombre),
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

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  static ImageProvider _imageProvider(dynamic foto) {
    if (foto is SelectedUploadFile) {
      if (foto.hasPath) return FileImage(File(foto.path!));
      if (foto.hasBytes) return MemoryImage(foto.bytes!);
    }
    if (foto is String && foto.isNotEmpty) return NetworkImage(foto);
    return const AssetImage('');
  }

}

// ──────────────────────────────────────────────
// STATELESS WIDGETS
// ──────────────────────────────────────────────

class _InfoBar extends StatelessWidget {
  final DateTime fechaInicio;
  final int totalAreas;
  final int completadas;
  final VoidCallback onReiniciar;

  const _InfoBar({
    required this.fechaInicio,
    required this.totalAreas,
    required this.completadas,
    required this.onReiniciar,
  });

  @override
  Widget build(BuildContext context) {
    final progreso = totalAreas > 0 ? completadas / totalAreas : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(_PlanEsperanzaPageState._formatDate(fechaInicio),
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700)),
                    const SizedBox(width: 16),
                    Icon(Icons.check_circle_outline, size: 14, color: AppTheme.green),
                    const SizedBox(width: 4),
                    Text('$completadas/$totalAreas',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.green)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progreso,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        completadas == totalAreas && totalAreas > 0
                            ? AppTheme.green
                            : AppTheme.primary),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onReiniciar,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reiniciar', style: TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
          ),
        ],
      ),
    );
  }
}

class _UbicacionHeader extends StatelessWidget {
  final String nombre;
  final int total;
  final int completadas;

  const _UbicacionHeader({
    required this.nombre,
    required this.total,
    required this.completadas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4, top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(Icons.location_on, size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(nombre,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15,
                    color: AppTheme.text)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: completadas == total && total > 0
                  ? AppTheme.green.withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$completadas/$total',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: completadas == total && total > 0
                        ? AppTheme.green
                        : Colors.grey.shade600)),
          ),
        ],
      ),
    );
  }
}

class _SubzonaHeader extends StatelessWidget {
  final String nombre;
  const _SubzonaHeader({required this.nombre});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right,
              size: 18, color: Colors.grey.shade400),
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
      margin: const EdgeInsets.only(left: 36, bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.crop_square,
                      size: 14, color: AppTheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diagnostico.elementoNombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14,
                        color: AppTheme.text),
                  ),
                ),
                if (tieneCambios)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Text('Sin guardar',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Foto + valoración
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: fotoActual != null
                      ? () => _showFotoDialog(context, fotoActual)
                      : null,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: fotoActual != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image(
                              image: _PlanEsperanzaPageState._imageProvider(
                                  fotoActual),
                              fit: BoxFit.cover,
                              width: 88,
                              height: 88,
                              errorBuilder: (_, __, ___) => _fotoPlaceholder(),
                            ),
                          )
                        : _fotoPlaceholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: saving ? null : onTomarFoto,
                        icon: Icon(
                            fotoActual != null ? Icons.swap_horiz : Icons.camera_alt,
                            size: 16),
                        label: Text(
                            fotoActual != null ? 'Cambiar' : 'Agregar foto',
                            style: const TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          backgroundColor: AppTheme.surfaceSoft,
                          foregroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      StarRatingInput(
                        initialRating: diagnostico.valoracion ?? 0,
                        onChanged: onValoracionChanged,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Observaciones
            TextField(
              decoration: InputDecoration(
                hintText: 'Agregar observaciones...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: AppTheme.surface,
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
            const SizedBox(height: 10),

            // Guardar
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: tieneCambios ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: FilledButton.icon(
                  onPressed: (saving || !tieneCambios) ? null : onGuardar,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(saving ? 'Guardando...' : 'Guardar'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fotoPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo, size: 28, color: Colors.grey.shade300),
        const SizedBox(height: 4),
        Text('Foto',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
      ],
    );
  }

  void _showFotoDialog(BuildContext context, dynamic foto) {
    final provider =
        _PlanEsperanzaPageState._imageProvider(foto);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            child: Image(image: provider, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _AreaInformeCard extends StatelessWidget {
  final AreaInforme area;
  const _AreaInformeCard({required this.area});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 36, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          ClipRounded(
            size: 56,
            child: area.urlFoto != null
                ? Image.network(
                    area.urlFoto!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _noImage(),
                  )
                : _noImage(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(area.elementoNombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                if (area.valoracion != null)
                  StarRating(rating: area.valoracion!, starSize: 16),
                if (area.observaciones != null &&
                    area.observaciones!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(area.observaciones!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ),
              ],
            ),
          ),
          if (area.valoracion != null)
            Text(area.valoracion!.toStringAsFixed(1),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary)),
        ],
      ),
    );
  }

  Widget _noImage() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.image_not_supported, color: Colors.grey.shade300),
    );
  }
}

class ClipRounded extends StatelessWidget {
  final double size;
  final Widget child;

  const ClipRounded({super.key, required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

class _AreaHistoricoCard extends StatefulWidget {
  final AreaHistorico area;
  final List<PlanResumen> planes;

  const _AreaHistoricoCard({
    required this.area,
    required this.planes,
  });

  @override
  State<_AreaHistoricoCard> createState() => _AreaHistoricoCardState();
}

class _AreaHistoricoCardState extends State<_AreaHistoricoCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final entradas = widget.area.entradas;
    if (entradas.isEmpty) return const SizedBox.shrink();

    double? primeraVal;
    double? ultimaVal;
    if (entradas.isNotEmpty) {
      primeraVal = entradas.first.valoracion;
      ultimaVal = entradas.last.valoracion;
    }

    String tendencia = '➡️';
    Color tendenciaColor = Colors.grey;
    double? diff;
    if (primeraVal != null && ultimaVal != null) {
      diff = ultimaVal - primeraVal;
      if (diff > 0.2) {
        tendencia = '📈';
        tendenciaColor = AppTheme.green;
      } else if (diff < -0.2) {
        tendencia = '📉';
        tendenciaColor = AppTheme.red;
      } else {
        tendencia = '➡️';
        tendenciaColor = Colors.grey;
      }
    }

    final ultima = entradas.last;

    return Container(
      margin: const EdgeInsets.only(left: 36, bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expandido = !_expandido),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: ultima.urlFoto != null
                        ? Image.network(ultima.urlFoto!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey.shade100,
                                child: Icon(Icons.image_not_supported,
                                    size: 20, color: Colors.grey.shade300)))
                        : Container(
                            color: Colors.grey.shade50,
                            child: Icon(Icons.image_not_supported,
                                size: 20, color: Colors.grey.shade300)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.area.elementoNombre,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        '${entradas.length} evaluacion(es) · ${_PlanEsperanzaPageState._formatDate(entradas.first.fecha)} → ${_PlanEsperanzaPageState._formatDate(entradas.last.fecha)}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Text('$tendencia ',
                    style: TextStyle(
                        fontSize: 18, color: tendenciaColor)),
                if (diff != null)
                  Text(
                    '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tendenciaColor),
                  ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expandido ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      color: Colors.grey.shade500, size: 22),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: entradas.map((e) {
                    return _buildEntryCard(e);
                  }).toList(),
                ),
              ),
            ),
            crossFadeState: _expandido
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(TimelineEntry entry) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today,
                  size: 11, color: AppTheme.primary),
              const SizedBox(width: 4),
              Text(
                _PlanEsperanzaPageState._formatDate(entry.fecha),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (entry.urlFoto != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                entry.urlFoto!,
                width: 140,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 140,
                  height: 80,
                  color: Colors.grey.shade200,
                  child: Icon(Icons.broken_image,
                      color: Colors.grey.shade400),
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (entry.valoracion != null)
            StarRating(rating: entry.valoracion!, starSize: 14),
          if (entry.observaciones != null &&
              entry.observaciones!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(entry.observaciones!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ),
        ],
      ),
    );
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
