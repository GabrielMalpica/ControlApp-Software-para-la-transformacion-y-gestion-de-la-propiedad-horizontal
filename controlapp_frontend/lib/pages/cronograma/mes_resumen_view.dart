import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pages/cronograma/secciones_actividades.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';

/// Resumen del mes: por día, cuántas actividades hay, cuántas se cerraron y
/// si hubo novedades. Tocar un día abre ese día en "Hoy".
class MesResumenView extends StatelessWidget {
  final int anio;
  final int mes;
  final List<TareaModel> tareas;
  final DateTime ahora;
  final String? Function(DateTime) festivo;
  final ValueChanged<DateTime> onDia;

  const MesResumenView({
    super.key,
    required this.anio,
    required this.mes,
    required this.tareas,
    required this.ahora,
    required this.festivo,
    required this.onDia,
  });

  @override
  Widget build(BuildContext context) {
    final primero = DateTime(anio, mes, 1);
    final ultimo = DateTime(anio, mes + 1, 0);
    final inicio = inicioSemana(primero);
    final semanas = ((ultimo.difference(inicio).inDays + 1) / 7).ceil();

    final porDia = <int, List<TareaModel>>{};
    for (final t in tareas) {
      final d = t.fechaInicio.toLocal();
      if (d.year == anio && d.month == mes) {
        porDia.putIfAbsent(d.day, () => []).add(t);
      }
    }

    return LayoutBuilder(
      builder: (context, c) {
        final angosto = c.maxWidth < 640;
        const nombres = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Toca un día para ver sus actividades.',
              style: TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            ExcludeSemantics(
              child: Row(
                children: [
                  for (final n in nombres)
                    Expanded(
                      child: Center(
                        child: Text(
                          n,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            for (var s = 0; s < semanas; s++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 7; i++) ...[
                        if (i > 0) SizedBox(width: angosto ? 4 : 6),
                        Expanded(
                          child: _celda(
                            inicio.add(Duration(days: s * 7 + i)),
                            porDia,
                            angosto,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _leyenda(
                  const SizedBox(
                    width: 24,
                    child: BarraAvance(fraccion: 0.6, alto: 6),
                  ),
                  'Parte cerrada del día',
                ),
                _leyenda(
                  Icon(
                    Icons.warning_rounded,
                    size: 18,
                    color: EstadoVisual.noSeHizo.color,
                  ),
                  'Con novedad (no se hizo, sin cerrar, atrasada o devuelta)',
                ),
                _leyenda(
                  const Icon(
                    Icons.celebration_outlined,
                    size: 18,
                    color: Color(0xFF991B1B),
                  ),
                  'Festivo',
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _leyenda(Widget icono, String texto) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      icono,
      const SizedBox(width: 6),
      Flexible(child: Text(texto, style: const TextStyle(fontSize: 13.5))),
    ],
  );

  Widget _celda(DateTime d, Map<int, List<TareaModel>> porDia, bool angosto) {
    final delMes = d.month == mes;
    final items = delMes
        ? (porDia[d.day] ?? const <TareaModel>[])
        : const <TareaModel>[];
    final unicas = unicasPorId(items);
    final pasado = !soloFecha(d).isAfter(soloFecha(ahora));
    final cerradas = unicas
        .where((t) => EstadoVisual.de(t, ahora: ahora).cerrada)
        .length;
    final novedad = unicas
        .where(
          (t) => EstadoVisual.de(t, ahora: ahora).grupo == GrupoEstado.novedad,
        )
        .length;
    final hoy = mismoDia(d, ahora);
    final fest = delMes ? festivo(d) : null;

    final etiqueta = [
      DateFormat("EEEE d 'de' MMMM", 'es').format(d),
      if (hoy) 'hoy',
      cantidadActividades(unicas.length),
      if (pasado && unicas.isNotEmpty)
        cerradas == 1 ? '1 cerrada' : '$cerradas cerradas',
      if (novedad > 0) '$novedad con novedad',
      if (fest != null) 'festivo: $fest',
    ].join(', ');

    return Opacity(
      opacity: delMes ? 1 : 0.4,
      child: Semantics(
        button: delMes,
        label: etiqueta,
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(angosto ? 10 : 14),
            side: BorderSide(
              color: hoy
                  ? AppTheme.primary
                  : AppTheme.primary.withValues(alpha: 0.14),
              width: hoy ? 3 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(angosto ? 10 : 14),
            onTap: delMes ? () => onDia(d) : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: angosto ? 70 : 100),
              child: Padding(
                padding: EdgeInsets.all(angosto ? 5 : 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: angosto ? 15 : 18,
                              fontWeight: FontWeight.w800,
                              // En celular el festivo se marca con el número en rojo.
                              color: fest != null
                                  ? const Color(0xFF991B1B)
                                  : null,
                            ),
                          ),
                        ),
                        if (fest != null && !angosto) ...[
                          const Spacer(),
                          const Icon(
                            Icons.celebration_outlined,
                            size: 16,
                            color: Color(0xFF991B1B),
                          ),
                        ],
                      ],
                    ),
                    if (fest != null && !angosto)
                      Text(
                        fest,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    const SizedBox(height: 4),
                    if (delMes)
                      Text(
                        unicas.isEmpty
                            ? (angosto ? '—' : 'Sin actividades')
                            : (angosto
                                  ? '${unicas.length}'
                                  : cantidadActividades(unicas.length)),
                        style: TextStyle(
                          fontSize: angosto ? 13 : 14,
                          color: unicas.isEmpty
                              ? AppTheme.textMuted
                              : AppTheme.text,
                        ),
                      ),
                    if (delMes && pasado && unicas.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      BarraAvance(fraccion: cerradas / unicas.length, alto: 6),
                    ],
                    if (novedad > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_rounded,
                            size: 16,
                            color: EstadoVisual.noSeHizo.color,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              angosto ? '$novedad' : '$novedad con novedad',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: EstadoVisual.noSeHizo.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
