import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/model/informe_detallado_opciones.dart';
import 'package:flutter_application_1/model/reporte_model.dart';
import 'package:flutter_application_1/service/chart_style.dart';
import 'package:flutter_application_1/service/tarea_labels.dart';
import 'package:flutter_application_1/service/theme.dart';

/// Lo que se recuerda del último informe (sin filtros: ver toPreferencias).
const _kPreferencias = 'informe_detallado_opciones_v1';

Future<OpcionesInformeDetallado> _cargarPreferencias() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPreferencias);
    if (raw != null && raw.isNotEmpty) {
      final json = jsonDecode(raw);
      if (json is Map) {
        return OpcionesInformeDetallado.fromJson(json.cast<String, dynamic>());
      }
    }
  } catch (_) {
    // Preferencias dañadas o no disponibles: se parte de la plantilla estándar.
  }
  return const OpcionesInformeDetallado();
}

Future<void> _guardarPreferencias(OpcionesInformeDetallado o) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPreferencias, jsonEncode(o.toPreferencias()));
  } catch (_) {
    // Best effort: si no se guarda, la próxima vez se vuelve a elegir.
  }
}

/// Abre el panel para personalizar el informe detallado y devuelve las
/// opciones elegidas, o null si el usuario lo cierra sin generar.
Future<OpcionesInformeDetallado?> mostrarOpcionesInformeDetallado(
  BuildContext context, {
  required List<TareaDetalleRow> tareas,
  required bool esAdministrador,
}) async {
  var inicial = await _cargarPreferencias();
  if (esAdministrador) inicial = inicial.paraAdministrador();
  if (!context.mounted) return null;

  final panel = InformeDetalladoOpcionesPanel(
    tareas: tareas,
    esAdministrador: esAdministrador,
    inicial: inicial,
  );

  final OpcionesInformeDetallado? elegidas;
  if (MediaQuery.sizeOf(context).width >= 760) {
    elegidas = await showDialog<OpcionesInformeDetallado>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 880),
          child: panel,
        ),
      ),
    );
  } else {
    elegidas = await showModalBottomSheet<OpcionesInformeDetallado>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: FractionallySizedBox(heightFactor: 0.94, child: panel),
      ),
    );
  }
  if (elegidas != null) await _guardarPreferencias(elegidas);
  return elegidas;
}

class InformeDetalladoOpcionesPanel extends StatefulWidget {
  final List<TareaDetalleRow> tareas;
  final bool esAdministrador;
  final OpcionesInformeDetallado inicial;

  const InformeDetalladoOpcionesPanel({
    super.key,
    required this.tareas,
    required this.esAdministrador,
    this.inicial = const OpcionesInformeDetallado(),
  });

  @override
  State<InformeDetalladoOpcionesPanel> createState() =>
      _InformeDetalladoOpcionesPanelState();
}

