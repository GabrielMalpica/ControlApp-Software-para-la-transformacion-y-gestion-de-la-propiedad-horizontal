import 'package:flutter/material.dart';

import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/duration_format.dart';

/// Un operario que se puede elegir para una tarea.
class OperarioElegible {
  final String id;
  final String nombre;

  /// Texto corto bajo el nombre ("8 h programadas esa semana").
  final String? detalle;

  /// Tiene otra tarea que se cruza en ese horario.
  final bool conCruce;

  const OperarioElegible({
    required this.id,
    required this.nombre,
    this.detalle,
    this.conCruce = false,
  });

  /// Desde la respuesta de `/operarios/sugerir` ({id, nombre, horasSemana,
  /// solapa}). `horasSemana` viene en minutos.
  factory OperarioElegible.desdeSugerencia(Map<String, dynamic> item) {
    final minutos = num.tryParse((item['horasSemana'] ?? '').toString());
    final conCruce = item['solapa'] == true;
    return OperarioElegible(
      id: (item['id'] ?? '').toString(),
      nombre: (item['nombre'] ?? item['id'] ?? 'Operario').toString(),
      conCruce: conCruce,
      detalle: conCruce
          ? 'Tiene cruce en ese horario'
          : minutos == null
          ? null
          : '${formatHoursMinutes(minutos.round())} programadas esa semana',
    );
  }
}

/// Hoja para elegir UNO O VARIOS operarios de una tarea. Arranca con los
/// operarios actuales marcados: para pasar de "A y B" a "A y C" basta con
/// desmarcar a B y marcar a C. Devuelve la lista final de ids (en el orden en
/// que quedaron marcados) o null si se cancela o no hubo cambios.
Future<List<String>?> seleccionarOperarios(
  BuildContext context, {
  required List<OperarioElegible> candidatos,
  required List<String> actualesIds,
  List<String> actualesNombres = const [],
  String titulo = 'Operarios de la tarea',
  String? descripcion,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SeleccionarOperariosSheet(
      candidatos: candidatos,
      actualesIds: actualesIds,
      actualesNombres: actualesNombres,
      titulo: titulo,
      descripcion: descripcion,
    ),
  );
}

class SeleccionarOperariosSheet extends StatefulWidget {
  final List<OperarioElegible> candidatos;
  final List<String> actualesIds;

  /// Nombres de los actuales, en el mismo orden que [actualesIds]: se usan
  /// si alguno no viene entre los candidatos (p.ej. ya no tiene horas).
  final List<String> actualesNombres;
  final String titulo;
  final String? descripcion;

  const SeleccionarOperariosSheet({
    super.key,
    required this.candidatos,
    required this.actualesIds,
    this.actualesNombres = const [],
    this.titulo = 'Operarios de la tarea',
    this.descripcion,
  });

  @override
  State<SeleccionarOperariosSheet> createState() =>
      _SeleccionarOperariosSheetState();
}

class _SeleccionarOperariosSheetState extends State<SeleccionarOperariosSheet> {
  late final List<OperarioElegible> _opciones;
  late final Set<String> _actuales;
  late final List<String> _seleccion;

  @override
  void initState() {
    super.initState();
    _actuales = widget.actualesIds.where((id) => id.isNotEmpty).toSet();
    _seleccion = _actuales.toList();

    final porId = <String, OperarioElegible>{
      for (final c in widget.candidatos)
        if (c.id.isNotEmpty) c.id: c,
    };
    // Los actuales siempre aparecen (arriba), aunque no vengan sugeridos.
    final actuales = <OperarioElegible>[];
    for (var i = 0; i < widget.actualesIds.length; i++) {
      final id = widget.actualesIds[i];
      if (id.isEmpty) continue;
      final nombre = i < widget.actualesNombres.length
          ? widget.actualesNombres[i]
          : id;
      actuales.add(
        porId.remove(id) ?? OperarioElegible(id: id, nombre: nombre),
      );
    }
    _opciones = [...actuales, ...porId.values];
  }

  bool get _sinCambios =>
      _seleccion.length == _actuales.length &&
      _seleccion.every(_actuales.contains);

  void _alternar(String id, bool marcar) {
    setState(() {
      if (marcar) {
        if (!_seleccion.contains(id)) _seleccion.add(id);
      } else {
        _seleccion.remove(id);
      }
    });
  }

  String _nombre(String id) =>
      _opciones.firstWhere((o) => o.id == id).nombre.trim();

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.85;
    final quedan = _seleccion.map(_nombre).join(', ');
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: alto),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                widget.titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.descripcion ??
                    'Marca a todas las personas que harán la tarea. Puedes '
                        'dejar a uno y cambiar al otro.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _opciones.length,
                itemBuilder: (_, i) {
                  final op = _opciones[i];
                  final marcado = _seleccion.contains(op.id);
                  final esActual = _actuales.contains(op.id);
                  final detalle = [
                    if (esActual) 'Operario actual',
                    if (op.detalle != null) op.detalle!,
                  ].join(' · ');
                  return CheckboxListTile(
                    value: marcado,
                    onChanged: (v) => _alternar(op.id, v == true),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(op.nombre),
                    subtitle: detalle.isEmpty ? null : Text(detalle),
                    secondary: op.conCruce
                        ? Tooltip(
                            message: 'Tiene otra tarea que se cruza',
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange.shade700,
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _seleccion.isEmpty
                        ? 'Marca al menos un operario.'
                        : 'Quedan: $quedan',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _seleccion.isEmpty
                          ? Colors.red.shade700
                          : Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                        ),
                        onPressed: _seleccion.isEmpty || _sinCambios
                            ? null
                            : () => Navigator.of(
                                context,
                              ).pop(List<String>.from(_seleccion)),
                        icon: const Icon(Icons.check),
                        label: Text(
                          _seleccion.length > 1
                              ? 'Asignar a ${_seleccion.length}'
                              : 'Asignar',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
