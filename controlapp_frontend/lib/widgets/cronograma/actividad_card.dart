import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/categoria_visual.dart';
import 'package:flutter_application_1/utils/cronograma/estado_visual.dart';
import 'package:flutter_application_1/widgets/cronograma/cronograma_ui.dart';

enum DensidadTarjeta {
  /// Celda de la semana por trabajador.
  compacta,

  /// Agenda del día del administrador.
  normal,

  /// Agenda del operario (hora grande a la izquierda).
  grande,
}

/// Tarjeta única de actividad: ícono y color de la categoría, horario,
/// nombre (sin cortar en normal y grande), lugar, trabajadores y estado con
/// texto. Toda la tarjeta es un botón con una descripción completa para
/// lectores de pantalla.
class ActividadCard extends StatelessWidget {
  final TareaModel tarea;
  final DensidadTarjeta densidad;
  final VoidCallback? onTap;
  final bool seleccionada;
  final DateTime? ahora;

  /// En la fila de una persona: se muestra "con Juan" en vez de la lista.
  final String? trabajadorFilaId;

  /// En la agenda del operario: él no aparece en "con ...".
  final String? trabajadorActualId;

  /// Cuántas actividades de la misma persona coinciden con esta (incluida).
  /// 0 o 1 = no se muestra.
  final int simultaneas;

  final bool cierrePendienteEnvio;

  const ActividadCard({
    super.key,
    required this.tarea,
    this.densidad = DensidadTarjeta.normal,
    this.onTap,
    this.seleccionada = false,
    this.ahora,
    this.trabajadorFilaId,
    this.trabajadorActualId,
    this.simultaneas = 0,
    this.cierrePendienteEnvio = false,
  });

  static final DateFormat _hm = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final visual = CategoriaVisual.deTarea(tarea);
    final estado = EstadoVisual.de(
      tarea,
      ahora: ahora,
      cierrePendienteEnvio: cierrePendienteEnvio,
    );
    final ini = tarea.fechaInicio.toLocal();
    final fin = tarea.fechaFin.toLocal();
    final trabajadores = trabajadoresDe([tarea]);
    final compartida = trabajadores.length > 1;

    final etiquetaSemantica = _descripcionSemantica(
      visual,
      estado,
      ini,
      fin,
      trabajadores,
    );

    final contenido = switch (densidad) {
      DensidadTarjeta.compacta => _compacta(
        visual,
        estado,
        ini,
        fin,
        trabajadores,
        compartida,
      ),
      DensidadTarjeta.normal => _normal(
        visual,
        estado,
        ini,
        fin,
        trabajadores,
        compartida,
      ),
      DensidadTarjeta.grande => _grande(
        visual,
        estado,
        ini,
        fin,
        trabajadores,
        compartida,
      ),
    };

    final radio = BorderRadius.circular(
      densidad == DensidadTarjeta.compacta ? 12 : 16,
    );
    final cerrada = estado.cerrada;

