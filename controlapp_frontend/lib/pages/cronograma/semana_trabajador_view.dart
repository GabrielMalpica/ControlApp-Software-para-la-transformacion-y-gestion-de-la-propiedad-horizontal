import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pages/cronograma/secciones_actividades.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/widgets/cronograma/actividad_card.dart';
import 'package:flutter_application_1/widgets/cronograma/desplazamiento_enlazado.dart';

const _diasCortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

//// Semana leída por persona: filas = trabajadores, columnas = días.
///
/// Es un sliver: va dentro del `CustomScrollView` de la página, así toda la
/// pantalla se desplaza con un solo scroll vertical (sin una tabla con su
/// propio scroll adentro). La fila de días queda fija arriba mientras se
/// recorre la tabla. Si los días no caben, las filas se desplazan juntas
/// hacia los lados (con las flechas o deslizando) y los nombres quedan fijos.
class SemanaTrabajadorSliver extends StatefulWidget {
  final List<DateTime> dias;

  /// Actividades de la semana ya filtradas (incluye el filtro de estado).
  final List<TareaModel> tareas;

  /// Las mismas sin el filtro de estado (para el avance de cada persona).
  final List<TareaModel> base;
  final List<TrabajadorRef> trabajadores;
  final DateTime ahora;
  final int? seleccionadaId;
  final ValueChanged<TareaModel> onAbrir;
  final ValueChanged<String> onElegirTrabajador;
  final String? Function(DateTime dia) festivo;

  const SemanaTrabajadorSliver({
    super.key,
    required this.dias,
    required this.tareas,
    required this.base,
    required this.trabajadores,
    required this.ahora,
    required this.seleccionadaId,
    required this.onAbrir,
    required this.onElegirTrabajador,
    required this.festivo,
  });

  @override
  State<SemanaTrabajadorSliver> createState() => _SemanaTrabajadorSliverState();
}

class _SemanaTrabajadorSliverState extends State<SemanaTrabajadorSliver> {
  static const double _anchoTrabajador = 176;
  static const double _anchoMinDia = 160;

