import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/tarea_labels.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';
import 'package:flutter_application_1/utils/frecuencia_utils.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_ui.dart';
import 'package:flutter_application_1/widgets/evidencia_gallery.dart';

/// Detalle de una actividad en lenguaje sencillo: cuándo, dónde, quién, en
/// qué estado, fotos y acciones permitidas. Sin códigos del sistema.
class DetalleActividad extends StatelessWidget {
  final TareaModel tarea;
  final DateTime? ahora;

  /// Actividades del mismo día (para avisar si la misma persona tiene otra
  /// a la vez).
  final List<TareaModel> delDia;
  final List<Widget> acciones;
  final Widget? historial;
  final VoidCallback? onCerrar;
  final String? avisoPermisos;

  const DetalleActividad({
    super.key,
    required this.tarea,
    this.ahora,
    this.delDia = const [],
    this.acciones = const [],
    this.historial,
    this.onCerrar,
    this.avisoPermisos,
  });

  static final _fechaLarga = DateFormat("EEEE d 'de' MMMM 'de' y", 'es');
  static final _hm = DateFormat('HH:mm');
  static final _hora12 = DateFormat('h:mm a', 'es');

  @override
  Widget build(BuildContext context) {
    final t = tarea;
    final visual = CategoriaVisual.deTarea(t);
    final estado = EstadoVisual.de(t, ahora: ahora);
    final ini = t.fechaInicio.toLocal();
    final fin = t.fechaFin.toLocal();
    final trabajadores = trabajadoresDe([t]);
    final simultaneas = simultaneasDe(t, delDia);
    final esEspecial = visual.esEspecial;
    final evidencias = t.evidencias ?? const <String>[];

    final fechaTxt = _capitalizar(_fechaLarga.format(ini));
    final frecuencia = esEspecial
        ? '${etiquetaCorrectiva()} (no programada)'
        : 'Preventiva · ${etiquetaFrecuencia(t.frecuencia, diaSemana: t.diaSemanaProgramado, fechaReferencia: ini)}';

    final recursos = t.recursosPlan.isNotEmpty
        ? t.recursosPlan.map((r) => r.resumen).join('\n')
        : [
            ...t.maquinariasAsignadas.map((m) => m.nombre),
            ...t.herramientasAsignadas.map(
              (h) => h.cantidad > 1 ? '${h.nombre} × ${h.cantidad}' : h.nombre,
            ),
          ].join('\n');

    final cerradoPor = (t.finalizadaPorNombre ?? '').trim();
    final cierre = t.fechaFinalizarTarea;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x1A0C6B43))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CategoriaChip(visual: visual),
                ),
              ),
              if (onCerrar != null)
                OutlinedButton.icon(
                  onPressed: onCerrar,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            children: [
              Semantics(
                header: true,
                child: Text(
                  t.descripcion,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: AppTheme.text,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  EstadoChip(estado: estado),
                  if (esEspecial) const EspecialBadge(),
                ],
              ),
              if (identical(estado, EstadoVisual.leTocaAhora))
                const _Nota(
                  'Está en su horario. Todavía no han marcado inicio ni cierre.',
                ),
              if (identical(estado, EstadoVisual.atrasada))
                const _Nota(
                  'Su horario ya pasó y nadie la ha cerrado.',
                  color: Color(0xFF991B1B),
                ),
              if (identical(estado, EstadoVisual.sinCerrar))
                const _Nota(
                  'Nadie registró el cierre de esta actividad. No se sabe si se hizo.',
                  color: Color(0xFF991B1B),
                ),
              const SizedBox(height: 18),
              _Fila(
                icono: Icons.schedule,
                titulo: 'Cuándo',
                valor:
                    '$fechaTxt\n${_hm.format(ini)} a ${_hm.format(fin)} (${duracionLegible(fin.difference(ini).inMinutes)})',
              ),
              _Fila(
                icono: Icons.location_on_outlined,
                titulo: 'Dónde',
                valor:
                    [
                          (t.ubicacionNombre ?? '').trim(),
                          (t.elementoNombre ?? '').trim(),
                        ]
                        .where((x) => x.isNotEmpty)
                        .join(' › ')
                        .ifEmpty('Sin lugar registrado'),
              ),
              _Fila(
                icono: Icons.person_outline,
                titulo: trabajadores.length > 1
                    ? 'Quiénes la hacen'
                    : 'Quién la hace',
                contenido: trabajadores.isEmpty
                    ? const Text('Sin asignar')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final p in trabajadores)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  TrabajadorAvatar(trabajador: p, tamano: 36),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.nombre,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (p.cargo.isNotEmpty)
                                          Text(
                                            p.cargo,
                                            style: const TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              _Fila(
                icono: Icons.event_repeat,
                titulo: 'Tipo',
                valor: frecuencia,
              ),
              if ((t.supervisorNombre ?? '').trim().isNotEmpty)
                _Fila(
                  icono: Icons.verified_user_outlined,
                  titulo: 'Supervisor',
                  valor: t.supervisorNombre!.trim(),
                ),
              if (recursos.trim().isNotEmpty)
                _Fila(
                  icono: Icons.handyman_outlined,
                  titulo: 'Maquinaria y herramientas',
                  valor: recursos,
                ),
              if (trabajadores.length > 1)
                _Caja(
                  color: const Color(0xFFFFF4D1),
                  borde: const Color(0xFFE5C25F),
                  icono: Icons.group,
                  iconoColor: const Color(0xFF5A4100),
                  titulo:
                      'Actividad compartida · ${trabajadores.length} personas',
                  texto:
                      'Es una sola actividad. Cuando una persona la cierra, queda cerrada para todas.',
                ),
              if (simultaneas.isNotEmpty)
                _Caja(
                  color: const Color(0xFFE5EDFD),
                  borde: const Color(0xFFA9BDF3),
                  icono: Icons.layers,
                  iconoColor: const Color(0xFF1D4ED8),
                  titulo:
                      'Al mismo tiempo, ${nombresEnLista(trabajadores.map((p) => p.primerNombre))} también tiene:',
                  texto:
                      '${simultaneas.map((o) => '${o.descripcion} (${_hm.format(o.fechaInicio.toLocal())}–${_hm.format(o.fechaFin.toLocal())})').join('\n')}\nSon actividades distintas, no una compartida.',
                ),
              if ((t.observacionesRechazo ?? '').trim().isNotEmpty)
                _Caja(
                  color: const Color(0xFFFDE8E8),
                  borde: const Color(0xFFF5B5B5),
                  icono: Icons.undo,
                  iconoColor: const Color(0xFFB91C1C),
                  titulo: 'Motivo de devolución',
                  texto: t.observacionesRechazo!.trim(),
                ),
              if ((t.observaciones ?? '').trim().isNotEmpty)
                _Caja(
                  color: const Color(0xFFFDF0E1),
                  borde: const Color(0xFFF3C892),
                  icono: Icons.notes,
                  iconoColor: const Color(0xFFB45309),
                  titulo: 'Observación',
                  texto: t.observaciones!.trim(),
                ),
              const SizedBox(height: 14),
              Text(
                evidencias.isEmpty
                    ? 'Fotos del trabajo'
                    : 'Fotos del trabajo (${evidencias.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (evidencias.isEmpty)
                const Text(
                  'Aún no hay fotos de esta actividad.',
                  style: TextStyle(color: AppTheme.textMuted),
                )
              else
                EvidenciaGallery(evidencias: evidencias),
              if (cerradoPor.isNotEmpty || cierre != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.task_alt,
                      size: 20,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          'Cerrada',
                          if (cerradoPor.isNotEmpty) 'por $cerradoPor',
                          if (cierre != null)
                            'el ${DateFormat("d 'de' MMMM", 'es').format(cierre)} a las ${_hora12.format(cierre)}',
                        ].join(' '),
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
              if (historial != null) ...[
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: ExpansionTile(
                      title: const Text(
                        'Historial de cambios',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      children: [historial!],
                    ),
                  ),
                ),
              ],
              if (acciones.isNotEmpty) ...[
                const SizedBox(height: 18),
                for (final a in acciones)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: a),
              ],
              if (avisoPermisos != null) ...[
                const SizedBox(height: 6),
                Text(
                  avisoPermisos!,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _capitalizar(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

extension on String {
  String ifEmpty(String otro) => trim().isEmpty ? otro : this;
}

class _Nota extends StatelessWidget {
  final String texto;
  final Color color;

  const _Nota(this.texto, {this.color = AppTheme.textMuted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(texto, style: TextStyle(color: color, fontSize: 14.5)),
    );
  }
}

class _Fila extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? valor;
  final Widget? contenido;

  const _Fila({
    required this.icono,
    required this.titulo,
    this.valor,
    this.contenido,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: AppTheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                contenido ??
                    Text(
                      valor ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Caja extends StatelessWidget {
  final Color color;
  final Color borde;
  final IconData icono;
  final Color iconoColor;
  final String titulo;
  final String texto;

  const _Caja({
    required this.color,
    required this.borde,
    required this.icono,
    required this.iconoColor,
    required this.titulo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: iconoColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(texto, style: const TextStyle(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre el detalle: panel lateral en tableta y escritorio, pantalla completa
/// en celular. [constructor] recibe la función para cerrarlo.
Future<void> mostrarDetalleActividad(
  BuildContext context, {
  required Widget Function(BuildContext context, VoidCallback cerrar)
  constructor,
}) async {
  final ancho = MediaQuery.sizeOf(context).width;
  if (ancho < 700) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('Actividad'),
            leading: IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: EscalaTexto(
            child: SafeArea(
              top: false,
              child: constructor(ctx, () => Navigator.of(ctx).pop()),
            ),
          ),
        ),
      ),
    );
    return;
  }
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar detalle',
    barrierColor: const Color(0x660E1E16),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) {
      final w = MediaQuery.sizeOf(ctx).width;
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.white,
          elevation: 12,
          child: SizedBox(
            width: w < 520 ? w : 480,
            height: double.infinity,
            child: SafeArea(
              child: EscalaTexto(
                child: constructor(ctx, () => Navigator.of(ctx).pop()),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      if (MediaQuery.of(ctx).disableAnimations) return child;
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.15, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: anim, child: child),
      );
    },
  );
}
