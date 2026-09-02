import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/cronograma_informe_jerarquico_model.dart';
import 'package:flutter_application_1/utils/duration_format.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

class CronogramaInformeJerarquico extends StatelessWidget {
  final CronogramaInformeJerarquicoModel? informe;
  final bool loading;
  final String? operarioId;
  final ValueChanged<String?> onOperarioChanged;
  final bool filtrarSemana;
  final ValueChanged<bool> onFiltrarSemanaChanged;
  final Widget? encabezado;
  final Widget? piePagina;

  const CronogramaInformeJerarquico({
    super.key,
    required this.informe,
    required this.loading,
    required this.operarioId,
    required this.onOperarioChanged,
    required this.filtrarSemana,
    required this.onFiltrarSemanaChanged,
    this.encabezado,
    this.piePagina,
  });

  Color _estadoColor(CronogramaInformeResumen resumen) {
    if (resumen.esperadas > 0 &&
        resumen.completas == resumen.esperadas &&
        resumen.parciales == 0) {
      return Colors.green.shade700;
    }
    if (resumen.conProgramacion > 0) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  String _estadoLabel(CronogramaInformeResumen resumen) {
    if (resumen.esperadas > 0 &&
        resumen.completas == resumen.esperadas &&
        resumen.parciales == 0) {
      return 'Completa';
    }
    if (resumen.conProgramacion > 0) return 'Parcial';
    return 'Sin programar';
  }

  IconData _estadoIcon(CronogramaInformeResumen resumen) {
    if (_estadoLabel(resumen) == 'Completa') {
      return Icons.check_circle_outline;
    }
    if (_estadoLabel(resumen) == 'Parcial') return Icons.timelapse;
    return Icons.error_outline;
  }

  Widget _estadoBadge(CronogramaInformeResumen resumen) {
    final color = _estadoColor(resumen);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        _estadoLabel(resumen),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _resumen(CronogramaInformeResumen resumen) {
    Widget item({
      required IconData icon,
      required String label,
      required String value,
      required Color color,
    }) {
      return Container(
        constraints: const BoxConstraints(minWidth: 145),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        item(
          icon: Icons.task_alt,
          label: 'Ocurrencias programadas',
          value: '${resumen.conProgramacion}/${resumen.esperadas}',
          color: Colors.blue.shade700,
        ),
        item(
          icon: Icons.check_circle_outline,
          label: 'Completas',
          value: '${resumen.completas}',
          color: Colors.green.shade700,
        ),
        item(
          icon: Icons.timelapse,
          label: 'Parciales',
          value: '${resumen.parciales}',
          color: Colors.orange.shade800,
        ),
        item(
          icon: Icons.warning_amber_rounded,
          label: 'Sin programar',
          value: '${resumen.sinProgramar}',
          color: Colors.red.shade700,
        ),
        item(
          icon: Icons.schedule,
          label: 'Tiempo programado / esperado',
          value:
              '${formatHoursMinutes(resumen.minutosProgramados)} / ${formatHoursMinutes(resumen.minutosEsperados)}',
          color: Colors.indigo.shade700,
        ),
      ],
    );
  }

  Widget _controlesFiltros(CronogramaInformeJerarquicoModel data) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: DropdownButtonFormField<String>(
            initialValue: operarioId ?? '__TODOS__',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Operario del informe',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: '__TODOS__',
                child: Text('Todos los operarios'),
              ),
              ...data.operarios.map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.nombre, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) =>
                onOperarioChanged(value == '__TODOS__' ? null : value),
          ),
        ),
        FilterChip(
          selected: filtrarSemana,
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(
            filtrarSemana ? 'Solo semana seleccionada' : 'Todo el mes',
          ),
          onSelected: onFiltrarSemanaChanged,
        ),
      ],
    );
  }

  List<String> _etiquetasSemanas(CronogramaInformeJerarquicoModel data) {
    final primerDia = DateTime(data.anio, data.mes, 1);
    final ultimoDia = DateTime(data.anio, data.mes + 1, 0);
    final offset = primerDia.weekday - DateTime.monday;

    return List.generate(5, (index) {
      final inicioDia = index == 0 ? 1 : (index * 7) - offset + 1;
      final finDia = ((index + 1) * 7) - offset;
      final inicio = DateTime(
        data.anio,
        data.mes,
        inicioDia.clamp(1, ultimoDia.day),
      );
      final fin = DateTime(data.anio, data.mes, finDia.clamp(1, ultimoDia.day));
      return 'Semana ${index + 1}\n${DateFormat('d MMM', 'es').format(inicio)} - ${DateFormat('d MMM', 'es').format(fin)}';
    });
  }

  int? _indiceSemana(DateTime fecha, CronogramaInformeJerarquicoModel data) {
    final local = fecha.toLocal();
    if (local.year != data.anio || local.month != data.mes) return null;
    final primerDia = DateTime(data.anio, data.mes, 1);
    final offset = primerDia.weekday - DateTime.monday;
    return ((local.day + offset - 1) ~/ 7).clamp(0, 4);
  }

  void _sumarOcurrenciaPorSemana(
    List<int> semanas,
    CronogramaInformeOcurrencia ocurrencia,
    CronogramaInformeJerarquicoModel data,
  ) {
    if (ocurrencia.bloques.isNotEmpty) {
      for (final bloque in ocurrencia.bloques) {
        final indice = _indiceSemana(bloque.fechaInicio, data);
        if (indice != null) semanas[indice] += bloque.duracionMinutos;
      }
      return;
    }
    if (ocurrencia.minutosProgramados <= 0) return;
    final indice = _indiceSemana(
      ocurrencia.fechaRealInicio ?? ocurrencia.fechaObjetivo,
      data,
    );
    if (indice != null) semanas[indice] += ocurrencia.minutosProgramados;
  }

  List<_FilaActividad> _filasActividad(CronogramaInformeJerarquicoModel data) {
    final filas = <_FilaActividad>[];
    for (final ubicacion in data.ubicaciones) {
      for (final definicion in ubicacion.definiciones) {
        final semanas = List<int>.filled(5, 0);
        for (final ocurrencia in definicion.ocurrencias) {
          _sumarOcurrenciaPorSemana(semanas, ocurrencia, data);
        }
        filas.add(
          _FilaActividad(
            actividad: definicion.descripcion,
            ubicacion: ubicacion.nombre,
            resumen: definicion.resumen,
            minutosSemanas: semanas,
          ),
        );
      }
    }
    filas.sort((a, b) {
      final porEstado = a.resumen.sinProgramar.compareTo(
        b.resumen.sinProgramar,
      );
      if (porEstado != 0) return -porEstado;
      return a.actividad.toLowerCase().compareTo(b.actividad.toLowerCase());
    });
    return filas;
  }

  List<_FilaHoras> _filasPorUbicacion(CronogramaInformeJerarquicoModel data) {
    final filas = <_FilaHoras>[];
    for (final ubicacion in data.ubicaciones) {
      final semanas = List<int>.filled(5, 0);
      for (final definicion in ubicacion.definiciones) {
        for (final ocurrencia in definicion.ocurrencias) {
          _sumarOcurrenciaPorSemana(semanas, ocurrencia, data);
        }
      }
      filas.add(
        _FilaHoras(
          nombre: ubicacion.nombre,
          minutosEsperados: ubicacion.resumen.minutosEsperados,
          minutosProgramados: ubicacion.resumen.minutosProgramados,
          minutosSemanas: semanas,
        ),
      );
    }
    filas.sort(_ordenarFilasHoras);
    return filas;
  }

  List<_FilaHoras> _filasPorOperario(CronogramaInformeJerarquicoModel data) {
    final acumulado = <String, _AcumuladoHoras>{};

    void agregar(
      CronogramaInformeOperario operario,
      int minutos,
      DateTime fecha,
    ) {
      final key = operario.id.isEmpty ? operario.nombre : operario.id;
      final item = acumulado.putIfAbsent(
        key,
        () => _AcumuladoHoras(operario.nombre),
      );
      item.programados += minutos;
      final indice = _indiceSemana(fecha, data);
      if (indice != null) item.semanas[indice] += minutos;
    }

    for (final ubicacion in data.ubicaciones) {
      for (final definicion in ubicacion.definiciones) {
        for (final ocurrencia in definicion.ocurrencias) {
          for (final operario in ocurrencia.operariosEsperados) {
            final key = operario.id.isEmpty ? operario.nombre : operario.id;
            final item = acumulado.putIfAbsent(
              key,
              () => _AcumuladoHoras(operario.nombre),
            );
            item.esperados += ocurrencia.duracionEsperadaMin;
          }
          if (ocurrencia.bloques.isNotEmpty) {
            for (final bloque in ocurrencia.bloques) {
              final unicos = <String>{};
              for (final operario in bloque.operarios) {
                final key = operario.id.isEmpty ? operario.nombre : operario.id;
                if (unicos.add(key)) {
                  agregar(operario, bloque.duracionMinutos, bloque.fechaInicio);
                }
              }
            }
          } else if (ocurrencia.minutosProgramados > 0 &&
              ocurrencia.operariosEsperados.isNotEmpty) {
            final fecha =
                ocurrencia.fechaRealInicio ?? ocurrencia.fechaObjetivo;
            for (final operario in ocurrencia.operariosEsperados) {
              agregar(operario, ocurrencia.minutosProgramados, fecha);
            }
          }
        }
      }
    }

    final filas = acumulado.values
        .map(
          (item) => _FilaHoras(
            nombre: item.nombre,
            minutosEsperados: item.esperados,
            minutosProgramados: item.programados,
            minutosSemanas: item.semanas,
          ),
        )
        .toList();
    filas.sort(_ordenarFilasHoras);
    return filas;
  }

  int _ordenarFilasHoras(_FilaHoras a, _FilaHoras b) {
    final porHoras = b.minutosProgramados.compareTo(a.minutosProgramados);
    if (porHoras != 0) return porHoras;
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  }

  String _horas(int minutos) => (minutos / 60).toStringAsFixed(1);

  Widget _encabezadoSeccion({
    required IconData icon,
    required String titulo,
    required String descripcion,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: Colors.indigo.shade700, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenedorSeccion({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: .2),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }

  Widget _tablaActividades(CronogramaInformeJerarquicoModel data) {
    final filas = _filasActividad(data);
    final semanas = _etiquetasSemanas(data);

    return _contenedorSeccion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _encabezadoSeccion(
            icon: Icons.table_chart_outlined,
            titulo: 'Informe de actividades',
            descripcion:
                'Incluye todas las tareas esperadas, incluso las que tienen 0 horas programadas.',
          ),
          const Divider(height: 1),
          if (filas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No hay tareas para los filtros seleccionados.'),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  Colors.blueGrey.shade50,
                ),
                headingTextStyle: TextStyle(
                  color: Colors.blueGrey.shade900,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                dataTextStyle: const TextStyle(fontSize: 12),
                horizontalMargin: 16,
                columnSpacing: 24,
                dataRowMinHeight: 54,
                dataRowMaxHeight: 68,
                border: TableBorder(
                  horizontalInside: BorderSide(color: Colors.grey.shade200),
                ),
                columns: [
                  const DataColumn(label: Text('Actividad')),
                  const DataColumn(label: Text('Ubicación')),
                  const DataColumn(label: Text('Programadas')),
                  const DataColumn(label: Text('Estado')),
                  const DataColumn(label: Text('Horas tarea'), numeric: true),
                  DataColumn(
                    label: Text(
                      filtrarSemana ? 'Programadas semana' : 'Programadas mes',
                    ),
                    numeric: true,
                  ),
                  ...semanas.map(
                    (label) => DataColumn(label: Text(label), numeric: true),
                  ),
                ],
                rows: filas.indexed.map((entry) {
                  final index = entry.$1;
                  final fila = entry.$2;
                  final esCero = fila.resumen.minutosProgramados == 0;
                  return DataRow(
                    color: WidgetStatePropertyAll(
                      esCero
                          ? Colors.red.withValues(alpha: .035)
                          : index.isEven
                          ? Colors.white
                          : Colors.blueGrey.withValues(alpha: .025),
                    ),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 300,
                          child: Text(
                            fila.actividad,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            fila.ubicacion,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${fila.resumen.conProgramacion}/${fila.resumen.esperadas}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      DataCell(_estadoBadge(fila.resumen)),
                      DataCell(
                        Text(
                          _horas(fila.resumen.minutosEsperados),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      DataCell(
                        Text(
                          _horas(fila.resumen.minutosProgramados),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: esCero ? Colors.red.shade700 : null,
                          ),
                        ),
                      ),
                      ...fila.minutosSemanas.map(
                        (minutos) => DataCell(Text(_horas(minutos))),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tablaHoras({
    required CronogramaInformeJerarquicoModel data,
    required String titulo,
    required String descripcion,
    required String columnaPrincipal,
    required IconData icon,
    required List<_FilaHoras> filas,
    required String emptyLabel,
  }) {
    final semanas = _etiquetasSemanas(data);
    return _contenedorSeccion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _encabezadoSeccion(
            icon: icon,
            titulo: titulo,
            descripcion: descripcion,
          ),
          const Divider(height: 1),
          if (filas.isEmpty)
            Padding(padding: const EdgeInsets.all(20), child: Text(emptyLabel))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  Colors.blueGrey.shade50,
                ),
                headingTextStyle: TextStyle(
                  color: Colors.blueGrey.shade900,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                dataTextStyle: const TextStyle(fontSize: 12),
                horizontalMargin: 16,
                columnSpacing: 28,
                border: TableBorder(
                  horizontalInside: BorderSide(color: Colors.grey.shade200),
                ),
                columns: [
                  DataColumn(label: Text(columnaPrincipal)),
                  const DataColumn(
                    label: Text('Horas requeridas'),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(
                      filtrarSemana ? 'Programadas semana' : 'Programadas mes',
                    ),
                    numeric: true,
                  ),
                  ...semanas.map(
                    (label) => DataColumn(label: Text(label), numeric: true),
                  ),
                ],
                rows: filas.indexed.map((entry) {
                  final index = entry.$1;
                  final fila = entry.$2;
                  return DataRow(
                    color: WidgetStatePropertyAll(
                      index.isEven
                          ? Colors.white
                          : Colors.blueGrey.withValues(alpha: .025),
                    ),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 260,
                          child: Text(
                            fila.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          _horas(fila.minutosEsperados),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      DataCell(
                        Text(
                          _horas(fila.minutosProgramados),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      ...fila.minutosSemanas.map(
                        (minutos) => DataCell(Text(_horas(minutos))),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _arbolUbicaciones(CronogramaInformeJerarquicoModel data) {
    return _contenedorSeccion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _encabezadoSeccion(
            icon: Icons.account_tree_outlined,
            titulo: 'Tareas por ubicación',
            descripcion:
                'Expande una ubicación para revisar sus tareas y su cumplimiento.',
          ),
          const Divider(height: 1),
          if (data.ubicaciones.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No hay ubicaciones para mostrar.')),
            )
          else
            ...data.ubicaciones.map(
              (ubicacion) => ExpansionTile(
                key: PageStorageKey('ubicacion-${ubicacion.id}'),
                initiallyExpanded: data.ubicaciones.length == 1,
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.withValues(alpha: .09),
                  foregroundColor: Colors.indigo.shade700,
                  child: const Icon(Icons.place_outlined, size: 20),
                ),
                title: Text(
                  ubicacion.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${ubicacion.definiciones.length} tarea(s) | '
                  'Programadas ${ubicacion.resumen.conProgramacion}/${ubicacion.resumen.esperadas}',
                ),
                children: ubicacion.definiciones.map((definicion) {
                  final resumen = definicion.resumen;
                  final motivo = definicion.ocurrencias
                      .where((item) => item.minutosProgramados == 0)
                      .map((item) => item.motivoMensaje ?? item.motivoCodigo)
                      .whereType<String>()
                      .map((item) => item.trim())
                      .where((item) => item.isNotEmpty)
                      .firstOrNull;
                  final detalle = <String>[
                    'Programadas ${resumen.conProgramacion}/${resumen.esperadas}',
                    '${formatHoursMinutes(resumen.minutosProgramados)} de ${formatHoursMinutes(resumen.minutosEsperados)}',
                    'Prioridad ${definicion.prioridad}',
                    if ((definicion.frecuencia ?? '').isNotEmpty)
                      definicion.frecuencia!,
                    if ((definicion.elementoNombre ?? '').isNotEmpty)
                      definicion.elementoNombre!,
                  ].join(' | ');

                  return Container(
                    margin: const EdgeInsets.fromLTRB(20, 3, 12, 7),
                    decoration: BoxDecoration(
                      color: _estadoColor(resumen).withValues(alpha: .035),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: Icon(
                        _estadoIcon(resumen),
                        color: _estadoColor(resumen),
                      ),
                      title: Text(
                        definicion.descripcion,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        motivo == null ? detalle : '$detalle\n$motivo',
                      ),
                      trailing: _estadoBadge(resumen),
                      isThreeLine: motivo != null,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = informe;
    if (loading && data == null) {
      return const SkeletonTable(rows: 6, cols: 4);
    }
    if (data == null) {
      return const Center(child: Text('No se pudo cargar el informe.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (encabezado != null) encabezado!,
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _controlesFiltros(data),
              const SizedBox(height: 14),
              _resumen(data.resumen),
              if (!data.trazabilidadDisponible)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Este periodo es anterior al registro de ocurrencias. Las tareas existentes se muestran, pero no es posible reconstruir las que quedaron en cero.',
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                ),
            ],
          ),
        ),
        _tablaActividades(data),
        _tablaHoras(
          data: data,
          titulo: 'Horas por ubicación',
          descripcion: 'Distribución de las horas programadas por ubicación.',
          columnaPrincipal: 'Ubicación',
          icon: Icons.place_outlined,
          filas: _filasPorUbicacion(data),
          emptyLabel: 'Sin ubicaciones para los filtros seleccionados.',
        ),
        _tablaHoras(
          data: data,
          titulo: 'Horas por trabajador',
          descripcion: 'Distribución de las horas programadas por operario.',
          columnaPrincipal: 'Trabajador',
          icon: Icons.people_outline,
          filas: _filasPorOperario(data),
          emptyLabel: 'Sin trabajadores para los filtros seleccionados.',
        ),
        _arbolUbicaciones(data),
        if (piePagina != null) piePagina!,
        const SizedBox(height: 16),
      ],
    );
  }
}

class _FilaActividad {
  final String actividad;
  final String ubicacion;
  final CronogramaInformeResumen resumen;
  final List<int> minutosSemanas;

  const _FilaActividad({
    required this.actividad,
    required this.ubicacion,
    required this.resumen,
    required this.minutosSemanas,
  });
}

class _FilaHoras {
  final String nombre;
  final int minutosEsperados;
  final int minutosProgramados;
  final List<int> minutosSemanas;

  const _FilaHoras({
    required this.nombre,
    required this.minutosEsperados,
    required this.minutosProgramados,
    required this.minutosSemanas,
  });
}

class _AcumuladoHoras {
  final String nombre;
  int esperados = 0;
  int programados = 0;
  final List<int> semanas = List<int>.filled(5, 0);

  _AcumuladoHoras(this.nombre);
}