  final _horizontal = DesplazamientoEnlazado();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context).scale(16) / 16;
    final altoDias = (58 * escala).clamp(58.0, 120.0);
    final altoAviso = (48 * escala).clamp(48.0, 90.0);
    final trabajadores = widget.trabajadores
        .where((w) => widget.base.any((t) => tareaEsDe(t, w.id)))
        .toList();

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final disponible = constraints.crossAxisExtent - _anchoTrabajador;
        final anchoDia = (disponible / widget.dias.length) < _anchoMinDia
            ? _anchoMinDia
            : disponible / widget.dias.length;
        final desborda = anchoDia * widget.dias.length > disponible + 1;

        if (trabajadores.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay actividades esta semana con estos filtros.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          );
        }

        return DecoratedSliver(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.14)),
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: EncabezadoFijoDelegate(
                  alto: altoDias + 1 + (desborda ? altoAviso : 0),
                  child: Column(
                    children: [
                      if (desborda)
                        SizedBox(
                          height: altoAviso,
                          child: AvisoDesplazarLados(
                            texto:
                                'La semana sigue hacia los lados. Usa las flechas o desliza la tabla; los nombres quedan fijos.',
                            onIzquierda: () =>
                                _horizontal.desplazar(-anchoDia * 2),
                            onDerecha: () =>
                                _horizontal.desplazar(anchoDia * 2),
                          ),
                        ),
                      SizedBox(
                        height: altoDias,
                        child: _filaEncabezado(anchoDia),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: trabajadores.length,
                itemBuilder: (context, i) =>
                    _filaTrabajador(trabajadores[i], anchoDia, i + 1),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filaEncabezado(double anchoDia) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: _anchoTrabajador,
          color: AppTheme.surfaceSoft,
          alignment: Alignment.center,
          child: const Text(
            'Trabajador',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _horizontal.alDesplazar,
            child: SingleChildScrollView(
              controller: _horizontal.controlador(0),
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final d in widget.dias) _encabezadoDia(d, anchoDia),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _encabezadoDia(DateTime d, double ancho) {
    final hoy = mismoDia(d, widget.ahora);
    final festivo = widget.festivo(d);
    final fondo = hoy
        ? AppTheme.primary
        : (festivo != null ? const Color(0xFFFDE8E8) : AppTheme.surfaceSoft);
    final fg = hoy
        ? Colors.white
        : (festivo != null ? const Color(0xFF7F1D1D) : AppTheme.text);
    return Semantics(
      header: true,
      label:
          '${DateFormat("EEEE d 'de' MMMM", 'es').format(d)}${hoy ? ', hoy' : ''}${festivo != null ? ', festivo $festivo' : ''}',
      excludeSemantics: true,
      child: Container(
        width: ancho,
        decoration: BoxDecoration(
          color: fondo,
          border: Border(
            left: BorderSide(color: AppTheme.primary.withValues(alpha: 0.10)),
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_diasCortos[d.weekday - 1]} ${d.day}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: fg,
              ),
            ),
            Text(
              hoy
                  ? 'Hoy'
                  : (festivo != null
                        ? 'Festivo'
                        : DateFormat('MMM', 'es').format(d)),
              style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaTrabajador(TrabajadorRef w, double anchoDia, int indice) {
    final suyasBase = widget.base.where((t) => tareaEsDe(t, w.id)).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.10)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _anchoTrabajador,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFFAFCFA),
            child: EncabezadoTrabajador(
              trabajador: w,
              suyas: suyasBase,
              ahora: widget.ahora,
              onTap: () => widget.onElegirTrabajador(w.id),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _horizontal.alDesplazar,
              child: SingleChildScrollView(
                controller: _horizontal.controlador(indice),
                scrollDirection: Axis.horizontal,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final d in widget.dias) _celda(w, d, anchoDia),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _celda(TrabajadorRef w, DateTime d, double ancho) {
    final items = widget.tareas
        .where((t) => tareaEsDe(t, w.id) && mismoDia(t.fechaInicio, d))
        .toList();
    final hoy = mismoDia(d, widget.ahora);
    final festivo = widget.festivo(d);
    return Container(
      width: ancho,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: hoy ? const Color(0xFFF5FAF6) : null,
        border: Border(
          left: BorderSide(color: AppTheme.primary.withValues(alpha: 0.10)),
        ),
      ),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                festivo != null ? 'Festivo' : 'Sin actividades',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 13.5,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final franja in agruparSimultaneas(items)) ...[
                  if (franja.simultaneas)
                    GrupoSimultaneas(
                      franja: franja,
                      compacto: true,
                      construir: (t) => _tarjeta(t, w),
                    )
                  else
                    _tarjeta(franja.tareas.first, w),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }

  Widget _tarjeta(TareaModel t, TrabajadorRef w) => ActividadCard(
    tarea: t,
    densidad: DensidadTarjeta.compacta,
    ahora: widget.ahora,
    seleccionada: t.id == widget.seleccionadaId,
    trabajadorFilaId: w.id,
    onTap: () => widget.onAbrir(t),
  );
}

// Semana en celular: franja de días y, debajo, el día elegido agrupado por
/// trabajador.
class SemanaMovilView extends StatelessWidget {
  final List<DateTime> dias;
  final DateTime diaSeleccionado;
  final ValueChanged<DateTime> onDia;
  final List<TareaModel> tareas;
  final List<TareaModel> base;
  final DateTime ahora;
  final int? seleccionadaId;
  final ValueChanged<TareaModel> onAbrir;
  final Widget cabecera;
  final VoidCallback? onQuitarFiltros;

  /// Selector de trabajador, junto al día (el día se agrupa por trabajador).
  final Widget? selectorTrabajador;

  const SemanaMovilView({
    super.key,
    required this.dias,
    required this.diaSeleccionado,
    required this.onDia,
    required this.tareas,
    required this.base,
    required this.ahora,
    required this.seleccionadaId,
    required this.onAbrir,
    required this.cabecera,
    this.onQuitarFiltros,
    this.selectorTrabajador,
  });

  @override
  Widget build(BuildContext context) {
    final delDia = tareas
        .where((t) => mismoDia(t.fechaInicio, diaSeleccionado))
        .toList();
    final baseDia = base
        .where((t) => mismoDia(t.fechaInicio, diaSeleccionado))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        cabecera,
        const SizedBox(height: 14),
        FranjaDias(
          dias: dias,
          seleccionado: diaSeleccionado,
          ahora: ahora,
          conteo: (d) => tareas.where((t) => mismoDia(t.fechaInicio, d)).length,
          onDia: onDia,
        ),
        const SizedBox(height: 14),
        Text(
          _capitalizar(
            DateFormat("EEEE d 'de' MMMM", 'es').format(diaSeleccionado),
          ),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (selectorTrabajador != null) ...[
          selectorTrabajador!,
          const SizedBox(height: 12),
        ],
        if (delDia.isEmpty)
          VacioCronograma(
            mensaje: base.isEmpty && onQuitarFiltros == null
                ? 'No hay actividades este día.'
                : 'No hay actividades este día con estos filtros.',
            onQuitarFiltros: onQuitarFiltros,
          )
        else
          ...seccionesPorTrabajador(
            tareas: delDia,
            base: baseDia,
            ahora: ahora,
            seleccionadaId: seleccionadaId,
            onAbrir: onAbrir,
          ),
        const SizedBox(height: 40),
      ],
    );
  }
}

String _capitalizar(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Siete botones grandes con el día y cuántas actividades tiene.
class FranjaDias extends StatelessWidget {
  final List<DateTime> dias;
  final DateTime seleccionado;
  final DateTime ahora;
  final int Function(DateTime) conteo;
  final ValueChanged<DateTime> onDia;

  const FranjaDias({
    super.key,
    required this.dias,
    required this.seleccionado,
    required this.ahora,
    required this.conteo,
    required this.onDia,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < dias.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _boton(dias[i])),
        ],
      ],
    );
  }

  Widget _boton(DateTime d) {
    final sel = mismoDia(d, seleccionado);
    final hoy = mismoDia(d, ahora);
    final n = conteo(d);
    return Semantics(
      button: true,
      selected: sel,
      label:
          '${DateFormat("EEEE d", 'es').format(d)}${hoy ? ', hoy' : ''}, ${cantidadActividades(n)}',
      excludeSemantics: true,
      child: Material(
        color: sel ? AppTheme.primary : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: hoy
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.18),
            width: hoy ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onDia(d),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _diasCortos[d.weekday - 1],
                    style: TextStyle(
                      fontSize: 12.5,
                      color: sel ? Colors.white70 : AppTheme.textMuted,
                    ),
                  ),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: sel ? Colors.white : AppTheme.text,
                    ),
                  ),
                  Text(
                    '$n',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: sel ? Colors.white70 : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