class _InformeDetalladoOpcionesPanelState
    extends State<InformeDetalladoOpcionesPanel> {
  late OpcionesInformeDetallado _o = widget.esAdministrador
      ? widget.inicial.paraAdministrador()
      : widget.inicial;
  late final ValoresFiltroInforme _valores = ValoresFiltroInforme.desde(
    widget.tareas,
  );
  late final Map<String, int> _porEstado = () {
    final m = <String, int>{};
    for (final t in widget.tareas) {
      final e = t.estado.toUpperCase();
      m[e] = (m[e] ?? 0) + 1;
    }
    return m;
  }();

  late final _tituloCtrl = TextEditingController(text: widget.inicial.titulo);
  late final _observacionesCtrl = TextEditingController(
    text: widget.inicial.observacionesGenerales,
  );

  /// Evita que un doble toque en "Generar" cierre el panel dos veces.
  bool _enviado = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  void _set(OpcionesInformeDetallado o) => setState(() => _o = o);

  OpcionesInformeDetallado get _conTextos => _o.copyWith(
    titulo: _tituloCtrl.text,
    observacionesGenerales: _observacionesCtrl.text,
  );

  void _generar() {
    if (_enviado) return;
    final o = _conTextos;
    if (o.errores.isNotEmpty) return;
    _enviado = true;
    Navigator.of(context).pop(o);
  }

  /// Alterna un valor de un filtro. null = sin filtro (todos marcados).
  Set<String>? _alternar(
    Set<String>? actual,
    List<String> todos,
    String valor,
    bool marcar,
  ) {
    final nuevo = {...(actual ?? todos.toSet())};
    if (marcar) {
      nuevo.add(valor);
    } else {
      nuevo.remove(valor);
    }
    final completo =
        nuevo.length == todos.length && todos.every(nuevo.contains);
    return completo ? null : nuevo;
  }

  bool _marcado(Set<String>? actual, String valor) =>
      actual == null || actual.contains(valor);

  /* --------------------------------- UI --------------------------------- */

  Widget _titulo(String texto, {String? ayuda}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTheme.text,
              ),
            ),
          ),
          if (ayuda != null) ...[
            const SizedBox(height: 2),
            Text(
              ayuda,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subtitulo(String texto) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(
      texto,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.textMuted,
      ),
    ),
  );

  Widget _chips(List<Widget> children) =>
      Wrap(spacing: 8, runSpacing: 4, children: children);

  Widget _plantillas() {
    final actual = _o.plantilla;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo(
          'Plantilla',
          ayuda: 'Un punto de partida; luego puedes ajustar todo.',
        ),
        _chips([
          for (final p in PlantillaInforme.values)
            if (p != PlantillaInforme.personalizado)
              ChoiceChip(
                label: Text(p.etiqueta),
                selected: actual == p,
                onSelected: (_) => _set(
                  _o.conPlantilla(p, esAdministrador: widget.esAdministrador),
                ),
              ),
          if (actual == PlantillaInforme.personalizado)
            const ChoiceChip(
              label: Text('Personalizado'),
              selected: true,
              onSelected: null,
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          actual == PlantillaInforme.auditoria
              ? '${actual.descripcion} Recomendada para clientes que pasan auditorías.'
              : actual.descripcion,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Widget _organizacion() {
    final corr = etiquetaCorrectiva(plural: true, minuscula: true);
    final descripciones = {
      OrganizacionInforme.actividad:
          'Preventivas agrupadas por actividad del cronograma, luego $corr.',
      OrganizacionInforme.ubicacion:
          'Una sección por ubicación con sus preventivas y $corr.',
      OrganizacionInforme.cronologico:
          'Día por día, cada tarea con sus datos y fotos.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo(
          'Cómo organizar el detalle',
          ayuda: _o.seccion('detalle')
              ? null
              : 'Aplica cuando incluyes "Detalle de tareas".',
        ),
        RadioGroup<OrganizacionInforme>(
          groupValue: _o.organizacion,
          onChanged: (v) {
            if (v != null) _set(_o.copyWith(organizacion: v));
          },
          child: Column(
            children: [
              for (final org in OrganizacionInforme.values)
                RadioListTile<OrganizacionInforme>(
                  value: org,
                  contentPadding: EdgeInsets.zero,
                  title: Text(org.etiqueta),
                  subtitle: Text(descripciones[org]!),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filtros() {
    final v = _valores;
    final tipos = [
      if (v.hayPreventivas) 'PREVENTIVA',
      if (v.hayCorrectivas) 'CORRECTIVA',
    ];
    final ubicSeleccionadas = _o.ubicaciones?.length ?? v.ubicaciones.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo(
          'Qué tareas incluir',
          ayuda:
              'Si dejas algo por fuera, el PDF dirá que es un informe filtrado.',
        ),
        if (tipos.length > 1) ...[
          _subtitulo('Tipo'),
          _chips([
            for (final t in tipos)
              FilterChip(
                label: Text(
                  t == 'PREVENTIVA'
                      ? 'Preventivas'
                      : etiquetaCorrectiva(plural: true),
                ),
                selected: _marcado(_o.tipos, t),
                onSelected: (sel) => _set(
                  _o.copyWith(tipos: () => _alternar(_o.tipos, tipos, t, sel)),
                ),
              ),
          ]),
        ],
        if (v.estados.length > 1) ...[
          _subtitulo('Estado'),
          _chips([
            for (final e in v.estados)
              FilterChip(
                label: Text(
                  '${ChartStyle.estadoLabel(e)} (${_porEstado[e] ?? 0})',
                ),
                selected: _marcado(_o.estados, e),
                onSelected: (sel) => _set(
                  _o.copyWith(
                    estados: () => _alternar(_o.estados, v.estados, e, sel),
                  ),
                ),
              ),
          ]),
        ],
        if (v.frecuencias.length > 1) ...[
          _subtitulo('Frecuencia (solo preventivas)'),
          _chips([
            for (final f in v.frecuencias)
              FilterChip(
                label: Text(etiquetaFrecuenciaInforme(f)),
                selected: _marcado(_o.frecuencias, f),
                onSelected: (sel) => _set(
                  _o.copyWith(
                    frecuencias: () =>
                        _alternar(_o.frecuencias, v.frecuencias, f, sel),
                  ),
                ),
              ),
          ]),
        ],
        if (v.ubicaciones.length > 1)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text(
                'Ubicaciones',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _o.ubicaciones == null
                    ? 'Todas (${v.ubicaciones.length})'
                    : '$ubicSeleccionadas de ${v.ubicaciones.length}',
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () =>
                            _set(_o.copyWith(ubicaciones: () => null)),
                        child: const Text('Marcar todas'),
                      ),
                      TextButton(
                        onPressed: () =>
                            _set(_o.copyWith(ubicaciones: () => <String>{})),
                        child: const Text('Desmarcar todas'),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _chips([
                    for (final u in v.ubicaciones)
                      FilterChip(
                        label: Text(u),
                        selected: _marcado(_o.ubicaciones, u),
                        onSelected: (sel) => _set(
                          _o.copyWith(
                            ubicaciones: () => _alternar(
                              _o.ubicaciones,
                              v.ubicaciones,
                              u,
                              sel,
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ],
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Solo tareas con evidencia'),
          subtitle: const Text('Deja por fuera las tareas sin fotos.'),
          value: _o.soloConEvidencia,
          onChanged: (sel) => _set(_o.copyWith(soloConEvidencia: sel)),
        ),
      ],
    );
  }

  Widget _secciones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo('Secciones del informe'),
        for (final s in seccionesInforme)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(s.titulo),
            subtitle: Text(s.descripcion),
            value: _o.seccion(s.clave),
            onChanged: (sel) => _set(_o.conSeccion(s.clave, sel ?? false)),
          ),
      ],
    );
  }

  Widget _campos() {
    final visibles = camposInforme.where(
      (c) => !(c.interna && widget.esAdministrador),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo(
          'Qué mostrar de cada tarea',
          ayuda: _o.seccion('detalle')
              ? 'Las marcadas como "interno" no las ve el cliente.'
              : 'Activa "Detalle de tareas" para elegir qué mostrar de cada una.',
        ),
        if (_o.seccion('detalle'))
          _chips([
            for (final c in visibles)
              Tooltip(
                message: c.descripcion,
                child: FilterChip(
                  label: Text(c.interna ? '${c.titulo} (interno)' : c.titulo),
                  selected: _o.campo(c.clave),
                  onSelected: (sel) => _set(_o.conCampo(c.clave, sel)),
                ),
              ),
          ]),
      ],
    );
  }

  Widget _desplegable<T>({
    required String etiqueta,
    required T valor,
    required List<T> opciones,
    required String Function(T) texto,
    required ValueChanged<T> alCambiar,
    String? ayuda,
  }) {
    return DropdownButtonFormField<T>(
      // La plantilla puede cambiar el valor desde afuera.
      key: ValueKey('$etiqueta-$valor'),
      initialValue: valor,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: etiqueta,
        helperText: ayuda,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final o in opciones)
          DropdownMenuItem<T>(value: o, child: Text(texto(o))),
      ],
      onChanged: (v) {
        if (v != null || null is T) alCambiar(v as T);
      },
    );
  }

  Widget _fotos() {
    if (!_o.seccion('detalle')) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo('Fotos'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Incluir fotos de evidencia'),
          subtitle: const Text(
            'Sin fotos, cada tarea indica cuántas tiene en la aplicación.',
          ),
          value: _o.incluirFotos,
          onChanged: (sel) => _set(_o.copyWith(incluirFotos: sel)),
        ),
        if (_o.incluirFotos)
          LayoutBuilder(
            builder: (context, constraints) {
              final doble = constraints.maxWidth >= 520;
              final ancho = doble
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: ancho,
                      child: _desplegable<int?>(
                        etiqueta: 'Fotos por tarea',
                        valor: _o.fotosPorTarea,
                        opciones: fotosPorTareaOpciones,
                        texto: (v) => v == null ? 'Todas (hasta 12)' : '$v',
                        ayuda:
                            'Si hay más, se eligen repartidas (antes y después).',
                        alCambiar: (v) =>
                            _set(_o.copyWith(fotosPorTarea: () => v)),
                      ),
                    ),
                    SizedBox(
                      width: ancho,
                      child: _desplegable<RegistrosConFoto>(
                        etiqueta: 'Registros con foto por actividad',
                        valor: _o.registrosPorActividad,
                        opciones: RegistrosConFoto.values,
                        texto: (v) => v.etiqueta,
                        ayuda: _o.registrosPorActividad == RegistrosConFoto.auto
                            ? 'Diarias: 3 repartidos en el periodo. Resto: todos.'
                            : 'Se reparten a lo largo del periodo.',
                        alCambiar: (v) =>
                            _set(_o.copyWith(registrosPorActividad: v)),
                      ),
                    ),
                    SizedBox(
                      width: ancho,
                      child: _desplegable<TamanoFoto>(
                        etiqueta: 'Tamaño',
                        valor: _o.tamanoFotos,
                        opciones: TamanoFoto.values,
                        texto: (v) => v.etiqueta,
                        alCambiar: (v) => _set(_o.copyWith(tamanoFotos: v)),
                      ),
                    ),
                    SizedBox(
                      width: ancho,
                      child: _desplegable<CalidadFoto>(
                        etiqueta: 'Calidad',
                        valor: _o.calidadFotos,
                        opciones: CalidadFoto.values,
                        texto: (v) => v.etiqueta,
                        ayuda: _o.calidadFotos == CalidadFoto.alta
                            ? 'Más nítida y pesada; máximo 250 fotos.'
                            : 'Máximo 400 fotos por informe.',
                        alCambiar: (v) => _set(_o.copyWith(calidadFotos: v)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _campoTexto(
    TextEditingController ctrl,
    String etiqueta, {
    int maxLength = 80,
    int maxLines = 1,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        maxLength: maxLength,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: etiqueta,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _textos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo('Textos del informe'),
        _campoTexto(
          _tituloCtrl,
          'Título (opcional)',
          hint: 'Reporte visual de actividades',
        ),
        _campoTexto(
          _observacionesCtrl,
          'Observaciones generales (opcional)',
          maxLength: 1500,
          maxLines: 4,
          hint: 'Se imprimen en la portada. Ej: este mes se reforzó...',
        ),
      ],
    );
  }

  Widget _pie() {
    final est = estimarInforme(widget.tareas, _o);
    final errores = _o.errores;
    final sinTareas = est.tareas == 0;
    final puedeGenerar = errores.isEmpty && !sinTareas;
    final String resumen;
    if (errores.isNotEmpty) {
      resumen = errores.first;
    } else if (sinTareas) {
      resumen = 'Ninguna tarea cumple los filtros elegidos.';
    } else {
      final fotos = _o.seccion('detalle') && _o.incluirFotos
          ? ' · ~${est.fotos} fotos'
          : ' · sin fotos';
      resumen =
          'Incluye ${est.tareas} ${est.tareas == 1 ? 'tarea' : 'tareas'}$fotos · ${est.textoTamano} · ${est.textoTiempo}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              resumen,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: puedeGenerar ? AppTheme.text : const Color(0xFFB42318),
              ),
            ),
          ),
          if (puedeGenerar && est.fotosOmitidasPorLimite > 0) ...[
            const SizedBox(height: 2),
            Text(
              'Supera el límite de ${est.limiteFotos} fotos: se repartirán de forma pareja entre las actividades.',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: puedeGenerar ? _generar : null,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Generar PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Informe detallado',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Elige qué incluir y cómo se ve antes de generar el PDF.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _plantillas(),
              _secciones(),
              _organizacion(),
              _filtros(),
              _campos(),
              _fotos(),
              _textos(),
            ],
          ),
        ),
        const Divider(height: 1),
        _pie(),
      ],
    );
  }
}
