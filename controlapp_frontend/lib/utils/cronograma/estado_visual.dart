import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/tarea_model.dart';

/// Grupo con el que se filtra y se cuenta el estado de una actividad.
enum GrupoEstado { pendiente, ahora, terminada, novedad }

/// Estado de una actividad en el lenguaje de la operación ("Pendiente",
/// "No se hizo"...) en vez del enum del sistema. Siempre se muestra con
/// ícono + texto, nunca solo con color (WCAG 1.4.1).
class EstadoVisual {
  final String etiqueta;
  final IconData icono;
  final Color color;
  final Color fondo;
  final GrupoEstado grupo;

  /// true si no es un estado del servidor sino una lectura de la hora
  /// ("Le toca ahora", "Atrasada").
  final bool calculado;

  /// true si la actividad ya se cerró (terminada, en revisión o no se hizo).
  final bool cerrada;

  const EstadoVisual({
    required this.etiqueta,
    required this.icono,
    required this.color,
    required this.fondo,
    required this.grupo,
    this.calculado = false,
    this.cerrada = false,
  });

  static const terminada = EstadoVisual(
    etiqueta: 'Terminada',
    icono: Icons.check_circle,
    color: Color(0xFF15803D),
    fondo: Color(0xFFE6F4EA),
    grupo: GrupoEstado.terminada,
    cerrada: true,
  );
  static const enRevision = EstadoVisual(
    etiqueta: 'En revisión',
    icono: Icons.hourglass_top,
    color: Color(0xFF6D28D9),
    fondo: Color(0xFFEFE7FD),
    grupo: GrupoEstado.terminada,
    cerrada: true,
  );
  static const noSeHizo = EstadoVisual(
    etiqueta: 'No se hizo',
    icono: Icons.report,
    color: Color(0xFFB45309),
    fondo: Color(0xFFFDF0E1),
    grupo: GrupoEstado.novedad,
    cerrada: true,
  );
  static const devuelta = EstadoVisual(
    etiqueta: 'Devuelta',
    icono: Icons.undo,
    color: Color(0xFFB91C1C),
    fondo: Color(0xFFFDE8E8),
    grupo: GrupoEstado.novedad,
  );
  static const porReprogramar = EstadoVisual(
    etiqueta: 'Por reprogramar',
    icono: Icons.event_repeat,
    color: Color(0xFFC2410C),
    fondo: Color(0xFFFDECE2),
    grupo: GrupoEstado.novedad,
  );
  static const atrasada = EstadoVisual(
    etiqueta: 'Atrasada',
    icono: Icons.warning_rounded,
    color: Color(0xFFB91C1C),
    fondo: Color(0xFFFDE8E8),
    grupo: GrupoEstado.novedad,
    calculado: true,
  );
  /// Abierta y de un día anterior: nadie registró el cierre.
  static const sinCerrar = EstadoVisual(
    etiqueta: 'Sin cerrar',
    icono: Icons.assignment_late,
    color: Color(0xFFB91C1C),
    fondo: Color(0xFFFDE8E8),
    grupo: GrupoEstado.novedad,
    calculado: true,
  );
  static const enCurso = EstadoVisual(
    etiqueta: 'En curso',
    icono: Icons.play_circle,
    color: Color(0xFF1D4ED8),
    fondo: Color(0xFFE5EDFD),
    grupo: GrupoEstado.ahora,
  );
  static const leTocaAhora = EstadoVisual(
    etiqueta: 'Le toca ahora',
    icono: Icons.schedule,
    color: Color(0xFF1D4ED8),
    fondo: Color(0xFFEEF3FE),
    grupo: GrupoEstado.ahora,
    calculado: true,
  );
  static const pendiente = EstadoVisual(
    etiqueta: 'Pendiente',
    icono: Icons.schedule,
    color: Color(0xFF475569),
    fondo: Color(0xFFEEF1F5),
    grupo: GrupoEstado.pendiente,
  );

  /// Cierre guardado en el teléfono sin conexión (cola offline).
  static const seEnviaraConSenal = EstadoVisual(
    etiqueta: 'Se enviará con señal',
    icono: Icons.cloud_off,
    color: Color(0xFFB45309),
    fondo: Color(0xFFFDF0E1),
    grupo: GrupoEstado.terminada,
    cerrada: true,
  );

  /// Estado a mostrar para [t] en el instante [ahora].
  factory EstadoVisual.de(
    TareaModel t, {
    DateTime? ahora,
    bool cierrePendienteEnvio = false,
  }) {
    if (cierrePendienteEnvio) return seEnviaraConSenal;
    final estado = (t.estado ?? '').trim().toUpperCase();
    switch (estado) {
      case 'APROBADA':
      case 'COMPLETADA':
        return terminada;
      case 'PENDIENTE_APROBACION':
        return enRevision;
      case 'NO_COMPLETADA':
        return noSeHizo;
      case 'RECHAZADA':
        return devuelta;
      case 'PENDIENTE_REPROGRAMACION':
        return porReprogramar;
    }
    final now = ahora ?? DateTime.now();
    if (!t.fechaFin.isAfter(now)) {
      final f = t.fechaFin.toLocal();
      final hoy = DateTime(now.year, now.month, now.day);
      return DateTime(f.year, f.month, f.day).isBefore(hoy) ? sinCerrar : atrasada;
    }
    if (estado == 'EN_PROCESO') return enCurso;
    if (!t.fechaInicio.isAfter(now)) return leTocaAhora;
    return pendiente;
  }
}

/// Texto completo del grupo, para filtros y resúmenes.
String etiquetaGrupoEstado(GrupoEstado g) {
  switch (g) {
    case GrupoEstado.pendiente:
      return 'Pendientes';
    case GrupoEstado.ahora:
      return 'Ahora';
    case GrupoEstado.terminada:
      return 'Terminadas';
    case GrupoEstado.novedad:
      return 'Con novedad';
  }
}