    return Semantics(
      button: onTap != null,
      selected: seleccionada,
      label: etiquetaSemantica,
      excludeSemantics: true,
      child: Material(
        color: cerrada && !visual.esEspecial ? Colors.white : visual.fondo,
        shape: RoundedRectangleBorder(
          borderRadius: radio,
          side: BorderSide(
            color: seleccionada
                ? AppTheme.primary
                : (visual.esEspecial
                      ? CategoriaVisual.especialAcento
                      : visual.borde),
            width: seleccionada ? 3 : (visual.esEspecial ? 1.6 : 1),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(
              densidad == DensidadTarjeta.compacta ? 9 : 12,
            ),
            child: contenido,
          ),
        ),
      ),
    );
  }

  String _descripcionSemantica(
    CategoriaVisual visual,
    EstadoVisual estado,
    DateTime ini,
    DateTime fin,
    List<TrabajadorRef> trabajadores,
  ) {
    final partes = <String>[
      '${_hm.format(ini)} a ${_hm.format(fin)}',
      tarea.descripcion,
      if ((tarea.ubicacionNombre ?? '').trim().isNotEmpty)
        tarea.ubicacionNombre!.trim(),
      nombresEnLista(trabajadores.map((t) => t.nombre)),
      estado.etiqueta,
      visual.nombre,
      if (trabajadores.length > 1)
        'Actividad compartida por ${trabajadores.length} personas',
      if (simultaneas > 1) '$simultaneas actividades a la vez',
    ];
    return '${partes.join('. ')}.';
  }

  Widget _badges(
    EstadoVisual estado,
    CategoriaVisual visual,
    List<TrabajadorRef> trabajadores,
    bool compartida, {
    bool compacto = false,
  }) {
    String? textoCompartida;
    if (compartida && trabajadorFilaId != null) {
      final otros = trabajadores
          .where((t) => t.id != trabajadorFilaId)
          .map((t) => t.primerNombre);
      textoCompartida = 'con ${nombresEnLista(otros)}';
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        EstadoChip(estado: estado, compacto: compacto),
        if (compartida)
          CompartidaBadge(
            personas: trabajadores.length,
            texto: textoCompartida,
            compacto: compacto,
          ),
        if (visual.esEspecial) EspecialBadge(compacto: compacto),
        if (simultaneas > 1)
          SimultaneaBadge(cantidad: simultaneas, compacto: compacto),
      ],
    );
  }

  Widget _lugar(String texto, {double fs = 14.5}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.location_on_outlined,
            size: fs + 2,
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: fs,
              color: AppTheme.textMuted,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  String get _lugarTexto {
    final u = (tarea.ubicacionNombre ?? '').trim();
    final e = (tarea.elementoNombre ?? '').trim();
    if (u.isEmpty && e.isEmpty) return 'Sin lugar';
    if (e.isEmpty || e == u) return u;
    if (u.isEmpty) return e;
    return '$u · $e';
  }

  Widget _compacta(
    CategoriaVisual visual,
    EstadoVisual estado,
    DateTime ini,
    DateTime fin,
    List<TrabajadorRef> trabajadores,
    bool compartida,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CategoriaTile(visual: visual, tamano: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_hm.format(ini)}–${_hm.format(fin)}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tarea.descripcion,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            height: 1.25,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: 4),
        _lugar(_lugarTexto, fs: 13),
        const SizedBox(height: 6),
        _badges(estado, visual, trabajadores, compartida, compacto: true),
      ],
    );
  }

  Widget _normal(
    CategoriaVisual visual,
    EstadoVisual estado,
    DateTime ini,
    DateTime fin,
    List<TrabajadorRef> trabajadores,
    bool compartida,
  ) {
    final minutos = fin.difference(ini).inMinutes;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoriaTile(visual: visual, tamano: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${_hm.format(ini)} – ${_hm.format(fin)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: '  ·  ${duracionLegible(minutos)}',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tarea.descripcion,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  height: 1.3,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 4),
              _lugar(_lugarTexto),
              if (trabajadores.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    AvataresTrabajadores(trabajadores: trabajadores),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nombresEnLista(trabajadores.map((t) => t.nombre)),
                        style: const TextStyle(fontSize: 14.5),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              _badges(estado, visual, trabajadores, compartida),
            ],
          ),
        ),
      ],
    );
  }

  Widget _grande(
    CategoriaVisual visual,
    EstadoVisual estado,
    DateTime ini,
    DateTime fin,
    List<TrabajadorRef> trabajadores,
    bool compartida,
  ) {
    final companeros = trabajadores
        .where((t) => t.id != trabajadorActualId)
        .map((t) => t.nombre)
        .toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: visual.borde),
          ),
          child: Column(
            children: [
              Text(
                _hm.format(ini),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'a ${_hm.format(fin)}',
                style: const TextStyle(fontSize: 14, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tarea.descripcion,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.25,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 4),
              _lugar(_lugarTexto, fs: 15),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(visual.icono, size: 18, color: visual.acento),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      visual.nombre,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: visual.acento,
                      ),
                    ),
                  ),
                ],
              ),
              if (compartida && companeros.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.group, size: 18, color: Color(0xFF5A4100)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Con ${nombresEnLista(companeros)}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF5A4100),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              _badges(estado, visual, trabajadores, false),
            ],
          ),
        ),
        if (onTap != null)
          const Padding(
            padding: EdgeInsets.only(left: 4, top: 16),
            child: Icon(Icons.chevron_right, color: AppTheme.textMuted),
          ),
      ],
    );
  }
}
