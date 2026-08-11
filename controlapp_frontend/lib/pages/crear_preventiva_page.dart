// ignore_for_file: curly_braces_in_flow_control_structures

// lib/pages/crear_preventiva_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:intl/intl.dart';

import '../api/preventiva_api.dart';
import '../api/empresa_api.dart';
import '../api/herramienta_api.dart';
import '../api/gerente_api.dart';

import '../model/preventiva_model.dart';
import '../model/conjunto_model.dart';
import '../model/usuario_model.dart';
import '../model/insumo_model.dart';
import '../model/maquinaria_model.dart';
import '../model/herramienta_model.dart';
import '../widgets/searchable_select_field.dart';

import '../service/theme.dart';
import '../service/api_exception.dart';
import '../utils/frecuencia_utils.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

enum SnackType { info, success, error }

class CrearEditarPreventivaPage extends StatefulWidget {
  final String nit;
  final Conjunto conjunto;
  final DefinicionPreventiva? existente;

  const CrearEditarPreventivaPage({
    super.key,
    required this.nit,
    required this.conjunto,
    this.existente,
  });

  @override
  State<CrearEditarPreventivaPage> createState() =>
      _CrearEditarPreventivaPageState();
}

class _CrearEditarPreventivaPageState extends State<CrearEditarPreventivaPage> {
  final _formKey = GlobalKey<FormState>();

  final _api = DefinicionPreventivaApi();
  final _gerenteApi = GerenteApi();
  final _empresaApi = EmpresaApi();
  final _herramientaApi = HerramientaApi();

  List<InsumoResponse> _catalogoInsumos = [];
  List<HerramientaDisponibilidadResponse> _catalogoHerramientas = [];
  List<Usuario> _supervisores = [];

  // Controllers básicos
  final _descripcionCtrl = TextEditingController();
  final _prioridadCtrl = TextEditingController(text: '2');

  // Duración – rendimiento
  bool _usaRendimiento = true;
  String? _unidadCalculo; // M2, M3, UNIDAD...
  final _cantidadCtrl = TextEditingController();
  final _rendimientoCtrl = TextEditingController();

  // POR_MINUTO: unidades/min | POR_HORA: unidades/h | MIN_POR_UNIDAD: min/unidad
  String _rendimientoTiempoBase = 'POR_MINUTO';

  final _duracionFijaMinCtrl = TextEditingController();

  // ✅ dividir en N días (opcional)
  bool _dividirEnDias = false;
  final _diasParaCompletarCtrl = TextEditingController();

  // Insumo principal
  int? _insumoPrincipalId;
  final _consumoPorUnidadCtrl = TextEditingController();

  final List<_InsumoPlanRow> _insumosPlanRows = [];
  final List<_MaquinariaPlanRow> _maquinariaPlanRows = [];
  final List<_HerramientaPlanRow> _herramientasPlanRows = [];

  String? _frecuencia;
  final Set<String> _diasSemanaProgramados = <String>{};
  int? _diaMesProgramado;
  final List<DateTime> _fechasProgramadas = [];

  final List<String> _operariosSeleccionadosCedulas = [];
  Usuario? _supervisorResponsable;

  bool _activo = true;

  UbicacionConElementos? _ubicacionSeleccionada;
  Elemento? _elementoSeleccionado;

  bool _guardando = false;

  List<UbicacionConElementos> get _ubicaciones => widget.conjunto.ubicaciones;
  List<Usuario> get _operarios => widget.conjunto.operarios;

  /// SEMANAL y QUINCENAL se programan eligiendo uno o varios dias de la semana.
  bool get _frecuenciaUsaDiaSemana =>
      frecuenciasPorDiaSemana.contains(_frecuencia);

  /// Solo SEMANAL admite varios dias; QUINCENAL se ejecuta un unico dia cada 14.
  bool get _usaSelectorMultipleSemanal =>
      frecuenciasMultiDiaSemana.contains(_frecuencia);

  /// Texto de ayuda bajo el selector de dias, segun frecuencia y modo.
  String _ayudaDiasSemana() {
    if (!_usaSelectorMultipleSemanal) {
      return 'La preventiva quincenal se ejecuta cada 14 días: '
          'la 1ª y la 3ª ocurrencia del día elegido dentro del mes.';
    }
    return widget.existente == null
        ? 'Cada día seleccionado se guardará como una preventiva semanal independiente.'
        : 'Se actualizará esta preventiva con el primer día elegido y se crearán '
              'preventivas adicionales para los demás días.';
  }

  bool get _frecuenciaUsaDiaMes => frecuenciasPorDiaMes.contains(_frecuencia);

  bool get _frecuenciaUsaFechasExplicitas =>
      frecuenciasPorFechasExplicitas.contains(_frecuencia);

  int? get _fechasRequeridasFrecuencia =>
      _frecuencia == null ? null : fechasRequeridasPorFrecuencia[_frecuencia!];

  List<String> get _diasSemanaSeleccionadosOrdenados => diasSemanaOpciones
      .where((dia) => _diasSemanaProgramados.contains(dia))
      .toList();

  String _fmtFechaProgramada(DateTime fecha) =>
      DateFormat('yyyy-MM-dd').format(fecha);

  int get _fechasProgramadasRestantes {
    final requeridas = _fechasRequeridasFrecuencia;
    if (requeridas == null) return 0;
    return requeridas - _fechasProgramadas.length;
  }

