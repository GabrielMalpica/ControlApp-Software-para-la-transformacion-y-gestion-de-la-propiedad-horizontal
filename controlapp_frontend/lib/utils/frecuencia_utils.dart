import 'package:flutter/material.dart';

/// Fuente unica para todo lo relacionado con la frecuencia de una preventiva:
/// catalogo, etiqueta legible, color y orden cronologico.
const List<String> frecuenciasPreventivas = [
  'DIARIA',
  'SEMANAL',
  'QUINCENAL',
  'MENSUAL',
  'BIMESTRAL',
  'TRIMESTRAL',
  'SEMESTRAL',
  'ANUAL',
];

/// Frecuencias que se programan eligiendo dia(s) de la semana.
const Set<String> frecuenciasPorDiaSemana = {'SEMANAL', 'QUINCENAL'};

/// De las anteriores, las que admiten marcar VARIOS dias.
/// Cada dia marcado se guarda como una preventiva independiente.
/// Una quincenal se ejecuta un unico dia cada 14, asi que no entra aqui.
const Set<String> frecuenciasMultiDiaSemana = {'SEMANAL'};

/// Frecuencias que se programan eligiendo un dia del mes.
const Set<String> frecuenciasPorDiaMes = {'MENSUAL'};

/// Frecuencias que exigen fechas explicitas del calendario.
const Set<String> frecuenciasPorFechasExplicitas = {
  'BIMESTRAL',
  'TRIMESTRAL',
  'SEMESTRAL',
  'ANUAL',
};

const Map<String, int> fechasRequeridasPorFrecuencia = {
  'BIMESTRAL': 2,
  'TRIMESTRAL': 3,
  'SEMESTRAL': 2,
  'ANUAL': 1,
};

const List<String> diasSemanaOpciones = [
  'LUNES',
  'MARTES',
  'MIERCOLES',
  'JUEVES',
  'VIERNES',
  'SABADO',
  'DOMINGO',
];

const Map<String, String> _diasSemanaLabel = {
  'LUNES': 'lunes',
  'MARTES': 'martes',
  'MIERCOLES': 'miércoles',
  'JUEVES': 'jueves',
  'VIERNES': 'viernes',
  'SABADO': 'sábado',
  'DOMINGO': 'domingo',
};

const Map<String, String> _frecuenciaLabel = {
  'DIARIA': 'Diaria',
  'SEMANAL': 'Semanal',
  'QUINCENAL': 'Quincenal',
  'MENSUAL': 'Mensual',
  'BIMESTRAL': 'Bimestral',
  'TRIMESTRAL': 'Trimestral',
  'SEMESTRAL': 'Semestral',
  'ANUAL': 'Anual',
};

/// Normaliza el valor recibido del backend: mayusculas, sin tildes y con `_`
/// en lugar de espacios o guiones.
String normalizarFrecuencia(String? raw) {
  return (raw ?? '')
      .trim()
      .toUpperCase()
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ñ', 'N')
      .replaceAll(RegExp(r'[\s\-]+'), '_');
}

String normalizarDiaSemana(String? raw) => normalizarFrecuencia(raw);

/// `'LUNES'` -> `'lunes'`. Devuelve `null` si no reconoce el dia.
String? etiquetaDiaSemana(String? diaSemana) {
  final clave = normalizarDiaSemana(diaSemana);
  if (clave.isEmpty) return null;
  return _diasSemanaLabel[clave];
}

/// Dia de la semana de una fecha en el formato del backend (`'LUNES'`...).
String diaSemanaDeFecha(DateTime fecha) =>
    diasSemanaOpciones[(fecha.weekday - 1) % 7];

/// Etiqueta legible de la frecuencia, indicando a que dia corresponde la tarea.
///
/// Ejemplos: `Semanal (lunes)`, `Quincenal (martes)`, `Mensual (día 15)`, `Diaria`.
///
/// Cuando la frecuencia depende del dia de la semana y la tarea no trae
/// `diaSemana` (datos anteriores a la migracion), se usa `fechaReferencia`
/// como respaldo.
String etiquetaFrecuencia(
  String? frecuencia, {
  String? diaSemana,
  int? diaMes,
  DateTime? fechaReferencia,
}) {
  final clave = normalizarFrecuencia(frecuencia);
  if (clave.isEmpty) return '—';

  final base = _frecuenciaLabel[clave] ?? clave;

  if (frecuenciasPorDiaSemana.contains(clave)) {
    final dia =
        etiquetaDiaSemana(diaSemana) ??
        (fechaReferencia == null
            ? null
            : etiquetaDiaSemana(diaSemanaDeFecha(fechaReferencia)));
    return dia == null ? base : '$base ($dia)';
  }

  if (frecuenciasPorDiaMes.contains(clave)) {
    final dia = diaMes ?? fechaReferencia?.day;
    return dia == null ? base : '$base (día $dia)';
  }

  return base;
}

/// Igual que [etiquetaFrecuencia] pero con el prefijo `Frecuencia: `,
/// para el bloque de detalle de una tarea.
String etiquetaFrecuenciaCompleta(
  String? frecuencia, {
  String? diaSemana,
  int? diaMes,
  DateTime? fechaReferencia,
}) =>
    'Frecuencia: ${etiquetaFrecuencia(frecuencia, diaSemana: diaSemana, diaMes: diaMes, fechaReferencia: fechaReferencia)}';

Color colorFrecuencia(String? frecuencia) {
  switch (normalizarFrecuencia(frecuencia)) {
    case 'DIARIA':
      return Colors.green;
    case 'SEMANAL':
      return Colors.blue;
    case 'QUINCENAL':
      return Colors.cyan;
    case 'MENSUAL':
      return Colors.purple;
    case 'BIMESTRAL':
      return Colors.indigo;
    case 'TRIMESTRAL':
      return Colors.teal;
    case 'SEMESTRAL':
      return Colors.orange;
    case 'ANUAL':
      return Colors.brown;
    default:
      return Colors.grey;
  }
}

/// Orden cronologico (de mas frecuente a menos), no alfabetico.
int ordenFrecuencia(String? frecuencia) {
  final index = frecuenciasPreventivas.indexOf(
    normalizarFrecuencia(frecuencia),
  );
  return index < 0 ? frecuenciasPreventivas.length : index;
}

/// Comparador para ordenar filas del cronograma por frecuencia.
int compararPorFrecuencia(String? a, String? b) {
  final orden = ordenFrecuencia(a).compareTo(ordenFrecuencia(b));
  if (orden != 0) return orden;
  return (a ?? '').compareTo(b ?? '');
}
