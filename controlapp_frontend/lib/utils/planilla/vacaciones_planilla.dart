import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'package:flutter_application_1/model/planilla_usuario_model.dart';

/// En qué punto de sus vacaciones está una persona hoy. La regla completa
/// está en docs/planilla-personal.md ("Días para vacaciones").
enum TipoEstadoVacaciones {
  /// No hay fecha de ingreso (solo los operarios la tienen).
  sinFechaIngreso,

  /// Ya salió de la empresa (fecha de retiro hoy o antes).
  retirado,

  /// Hoy cae dentro de un rango marcado como vacaciones en Asistencia.
  deVacaciones,

  /// Tiene vacaciones marcadas más adelante en Asistencia.
  programadas,

  /// Aún no cumple su primer año: las primeras vacaciones llegan en el
  /// primer aniversario de ingreso.
  primerAnio,

  /// Ya tomó vacaciones desde su último aniversario.
  yaTomo,

  /// Cumplió otro año y no ha tomado las vacaciones de ese período.
  pendientes,
}

class EstadoVacaciones {
  final TipoEstadoVacaciones tipo;

  /// Texto de la celda (el mismo que se copia a Excel).
  final String texto;

  /// Próximo aniversario de ingreso (después de hoy).
  final DateTime? proximoAniversario;

  /// Días que faltan para [proximoAniversario].
  final int? diasParaAniversario;

  /// Último día de vacaciones ya disfrutado (Asistencia o la fecha de
  /// últimas vacaciones registrada en la hoja de vida).
  final DateTime? ultimasVacaciones;

  const EstadoVacaciones({
    required this.tipo,
    required this.texto,
    this.proximoAniversario,
    this.diasParaAniversario,
    this.ultimasVacaciones,
  });
}

/// Aniversario de [ingreso] en [anio]. Quien entró un 29 de febrero cumple
/// el 28 en los años no bisiestos.
DateTime aniversarioIngreso(DateTime ingreso, int anio) {
  final ultimoDiaMes = DateTime.utc(anio, ingreso.month + 1, 0).day;
  return DateTime.utc(anio, ingreso.month, math.min(ingreso.day, ultimoDiaMes));
}

/// Calcula el estado de vacaciones de una persona a la fecha [hoy].
///
/// Cada año, en el aniversario de la fecha de ingreso, le tocan vacaciones.
/// Se miran, en este orden: retiro, vacaciones en curso, vacaciones
/// programadas, primer año, si ya tomó las del período actual (algún día de
/// vacaciones desde el último aniversario) o si están pendientes.
EstadoVacaciones calcularEstadoVacaciones({
  required DateTime? fechaIngreso,
  DateTime? fechaSalida,
  DateTime? fechaUltimasVacaciones,
  List<BloqueVacaciones> bloques = const [],
  required DateTime hoy,
}) {
  final h = _dia(hoy);
  if (fechaIngreso == null) {
    return const EstadoVacaciones(
      tipo: TipoEstadoVacaciones.sinFechaIngreso,
      texto: 'Sin fecha de ingreso',
    );
  }
  final ingreso = _dia(fechaIngreso);

  if (fechaSalida != null && !_dia(fechaSalida).isAfter(h)) {
    return EstadoVacaciones(
      tipo: TipoEstadoVacaciones.retirado,
      texto: 'Retirado el ${fechaCorta(fechaSalida, conAnio: true)}',
    );
  }

  var proximo = aniversarioIngreso(ingreso, h.year);
  if (!proximo.isAfter(h)) proximo = aniversarioIngreso(ingreso, h.year + 1);
  final ultimo = aniversarioIngreso(ingreso, proximo.year - 1);
  final cumplioAnio = ultimo.isAfter(ingreso);
  final dias = _diasEntre(h, proximo);

  final ordenados = [...bloques]..sort((a, b) => a.desde.compareTo(b.desde));
  DateTime? ultimasVacaciones = fechaUltimasVacaciones == null
      ? null
      : _dia(fechaUltimasVacaciones);
  if (ultimasVacaciones != null && ultimasVacaciones.isAfter(h)) {
    ultimasVacaciones = null;
  }
  BloqueVacaciones? enCurso;
  BloqueVacaciones? siguiente;
  for (final b in ordenados) {
    final desde = _dia(b.desde);
    final hasta = _dia(b.hasta);
    if (!desde.isAfter(h) && !hasta.isBefore(h)) {
      enCurso ??= b;
    } else if (desde.isAfter(h)) {
      siguiente ??= b;
    } else if (ultimasVacaciones == null || hasta.isAfter(ultimasVacaciones)) {
      ultimasVacaciones = hasta;
    }
  }

  EstadoVacaciones estado(TipoEstadoVacaciones tipo, String texto) =>
      EstadoVacaciones(
        tipo: tipo,
        texto: texto,
        proximoAniversario: proximo,
        diasParaAniversario: dias,
        ultimasVacaciones: ultimasVacaciones,
      );

  if (enCurso != null) {
    return estado(
      TipoEstadoVacaciones.deVacaciones,
      'De vacaciones hasta el ${fechaCorta(enCurso.hasta, conAnio: enCurso.hasta.year != h.year)}',
    );
  }

  if (siguiente != null) {
    final enDias = _diasEntre(h, _dia(siguiente.desde));
    final conAnio =
        siguiente.desde.year != h.year || siguiente.hasta.year != h.year;
    return estado(
      TipoEstadoVacaciones.programadas,
      'Programadas del ${fechaCorta(siguiente.desde, conAnio: conAnio)} '
      'al ${fechaCorta(siguiente.hasta, conAnio: conAnio)} · ${_enDias(enDias)}',
    );
  }

  if (!cumplioAnio) {
    return estado(
      TipoEstadoVacaciones.primerAnio,
      'Primer año · le tocan en ${_nDias(dias)}',
    );
  }

  if (ultimasVacaciones != null && !ultimasVacaciones.isBefore(ultimo)) {
    return estado(
      TipoEstadoVacaciones.yaTomo,
      'Ya tomó las de este año · faltan ${_nDias(dias)}',
    );
  }

  final hace = _diasEntre(ultimo, h);
  return estado(
    TipoEstadoVacaciones.pendientes,
    hace == 0
        ? 'Le tocan desde hoy'
        : 'Pendientes desde el ${fechaCorta(ultimo, conAnio: true)} · hace ${_nDias(hace)}',
  );
}

/// `15/11` o `15/11/2026`.
String fechaCorta(DateTime fecha, {bool conAnio = false}) =>
    DateFormat(conAnio ? 'dd/MM/yyyy' : 'dd/MM').format(fecha);

String _nDias(int n) => n == 1 ? '1 día' : '$n días';

String _enDias(int n) => switch (n) {
  0 => 'hoy',
  1 => 'mañana',
  _ => 'en $n días',
};

DateTime _dia(DateTime d) => DateTime.utc(d.year, d.month, d.day);

int _diasEntre(DateTime desde, DateTime hasta) =>
    _dia(hasta).difference(_dia(desde)).inDays;
