import 'package:flutter/material.dart';
import '../model/conjunto_model.dart';

String normalizeScheduleDay(String raw) {
  var out = raw.trim().toUpperCase();
  const replacements = <String, String>{
    'Á': 'A',
    'É': 'E',
    'Í': 'I',
    'Ó': 'O',
    'Ú': 'U',
    'Ü': 'U',
    'Ñ': 'N',
    '_': '',
    '-': '',
    ' ': '',
  };

  replacements.forEach((key, value) {
    out = out.replaceAll(key, value);
  });
  return out;
}

int? weekdayFromScheduleDay(String? rawDay) {
  if (rawDay == null) return null;

  switch (normalizeScheduleDay(rawDay)) {
    case 'LUNES':
    case 'MONDAY':
      return DateTime.monday;
    case 'MARTES':
    case 'TUESDAY':
      return DateTime.tuesday;
    case 'MIERCOLES':
    case 'WEDNESDAY':
      return DateTime.wednesday;
    case 'JUEVES':
    case 'THURSDAY':
      return DateTime.thursday;
    case 'VIERNES':
    case 'FRIDAY':
      return DateTime.friday;
    case 'SABADO':
    case 'SATURDAY':
      return DateTime.saturday;
    case 'DOMINGO':
    case 'SUNDAY':
      return DateTime.sunday;
    default:
      return null;
  }
}

TimeOfDay? parseHourToTimeOfDay(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.trim().split(':');
  if (parts.length < 2) return null;

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

  return TimeOfDay(hour: hour, minute: minute);
}

int? parseHourToMinutes(String? raw) {
  final time = parseHourToTimeOfDay(raw);
  return time == null ? null : timeOfDayToMinutes(time);
}

int timeOfDayToMinutes(TimeOfDay time) => (time.hour * 60) + time.minute;

/// true si [inicio, fin) cae, aunque sea parcialmente, fuera del horario
/// GENERAL del conjunto ese día. Una plaza puede tener horarioEspecial=true
/// y aun así coincidir con el horario general (no se marca); solo se marca
/// cuando la tarea realmente excede esa ventana o cae un día que el
/// conjunto no opera -el criterio que importa para el distintivo visual,
/// no el simple hecho de que la plaza tenga horario especial configurado-.
bool tareaFueraDeHorarioGeneral({
  required List<HorarioConjunto> horariosConjunto,
  required DateTime inicio,
  required DateTime fin,
}) {
  HorarioConjunto? horarioDia;
  for (final h in horariosConjunto) {
    if (weekdayFromScheduleDay(h.dia) == inicio.weekday) {
      horarioDia = h;
      break;
    }
  }
  if (horarioDia == null) return true;

  final aperturaMin = parseHourToMinutes(horarioDia.horaApertura);
  final cierreMin = parseHourToMinutes(horarioDia.horaCierre);
  if (aperturaMin == null || cierreMin == null) return true;

  final iniMin = inicio.hour * 60 + inicio.minute;
  final finMin = fin.hour * 60 + fin.minute;
  return iniMin < aperturaMin || finMin > cierreMin;
}

String formatMinutesAsHour(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}
