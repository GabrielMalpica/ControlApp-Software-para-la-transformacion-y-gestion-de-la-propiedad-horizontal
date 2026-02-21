// lib/pages/crear_preventiva_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/service/app_constants.dart';

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

import '../service/theme.dart';

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
  List<MaquinariaResponse> _catalogoMaquinaria = [];
  List<HerramientaResponse> _catalogoHerramientas = [];
  List<Usuario> _supervisores = [];

  // ✅ Cache de dropdown items (evita freeze fuerte)
  List<DropdownMenuItem<int>> _insumoItems = [];
  List<DropdownMenuItem<int>> _maquinariaItems = [];
  List<DropdownMenuItem<int>> _herramientaItems = [];

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

  String? _frecuencia; // DIARIA | SEMANAL | MENSUAL
  String? _diaSemanaProgramado;
  int? _diaMesProgramado;

  final List<String> _operariosSeleccionadosCedulas = [];
  Usuario? _supervisorResponsable;

  bool _activo = true;

  UbicacionConElementos? _ubicacionSeleccionada;
  Elemento? _elementoSeleccionado;

  bool _guardando = false;

  List<UbicacionConElementos> get _ubicaciones => widget.conjunto.ubicaciones;
  List<Usuario> get _operarios => widget.conjunto.operarios;

  // =========================================================
  // ✅ NUEVO: Disponibilidad de maquinaria
  // =========================================================
  DisponibilidadMaquinariaResponse? _dispMaq;
  bool _cargandoDispMaq = false;

  // maps rápidos
  final Map<int, MaquinariaOcupadaItem> _ocupadaPorId = {};

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // ===========================
  // helpers fechas disponibilidad
  // ===========================
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _proximaFechaProgramada() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);

    if (_frecuencia == 'SEMANAL' && _diaSemanaProgramado != null) {
      const map = {
        'LUNES': 1,
        'MARTES': 2,
        'MIERCOLES': 3,
        'JUEVES': 4,
        'VIERNES': 5,
        'SABADO': 6,
        'DOMINGO': 7,
      };
      final target = map[_diaSemanaProgramado!] ?? 1;
      final today = base.weekday; // 1..7
      var delta = target - today;
      if (delta < 0) delta += 7;
      if (delta == 0) delta = 7; // "próximo", no "hoy"
      return base.add(Duration(days: delta));
    }

    if (_frecuencia == 'MENSUAL' && _diaMesProgramado != null) {
      final y = base.year;
      final m = base.month;
      final day = _diaMesProgramado!.clamp(1, 28); // evita reventar por 31
      var dt = DateTime(y, m, day);
      if (!dt.isAfter(base)) dt = DateTime(y, m + 1, day);
      return dt;
    }

    // DIARIA o fallback
    return base.add(const Duration(days: 1));
  }

  Future<void> _consultarDisponibilidadMaquinaria() async {
    final totalMin = _previewMinutosBien();
    if (totalMin == null) {
      _snack(
        'Define la duración para consultar disponibilidad',
        type: SnackType.info,
      );
      return;
    }

    final inicio = _dateOnly(_proximaFechaProgramada());
    final dias = _dividirEnDias
        ? (int.tryParse(_diasParaCompletarCtrl.text) ?? 1)
        : 1;
    final finUso = inicio.add(Duration(days: (dias <= 1 ? 0 : dias - 1)));

    setState(() {
      _cargandoDispMaq = true;
      _dispMaq = null;
      _ocupadaPorId.clear();
    });

    try {
      final r = await _api.maquinariaDisponible(
        nit: widget.nit,
        fechaInicioUso: inicio,
        fechaFinUso: finUso,
        excluirTareaId: widget.existente?.id,
      );
      print(r);

      if (!mounted) return;

      for (final o in r.ocupadas) {
        _ocupadaPorId[o.maquinariaId] = o;
      }

      setState(() => _dispMaq = r);
    } catch (e) {
      if (!mounted) return;
      _snack('Error consultando disponibilidad: $e', type: SnackType.error);
    } finally {
      if (!mounted) return;
      setState(() => _cargandoDispMaq = false);
    }
  }

  // ✅ Filtrado: si ya consultaste, muestra solo disponibles
  List<_MaqOption> _maqOptionsDisponibles() {
    if (_dispMaq == null) {
      // fallback: si no consultaste, muestra catálogo general como "EMPRESA" por defecto
      return _catalogoMaquinaria
          .map(
            (m) => _MaqOption(
              id: m.id,
              nombre: m.nombre,
              origen: 'EMPRESA',
              marca: m.marca,
            ),
          )
          .toList();
    }

    final opts = <_MaqOption>[];

    // disponibles del conjunto
    for (final m in _dispMaq!.propiasDisponibles) {
      opts.add(
        _MaqOption(
          id: m.id,
          nombre: m.nombre,
          origen: 'CONJUNTO',
          marca: m.marca,
        ),
      );
    }

    // disponibles empresa
    for (final m in _dispMaq!.empresaDisponibles) {
      opts.add(
        _MaqOption(
          id: m.id,
          nombre: m.nombre,
          origen: 'EMPRESA',
          marca: m.marca,
        ),
      );
    }

    // opcional: ordena alfabético, o primero conjunto y luego empresa
    opts.sort((a, b) {
      final o = a.origen.compareTo(b.origen);
      if (o != 0) return o; // CONJUNTO primero si quieres, ajusta
      return a.nombre.compareTo(b.nombre);
    });

    return opts;
  }

  // ===========================
  // carga de datos
  // ===========================
  Future<void> _initData() async {
    await Future.wait([
      _cargarCatalogoInsumos(),
      _cargarCatalogoMaquinaria(),
      _cargarCatalogoHerramientas(),
      _cargarSupervisores(),
    ]);

    if (!mounted) return;
    _cargarDesdeExistenteOInit();
    await _consultarDisponibilidadMaquinaria();

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _cargarCatalogoInsumos() async {
    try {
      final lista = await _empresaApi.listarCatalogo();
      if (!mounted) return;
      setState(() {
        _catalogoInsumos = lista;
        _insumoItems = _catalogoInsumos
            .map(
              (i) => DropdownMenuItem(
                value: i.id,
                child: Text('${i.nombre} (${i.unidad})'),
              ),
            )
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Error cargando catálogo de insumos: $e', type: SnackType.error);
    }
  }

  Future<void> _cargarCatalogoMaquinaria() async {
    try {
      final lista = await _empresaApi.listarMaquinaria();
      if (!mounted) return;
      setState(() {
        _catalogoMaquinaria = lista;
        _maquinariaItems = _catalogoMaquinaria
            .map((m) => DropdownMenuItem(value: m.id, child: Text(m.nombre)))
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      _snack(
        'Error cargando catálogo de maquinaria: $e',
        type: SnackType.error,
      );
    }
  }

  Future<void> _cargarCatalogoHerramientas() async {
    try {
      final empresaId = AppConstants.empresaNit;

      final res = await _herramientaApi.listarHerramientas(
        empresaId: empresaId,
        take: 100,
        skip: 0,
      );

      final raw = (res['data'] as List?) ?? [];

      final lista = raw
          .map(
            (e) => HerramientaResponse.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _catalogoHerramientas = lista;
        _herramientaItems = _catalogoHerramientas
            .map(
              (h) => DropdownMenuItem(
                value: h.id,
                child: Text('${h.nombre} (${h.unidad})'),
              ),
            )
            .toList(growable: false);
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

      _diaSemanaProgramado = existente.diaSemanaProgramado;
      _diaMesProgramado = existente.diaMesProgramado;

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
          existente.maquinariaPlan.map(
            (m) => _MaquinariaPlanRow(
              maquinariaId: m.maquinariaId,
              tipoInicial: m.tipo,
            ),
          ),
        );

      _herramientasPlanRows.clear();
      for (final h in existente.herramientasPlan) {
        _herramientasPlanRows.add(
          _HerramientaPlanRow(
            herramientaId: h.herramientaId,
            cantidadInicial: h.cantidad,
            estadoInicial: h.estado,
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
        _elementoSeleccionado = _ubicacionSeleccionada!.elementos.firstWhere(
          (e) => e.id == existente.elementoId,
          orElse: () => _ubicacionSeleccionada!.elementos.isNotEmpty
              ? _ubicacionSeleccionada!.elementos.first
              : _dummyElemento(),
        );
      }
    } else {
      if (_ubicaciones.isNotEmpty) {
        _ubicacionSeleccionada = _ubicaciones.first;
        if (_ubicacionSeleccionada!.elementos.isNotEmpty) {
          _elementoSeleccionado = _ubicacionSeleccionada!.elementos.first;
        }
      }
      _frecuencia = 'MENSUAL';
      _diaMesProgramado = 1;
      _diaSemanaProgramado = 'LUNES';
      _prioridadCtrl.text = '2';
      _usaRendimiento = true;
      _rendimientoTiempoBase = 'POR_MINUTO';

      _dividirEnDias = false;
      _diasParaCompletarCtrl.text = '';
    }

    if (_frecuencia == 'SEMANAL') {
      _diaSemanaProgramado ??= 'LUNES';
      _diaMesProgramado = null;
    } else if (_frecuencia == 'MENSUAL') {
      _diaMesProgramado ??= 1;
      _diaSemanaProgramado = null;
    } else {
      _diaSemanaProgramado = null;
      _diaMesProgramado = null;
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
    for (final m in _maquinariaPlanRows) {
      m.tipoCtrl.dispose();
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

    if (_frecuencia == 'SEMANAL' &&
        (_diaSemanaProgramado == null || _diaSemanaProgramado!.isEmpty)) {
      _snack('Selecciona el día de la semana');
      return;
    }

    if (_frecuencia == 'MENSUAL' &&
        (_diaMesProgramado == null ||
            _diaMesProgramado! < 1 ||
            _diaMesProgramado! > 31)) {
      _snack('Selecciona el día del mes (1–31)');
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
        .where((r) => r.maquinariaId != null)
        .map(
          (r) => MaquinariaPlanItemRequest(
            maquinariaId: r.maquinariaId!,
            tipo: r.tipoCtrl.text.trim().isNotEmpty
                ? r.tipoCtrl.text.trim()
                : null,
            origen: r.origen, // ✅ viene automático del dropdown
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
            estado: r.estado ?? 'OPERATIVA',
          ),
        )
        .toList();

    int? diasParaCompletar;
    if (_dividirEnDias) {
      final d = _tryInt(_diasParaCompletarCtrl.text.trim());
      if (d != null && d > 1) diasParaCompletar = d;
    }

    final req = DefinicionPreventivaRequest(
      ubicacionId: _ubicacionSeleccionada!.id,
      elementoId: _elementoSeleccionado!.id,
      descripcion: _descripcionCtrl.text.trim(),
      frecuencia: _frecuencia!,
      prioridad: prioridad,
      diaSemanaProgramado: _frecuencia == 'SEMANAL'
          ? _diaSemanaProgramado
          : null,
      diaMesProgramado: _frecuencia == 'MENSUAL' ? _diaMesProgramado : null,
      unidadCalculo: unidadCalculo,
      areaNumerica: cantidad,
      rendimientoBase: rendimiento,
      duracionMinutosFija: duracionMinFija,
      rendimientoTiempoBase: _usaRendimiento ? _rendimientoTiempoBase : null,

      diasParaCompletar: diasParaCompletar,

      insumoPrincipalId: _insumoPrincipalId,
      consumoPrincipalPorUnidad: consumoPrincipal,
      insumosPlan: insumosPlanRequests.isNotEmpty ? insumosPlanRequests : null,
      maquinariaPlan: maquinariaPlanRequests.isNotEmpty
          ? maquinariaPlanRequests
          : null,
      herramientasPlan: herramientasPlanRequests.isNotEmpty
          ? herramientasPlanRequests
          : null,
      operariosIds: operariosIdsInt,
      responsableSugeridoId: responsableId,
      supervisorId: supervisorId,
      activo: _activo,
    );

    setState(() => _guardando = true);
    try {
      if (widget.existente == null) {
        await _api.crear(widget.nit, req);
      } else {
        await _api.editar(widget.nit, widget.existente!.id, req);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      // ✅ Si el backend ya manda {ok:false, reason, message, ...}
      if (e is ApiError) {
        // mensaje amigable
        if (e.reason == 'MAQUINARIA_NO_DISPONIBLE') {
          await _showMaquinariaNoDisponibleDialog(e);
        } else {
          await _showFriendlyErrorDialog(
            title: 'No se pudo guardar',
            message: e.message,
            details: e.details,
          );
        }
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
      default:
        bg = Colors.blue; // o AppTheme.primary
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
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

  Future<void> _showMaquinariaNoDisponibleDialog(ApiError e) async {
    // e.details puede ser Map o String
    Map<String, dynamic>? body;
    try {
      if (e.details is Map<String, dynamic>) {
        body = e.details as Map<String, dynamic>;
      } else if (e.details is String) {
        body = jsonDecode(e.details as String) as Map<String, dynamic>;
      }
    } catch (_) {
      body = null;
    }

    final conflictos = (body?['conflictos'] as List?) ?? const [];
    // Muestra máximo 3 (para no saturar)
    final top = conflictos.take(3).toList();
    final extra = conflictos.length - top.length;

    String fmtDate(dynamic s) {
      if (s == null) return '';
      try {
        final dt = DateTime.parse(s.toString()).toLocal();
        return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return s.toString();
      }
    }

    Widget conflictoTile(Map<String, dynamic> c) {
      final maquinariaId = c['maquinariaId'];
      final ocupadoPor = (c['ocupadoPor'] as Map?)?.cast<String, dynamic>();
      final desc = ocupadoPor?['descripcion']?.toString() ?? 'Tarea';
      final conj = ocupadoPor?['conjuntoId']?.toString() ?? '—';
      final ini = fmtDate(ocupadoPor?['ini']);
      final fin = fmtDate(ocupadoPor?['fin']);

      final entrega = fmtDate((c['rangoSolicitado'] as Map?)?['entrega']);
      final recogida = fmtDate((c['rangoSolicitado'] as Map?)?['recogida']);

      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.construction),
        title: Text('Máquina #$maquinariaId • $desc'),
        subtitle: Text(
          'Conjunto: $conj\n'
          'Ocupada: $ini → $fin\n'
          'Reserva (entrega/recogida): $entrega → $recogida',
        ),
      );
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Maquinaria ocupada'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.message.isNotEmpty
                    ? e.message
                    : 'La maquinaria seleccionada está ocupada en esas fechas.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Conflictos detectados:',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              ...top.map(
                (x) => conflictoTile((x as Map).cast<String, dynamic>()),
              ),
              if (extra > 0) Text('… y $extra conflicto(s) más.'),
              const SizedBox(height: 8),
              const Text(
                'Sugerencia: consulta disponibilidad y selecciona otra máquina u origen (Conjunto/Empresa).',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _consultarDisponibilidadMaquinaria();
            },
            icon: const Icon(Icons.search),
            label: const Text('Consultar disponibilidad'),
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

  List<MaquinariaDisponibleItem> _opcionesMaquinariaDropdown() {
    if (_dispMaq == null) return [];

    final ocupadasIds = _ocupadaPorId.keys.toSet();
    final seen = <int>{};
    final opciones = <MaquinariaDisponibleItem>[];

    for (final m in [
      ..._dispMaq!.propiasDisponibles,
      ..._dispMaq!.empresaDisponibles,
    ]) {
      if (ocupadasIds.contains(m.id)) continue;
      if (!seen.add(m.id)) continue;
      opciones.add(m);
    }

    opciones.sort((a, b) {
      final origenA = a.origen.trim().toUpperCase();
      final origenB = b.origen.trim().toUpperCase();
      final byOrigen = origenA.compareTo(origenB);
      if (byOrigen != 0) return byOrigen;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });

    return opciones;
  }

  String _labelMaq(MaquinariaDisponibleItem m) {
    final o = m.origen.trim().toUpperCase();
    final tag = (o == 'CONJUNTO') ? 'Conjunto' : 'Empresa';
    final marca = m.marca.trim().isEmpty ? '' : ' • ${m.marca}';
    return '[$tag] ${m.nombre}$marca';
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
                      decoration: const InputDecoration(
                        labelText: 'Ubicación',
                        border: OutlineInputBorder(),
                      ),
                      value: _ubicacionSeleccionada?.id,
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
                        setState(() {
                          _ubicacionSeleccionada = u;
                          _elementoSeleccionado = u.elementos.isNotEmpty
                              ? u.elementos.first
                              : null;
                        });
                      },
                      validator: (v) =>
                          v == null ? 'Selecciona una ubicación' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Elemento',
                        border: OutlineInputBorder(),
                      ),
                      value: _elementoSeleccionado?.id,
                      items: (_ubicacionSeleccionada?.elementos ?? [])
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final el = _ubicacionSeleccionada!.elementos.firstWhere(
                          (x) => x.id == v,
                        );
                        setState(() => _elementoSeleccionado = el);
                      },
                      validator: (v) =>
                          v == null ? 'Selecciona un elemento' : null,
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
                      decoration: const InputDecoration(
                        labelText: 'Frecuencia',
                        border: OutlineInputBorder(),
                      ),
                      value: _frecuencia,
                      items: const ['DIARIA', 'SEMANAL', 'MENSUAL']
                          .map(
                            (f) => DropdownMenuItem(value: f, child: Text(f)),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _frecuencia = v;
                          if (_frecuencia != 'SEMANAL')
                            _diaSemanaProgramado = null;
                          if (_frecuencia != 'MENSUAL')
                            _diaMesProgramado = null;

                          if (_frecuencia == 'SEMANAL' &&
                              _diaSemanaProgramado == null) {
                            _diaSemanaProgramado = 'LUNES';
                          }
                          if (_frecuencia == 'MENSUAL' &&
                              _diaMesProgramado == null) {
                            _diaMesProgramado = 1;
                          }
                        });
                      },
                      validator: (v) =>
                          v == null ? 'Selecciona una frecuencia' : null,
                    ),
                    const SizedBox(height: 12),

                    if (_frecuencia == 'SEMANAL') ...[
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Día de la semana',
                          border: OutlineInputBorder(),
                        ),
                        value: _diaSemanaProgramado,
                        items:
                            const [
                                  'LUNES',
                                  'MARTES',
                                  'MIERCOLES',
                                  'JUEVES',
                                  'VIERNES',
                                  'SABADO',
                                  'DOMINGO',
                                ]
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d,
                                    child: Text(d),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) =>
                            setState(() => _diaSemanaProgramado = v),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_frecuencia == 'MENSUAL') ...[
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Día del mes',
                          border: OutlineInputBorder(),
                        ),
                        value: _diaMesProgramado,
                        items: List.generate(31, (i) => i + 1)
                            .map(
                              (d) =>
                                  DropdownMenuItem(value: d, child: Text('$d')),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _diaMesProgramado = v),
                      ),
                      const SizedBox(height: 12),
                    ],

                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Prioridad',
                        border: OutlineInputBorder(),
                      ),
                      value: prioridadValue,
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
                        value: _unidadCalculo,
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
                        value: _rendimientoTiempoBase,
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
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Insumo principal (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      value: _insumoPrincipalId,
                      items: _insumoItems,
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
              // ✅ 4.1 Maquinaria: botón consultar + resumen + filtrado
              // =========================================================
              _sectionCard(
                title: '4.1) Maquinaria planificada',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _cargandoDispMaq
                          ? null
                          : _consultarDisponibilidadMaquinaria,
                      icon: _cargandoDispMaq
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: const Text('Consultar disponibilidad'),
                    ),
                    const SizedBox(height: 10),
                    if (_dispMaq != null) ...[
                      Builder(
                        builder: (_) {
                          final ocupadasBorrador = _dispMaq!.ocupadas
                              .where(
                                (o) =>
                                    (o.fuente ?? '').trim().toUpperCase() ==
                                    'BORRADOR_PREVENTIVA',
                              )
                              .length;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '✅ Empresa: ${_dispMaq!.empresaDisponibles.length} | '
                                  '✅ Conjunto: ${_dispMaq!.propiasDisponibles.length} | '
                                  '⛔ Ocupadas: ${_dispMaq!.ocupadas.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (ocupadasBorrador > 0) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Aviso: $ocupadasBorrador ocupación(es) vienen de preventivas en borrador. '
                                    'Si se solapan, el cronograma no podrá publicarse.',
                                    style: TextStyle(
                                      color: Colors.orange.shade900,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],

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
                        label: const Text('Agregar maquinaria'),
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
                      value: _supervisorResponsable?.cedula,
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

              SizedBox(
                width: double.infinity,
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
                  label: Text(
                    _guardando ? 'Guardando...' : 'Guardar definición',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Insumo',
                border: OutlineInputBorder(),
              ),
              value: row.insumoId,
              items: _insumoItems,
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

    final opciones = _opcionesMaquinariaDropdown();

    if (_dispMaq == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8.0),
        child: Text('Consulta disponibilidad para listar maquinaria.'),
      );
    }

    // si la selección actual ya no está en opciones (por filtros), la dejamos como "no disponible"
    final selectedExists = row.maquinariaId == null
        ? true
        : opciones.any((o) => o.id == row.maquinariaId);

    final items = <DropdownMenuItem<int>>[
      ...opciones.map(
        (m) => DropdownMenuItem<int>(value: m.id, child: Text(_labelMaq(m))),
      ),
      if (!selectedExists && row.maquinariaId != null)
        DropdownMenuItem<int>(
          value: row.maquinariaId,
          child: Text('[No disponible] #${row.maquinariaId}'),
        ),
    ];

    // hint ocupada (si aplica)
    final ocupada = row.maquinariaId != null
        ? _ocupadaPorId[row.maquinariaId!]
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                    labelText: 'Maquinaria',
                    border: const OutlineInputBorder(),
                    helperText: ocupada == null
                        ? null
                        : (ocupada.fuente ?? '').trim().toUpperCase() ==
                              'BORRADOR_PREVENTIVA'
                        ? '⛔ Ocupada por otra preventiva en borrador: ${ocupada.descripcion ?? ''}'
                              .trim()
                        : '⛔ Ocupada: ${ocupada.descripcion ?? ''}'.trim(),
                  ),
                  value: row.maquinariaId,
                  items: items,
                  onChanged: (id) {
                    if (id == null) return;

                    final sel = opciones.firstWhere(
                      (x) => x.id == id,
                      orElse: () => MaquinariaDisponibleItem(
                        id: id,
                        nombre: 'Maquinaria',
                        tipo: '',
                        marca: '',
                        origen: 'EMPRESA',
                      ),
                    );

                    setState(() {
                      row.maquinariaId = id;
                      row.origen = sel.origen; // ✅ automático
                    });
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() {
                    row.tipoCtrl.dispose();
                    _maquinariaPlanRows.removeAt(index);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: row.tipoCtrl,
            decoration: const InputDecoration(
              labelText: 'Tipo / uso (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHerramientaPlanRow(int index) {
    final row = _herramientasPlanRows[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Herramienta',
                border: OutlineInputBorder(),
              ),
              value: row.herramientaId,
              items: _herramientaItems,
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
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Estado',
                border: OutlineInputBorder(),
              ),
              value: row.estado ?? 'OPERATIVA',
              items: const [
                DropdownMenuItem(value: 'OPERATIVA', child: Text('Operativa')),
                DropdownMenuItem(value: 'DANADA', child: Text('Dañada')),
                DropdownMenuItem(value: 'PERDIDA', child: Text('Perdida')),
                DropdownMenuItem(value: 'BAJA', child: Text('Baja')),
              ],
              onChanged: (v) => setState(() => row.estado = v ?? 'OPERATIVA'),
            ),
          ),
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

class _MaquinariaPlanRow {
  int? maquinariaId;
  String? origen; // 'CONJUNTO' | 'EMPRESA'
  final TextEditingController tipoCtrl;

  _MaquinariaPlanRow({this.maquinariaId, String? tipoInicial, this.origen})
    : tipoCtrl = TextEditingController(text: tipoInicial ?? '');
}

class _MaqOption {
  final int id;
  final String nombre;
  final String origen; // 'EMPRESA' | 'CONJUNTO'
  final String? marca;

  _MaqOption({
    required this.id,
    required this.nombre,
    required this.origen,
    this.marca,
  });
}

class _HerramientaPlanRow {
  int? herramientaId;
  final TextEditingController cantidadCtrl;
  String? estado;

  _HerramientaPlanRow({
    this.herramientaId,
    num? cantidadInicial,
    String? estadoInicial,
  }) : cantidadCtrl = TextEditingController(
         text: cantidadInicial != null ? cantidadInicial.toString() : '',
       ),
       estado = estadoInicial ?? 'OPERATIVA';
}