  String _mensajeFechasFrecuenciaExacta() {
    final requeridas = _fechasRequeridasFrecuencia ?? 0;
    return 'Debes seleccionar exactamente $requeridas fecha${requeridas == 1 ? '' : 's'} para la frecuencia ${_frecuencia ?? ''}.';
  }

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // ===========================
  // helpers fechas disponibilidad
  // ===========================
  Future<void> _initData() async {
    await Future.wait([
      _cargarCatalogoInsumos(),
      _cargarCatalogoHerramientas(),
      _cargarSupervisores(),
    ]);

    if (!mounted) return;
    _cargarDesdeExistenteOInit();

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _agregarFechaProgramada() async {
    final requeridas = _fechasRequeridasFrecuencia;
    if (requeridas != null && _fechasProgramadas.length >= requeridas) {
      _snack(
        'No puedes agregar más fechas. ${_mensajeFechasFrecuenciaExacta()}',
        type: SnackType.error,
      );
      return;
    }

    final ahora = DateTime.now();
    final seleccionada = await showDatePicker(
      context: context,
      initialDate: _fechasProgramadas.isNotEmpty
          ? _fechasProgramadas.last
          : ahora,
      firstDate: DateTime(ahora.year - 1),
      lastDate: DateTime(ahora.year + 10),
    );
    if (seleccionada == null) return;

    final normalizada = DateTime(
      seleccionada.year,
      seleccionada.month,
      seleccionada.day,
    );

    setState(() {
      final existe = _fechasProgramadas.any(
        (item) =>
            item.year == normalizada.year &&
            item.month == normalizada.month &&
            item.day == normalizada.day,
      );
      if (!existe) {
        _fechasProgramadas.add(normalizada);
        _fechasProgramadas.sort((a, b) => a.compareTo(b));
      }
    });
  }

  Future<void> _cargarCatalogoInsumos() async {
    try {
      final lista = await _empresaApi.listarCatalogo();
      if (!mounted) return;
      setState(() {
        _catalogoInsumos = lista;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Error cargando catálogo de insumos: $e', type: SnackType.error);
    }
  }

  Future<void> _cargarCatalogoHerramientas() async {
    try {
      final raw = await _herramientaApi.listarDisponibilidadConjunto(
        nitConjunto: widget.nit,
        empresaId: AppConstants.empresaNit,
      );

      final lista =
          raw
              .map(
                (e) => HerramientaDisponibilidadResponse.fromJson(
                  (e as Map).cast<String, dynamic>(),
                ),
              )
              .where((h) => h.totalDisponible > 0)
              .toList()
            ..sort((a, b) {
              final aConjunto = a.disponibleConjunto > 0 ? 1 : 0;
              final bConjunto = b.disponibleConjunto > 0 ? 1 : 0;
              if (aConjunto != bConjunto) return bConjunto.compareTo(aConjunto);
              return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
            });

      if (!mounted) return;

      setState(() {
        _catalogoHerramientas = lista;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(
        'Error cargando catálogo de herramientas: $e',
        type: SnackType.error,
      );
    }
  }

  Future<void> _cargarSupervisores() async {
    try {
      final supervisores = await _gerenteApi.listarSupervisores();
      if (!mounted) return;
      setState(() => _supervisores = supervisores);
    } catch (e) {
      if (!mounted) return;
      _snack('Error cargando supervisores: $e', type: SnackType.error);
    }
  }

  // ===========================
  // cargar existente / defaults
  // ===========================
  void _cargarDesdeExistenteOInit() {
    final existente = widget.existente;

    if (existente != null) {
      _descripcionCtrl.text = existente.descripcion;
      _prioridadCtrl.text = (existente.prioridad.clamp(1, 3)).toString();
      _frecuencia = existente.frecuencia;
      _unidadCalculo = existente.unidadCalculo;

      _diasSemanaProgramados
        ..clear()
        ..addAll(
          existente.diaSemanaProgramado == null ||
                  existente.diaSemanaProgramado!.isEmpty
              ? const <String>[]
              : [existente.diaSemanaProgramado!],
        );
      _diaMesProgramado = existente.diaMesProgramado;
      _fechasProgramadas
        ..clear()
        ..addAll(existente.fechasProgramadas);

      if (existente.duracionMinutosFija != null) {
        _usaRendimiento = false;
        _duracionFijaMinCtrl.text = existente.duracionMinutosFija!.toString();
      } else {
        _usaRendimiento = true;
        if (existente.areaNumerica != null) {
          _cantidadCtrl.text = existente.areaNumerica!.toString();
        }
        if (existente.rendimientoBase != null) {
          _rendimientoCtrl.text = existente.rendimientoBase!.toString();
        }
      }

      final base = (existente as dynamic).rendimientoTiempoBase;
      if (base is String && base.isNotEmpty) {
        _rendimientoTiempoBase = base;
      }

      final dias = existente.diasParaCompletar;
      if (dias != null && dias > 1) {
        _dividirEnDias = true;
        _diasParaCompletarCtrl.text = dias.toString();
      } else {
        _dividirEnDias = false;
        _diasParaCompletarCtrl.text = '';
      }

      _insumoPrincipalId = existente.insumoPrincipalId;
      if (existente.consumoPrincipalPorUnidad != null) {
        _consumoPorUnidadCtrl.text = existente.consumoPrincipalPorUnidad!
            .toString();
      }

      _insumosPlanRows
        ..clear()
        ..addAll(
          existente.insumosPlan.map(
            (i) => _InsumoPlanRow(
              insumoId: i.insumoId,
              consumoInicial: i.consumoPorUnidad,
            ),
          ),
        );

      _maquinariaPlanRows
        ..clear()
        ..addAll(
          existente.maquinariaPlan
              .where((m) => m.tipoEnum != null)
              .map(
                (m) => _MaquinariaPlanRow(
                  tipo: m.tipoEnum,
                  cantidad: (m.cantidad ?? 1).round().clamp(1, 99),
                  maquinariaSugeridaId: m.maquinariaSugeridaId,
                ),
              ),
        );

      _herramientasPlanRows.clear();
      for (final h in existente.herramientasPlan) {
        _herramientasPlanRows.add(
          _HerramientaPlanRow(
            herramientaId: h.herramientaId,
            cantidadInicial: h.cantidad,
          ),
        );
      }

      _activo = existente.activo;

      _operariosSeleccionadosCedulas.clear();
      if (existente.operariosIds.isNotEmpty) {
        for (final opId in existente.operariosIds) {
          final usuario = _operarios.firstWhere(
            (o) => int.tryParse(o.cedula) == opId,
            orElse: () => _dummyOperario(),
          );
          if (usuario.cedula != '0') {
            _operariosSeleccionadosCedulas.add(usuario.cedula);
          }
        }
      }

      if (existente.supervisorId != null) {
        final targetCedula = existente.supervisorId!.toString();
        _supervisorResponsable = _supervisores.firstWhere(
          (s) => s.cedula == targetCedula,
          orElse: () =>
              _supervisores.isNotEmpty ? _supervisores.first : _dummyOperario(),
        );
      }

      _ubicacionSeleccionada = _ubicaciones.firstWhere(
        (u) => u.id == existente.ubicacionId,
        orElse: () =>
            _ubicaciones.isNotEmpty ? _ubicaciones.first : _dummyUbicacion(),
      );

      if (_ubicacionSeleccionada != null) {
        final hojas = _ubicacionSeleccionada!.elementosHoja;
        _elementoSeleccionado = hojas.firstWhere(
          (e) => e.id == existente.elementoId,
          orElse: () => hojas.isNotEmpty ? hojas.first : _dummyElemento(),
        );
      }
    } else {
      if (_ubicaciones.isNotEmpty) {
        _ubicacionSeleccionada = _ubicaciones.first;
        final hojas = _ubicacionSeleccionada!.elementosHoja;
        if (hojas.isNotEmpty) {
          _elementoSeleccionado = hojas.first;
        }
      }
      _frecuencia = 'MENSUAL';
      _diaMesProgramado = 1;
      _diasSemanaProgramados
        ..clear()
        ..add('LUNES');
      _fechasProgramadas.clear();
      _prioridadCtrl.text = '2';
      _usaRendimiento = true;
      _rendimientoTiempoBase = 'POR_MINUTO';

      _dividirEnDias = false;
      _diasParaCompletarCtrl.text = '';
    }

    if (_frecuenciaUsaDiaSemana) {
      if (_diasSemanaProgramados.isEmpty) {
        _diasSemanaProgramados.add('LUNES');
      }
      _diaMesProgramado = null;
      _fechasProgramadas.clear();
    } else if (_frecuenciaUsaDiaMes) {
      _diaMesProgramado ??= 1;
      _diasSemanaProgramados.clear();
      _fechasProgramadas.clear();
    } else if (_frecuenciaUsaFechasExplicitas) {
      _diasSemanaProgramados.clear();
      _diaMesProgramado = null;
    } else {
      _diasSemanaProgramados.clear();
      _diaMesProgramado = null;
      _fechasProgramadas.clear();
    }
  }

  Usuario _dummyOperario() => Usuario(
    cedula: '0',
    nombre: 'Operario',
    correo: '',
    rol: '',
    telefono: BigInt.zero,
    fechaNacimiento: DateTime.now(),
  );

  UbicacionConElementos _dummyUbicacion() => UbicacionConElementos(
    id: 0,
    nombre: 'Sin ubicación',
    elementos: const [],
  );

  Elemento _dummyElemento() => Elemento(id: 0, nombre: 'Sin elemento');

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _prioridadCtrl.dispose();
    _cantidadCtrl.dispose();
    _rendimientoCtrl.dispose();
    _duracionFijaMinCtrl.dispose();
    _consumoPorUnidadCtrl.dispose();
    _diasParaCompletarCtrl.dispose();

    for (final r in _insumosPlanRows) {
      r.consumoCtrl.dispose();
    }
    for (final h in _herramientasPlanRows) {
      h.cantidadCtrl.dispose();
    }

    super.dispose();
  }

  // ===========================
  // parsers
  // ===========================
  String _soloDigitos(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
  int? _tryInt(String s) => int.tryParse(_soloDigitos(s));
  double? _tryDouble(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  String _unidadLabel() => (_unidadCalculo ?? 'unidad').toLowerCase();

  String _rendimientoHelper() {
    final u = _unidadLabel();
    switch (_rendimientoTiempoBase) {
      case 'POR_MINUTO':
        return 'Ej: 2 ($u/min) → haces 2 $u por minuto';
      case 'POR_HORA':
        return 'Ej: 120 ($u/h) → haces 120 $u por hora';
      case 'MIN_POR_UNIDAD':
        return 'Ej: 0.5 (min/$u) → tardas 0.5 min por cada $u';
      default:
        return '';
    }
  }

  int? _previewMinutosBien() {
    if (!_usaRendimiento) {
      final m = _tryInt(_duracionFijaMinCtrl.text);
      if (m == null || m <= 0) return null;
      return m;
    }

    final cant = _tryDouble(_cantidadCtrl.text);
    final rend = _tryDouble(_rendimientoCtrl.text);
    if (cant == null || rend == null || rend <= 0) return null;

    switch (_rendimientoTiempoBase) {
      case 'POR_MINUTO':
        return (cant / rend).round();
      case 'POR_HORA':
        return (cant / rend * 60).round();
      case 'MIN_POR_UNIDAD':
        return (cant * rend).round();
      default:
        return null;
    }
  }

  int? _previewMinutosPorDia() {
    final total = _previewMinutosBien();
    if (!_dividirEnDias) return null;
    if (total == null || total <= 0) return null;

    final dias = _tryInt(_diasParaCompletarCtrl.text.trim());
    if (dias == null || dias <= 1) return null;

    final porDia = (total / dias).ceil();
    return porDia > 0 ? porDia : null;
  }

  // ===========================
  // selector operarios
  // ===========================
  Future<void> _mostrarSelectorOperarios() async {
    if (_operarios.isEmpty) {
      _snack('No hay operarios en este conjunto');
      return;
    }

    final seleccionTemp = Set<String>.from(_operariosSeleccionadosCedulas);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setStateDialog) {
            return AlertDialog(
              title: const Text('Seleccionar operarios responsables'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _operarios.length,
                  itemBuilder: (_, index) {
                    final op = _operarios[index];
                    final cedula = op.cedula;
                    if (cedula.isEmpty) return const SizedBox.shrink();

                    final checked = seleccionTemp.contains(cedula);
                    return CheckboxListTile(
                      value: checked,
                      title: Text(op.nombre),
                      subtitle: Text('Cédula: $cedula'),
                      onChanged: (v) {
                        if (v == true) {
                          seleccionTemp.add(cedula);
                        } else {
                          seleccionTemp.remove(cedula);
                        }
                        setStateDialog(() {});
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() {
        _operariosSeleccionadosCedulas
          ..clear()
          ..addAll(seleccionTemp);
      });
    }
  }

  // ===========================
  // guardar
  // ===========================
  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_ubicacionSeleccionada == null || _elementoSeleccionado == null) {
      _snack('Selecciona ubicación y elemento');
      return;
    }
    if (_frecuencia == null) {
      _snack('Selecciona la frecuencia');
      return;
    }

    if (_frecuenciaUsaDiaSemana && _diasSemanaProgramados.isEmpty) {
      _snack(
        _usaSelectorMultipleSemanal
            ? 'Selecciona al menos un día de la semana'
            : 'Selecciona el día de la semana en el que se ejecuta',
      );
      return;
    }

    if (_frecuenciaUsaDiaMes &&
        (_diaMesProgramado == null ||
            _diaMesProgramado! < 1 ||
            _diaMesProgramado! > 31)) {
      _snack('Selecciona el día del mes (1–31)');
      return;
    }

    if (_frecuenciaUsaFechasExplicitas) {
      final requeridas = _fechasRequeridasFrecuencia ?? 0;
      if (_fechasProgramadas.length < requeridas) {
        final faltan = requeridas - _fechasProgramadas.length;
        _snack(
          'Faltan $faltan fecha${faltan == 1 ? '' : 's'} para completar la frecuencia ${_frecuencia!}.',
        );
        return;
      }
      if (_fechasProgramadas.length > requeridas) {
        _snack(
          'No puedes guardar más de $requeridas fecha${requeridas == 1 ? '' : 's'} para la frecuencia ${_frecuencia!}.',
        );
        return;
      }
    }

    if (_frecuenciaUsaFechasExplicitas && _fechasProgramadas.isEmpty) {
      _snack('Agrega al menos una fecha programada en el calendario');
      return;
    }

    if (_operariosSeleccionadosCedulas.isEmpty) {
      _snack('Selecciona al menos un operario');
      return;
    }

    final operariosIdsInt = _operariosSeleccionadosCedulas
        .map((ced) => int.tryParse(_soloDigitos(ced)))
        .whereType<int>()
        .toList();

    if (operariosIdsInt.isEmpty) {
      _snack('No se pudieron interpretar las cédulas de operarios');
      return;
    }

    final responsableId = operariosIdsInt.first;

    if (_supervisorResponsable == null) {
      _snack('Selecciona un supervisor responsable');
      return;
    }

    final supervisorId = _tryInt(_supervisorResponsable!.cedula);
    if (supervisorId == null) {
      _snack('Supervisor responsable inválido');
      return;
    }

    // ========= DURACIÓN =========
    String? unidadCalculo;
    double? cantidad;
    double? rendimiento;
    int? duracionMinFija;

    if (_usaRendimiento) {
      if (_unidadCalculo == null ||
          _cantidadCtrl.text.trim().isEmpty ||
          _rendimientoCtrl.text.trim().isEmpty) {
        _snack('Completa unidad, cantidad y rendimiento o usa duración fija.');
        return;
      }
      unidadCalculo = _unidadCalculo;
      cantidad = _tryDouble(_cantidadCtrl.text);
      rendimiento = _tryDouble(_rendimientoCtrl.text);

      if (cantidad == null || rendimiento == null || rendimiento <= 0) {
        _snack('Cantidad y rendimiento deben ser números válidos');
        return;
      }
    } else {
      if (_duracionFijaMinCtrl.text.trim().isEmpty) {
        _snack('Indica la duración fija en minutos');
        return;
      }
      duracionMinFija = _tryInt(_duracionFijaMinCtrl.text.trim());
      if (duracionMinFija == null || duracionMinFija <= 0) {
        _snack('Duración fija debe ser un entero > 0');
        return;
      }
    }

    final prioridad = (int.tryParse(_prioridadCtrl.text.trim()) ?? 2).clamp(
      1,
      3,
    );

    final consumoPrincipal = _consumoPorUnidadCtrl.text.trim().isNotEmpty
        ? _tryDouble(_consumoPorUnidadCtrl.text)
        : null;

    final insumosPlanRequests = _insumosPlanRows
        .where(
          (r) => r.insumoId != null && r.consumoCtrl.text.trim().isNotEmpty,
        )
        .map(
          (r) => InsumoPlanItemRequest(
            insumoId: r.insumoId!,
            consumoPorUnidad: _tryDouble(r.consumoCtrl.text.trim()) ?? 0,
          ),
        )
        .toList();

    final maquinariaPlanRequests = _maquinariaPlanRows
        .where((r) => r.tipo != null)
        .map(
          (r) => MaquinariaPlanItemRequest(
            tipo: r.tipo!,
            cantidad: r.cantidad,
            maquinariaSugeridaId: r.maquinariaSugeridaId,
          ),
        )
        .toList();

    final herramientasPlanRequests = _herramientasPlanRows
        .where(
          (r) =>
              r.herramientaId != null && r.cantidadCtrl.text.trim().isNotEmpty,
        )
        .map(
          (r) => HerramientaPlanItemRequest(
            herramientaId: r.herramientaId!,
            cantidad: _tryDouble(r.cantidadCtrl.text.trim()) ?? 0,
            estado: 'OPERATIVA',
          ),
        )
        .toList();

    int? diasParaCompletar;
    if (_dividirEnDias) {
      final d = _tryInt(_diasParaCompletarCtrl.text.trim());
      if (d != null && d > 1) diasParaCompletar = d;
    }

    final diasSemanaSeleccionados = _diasSemanaSeleccionadosOrdenados;

    DefinicionPreventivaRequest buildRequest({String? diaSemanaProgramado}) {
      return DefinicionPreventivaRequest(
        ubicacionId: _ubicacionSeleccionada!.id,
        elementoId: _elementoSeleccionado!.id,
        descripcion: _descripcionCtrl.text.trim(),
        frecuencia: _frecuencia!,
        prioridad: prioridad,
        diaSemanaProgramado: _frecuenciaUsaDiaSemana
            ? diaSemanaProgramado
            : null,
        diaMesProgramado: _frecuenciaUsaDiaMes ? _diaMesProgramado : null,
        fechasProgramadasJson: _frecuenciaUsaFechasExplicitas
            ? _fechasProgramadas.map(_fmtFechaProgramada).toList()
            : null,
        unidadCalculo: unidadCalculo,
        areaNumerica: cantidad,
        rendimientoBase: rendimiento,
        duracionMinutosFija: duracionMinFija,
        rendimientoTiempoBase: _usaRendimiento ? _rendimientoTiempoBase : null,
        diasParaCompletar: diasParaCompletar,
        insumoPrincipalId: _insumoPrincipalId,
        consumoPrincipalPorUnidad: consumoPrincipal,
        insumosPlan: insumosPlanRequests,
        maquinariaPlan: maquinariaPlanRequests,
        herramientasPlan: herramientasPlanRequests,
        operariosIds: operariosIdsInt,
        responsableSugeridoId: responsableId,
        supervisorId: supervisorId,
        activo: _activo,
      );
    }

    final req = buildRequest(
      diaSemanaProgramado:
          _frecuenciaUsaDiaSemana && diasSemanaSeleccionados.isNotEmpty
          ? diasSemanaSeleccionados.first
          : null,
    );

    setState(() => _guardando = true);
    try {
      if (_usaSelectorMultipleSemanal && diasSemanaSeleccionados.length > 1) {
        final diaPrincipal = diasSemanaSeleccionados.first;

        if (widget.existente == null) {
          for (final dia in diasSemanaSeleccionados) {
            await _api.crear(
              widget.nit,
              buildRequest(diaSemanaProgramado: dia),
            );
          }
        } else {
          await _api.editar(
            widget.nit,
            widget.existente!.id,
            buildRequest(diaSemanaProgramado: diaPrincipal),
          );

          for (final dia in diasSemanaSeleccionados.skip(1)) {
            await _api.crear(
              widget.nit,
              buildRequest(diaSemanaProgramado: dia),
            );
          }
        }
      } else if (widget.existente == null) {
        await _api.crear(widget.nit, req);
      } else {
        await _api.editar(widget.nit, widget.existente!.id, req);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      // ✅ Si el backend ya manda {ok:false, reason, message, ...}
      if (e is ApiException) {
        await _showFriendlyErrorDialog(
          title: 'No se pudo guardar',
          message: e.message,
          details: e.details,
        );
        return;
      }

      _snack('Error al guardar preventiva: $e', type: SnackType.error);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String msg, {SnackType type = SnackType.info}) {
    Color? bg;
    switch (type) {
      case SnackType.error:
        bg = Colors.red;
        break;
      case SnackType.success:
        bg = Colors.green;
        break;
      case SnackType.info:
        bg = Colors.blue; // o AppTheme.primary
    }

    AppFeedback.showFromSnackBar(
      context,
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  Future<void> _showFriendlyErrorDialog({
    required String title,
    required String message,
    dynamic details,
  }) async {
    final pretty = () {
      try {
        if (details == null) return null;
        if (details is String) return details;
        return const JsonEncoder.withIndent('  ').convert(details);
      } catch (_) {
        return details?.toString();
      }
    }();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (pretty != null) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Ver detalles'),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(pretty, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _pillInfo({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<SearchableSelectOption<int>> _buildInsumoOptions() {
    return _catalogoInsumos
        .map(
          (i) => SearchableSelectOption<int>(
            value: i.id,
            label: '${i.nombre} (${i.unidad})',
            subtitle: i.categoria.label,
          ),
        )
        .toList(growable: false);
  }

  List<SearchableSelectOption<int>> _buildHerramientaOptions() {
    return _catalogoHerramientas
        .map((h) {
          final esConjunto = h.disponibleConjunto > 0;
          final tag = esConjunto ? '[CONJUNTO]' : '[EMPRESA]';
          final detalle = esConjunto
              ? 'disponible conjunto: ${h.disponibleConjunto}'
              : 'disponible empresa: ${h.disponibleEmpresa}';

          return SearchableSelectOption<int>(
            value: h.herramientaId,
            label: '$tag ${h.nombre} (${h.unidad})',
            subtitle: '${h.categoria.label} · $detalle',
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final prioridadValue = (int.tryParse(_prioridadCtrl.text) ?? 2).clamp(1, 3);
    final preview = _previewMinutosBien();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          widget.existente == null
              ? 'Crear tarea preventiva'
              : 'Editar tarea preventiva',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _sectionCard(
                title: '1) Dónde se ejecuta',
                child: Column(
                  children: [
                    DropdownButtonFormField<int>(
                      key: ValueKey<String>(
                        'ubicacion_${_ubicacionSeleccionada?.id ?? 'none'}',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Ubicación',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _ubicacionSeleccionada?.id,
                      items: _ubicaciones
                          .map(
                            (u) => DropdownMenuItem(
                              value: u.id,
                              child: Text(u.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final u = _ubicaciones.firstWhere((x) => x.id == v);
                        final hojas = u.elementosHoja;
                        setState(() {
                          _ubicacionSeleccionada = u;
                          _elementoSeleccionado = hojas.isNotEmpty
                              ? hojas.first
                              : null;
                        });
                      },
                      validator: (v) =>
                          v == null ? 'Selecciona una ubicación' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey<String>(
                        'elemento_${_elementoSeleccionado?.id ?? 'none'}',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Area final',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _elementoSeleccionado?.id,
                      items: (_ubicacionSeleccionada?.elementosHoja ?? [])
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final el = _ubicacionSeleccionada!.elementosHoja
                            .firstWhere((x) => x.id == v);
                        setState(() => _elementoSeleccionado = el);
                      },
                      validator: (v) =>
                          v == null ? 'Selecciona un area final' : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _sectionCard(
                title: '2) Qué se va a hacer',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _descripcionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descripción / actividad',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Describe la actividad'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'frecuencia_${_frecuencia ?? 'none'}',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Frecuencia',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _frecuencia,
                      items: frecuenciasPreventivas
                          .map(
                            (f) => DropdownMenuItem(value: f, child: Text(f)),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _frecuencia = v;
                          if (!_frecuenciaUsaDiaSemana) {
                            _diasSemanaProgramados.clear();
                          }
                          if (!_frecuenciaUsaDiaMes) {
                            _diaMesProgramado = null;
                          }
                          if (!_frecuenciaUsaFechasExplicitas) {
                            _fechasProgramadas.clear();
                          }

                          if (_frecuenciaUsaDiaSemana &&
                              _diasSemanaProgramados.isEmpty) {
                            _diasSemanaProgramados.add('LUNES');
                          }
                          if (_frecuenciaUsaDiaMes &&
                              _diaMesProgramado == null) {
                            _diaMesProgramado = 1;
                          }
                        });
                      },
                      validator: (v) =>
                          v == null ? 'Selecciona una frecuencia' : null,
                    ),
                    const SizedBox(height: 12),

                    if (_frecuenciaUsaDiaSemana) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _usaSelectorMultipleSemanal
                              ? 'Días de la semana'
                              : 'Día de la semana',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: diasSemanaOpciones.map((dia) {
                            final selected = _diasSemanaProgramados.contains(
                              dia,
                            );
                            return ChoiceChip(
                              label: Text(
                                dia,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              selected: selected,
                              showCheckmark: true,
                              selectedColor: AppTheme.primary,
                              backgroundColor: Colors.grey.shade200,
                              side: BorderSide(
                                color: selected
                                    ? AppTheme.primary
                                    : Colors.grey.shade400,
                                width: selected ? 2 : 1,
                              ),
                              onSelected: (value) {
                                setState(() {
                                  if (!_usaSelectorMultipleSemanal) {
                                    // Un solo dia: al elegir otro se deselecciona el anterior.
                                    if (value) {
                                      _diasSemanaProgramados
                                        ..clear()
                                        ..add(dia);
                                    }
                                    return;
                                  }
                                  if (value) {
                                    _diasSemanaProgramados.add(dia);
                                  } else {
                                    _diasSemanaProgramados.remove(dia);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_ayudaDiasSemana()),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_frecuenciaUsaDiaMes) ...[
                      DropdownButtonFormField<int>(
                        key: ValueKey<String>(
                          'diaMes_${_diaMesProgramado ?? 'none'}',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Día del mes',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _diaMesProgramado,
                        items: List.generate(31, (i) => i + 1)
                            .map(
                              (d) =>
                                  DropdownMenuItem(value: d, child: Text('$d')),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _diaMesProgramado = v),
                      ),
                      const SizedBox(height: 8),
                      if (_frecuencia != 'MENSUAL')
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'La recurrencia toma como referencia el mes en que se crea esta preventiva.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],

                    if (_frecuenciaUsaFechasExplicitas) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Fechas programadas',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _mensajeFechasFrecuenciaExacta(),
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.left,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _agregarFechaProgramada,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('Agregar fecha'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_fechasProgramadas.isEmpty)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Aún no hay fechas seleccionadas.'),
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            alignment: WrapAlignment.start,
                            spacing: 8,
                            runSpacing: 8,
                            children: _fechasProgramadas.map((fecha) {
                              return InputChip(
                                label: Text(_fmtFechaProgramada(fecha)),
                                onDeleted: () {
                                  setState(() {
                                    _fechasProgramadas.removeWhere(
                                      (item) =>
                                          item.year == fecha.year &&
                                          item.month == fecha.month &&
                                          item.day == fecha.day,
                                    );
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _fechasProgramadasRestantes > 0
                              ? 'Faltan $_fechasProgramadasRestantes fecha${_fechasProgramadasRestantes == 1 ? '' : 's'} por seleccionar.'
                              : 'Cantidad de fechas completada para esta frecuencia.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    DropdownButtonFormField<int>(
                      key: ValueKey<String>('prioridad_$prioridadValue'),
                      decoration: const InputDecoration(
                        labelText: 'Prioridad',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: prioridadValue,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1 - Alta')),
                        DropdownMenuItem(value: 2, child: Text('2 - Media')),
                        DropdownMenuItem(value: 3, child: Text('3 - Baja')),
                      ],
                      onChanged: (v) => setState(
                        () => _prioridadCtrl.text = (v ?? 2).toString(),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _sectionCard(
                title: '3) Duración planificada',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Calcular por rendimiento + cantidad'),
                      subtitle: const Text(
                        'Si lo desactivas, usas duración fija (minutos).',
                      ),
                      value: _usaRendimiento,
                      onChanged: (v) => setState(() => _usaRendimiento = v),
                    ),
                    if (_usaRendimiento) ...[
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Unidad de cálculo',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _unidadCalculo,
                        items: const ['M', 'M2', 'M3', 'UNIDAD']
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _unidadCalculo = v),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Base del rendimiento',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _rendimientoTiempoBase,
                        items: const [
                          DropdownMenuItem(
                            value: 'POR_MINUTO',
                            child: Text('Unidades por minuto'),
                          ),
                          DropdownMenuItem(
                            value: 'POR_HORA',
                            child: Text('Unidades por hora'),
                          ),
                          DropdownMenuItem(
                            value: 'MIN_POR_UNIDAD',
                            child: Text('Minutos por unidad'),
                          ),
                        ],
                        onChanged: (v) => setState(
                          () => _rendimientoTiempoBase = v ?? 'POR_MINUTO',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _cantidadCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cantidad total',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _rendimientoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Rendimiento',
                          helperText: _rendimientoHelper(),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (preview != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _pillInfo(
                                icon: Icons.timer_outlined,
                                text:
                                    'Estimado: $preview min (~ ${(preview / 60).toStringAsFixed(2)} h)',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ] else ...[
                      TextFormField(
                        controller: _duracionFijaMinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Duración fija (minutos)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],

                    // ✅ Repartir en varios días
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Repartir en varios días'),
                            subtitle: const Text(
                              'Útil para actividades largas (ej: 10 horas en 5 días).',
                            ),
                            value: _dividirEnDias,
                            onChanged: (v) => setState(() {
                              _dividirEnDias = v;
                              if (!v) _diasParaCompletarCtrl.text = '';
                            }),
                          ),
                          if (_dividirEnDias) ...[
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _diasParaCompletarCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '¿En cuántos días completar?',
                                hintText: 'Ej: 5',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                if (!_dividirEnDias) return null;
                                final n = _tryInt(v?.trim() ?? '');
                                if (n == null)
                                  return 'Ingresa un número válido';
                                if (n < 2) return 'Debe ser 2 o más';
                                if (n > 31) return 'Máximo 31 días';
                                return null;
                              },
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 10),
                            Builder(
                              builder: (_) {
                                final total = _previewMinutosBien();
                                final porDia = _previewMinutosPorDia();

                                if (total == null) {
                                  return const Text(
                                    '💡 Define primero la duración (o el rendimiento) para calcular el reparto.',
                                  );
                                }
                                if (porDia == null)
                                  return const SizedBox.shrink();

                                return Text(
                                  '📌 Total: $total min (~ ${(total / 60).toStringAsFixed(2)} h)\n'
                                  '📅 Reparto: ~$porDia min/día (~ ${(porDia / 60).toStringAsFixed(2)} h/día)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _sectionCard(
                title: '4) Recursos – Insumos',
                child: Column(
                  children: [
                    SearchableSelectField<int>(
                      label: 'Insumo principal (opcional)',
                      value: _insumoPrincipalId,
                      prefixIcon: const Icon(Icons.inventory_2_outlined),
                      searchHint:
                          'Buscar insumo por nombre, unidad o categoria',
                      clearLabel: 'Sin insumo principal',
                      options: _buildInsumoOptions(),
                      onChanged: (v) => setState(() => _insumoPrincipalId = v),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _consumoPorUnidadCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Consumo por unidad (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Otros insumos',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _insumosPlanRows.length,
                      itemBuilder: (_, i) => _buildInsumoPlanRow(i),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () => _insumosPlanRows.add(_InsumoPlanRow()),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar insumo'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // =========================================================
              // 4.1 Maquinaria: solo la NECESIDAD (tipo + cantidad).
              // La maquina concreta se asigna despues, para toda la empresa,
              // desde el cronograma de maquinaria.
              // =========================================================
              _sectionCard(
                title: '4.1) Maquinaria necesaria',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Colors.blue.shade800,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Indica solo el tipo de máquina que hace falta. '
                              'La máquina concreta se asigna después, para toda la '
                              'empresa, desde el cronograma de maquinaria.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _maquinariaPlanRows.length,
                      itemBuilder: (_, i) => _buildMaquinariaPlanRow(i),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () => _maquinariaPlanRows.add(_MaquinariaPlanRow()),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar necesidad de maquinaria'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _sectionCard(
                title: '4.2) Herramientas planificadas',
                child: Column(
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _herramientasPlanRows.length,
                      itemBuilder: (_, i) => _buildHerramientaPlanRow(i),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () =>
                              _herramientasPlanRows.add(_HerramientaPlanRow()),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar herramienta'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _sectionCard(
                title: '5) Equipo responsable',
                child: Column(
                  children: [
                    InkWell(
                      onTap: _mostrarSelectorOperarios,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Operarios responsables',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _operariosSeleccionadosCedulas.isEmpty
                                    ? 'Seleccionar operarios'
                                    : '${_operariosSeleccionadosCedulas.length} operario(s) seleccionado(s)',
                              ),
                            ),
                            const Icon(Icons.people_alt_outlined),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Supervisor responsable',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _supervisorResponsable?.cedula,
                      items: _supervisores
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.cedula,
                              child: Text(s.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: (cedula) {
                        if (cedula == null) return;
                        final sup = _supervisores.firstWhere(
                          (s) => s.cedula == cedula,
                        );
                        setState(() => _supervisorResponsable = sup);
                      },
                      validator: (v) =>
                          v == null ? 'Selecciona un supervisor' : null,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Definición activa'),
                      value: _activo,
                      onChanged: (v) => setState(() => _activo = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_guardando ? 'Guardando...' : 'Guardar'),
                  style: AppTheme.saveButtonStyle,
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================
  // rows
  // ===========================
  Widget _buildInsumoPlanRow(int index) {
    final row = _insumosPlanRows[index];
    final insumoOptions = _buildInsumoOptions();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SearchableSelectField<int>(
              label: 'Insumo',
              value: row.insumoId,
              prefixIcon: const Icon(Icons.inventory_2_outlined),
              searchHint: 'Buscar insumo',
              clearLabel: 'Sin insumo',
              options: insumoOptions,
              onChanged: (v) => setState(() => row.insumoId = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.consumoCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Consumo / unidad',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() {
                row.consumoCtrl.dispose();
                _insumosPlanRows.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMaquinariaPlanRow(int index) {
    final row = _maquinariaPlanRows[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: SearchableSelectField<TipoMaquinariaFlutter>(
              label: 'Tipo de maquinaria',
              value: row.tipo,
              prefixIcon: const Icon(Icons.precision_manufacturing),
              searchHint: 'Buscar tipo de maquinaria',
              clearLabel: 'Sin definir',
              options: TipoMaquinariaFlutter.values
                  .map(
                    (tipo) => SearchableSelectOption<TipoMaquinariaFlutter>(
                      value: tipo,
                      label: tipo.label,
                    ),
                  )
                  .toList(),
              onChanged: (tipo) => setState(() => row.tipo = tipo),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextFormField(
              key: ValueKey('maqCantidad_${index}_${row.cantidad}'),
              initialValue: '${row.cantidad}',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                final n = int.tryParse(value.trim());
                if (n != null && n > 0) row.cantidad = n;
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Quitar',
            onPressed: () =>
                setState(() => _maquinariaPlanRows.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Widget _buildHerramientaPlanRow(int index) {
    final row = _herramientasPlanRows[index];
    final herramientaOptions = _buildHerramientaOptions();
    final seleccionada = row.herramientaId == null
        ? null
        : _catalogoHerramientas
              .where((h) => h.herramientaId == row.herramientaId)
              .cast<HerramientaDisponibilidadResponse?>()
              .firstWhere((h) => h != null, orElse: () => null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SearchableSelectField<int>(
                  label: 'Herramienta',
                  value: row.herramientaId,
                  prefixIcon: const Icon(Icons.handyman_outlined),
                  searchHint:
                      'Buscar herramienta por nombre, unidad o categoria',
                  clearLabel: 'Sin herramienta',
                  options: herramientaOptions,
                  onChanged: (v) => setState(() => row.herramientaId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: row.cantidadCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cantidad',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() {
                    row.cantidadCtrl.dispose();
                    _herramientasPlanRows.removeAt(index);
                  });
                },
              ),
            ],
          ),
          if (seleccionada != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Disponible ahora -> conjunto: ${seleccionada.disponibleConjunto} · empresa: ${seleccionada.disponibleEmpresa}. Al crear la tarea se reserva primero del conjunto y, si no alcanza, desde empresa.',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InsumoPlanRow {
  int? insumoId;
  final TextEditingController consumoCtrl;

  _InsumoPlanRow({this.insumoId, double? consumoInicial})
    : consumoCtrl = TextEditingController(
        text: consumoInicial != null ? consumoInicial.toString() : '',
      );
}

/// Necesidad de maquinaria de la preventiva: que tipo y cuantas.
/// La maquina concreta se asigna despues desde el cronograma de maquinaria.
class _MaquinariaPlanRow {
  TipoMaquinariaFlutter? tipo;
  int cantidad;
  int? maquinariaSugeridaId;

  _MaquinariaPlanRow({this.tipo, this.cantidad = 1, this.maquinariaSugeridaId});
}

class _HerramientaPlanRow {
  int? herramientaId;
  final TextEditingController cantidadCtrl;

  _HerramientaPlanRow({this.herramientaId, num? cantidadInicial})
    : cantidadCtrl = TextEditingController(
        text: cantidadInicial != null ? cantidadInicial.toString() : '',
      );
}
