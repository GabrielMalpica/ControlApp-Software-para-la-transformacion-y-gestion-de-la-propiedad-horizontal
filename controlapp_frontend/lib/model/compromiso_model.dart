class CompromisoModel {
  CompromisoModel({
    required this.id,
    required this.titulo,
    required this.completado,
    required this.creadaEn,
    required this.cerradaEn,
    required this.actualizadaEn,
    required this.diasAbierto,
    required this.ansEstado,
    required this.ansColor,
    required this.ansLabel,
    this.creadoPorId,
    this.creadoPorNombre,
    this.creadoPorRol,
  });

  final int id;
  String titulo;
  bool completado;
  DateTime? creadaEn;
  DateTime? cerradaEn;
  DateTime? actualizadaEn;
  int diasAbierto;
  String ansEstado;
  String ansColor;
  String ansLabel;
  String? creadoPorId;
  String? creadoPorNombre;
  String? creadoPorRol;

  String get autorLabel {
    final nombre = (creadoPorNombre ?? '').trim();
    final rol = (creadoPorRol ?? '').trim();
    if (nombre.isEmpty && rol.isEmpty) return 'Autor sin registrar';
    if (nombre.isEmpty) return rol;
    if (rol.isEmpty) return nombre;
    return '$nombre - $rol';
  }

  String get antiguedadLabel {
    if (completado) return 'Cerrado';
    if (diasAbierto <= 0) return 'Hoy';
    if (diasAbierto == 1) return '1 dia abierto';
    return '$diasAbierto dias abierto';
  }

  String get fechaCreacionLabel {
    final fecha = creadaEn;
    if (fecha == null) return 'Creado: sin fecha';
    return 'Creado: ${_formatDate(fecha)}';
  }

  String get fechaCierreLabel {
    if (!completado) return 'Abierto';
    final fecha = cerradaEn;
    if (fecha == null) return 'Cerrado: sin fecha';
    return 'Cerrado: ${_formatDate(fecha)}';
  }

  factory CompromisoModel.fromJson(Map<String, dynamic> json) {
    return CompromisoModel(
      id: (json['id'] as num).toInt(),
      titulo: (json['titulo'] ?? '').toString(),
      completado: json['completado'] == true,
      creadaEn: _parseDate(json['creadaEn']),
      cerradaEn: _parseDate(json['cerradaEn']),
      actualizadaEn: _parseDate(json['actualizadaEn']),
      diasAbierto: _parseInt(json['diasAbierto']),
      ansEstado: (json['ansEstado'] ?? '').toString(),
      ansColor: (json['ansColor'] ?? '').toString(),
      ansLabel: (json['ansLabel'] ?? '').toString(),
      creadoPorId: json['creadoPorId']?.toString(),
      creadoPorNombre: json['creadoPorNombre']?.toString(),
      creadoPorRol: json['creadoPorRol']?.toString(),
    );
  }

  void updateFrom(CompromisoModel other) {
    titulo = other.titulo;
    completado = other.completado;
    creadaEn = other.creadaEn;
    cerradaEn = other.cerradaEn;
    actualizadaEn = other.actualizadaEn;
    diasAbierto = other.diasAbierto;
    ansEstado = other.ansEstado;
    ansColor = other.ansColor;
    ansLabel = other.ansLabel;
    creadoPorId = other.creadoPorId;
    creadoPorNombre = other.creadoPorNombre;
    creadoPorRol = other.creadoPorRol;
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  static int _parseInt(dynamic raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? 0;
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }
}
