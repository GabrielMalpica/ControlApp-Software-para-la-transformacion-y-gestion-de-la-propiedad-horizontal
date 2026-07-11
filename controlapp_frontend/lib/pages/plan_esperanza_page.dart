import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/plan_esperanza_api.dart';
import 'package:flutter_application_1/model/plan_esperanza_model.dart';
import 'package:flutter_application_1/pdf/pdf_actions.dart';
import 'package:flutter_application_1/pdf/plan_esperanza_pdf.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/evidence_utils.dart';
import 'package:flutter_application_1/utils/pickers/camera_capture_bridge.dart';
import 'package:flutter_application_1/utils/pickers/file_pick_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';
import 'package:flutter_application_1/widgets/star_rating.dart';

class PlanEsperanzaPage extends StatefulWidget {
  final String nit;
  final String? nombreConjunto;

  const PlanEsperanzaPage({super.key, required this.nit, this.nombreConjunto});

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
  HistoricoResponse? _historico;
  List<PlanResumen> _allPlanes = [];
  final Set<int> _selectedHistoricoPlanIds = {};

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
        _historico = null;
        _selectedHistoricoPlanIds.clear();
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

  Future<InformeResponse?> _loadInforme(int planId) async {
    try {
      final informe = await _api.obtenerInforme(planId);
      if (!mounted) return null;
      return informe;
    } catch (e) {
      if (!mounted) return null;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(
          e,
          fallback: 'No se pudo cargar el informe.',
        ),
      );
    }
    return null;
  }

  Future<void> _loadHistorico({List<int>? planIds}) async {
    try {
      final historico = await _api.obtenerHistorico(
        widget.nit,
        planIds: planIds,
      );
      if (!mounted) return;
      setState(() => _historico = historico);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(
          e,
          fallback: 'No se pudo cargar el historico.',
        ),
      );
    }
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && _allPlanes.isEmpty) {
      _loadAllPlanes();
    } else if (_tabController.index == 2) {
      if (_allPlanes.isEmpty) {
        _loadAllPlanes();
      }
      if (_historico == null) {
        _loadHistorico();
      }
    }
  }

  Future<void> _loadAllPlanes() async {
    try {
      final planes = await _api.listarPlanes(widget.nit);
      if (!mounted) return;
      setState(() {
        _allPlanes = planes;
        if (_selectedHistoricoPlanIds.isEmpty && planes.isNotEmpty) {
          _selectedHistoricoPlanIds.addAll(planes.take(3).map((p) => p.id));
        }
      });
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(
          e,
          fallback: 'No se pudieron cargar los planes.',
        ),
      );
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
          'finales del conjunto. ¿Desea continuar?',
        ),
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
                borderRadius: BorderRadius.circular(12),
              ),
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
        _historico = null;
        _saving = false;
      });
      _tabController.animateTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo iniciar el plan.'),
      );
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
          'Se guardaran las calificaciones, observaciones y fotos pendientes. '
          'Luego ya no podra editar los diagnosticos.',
        ),
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
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await _guardarCambiosPendientes();
      await _api.finalizarPlan(_planActivo!.id);
      if (!mounted) return;
      await _loadAll();
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(
        context,
        message: AppError.messageOf(
          e,
          fallback: 'No se pudo finalizar el plan.',
        ),
      );
    }
  }

  Future<void> _reiniciarPlan() async {
    final check = await _api.verificarZonasNuevas(widget.nit);
    if (!mounted) return;

    final opcion = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final mensaje = check.hayZonasNuevas
            ? 'Se han agregado ${check.zonasActuales - check.zonasExistentes} '
                  'zona(s) nueva(s). ¿Que desea hacer con las evidencias actuales?'
            : '¿Que desea hacer con las evidencias actuales?';
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Mantener evidencias'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
      final plan = await _api.reiniciarPlan(
        widget.nit,
        mantenerEvidencias: opcion == 'mantener',
      );
      if (!mounted) return;
      _editValoraciones.clear();
      _editObservaciones.clear();
      _editFotos.clear();
      setState(() {
        _planActivo = plan;
        _historico = null;
        _saving = false;
      });
      _tabController.animateTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.showError(
        context,
        message: AppError.messageOf(
          e,
          fallback: 'No se pudo reiniciar el plan.',
        ),
      );
    }
  }

  Future<void> _guardarCambiosPendientes() async {
    final plan = _planActivo;
    if (plan == null) return;

    final updatedDiagnosticos = <DiagnosticoAreaModel>[];
    for (final diag in plan.diagnosticos) {
      final valoracion = _editValoraciones[diag.id];
      final observaciones = _editObservaciones[diag.id];
      final foto = _editFotos[diag.id];

      if (valoracion == null && observaciones == null && foto == null) {
        updatedDiagnosticos.add(diag);
        continue;
      }

      final updated = await _api.guardarDiagnostico(
        diag.id,
        valoracion: valoracion,
        observaciones: observaciones,
        foto: foto,
      );
      updatedDiagnosticos.add(updated);
    }

    _editValoraciones.clear();
    _editObservaciones.clear();
    _editFotos.clear();
    if (!mounted) return;
    setState(() {
      _planActivo = PlanEsperanzaActivo(
        id: plan.id,
        conjuntoId: plan.conjuntoId,
        fechaInicio: plan.fechaInicio,
        fechaFin: plan.fechaFin,
        completado: plan.completado,
        diagnosticos: updatedDiagnosticos,
      );
    });
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Agregar foto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
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
              'Cada cuantos meses se debe realizar el Plan Esperanza?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Meses',
                suffixText: 'meses',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                AppFeedback.showError(
                  ctx,
                  message: 'Ingrese un valor entre 1 y 60.',
                );
                return;
              }
              Navigator.pop(ctx, v);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      try {
        final config = await _api.actualizarConfig(widget.nit, result);
        if (!mounted) return;
        setState(() => _config = config);
      } catch (e) {
        if (!mounted) return;
        AppFeedback.showError(
          context,
          message: AppError.messageOf(
            e,
            fallback: 'No se pudo actualizar la configuracion.',
          ),
        );
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
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
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
                    Icon(Icons.cloud_off, size: 64, color: Colors.red.shade200),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _loadAll,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                borderRadius: BorderRadius.circular(16),
              ),
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
                child: Icon(
                  Icons.health_and_safety,
                  size: 64,
                  color: AppTheme.primary.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'No hay un Plan Esperanza activo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Inicie uno nuevo para comenzar los diagnosticos '
                'de todas las areas del conjunto.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _iniciarPlan,
                icon: const Icon(Icons.play_arrow, size: 22),
                label: Text(
                  _saving ? 'Iniciando...' : 'Empezar Plan Esperanza',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
              child: const Icon(
                Icons.check_circle,
                size: 64,
                color: AppTheme.green,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Plan completado',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _planActivo!.fechaFin != null
                  ? 'Finalizado el ${_formatDate(_planActivo!.fechaFin)}'
                  : '',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _iniciarPlan,
              icon: const Icon(Icons.refresh),
              label: const Text('Iniciar nuevo plan'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final diagnosticos = _planActivo!.diagnosticos;
    final agrupado = _agruparDiagnosticos(diagnosticos);
    final totalGuardados = diagnosticos
        .where((d) => d.valoracion != null)
        .length;

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
                  child: Text('No hay areas diagnosticadas en este plan.'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  children: [
                    for (final ubic in agrupado.entries) ...[
                      _UbicacionHeader(
                        nombre: ubic.key,
                        total: _totalEnUbicacion(ubic.value),
                        completadas: _completadasEnUbicacion(ubic.value),
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
                            onValoracionChanged: (v) =>
                                setState(() => _editValoraciones[diag.id] = v),
                            onObservacionesChanged: (v) =>
                                setState(() => _editObservaciones[diag.id] = v),
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
    List<DiagnosticoAreaModel> diagnosticos,
  ) {
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

  int _totalEnUbicacion(Map<String, List<DiagnosticoAreaModel>> subzonas) {
    return subzonas.values.fold(0, (s, l) => s + l.length);
  }

  int _completadasEnUbicacion(
    Map<String, List<DiagnosticoAreaModel>> subzonas,
  ) {
    return subzonas.values.fold(
      0,
      (s, l) => s + l.where((d) => d.valoracion != null).length,
    );
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
            Text(
              'No hay planes registrados',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Inicie un Plan Esperanza para ver informes.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (_allPlanes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: _allPlanes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final plan = _allPlanes[index];
        final color = plan.completado ? AppTheme.green : Colors.orange;
        return _PlanInformeTile(
          plan: plan,
          color: color,
          onTap: () => _abrirInforme(plan),
        );
      },
    );
  }

  Future<void> _abrirInforme(PlanResumen plan) async {
    setState(() => _saving = true);
    final informe = await _loadInforme(plan.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (informe == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: _InformeDialog(
          informe: informe,
          onPdf: () => _descargarInformePdf(informe),
        ),
      ),
    );
  }

  Future<void> _descargarInformePdf(InformeResponse informe) async {
    try {
      final bytes = await buildPlanEsperanzaInformePdf(informe);
      final conjunto = _safeFileSegment(informe.conjuntoNombre);
      await openOrDownloadPdf(
        bytes,
        'plan_esperanza_${conjunto.isEmpty ? 'conjunto' : conjunto}_${_fileDate(informe.fechaInicio)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo generar el PDF.'),
      );
    }
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
              onPressed: () => _loadHistorico(),
              icon: const Icon(Icons.refresh),
              label: const Text('Cargar historico'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
            Text(
              'Aun no hay planes registrados.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final historico = _historico!;

    final planesSeleccionables = _allPlanes.isNotEmpty
        ? _allPlanes
        : historico.planes;

    return Column(
      children: [
        _HistoricoSelector(
          planes: planesSeleccionables,
          selectedIds: _selectedHistoricoPlanIds,
          onChanged: (ids) {
            setState(() {
              _selectedHistoricoPlanIds
                ..clear()
                ..addAll(ids);
            });
          },
          onGenerar: _selectedHistoricoPlanIds.isEmpty
              ? null
              : () =>
                    _loadHistorico(planIds: _selectedHistoricoPlanIds.toList()),
          onPdf: historico.planes.isEmpty
              ? null
              : () => _descargarHistoricoPdf(historico),
        ),
        Expanded(child: _HistoricoDetalle(historico: historico)),
      ],
    );
  }

  Future<void> _descargarHistoricoPdf(HistoricoResponse historico) async {
    try {
      final bytes = await buildPlanEsperanzaHistoricoPdf(
        historico,
        conjuntoNombre: widget.nombreConjunto ?? 'Plan Esperanza',
      );
      await openOrDownloadPdf(
        bytes,
        'historico_plan_esperanza_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        message: AppError.messageOf(e, fallback: 'No se pudo generar el PDF.'),
      );
    }
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  static String _fileDate(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  static String _safeFileSegment(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static ImageProvider _imageProvider(dynamic foto) {
    if (foto is SelectedUploadFile) {
      if (foto.hasPath) return FileImage(File(foto.path!));
      if (foto.hasBytes) return MemoryImage(foto.bytes!);
    }
    if (foto is String) {
      final urls = evidenceUrlCandidates(foto);
      if (urls.isNotEmpty) return NetworkImage(urls.first);
    }
    return const AssetImage('');
  }

  static Widget _buildPhotoWidget(
    dynamic foto, {
    required Widget fallback,
    required BoxFit fit,
    double? width,
    double? height,
  }) {
    if (foto is SelectedUploadFile) {
      return Image(
        image: _imageProvider(foto),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    if (foto is String && foto.trim().isNotEmpty) {
      return _CandidateNetworkImage(
        urls: evidenceUrlCandidates(foto),
        fit: fit,
        width: width,
        height: height,
        fallback: fallback,
      );
    }

    return fallback;
  }
}

// ──────────────────────────────────────────────
// STATELESS WIDGETS
// ──────────────────────────────────────────────

class _PlanInformeTile extends StatelessWidget {
  final PlanResumen plan;
  final Color color;
  final VoidCallback onTap;

  const _PlanInformeTile({
    required this.plan,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(Icons.description, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Informe ${_PlanEsperanzaPageState._formatDate(plan.fechaInicio)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${plan.totalAreas} areas - ${plan.completado ? "Finalizado" : "Activo"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _InformeDialog extends StatelessWidget {
  final InformeResponse informe;
  final VoidCallback onPdf;

  const _InformeDialog({required this.informe, required this.onPdf});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.description, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Informe ${_PlanEsperanzaPageState._formatDate(informe.fechaInicio)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Guardar PDF',
                  icon: Icon(Icons.picture_as_pdf, color: Colors.red.shade400),
                  onPressed: onPdf,
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _InformeDetalle(informe: informe)),
        ],
      ),
    );
  }
}

class _InformeDetalle extends StatelessWidget {
  final InformeResponse informe;

  const _InformeDetalle({required this.informe});

  @override
  Widget build(BuildContext context) {
    if (informe.ubicaciones.isEmpty) {
      return Center(
        child: Text(
          'No hay datos en este informe.',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final ubic in informe.ubicaciones) ...[
          _UbicacionHeader(
            nombre: ubic.ubicacionNombre,
            total: ubic.subzonas.fold<int>(0, (s, sz) => s + sz.areas.length),
            completadas: ubic.subzonas.fold<int>(
              0,
              (s, sz) => s + sz.areas.where((a) => a.valoracion != null).length,
            ),
          ),
          for (final subz in ubic.subzonas) ...[
            _SubzonaHeader(nombre: subz.subzonaNombre),
            for (final area in subz.areas) _AreaInformeCard(area: area),
          ],
        ],
      ],
    );
  }
}

class _HistoricoSelector extends StatelessWidget {
  final List<PlanResumen> planes;
  final Set<int> selectedIds;
  final ValueChanged<Set<int>> onChanged;
  final VoidCallback? onGenerar;
  final VoidCallback? onPdf;

  const _HistoricoSelector({
    required this.planes,
    required this.selectedIds,
    required this.onChanged,
    required this.onGenerar,
    required this.onPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: AppTheme.primary, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${selectedIds.length} plan(es) seleccionados',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.picture_as_pdf,
                  color: onPdf == null
                      ? Colors.grey.shade400
                      : Colors.red.shade400,
                  size: 22,
                ),
                tooltip: 'Guardar PDF',
                onPressed: onPdf,
              ),
              FilledButton.icon(
                onPressed: onGenerar,
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Generar'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final plan in planes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: selectedIds.contains(plan.id),
                      label: Text(
                        _PlanEsperanzaPageState._formatDate(plan.fechaInicio),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onSelected: (selected) {
                        final next = Set<int>.from(selectedIds);
                        if (selected) {
                          next.add(plan.id);
                        } else {
                          next.remove(plan.id);
                        }
                        onChanged(next);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoricoDetalle extends StatelessWidget {
  final HistoricoResponse historico;

  const _HistoricoDetalle({required this.historico});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final ubic in historico.ubicaciones) ...[
          _UbicacionHeader(
            nombre: ubic.ubicacionNombre,
            total: ubic.subzonas.fold<int>(0, (s, sz) => s + sz.areas.length),
            completadas: ubic.subzonas.fold<int>(
              0,
              (s, sz) =>
                  s +
                  sz.areas.where((a) {
                    return a.entradas.any((e) => e.valoracion != null);
                  }).length,
            ),
          ),
          for (final subz in ubic.subzonas) ...[
            _SubzonaHeader(nombre: subz.subzonaNombre),
            for (final area in subz.areas)
              _AreaHistoricoCard(area: area, planes: historico.planes),
          ],
        ],
      ],
    );
  }
}

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
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _PlanEsperanzaPageState._formatDate(fechaInicio),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: AppTheme.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$completadas/$totalAreas',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.green,
                      ),
                    ),
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
                          : AppTheme.primary,
                    ),
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
            child: Icon(Icons.location_on, size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nombre,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppTheme.text,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: completadas == total && total > 0
                  ? AppTheme.green.withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$completadas/$total',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: completadas == total && total > 0
                    ? AppTheme.green
                    : Colors.grey.shade600,
              ),
            ),
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
          Icon(
            Icons.subdirectory_arrow_right,
            size: 18,
            color: Colors.grey.shade400,
          ),
          const SizedBox(width: 4),
          Text(
            nombre,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
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

  const _DiagnosticoCard({
    required this.diagnostico,
    this.editValoracion,
    this.editObservaciones,
    this.editFoto,
    required this.saving,
    required this.onTomarFoto,
    required this.onValoracionChanged,
    required this.onObservacionesChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tieneCambios =
        editValoracion != null || editObservaciones != null || editFoto != null;
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
                  child: Icon(
                    Icons.crop_square,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diagnostico.elementoNombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.text,
                    ),
                  ),
                ),
                if (tieneCambios)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Text(
                      'Pendiente',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
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
                             child: _PlanEsperanzaPageState._buildPhotoWidget(
                               fotoActual,
                               fallback: _fotoPlaceholder(),
                               fit: BoxFit.cover,
                               width: 88,
                               height: 88,
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
                          fotoActual != null
                              ? Icons.swap_horiz
                              : Icons.camera_alt,
                          size: 16,
                        ),
                        label: Text(
                          fotoActual != null ? 'Cambiar' : 'Agregar foto',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          backgroundColor: AppTheme.surfaceSoft,
                          foregroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      StarRatingInput(
                        initialRating:
                            editValoracion ?? diagnostico.valoracion ?? 0,
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
              controller:
                  TextEditingController(
                      text:
                          editObservaciones ?? diagnostico.observaciones ?? '',
                    )
                    ..selection = TextSelection.fromPosition(
                      TextPosition(
                        offset:
                            (editObservaciones ??
                                    diagnostico.observaciones ??
                                    '')
                                .length,
                      ),
                    ),
              onChanged: onObservacionesChanged,
            ),
            if (tieneCambios) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Se guardara al finalizar el plan.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
        Text(
          'Foto',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
        ),
      ],
    );
  }

  void _showFotoDialog(BuildContext context, dynamic foto) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            child: Container(
              color: Colors.black,
              constraints: const BoxConstraints(minHeight: 240, minWidth: 240),
              child: _PlanEsperanzaPageState._buildPhotoWidget(
                foto,
                fallback: Center(
                  child: Icon(
                    Icons.image_not_supported,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 52,
                  ),
                ),
                fit: BoxFit.contain,
              ),
            ),
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
          GestureDetector(
            onTap: area.urlFoto != null
                ? () => _showStaticPhotoDialog(context, area.urlFoto!)
                : null,
            child: ClipRounded(
              size: 56,
              child: area.urlFoto != null
                  ? _PlanEsperanzaPageState._buildPhotoWidget(
                      area.urlFoto!,
                      fallback: _noImage(),
                      fit: BoxFit.cover,
                      width: 56,
                      height: 56,
                    )
                  : _noImage(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  area.elementoNombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                if (area.valoracion != null)
                  StarRating(rating: area.valoracion!, starSize: 16),
                if (area.observaciones != null &&
                    area.observaciones!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      area.observaciones!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (area.valoracion != null)
            Text(
              area.valoracion!.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
            ),
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

  void _showStaticPhotoDialog(BuildContext context, String fotoUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            child: Container(
              color: Colors.black,
              constraints: const BoxConstraints(minHeight: 240, minWidth: 240),
              child: _PlanEsperanzaPageState._buildPhotoWidget(
                fotoUrl,
                fallback: Center(
                  child: Icon(
                    Icons.image_not_supported,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 52,
                  ),
                ),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
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

class _CandidateNetworkImage extends StatelessWidget {
  final List<String> urls;
  final BoxFit fit;
  final Widget fallback;
  final double? width;
  final double? height;

  const _CandidateNetworkImage({
    required this.urls,
    required this.fit,
    required this.fallback,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUrls = urls.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return _buildFromIndex(cleanUrls, 0);
  }

  Widget _buildFromIndex(List<String> cleanUrls, int index) {
    if (cleanUrls.isEmpty || index >= cleanUrls.length) {
      return fallback;
    }

    return Image.network(
      cleanUrls[index],
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _buildFromIndex(cleanUrls, index + 1),
    );
  }
}

class _AreaHistoricoCard extends StatefulWidget {
  final AreaHistorico area;
  final List<PlanResumen> planes;

  const _AreaHistoricoCard({required this.area, required this.planes});

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
                        ? GestureDetector(
                            onTap: () => _showPhotoDialog(ultima.urlFoto!),
                            child: _PlanEsperanzaPageState._buildPhotoWidget(
                              ultima.urlFoto!,
                              fallback: _imageFallback(),
                              fit: BoxFit.cover,
                              width: 40,
                              height: 40,
                            ),
                          )
                        : _imageFallback(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.area.elementoNombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entradas.length} evaluacion(es) · ${_PlanEsperanzaPageState._formatDate(entradas.first.fecha)} → ${_PlanEsperanzaPageState._formatDate(entradas.last.fecha)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$tendencia ',
                  style: TextStyle(fontSize: 18, color: tendenciaColor),
                ),
                if (diff != null)
                  Text(
                    '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tendenciaColor,
                    ),
                  ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expandido ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more,
                    color: Colors.grey.shade500,
                    size: 22,
                  ),
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
              Icon(Icons.calendar_today, size: 11, color: AppTheme.primary),
              const SizedBox(width: 4),
              Text(
                _PlanEsperanzaPageState._formatDate(entry.fecha),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (entry.urlFoto != null)
            GestureDetector(
              onTap: () => _showPhotoDialog(entry.urlFoto!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _PlanEsperanzaPageState._buildPhotoWidget(
                  entry.urlFoto!,
                  fallback: Container(
                    width: 140,
                    height: 80,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.broken_image, color: Colors.grey.shade400),
                  ),
                  fit: BoxFit.cover,
                  width: 140,
                  height: 80,
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (entry.valoracion != null)
            StarRating(rating: entry.valoracion!, starSize: 14),
          if (entry.observaciones != null && entry.observaciones!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                entry.observaciones!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _imageFallback() {
    return Container(
      color: Colors.grey.shade100,
      child: Icon(
        Icons.image_not_supported,
        size: 20,
        color: Colors.grey.shade300,
      ),
    );
  }

  void _showPhotoDialog(String fotoUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            child: Container(
              color: Colors.black,
              constraints: const BoxConstraints(minHeight: 240, minWidth: 240),
              child: _PlanEsperanzaPageState._buildPhotoWidget(
                fotoUrl,
                fallback: Center(
                  child: Icon(
                    Icons.image_not_supported,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 52,
                  ),
                ),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
