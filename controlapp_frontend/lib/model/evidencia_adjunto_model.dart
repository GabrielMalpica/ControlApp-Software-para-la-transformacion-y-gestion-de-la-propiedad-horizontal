class EvidenciaAdjunto {
  final String nombre;
  final String? path;
  final List<int>? bytes;

  const EvidenciaAdjunto({
    required this.nombre,
    this.path,
    this.bytes,
  });
}
