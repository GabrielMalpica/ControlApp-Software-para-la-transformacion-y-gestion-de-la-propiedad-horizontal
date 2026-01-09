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
  final String nit; // NIT del conjunto
  final Conjunto conjunto; // ya viene con ubicaciones y operarios
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

  // Catálogo de insumos de la empresa
  final EmpresaApi _empresaApi = EmpresaApi();
  List<InsumoResponse> _catalogoInsumos = [];

  // Catálogo de maquinaria de la empresa
  List<MaquinariaResponse> _catalogoMaquinaria = [];

  // Supervisores
  List<Usuario> _supervisores = [];

  // Controllers básicos
  final _descripcionCtrl = TextEditingController();
  final _prioridadCtrl = TextEditingController(text: '5');

  // Duración – rendimiento
  bool _usaRendimiento = true;
  String? _unidadCalculo; // "M2", "HORA", "UNIDAD", ...
  final _areaCtrl = TextEditingController();
  final _rendimientoCtrl = TextEditingController(); // m2/hora, etc.

  // Duración fija
  final _duracionFijaCtrl = TextEditingController();

  // Insumo principal
  int? _insumoPrincipalId;
  final _consumoPorUnidadCtrl = TextEditingController();

  // Insumos planificados adicionales
  final List<_InsumoPlanRow> _insumosPlanRows = [];

  // Maquinaria planificada (sin horas / cantidad)
  final List<_MaquinariaPlanRow> _maquinariaPlanRows = [];

  // Frecuencia
  String? _frecuencia;

  // Operarios responsables (uno o varios) -> guardamos cédulas como String
  final List<String> _operariosSeleccionadosCedulas = [];

  // Supervisor responsable (obligatorio)
  Usuario? _supervisorResponsable;

  bool _activo = true;

  // Ubicación / elemento
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
      setState(() {
        _catalogoInsumos = lista;
      });
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
      setState(() {
        _catalogoMaquinaria = lista;
      });
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
      setState(() {
        _supervisores = supervisores;
      });
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
      // 1. Datos básicos
      _descripcionCtrl.text = existente.descripcion;
      _prioridadCtrl.text = existente.prioridad.toString();
      _frecuencia = existente.frecuencia;
      _unidadCalculo = existente.unidadCalculo;

      // 2. Duración / rendimiento
      if (existente.duracionHorasFija != null) {
        _usaRendimiento = false;
        _duracionFijaCtrl.text = existente.duracionHorasFija!.toString();
      } else {
        _usaRendimiento = true;
        if (existente.areaNumerica != null) {
          _areaCtrl.text = existente.areaNumerica!.toString();
        }
        if (existente.rendimientoBase != null) {
          _rendimientoCtrl.text = existente.rendimientoBase!.toString();
        }
      }

      // 3. Insumo principal
      _insumoPrincipalId = existente.insumoPrincipalId;
      if (existente.consumoPrincipalPorUnidad != null) {
        _consumoPorUnidadCtrl.text = existente.consumoPrincipalPorUnidad!
            .toString();
      }

      // 4. Insumos planificados adicionales
      _insumosPlanRows.clear();
      if (existente.insumosPlan.isNotEmpty) {
        for (final i in existente.insumosPlan) {
          _insumosPlanRows.add(
            _InsumoPlanRow(
              insumoId: i.insumoId,
              consumoInicial: i.consumoPorUnidad,
            ),
          );
        }
      }

      // 4.1 Maquinaria planificada (sin cantidad)
      _maquinariaPlanRows.clear();
      if (existente.maquinariaPlan.isNotEmpty) {
        for (final m in existente.maquinariaPlan) {
          _maquinariaPlanRows.add(
            _MaquinariaPlanRow(
              maquinariaId: m.maquinariaId,
              tipoInicial: m.tipo,
            ),
          );
        }
      }

      // 5. Activo
      _activo = existente.activo;

      // 6. Operarios seleccionados (leemos la LISTA del backend)
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
      } else if (existente.responsableSugeridoId != null) {
        // Fallback: al menos marcar el responsable principal
        final usuario = _operarios.firstWhere(
          (o) => int.tryParse(o.cedula) == existente.responsableSugeridoId,
          orElse: () => _dummyOperario(),
        );
        if (usuario.cedula != '0') {
          _operariosSeleccionadosCedulas.add(usuario.cedula);
        }
      }

      // 7. Supervisor responsable
      if (existente.supervisorId != null) {
        final targetCedula = existente.supervisorId!.toString();
        _supervisorResponsable = _supervisores.firstWhere(
          (s) => s.cedula == targetCedula,
          orElse: () =>
              _supervisores.isNotEmpty ? _supervisores.first : _dummyOperario(),
        );
      }

      // 8. Ubicación y elemento
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
      // Nueva definición preventiva
      if (_ubicaciones.isNotEmpty) {
        _ubicacionSeleccionada = _ubicaciones.first;
        if (_ubicacionSeleccionada!.elementos.isNotEmpty) {
          _elementoSeleccionado = _ubicacionSeleccionada!.elementos.first;
        }
      }
      _frecuencia = 'MENSUAL';
      _usaRendimiento = true;
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
    _areaCtrl.dispose();
    _rendimientoCtrl.dispose();
    _duracionFijaCtrl.dispose();
    _consumoPorUnidadCtrl.dispose();
    for (final r in _insumosPlanRows) {
      r.consumoCtrl.dispose();
    }
    for (final m in _maquinariaPlanRows) {
      m.tipoCtrl.dispose();
    }
    super.dispose();
  }

  double? _calcularConsumoPrincipalTotal() {
    final consumoText = _consumoPorUnidadCtrl.text.trim();
    if (consumoText.isEmpty) return null;

    final consumo = double.tryParse(consumoText);
    if (consumo == null) return null;

    if (_unidadCalculo == 'HORA') {
      final horasText = _duracionFijaCtrl.text.trim();
      final horas = int.tryParse(horasText);
      if (horas != null && horas > 0) {
        return consumo * horas;
      }
    }

    final areaText = _areaCtrl.text.trim();
    final area = double.tryParse(areaText);
    if (area != null && area > 0) {
      return consumo * area;
    }

    return null;
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
                TextButton(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona ubicación y elemento')),
      );
      return;
    }

    if (_frecuencia == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona la frecuencia')));
      return;
    }

    // ========= OPERARIOS (uno o varios) =========
    if (_operariosSeleccionadosCedulas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un operario')),
      );
      return;
    }

    String _soloDigitos(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

    final operariosIdsInt = _operariosSeleccionadosCedulas
        .map((ced) => _soloDigitos(ced))
        .map((cedLimpia) => int.tryParse(cedLimpia))
        .whereType<int>()
        .toList();

    if (operariosIdsInt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron interpretar las cédulas de operarios'),
        ),
      );
      return;
    }

    // El responsable principal (para el campo existente) será el primero
    final responsableId = operariosIdsInt.first;

    // ========= SUPERVISOR =========
    if (_supervisorResponsable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un supervisor responsable')),
      );
      return;
    }

    final supervisorCedulaLimpia = _soloDigitos(_supervisorResponsable!.cedula);
    final supervisorId = int.tryParse(supervisorCedulaLimpia);

    if (supervisorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supervisor responsable inválido')),
      );
      return;
    }

    // ========= DURACIÓN =========
    String? unidadCalculo;
    double? area;
    double? rendimiento;
    int? duracionFija;

    if (_usaRendimiento) {
      if (_unidadCalculo == null ||
          _areaCtrl.text.trim().isEmpty ||
          _rendimientoCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Completa unidad de cálculo, área y rendimiento o cambia a duración fija.',
            ),
          ),
        );
        return;
      }
      unidadCalculo = _unidadCalculo;
      area = double.tryParse(_areaCtrl.text.trim());
      rendimiento = double.tryParse(_rendimientoCtrl.text.trim());
      if (area == null || rendimiento == null || rendimiento <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Área y rendimiento deben ser números válidos'),
          ),
        );
        return;
      }
    } else {
      if (_duracionFijaCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indica la duración fija en horas')),
        );
        return;
      }
      duracionFija = int.tryParse(_duracionFijaCtrl.text.trim());
      if (duracionFija == null || duracionFija <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duración fija debe ser un entero > 0')),
        );
        return;
      }
    }

    final prioridad = int.tryParse(_prioridadCtrl.text.trim()) ?? 5;

    final consumoPrincipal = _consumoPorUnidadCtrl.text.trim().isNotEmpty
        ? double.tryParse(_consumoPorUnidadCtrl.text.trim())
        : null;

    // ========= INSUMOS PLANIFICADOS =========
    final insumosPlanRequests = _insumosPlanRows
        .where(
          (r) => r.insumoId != null && r.consumoCtrl.text.trim().isNotEmpty,
        )
        .map(
          (r) => InsumoPlanItemRequest(
            insumoId: r.insumoId!,
            consumoPorUnidad: double.parse(r.consumoCtrl.text.trim()),
          ),
        )
        .toList();

    // ========= MAQUINARIA PLANIFICADA =========
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

    // ========= ARMAR REQUEST =========
    final req = DefinicionPreventivaRequest(
      ubicacionId: _ubicacionSeleccionada!.id,
      elementoId: _elementoSeleccionado!.id,
      descripcion: _descripcionCtrl.text.trim(),
      frecuencia: _frecuencia!,
      prioridad: prioridad,
      unidadCalculo: unidadCalculo,
      areaNumerica: area,
      rendimientoBase: rendimiento,
      duracionHorasFija: duracionFija,
      insumoPrincipalId: _insumoPrincipalId,
      consumoPrincipalPorUnidad: consumoPrincipal,
      insumosPlan: insumosPlanRequests.isNotEmpty ? insumosPlanRequests : null,
      maquinariaPlan: maquinariaPlanRequests.isNotEmpty
          ? maquinariaPlanRequests
          : null,
      operariosIds: operariosIdsInt, // lista completa
      responsableSugeridoId: responsableId, // principal
      supervisorId: supervisorId,
      activo: _activo,
    );

    // ========= GUARDAR =========
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar preventiva: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Dónde
              const Text(
                '1. Dónde se ejecuta',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Ubicación',
                  border: OutlineInputBorder(),
                ),
                value: _ubicacionSeleccionada?.id,
                items: _ubicaciones
                    .map(
                      (u) =>
                          DropdownMenuItem(value: u.id, child: Text(u.nombre)),
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
                validator: (v) => v == null ? 'Selecciona una ubicación' : null,
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
                      (e) =>
                          DropdownMenuItem(value: e.id, child: Text(e.nombre)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final el = _ubicacionSeleccionada!.elementos.firstWhere(
                    (x) => x.id == v,
                  );
                  setState(() => _elementoSeleccionado = el);
                },
                validator: (v) => v == null ? 'Selecciona un elemento' : null,
              ),
              const SizedBox(height: 24),

              // 2. Qué
              const Text(
                '2. Qué se va a hacer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
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
                items:
                    const [
                      'DIARIA',
                      'SEMANAL',
                      'QUINCENAL',
                      'MENSUAL',
                      'BIMESTRAL',
                      'TRIMESTRAL',
                      'SEMESTRAL',
                      'ANUAL',
                    ].map((f) {
                      return DropdownMenuItem(value: f, child: Text(f));
                    }).toList(),
                onChanged: (v) => setState(() => _frecuencia = v),
                validator: (v) =>
                    v == null ? 'Selecciona una frecuencia' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _prioridadCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prioridad (1 alta – 9 baja)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // 3. Duración planificada
              const Text(
                '3. Duración planificada',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SwitchListTile(
                title: const Text('Calcular por rendimiento y área'),
                subtitle: const Text(
                  'Si lo desactivas, usas duración fija en horas',
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
                  items:
                      const [
                        'M2',
                        'M3',
                        'ML',
                        'UNIDAD',
                        'HORA',
                        'LITRO',
                        'KILO',
                      ].map((u) {
                        return DropdownMenuItem(value: u, child: Text(u));
                      }).toList(),
                  onChanged: (v) => setState(() => _unidadCalculo = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _areaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cantidad (área / unidades)',
                    helperText: 'Ej: 200 si son 200 m² o 10 unidades',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _rendimientoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Rendimiento base (ej. m² por hora)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _duracionFijaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duración fija (horas)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // 4. Recursos planificados – Insumos
              const Text(
                '4. Recursos planificados – Insumos',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              TextFormField(
                controller: _consumoPorUnidadCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Consumo por unidad',
                  helperText: _unidadCalculo == null
                      ? 'Ej: litros por m², litros por hora, unidades por unidad'
                      : 'Cantidad de insumo por ${_unidadCalculo!.toLowerCase()}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              Builder(
                builder: (_) {
                  final total = _calcularConsumoPrincipalTotal();
                  if (total == null) return const SizedBox.shrink();
                  return Text(
                    'Consumo estimado total: ${total.toStringAsFixed(2)} (unidad del insumo)',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  );
                },
              ),
              const SizedBox(height: 16),

              const Text(
                'Otros insumos planificados',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  for (int i = 0; i < _insumosPlanRows.length; i++)
                    _buildInsumoPlanRow(i),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _insumosPlanRows.add(_InsumoPlanRow());
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar insumo'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              const Text(
                '4.1 Maquinaria planificada',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  for (int i = 0; i < _maquinariaPlanRows.length; i++)
                    _buildMaquinariaPlanRow(i),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _maquinariaPlanRows.add(_MaquinariaPlanRow());
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar maquinaria'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 5. Operarios y supervisor
              const Text(
                '5. Operarios y supervisor',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              InkWell(
                onTap: _mostrarSelectorOperarios,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Operarios responsables',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _operariosSeleccionadosCedulas.isEmpty
                        ? 'Seleccionar operarios'
                        : '${_operariosSeleccionadosCedulas.length} operario(s) seleccionado(s)',
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
                validator: (v) => v == null ? 'Selecciona un supervisor' : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Definición activa'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'Guardando...' : 'Guardar definición'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
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
