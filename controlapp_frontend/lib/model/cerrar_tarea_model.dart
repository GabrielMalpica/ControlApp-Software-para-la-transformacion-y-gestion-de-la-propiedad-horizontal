// lib/model/cerrar_tarea_request.dart
class CerrarTareaRequest {
  final String? observaciones;
  final DateTime? fechaFinalizarTarea;

  /// Lista de items {insumoId, cantidad} (se convierte a JSON string)
  final List<Map<String, num>> insumosUsados;

  /// paths locales de imágenes (PC o móvil)
  final List<String> evidenciaPaths;

  CerrarTareaRequest({
    this.observaciones,
    this.fechaFinalizarTarea,
    this.insumosUsados = const [],
    this.evidenciaPaths = const [],
  });
}
