import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';
import 'package:flutter_application_1/widgets/cronograma/actividad_card.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_ui.dart';

/// Bloques de lista reutilizados por Hoy, la semana en celular y la agenda
/// del operario.

final DateFormat _hm = DateFormat('HH:mm');

/// Tarjetas en una o dos columnas según el ancho disponible.
class RejillaTarjetas extends StatelessWidget {
  final List<Widget> hijos;
  final double anchoMinimo;

  const RejillaTarjetas({
    super.key,
    required this.hijos,
    this.anchoMinimo = 330,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columnas = (c.maxWidth / anchoMinimo).floor().clamp(1, 3);
        if (columnas == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < hijos.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                hijos[i],
              ],
            ],
          );
        }
        final ancho = (c.maxWidth - 10 * (columnas - 1)) / columnas;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final h in hijos) SizedBox(width: ancho, child: h)],
        );
      },
    );
  }
}

/// Encabezado "07:00 · Empiezan 5 actividades en esta hora".
class EncabezadoHora extends StatelessWidget {
  final int hora;
  final int cantidad;

  const EncabezadoHora({super.key, required this.hora, required this.cantidad});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            Text(
              '${hora.toString().padLeft(2, '0')}:00',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              cantidad == 1
                  ? 'Empieza 1 actividad en esta hora'
                  : 'Empiezan $cantidad actividades en esta hora',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Caja punteada azul que agrupa actividades de la misma persona a la vez.
class GrupoSimultaneas extends StatelessWidget {
  final FranjaActividades franja;
  final Widget Function(TareaModel t) construir;
  final bool compacto;

  const GrupoSimultaneas({
    super.key,
    required this.franja,
    required this.construir,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    final etiqueta = compacto
        ? '${franja.tareas.length} al mismo tiempo'
        : '${_hm.format(franja.inicio.toLocal())} – ${_hm.format(franja.fin.toLocal())} · ${franja.tareas.length} actividades al mismo tiempo';
    return Container(
      padding: EdgeInsets.all(compacto ? 6 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8DA6E8), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Row(
              children: [
                const Icon(Icons.layers, size: 18, color: Color(0xFF1E3A8A)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    etiqueta,
                    style: TextStyle(
                      fontSize: compacto ? 12.5 : 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E3A8A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < franja.tareas.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            construir(franja.tareas[i]),
          ],
        ],
      ),
    );
  }
}

/// Encabezado de una persona con su avance ("3 de 5 cerradas").
class EncabezadoTrabajador extends StatelessWidget {
  final TrabajadorRef trabajador;
  final List<TareaModel> suyas;
  final DateTime ahora;
  final VoidCallback? onTap;

  const EncabezadoTrabajador({
    super.key,
    required this.trabajador,
    required this.suyas,
    required this.ahora,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unicas = unicasPorId(suyas);
    final cerradas = unicas
        .where((t) => EstadoVisual.de(t, ahora: ahora).cerrada)
        .length;
    final total = unicas.length;
    final contenido = Row(
      children: [
        TrabajadorAvatar(trabajador: trabajador, tamano: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trabajador.nombre,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                [
                  if (trabajador.cargo.isNotEmpty) trabajador.cargo,
                  '$cerradas de $total cerradas',
                ].join(' · '),
                style: const TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 6),
              BarraAvance(fraccion: total == 0 ? 0 : cerradas / total),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      header: true,
      label:
          '${trabajador.nombre}. Cerradas: $cerradas de ${cantidadActividades(total)}.',
      excludeSemantics: true,
      child: onTap == null
          ? contenido
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: contenido,
            ),
    );
  }
}

class BarraAvance extends StatelessWidget {
  final double fraccion;
  final double alto;
  final Color color;
  final Color fondo;

  const BarraAvance({
    super.key,
    required this.fraccion,
    this.alto = 8,
    this.color = const Color(0xFF15803D),
    this.fondo = const Color(0xFFE3EAE5),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(alto),
      child: LinearProgressIndicator(
        value: fraccion.clamp(0, 1),
        minHeight: alto,
        color: color,
        backgroundColor: fondo,
      ),
    );
  }
}

/// Actividades agrupadas por persona (y, dentro, las simultáneas juntas).
List<Widget> seccionesPorTrabajador({
  required List<TareaModel> tareas,
  required List<TareaModel> base,
  required DateTime ahora,
  required int? seleccionadaId,
  required ValueChanged<TareaModel> onAbrir,
  ValueChanged<String>? onElegirTrabajador,
}) {
  final out = <Widget>[];
  for (final w in trabajadoresDe(tareas)) {
    final suyas = tareas.where((t) => tareaEsDe(t, w.id)).toList();
    if (suyas.isEmpty) continue;
    final suyasBase = base.where((t) => tareaEsDe(t, w.id)).toList();
    out.add(
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EncabezadoTrabajador(
              trabajador: w,
              suyas: suyasBase,
              ahora: ahora,
              onTap: onElegirTrabajador == null
                  ? null
                  : () => onElegirTrabajador(w.id),
            ),
            const SizedBox(height: 12),
            for (final franja in agruparSimultaneas(suyas)) ...[
              if (franja.simultaneas)
                GrupoSimultaneas(
                  franja: franja,
                  construir: (t) => ActividadCard(
                    tarea: t,
                    ahora: ahora,
                    seleccionada: t.id == seleccionadaId,
                    trabajadorFilaId: w.id,
                    onTap: () => onAbrir(t),
                  ),
                )
              else
                ActividadCard(
                  tarea: franja.tareas.first,
                  ahora: ahora,
                  seleccionada: franja.tareas.first.id == seleccionadaId,
                  trabajadorFilaId: w.id,
                  onTap: () => onAbrir(franja.tareas.first),
                ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
    out.add(const SizedBox(height: 14));
  }
  return out;
}

/// Estado vacío con causa y acción.
class VacioCronograma extends StatelessWidget {
  final String mensaje;
  final IconData icono;
  final VoidCallback? onQuitarFiltros;

  const VacioCronograma({
    super.key,
    required this.mensaje,
    this.icono = Icons.event_available,
    this.onQuitarFiltros,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Icon(icono, size: 44, color: AppTheme.primary),
          const SizedBox(height: 10),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (onQuitarFiltros != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onQuitarFiltros,
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Quitar filtros'),
            ),
          ],
        ],
      ),
    );
  }
}
