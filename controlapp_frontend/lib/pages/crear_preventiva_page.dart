// lib/pages/crear_preventiva_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/maquinaria_model.dart';

import '../model/preventiva_model.dart';
import '../model/conjunto_model.dart';
import '../model/usuario_model.dart';
import '../service/theme.dart';
import '../api/preventiva_api.dart';
import '../api/empresa_api.dart';
import '../model/insumo_model.dart';

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
  final GerenteApi _gerenteApi = GerenteApi();

  final EmpresaApi _empresaApi = EmpresaApi();
  List<InsumoResponse> _catalogoInsumos = [];
  List<MaquinariaResponse> _catalogoMaquinaria = [];
  List<Usuario> _supervisores = [];

  // Controllers básicos
  final _descripcionCtrl = TextEditingController();
  final _prioridadCtrl = TextEditingController(text: '2');

  // Duración – rendimiento
  bool _usaRendimiento = true;
  String? _unidadCalculo; // M2, M3, ML, UNIDAD...
  final _cantidadCtrl = TextEditingController(); // antes _areaCtrl
  final _rendimientoCtrl = TextEditingController(); // valor numérico

  // ✅ NUEVO: cómo interpretar rendimiento
  // POR_MINUTO: unidades/min
  // MIN_POR_UNIDAD: min/unidad
  // POR_HORA: unidades/h
  String _rendimientoTiempoBase = 'POR_MINUTO';

  // Duración fija (minutos)
  final _duracionFijaMinCtrl = TextEditingController();

  // Insumo principal
  int? _insumoPrincipalId;
  final _consumoPorUnidadCtrl = TextEditingController();

  final List<_InsumoPlanRow> _insumosPlanRows = [];
  final List<_MaquinariaPlanRow> _maquinariaPlanRows = [];

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

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await Future.wait([
      _cargarCatalogoInsumos(),
      _cargarCatalogoMaquinaria(),
      _cargarSupervisores(),
    ]);
    if (!mounted) return;
    _cargarDesdeExistenteOInit();
    setState(() {});
  }

  Future<void> _cargarCatalogoInsumos() async {
    try {
      final lista = await _empresaApi.listarCatalogo();
      if (!mounted) return;
      setState(() => _catalogoInsumos = lista);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando catálogo de insumos: $e')),
      );
    }
  }

  Future<void> _cargarCatalogoMaquinaria() async {
    try {
      final lista = await _empresaApi.listarMaquinaria();
      if (!mounted) return;
      setState(() => _catalogoMaquinaria = lista);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando catálogo de maquinaria: $e')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando supervisores: $e')),
      );
    }
  }

  void _cargarDesdeExistenteOInit() {
    final existente = widget.existente;

    if (existente != null) {
      _descripcionCtrl.text = existente.descripcion;
      _prioridadCtrl.text = (existente.prioridad.clamp(1, 3)).toString();
      _frecuencia = existente.frecuencia;
      _unidadCalculo = existente.unidadCalculo;

      _diaSemanaProgramado = existente.diaSemanaProgramado;
      _diaMesProgramado = existente.diaMesProgramado;

      // Duración / rendimiento
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

      // Si tu modelo DefinicionPreventiva ya trae rendimientoTiempoBase, úsalo:
      final base = (existente as dynamic).rendimientoTiempoBase;
      if (base is String && base.isNotEmpty) {
        _rendimientoTiempoBase = base;
      }

      _insumoPrincipalId = existente.insumoPrincipalId;
      if (existente.consumoPrincipalPorUnidad != null) {
        _consumoPorUnidadCtrl.text = existente.consumoPrincipalPorUnidad!
            .toString();
      }

      _insumosPlanRows.clear();
      for (final i in existente.insumosPlan) {
        _insumosPlanRows.add(
          _InsumoPlanRow(
            insumoId: i.insumoId,
            consumoInicial: i.consumoPorUnidad,
          ),
        );
      }

      _maquinariaPlanRows.clear();
      for (final m in existente.maquinariaPlan) {
        _maquinariaPlanRows.add(
          _MaquinariaPlanRow(maquinariaId: m.maquinariaId, tipoInicial: m.tipo),
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
          if (usuario.cedula != '0')
            _operariosSeleccionadosCedulas.add(usuario.cedula);
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
    for (final r in _insumosPlanRows) {
      r.consumoCtrl.dispose();
    }
    for (final m in _maquinariaPlanRows) {
      m.tipoCtrl.dispose();
    }
    super.dispose();
  }

  String _soloDigitos(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  int? _tryInt(String s) => int.tryParse(_soloDigitos(s));

  double? _tryDouble(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  String _unidadLabel() {
    final u = _unidadCalculo ?? 'unidad';
    return u.toLowerCase();
  }

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

  int? _previewMinutos() {
    if (!_usaRendimiento) {
      final m = _tryInt(_duracionFijaMinCtrl.text);
      if (m == null || m <= 0) return null;
      return m;
    }

    final cant = _tryDouble(_cantidadCtrl.text);
    final rend = _tryDouble(_rendimientoCtrl.text);
    if (cant == null || rend == null || rend <= 0) return null;

    switch (_rendimientoTiempoBase) {
      case 'POR_MINUTO': // unidades/min
        return (cant / rend * 60)
            .round(); // ← OJO: aquí NO, es *1 (min), no *60
      case 'POR_HORA': // unidades/h
        return (cant / rend * 60).round();
      case 'MIN_POR_UNIDAD': // min/unidad
        return (cant * rend).round();
    }
    return null;
  }

  // ✅ IMPORTANTE:
  // POR_MINUTO es unidades/min => minutos = cantidad / rendimiento
  // (NO multiplicar por 60)
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
      case 'POR_MINUTO': // unidades/min
        return (cant / rend).round();
      case 'POR_HORA': // unidades/h
        return (cant / rend * 60).round();
      case 'MIN_POR_UNIDAD': // min/unidad
        return (cant * rend).round();
      default:
        return null;
    }
  }

  Future<void> _mostrarSelectorOperarios() async {
    if (_operarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay operarios en este conjunto')),
      );
      return;
    }

    final seleccionTemp = Set<String>.from(_operariosSeleccionadosCedulas);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
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
          ),
        )
        .toList();

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

      // ✅ ahora sí: minutos fijos
      duracionMinutosFija: duracionMinFija,

      // ✅ NUEVO: esto es lo que el back necesita para interpretar el rendimiento
      rendimientoTiempoBase: _usaRendimiento ? _rendimientoTiempoBase : null,

      insumoPrincipalId: _insumoPrincipalId,
      consumoPrincipalPorUnidad: consumoPrincipal,
      insumosPlan: insumosPlanRequests.isNotEmpty ? insumosPlanRequests : null,
      maquinariaPlan: maquinariaPlanRequests.isNotEmpty
          ? maquinariaPlanRequests
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
      _snack('Error al guardar preventiva: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
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
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
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
                      const SizedBox(height: 8),
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
                          helperText:
                              'Ej: 200 (si son 200 m²) o 10 (si son 10 unidades)',
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
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            '⏱️ Estimado: $preview min (~ ${(preview / 60).toStringAsFixed(2)} h)',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _duracionFijaMinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Duración fija (minutos)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _sectionCard(
                title: '4) Recursos planificados – Insumos',
                child: Column(
                  children: [
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Insumo principal (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      value: _insumoPrincipalId,
                      items: _catalogoInsumos
                          .map(
                            (i) => DropdownMenuItem(
                              value: i.id,
                              child: Text('${i.nombre} (${i.unidad})'),
                            ),
                          )
                          .toList(),
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
                        helperText:
                            'Ej: litros por m², litros por unidad, etc.',
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
                    Column(
                      children: [
                        for (int i = 0; i < _insumosPlanRows.length; i)
                          _buildInsumoPlanRow(i),
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
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _sectionCard(
                title: '4.1) Maquinaria planificada',
                child: Column(
                  children: [
                    for (int i = 0; i < _maquinariaPlanRows.length; i)
                      _buildMaquinariaPlanRow(i),
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

  Widget _buildInsumoPlanRow(int index) {
    final row = _insumosPlanRows[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Insumo',
                border: OutlineInputBorder(),
              ),
              value: row.insumoId,
              items: _catalogoInsumos
                  .map(
                    (i) => DropdownMenuItem(value: i.id, child: Text(i.nombre)),
                  )
                  .toList(),
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
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Maquinaria',
                border: OutlineInputBorder(),
              ),
              value: row.maquinariaId,
              items: _catalogoMaquinaria
                  .map(
                    (m) => DropdownMenuItem(value: m.id, child: Text(m.nombre)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => row.maquinariaId = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.tipoCtrl,
              decoration: const InputDecoration(
                labelText: 'Tipo / uso (opcional)',
                border: OutlineInputBorder(),
              ),
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
  final TextEditingController tipoCtrl;

  _MaquinariaPlanRow({this.maquinariaId, String? tipoInicial})
    : tipoCtrl = TextEditingController(text: tipoInicial ?? '');
}
