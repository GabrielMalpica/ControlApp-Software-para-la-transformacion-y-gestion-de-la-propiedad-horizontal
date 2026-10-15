/// Solicitudes que llegan desde la página web (rutas /commerce/web/* del
/// backend): postulaciones de trabajadores y conjuntos registrados. Los datos
/// viven en WordPress y los archivos en Google Drive; desde la app solo se
/// marca una postulación como revisada o se borra.
library;

String? _texto(dynamic value) {
  if (value == null) return null;
  final limpio = value.toString().trim();
  return limpio.isEmpty ? null : limpio;
}

DateTime? _fecha(dynamic value) {
  final raw = _texto(value);
  return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
}

List<String> _lista(dynamic value) {
  if (value is! List) return const <String>[];
  return value.map(_texto).whereType<String>().toList(growable: false);
}

class DocumentoWeb {
  const DocumentoWeb({
    required this.tipo,
    required this.etiqueta,
    this.driveFileId,
    this.mime,
    this.nombre,
    this.enServidor = false,
    this.urlServidor,
    this.pendiente = false,
  });

  final String tipo;
  final String etiqueta;
  final String? driveFileId;
  final String? mime;
  final String? nombre;

  /// Archivo anterior al cambio a Drive: sigue en el servidor de la web.
  final bool enServidor;
  final String? urlServidor;

  /// Recibido por la web pero todavía en cola para subir a Drive.
  final bool pendiente;

  bool get esImagen => (mime ?? '').toLowerCase().startsWith('image/');
  bool get enDrive => driveFileId != null;

  String? get urlDrive => driveFileId == null
      ? null
      : 'https://drive.google.com/file/d/$driveFileId/view';

  factory DocumentoWeb.fromJson(Map<String, dynamic> json) {
    final tipo = _texto(json['tipo']) ?? 'otro';
    return DocumentoWeb(
      tipo: tipo,
      etiqueta: _texto(json['etiqueta']) ?? tipo,
      driveFileId: _texto(json['driveFileId']),
      mime: _texto(json['mime']),
      nombre: _texto(json['nombre']),
      enServidor: json['enServidor'] == true,
      urlServidor: _texto(json['urlServidor']),
      pendiente: json['pendiente'] == true,
    );
  }
}

List<DocumentoWeb> _documentos(dynamic value) {
  if (value is! List) return const <DocumentoWeb>[];
  return value
      .whereType<Map<String, dynamic>>()
      .map(DocumentoWeb.fromJson)
      .toList(growable: false);
}

class PostulacionWeb {
  const PostulacionWeb({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.estado,
    required this.estadoEtiqueta,
    this.telefono,
    this.correo,
    this.documentoTipo,
    this.documentoUltimos4,
    this.habilidades = const <String>[],
    this.zonas = const <String>[],
    this.observaciones,
    this.creadoEn,
    this.foto,
    this.documentos = const <DocumentoWeb>[],
    this.revisada = false,
    this.revisadaEn,
    this.revisadaPor,
  });

  final int id;
  final String nombres;
  final String apellidos;
  final String? telefono;
  final String? correo;
  final String? documentoTipo;
  final String? documentoUltimos4;
  final List<String> habilidades;
  final List<String> zonas;
  final String estado;
  final String estadoEtiqueta;
  final String? observaciones;
  final DateTime? creadoEn;
  final DocumentoWeb? foto;
  final List<DocumentoWeb> documentos;

  /// Marca del equipo "ya la revisamos" (no cambia el estado en WordPress).
  final bool revisada;
  final DateTime? revisadaEn;
  final String? revisadaPor;

  String get nombreCompleto => '$nombres $apellidos'.trim();

  factory PostulacionWeb.fromJson(Map<String, dynamic> json) {
    final estado = _texto(json['estado']) ?? 'pendiente';
    final foto = json['foto'];
    return PostulacionWeb(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombres: _texto(json['nombres']) ?? '',
      apellidos: _texto(json['apellidos']) ?? '',
      telefono: _texto(json['telefono']),
      correo: _texto(json['correo']),
      documentoTipo: _texto(json['documentoTipo']),
      documentoUltimos4: _texto(json['documentoUltimos4']),
      habilidades: _lista(json['habilidades']),
      zonas: _lista(json['zonas']),
      estado: estado,
      estadoEtiqueta: _texto(json['estadoEtiqueta']) ?? estado,
      observaciones: _texto(json['observaciones']),
      creadoEn: _fecha(json['creadoEn']),
      foto: foto is Map<String, dynamic> ? DocumentoWeb.fromJson(foto) : null,
      documentos: _documentos(json['documentos']),
      revisada: json['revisada'] == true,
      revisadaEn: _fecha(json['revisadaEn']),
      revisadaPor: _texto(json['revisadaPor']),
    );
  }
}

/// Resultado de borrar una postulación desde la app.
class PostulacionEliminada {
  const PostulacionEliminada({
    required this.archivosEnPapelera,
    required this.archivosSinMover,
  });

  /// Documentos que quedaron en la papelera de Drive (se recuperan 30 días).
  final int archivosEnPapelera;

  /// Documentos que no se pudieron mover y siguen en Drive.
  final int archivosSinMover;

  factory PostulacionEliminada.fromJson(Map<String, dynamic> json) {
    return PostulacionEliminada(
      archivosEnPapelera: (json['archivosEnPapelera'] as num?)?.toInt() ?? 0,
      archivosSinMover: (json['archivosSinMover'] as num?)?.toInt() ?? 0,
    );
  }
}

class RegistroConjuntoWeb {
  const RegistroConjuntoWeb({
    required this.id,
    required this.nombre,
    required this.estado,
    required this.estadoEtiqueta,
    this.nit,
    this.telefono,
    this.correo,
    this.nota,
    this.registradoEn,
    this.documentos = const <DocumentoWeb>[],
  });

  final int id;
  final String nombre;
  final String? nit;
  final String? telefono;
  final String? correo;
  final String estado;
  final String estadoEtiqueta;
  final String? nota;
  final DateTime? registradoEn;
  final List<DocumentoWeb> documentos;

  factory RegistroConjuntoWeb.fromJson(Map<String, dynamic> json) {
    final estado = _texto(json['estado']) ?? 'pending';
    return RegistroConjuntoWeb(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: _texto(json['nombre']) ?? 'Sin nombre',
      nit: _texto(json['nit']),
      telefono: _texto(json['telefono']),
      correo: _texto(json['correo']),
      estado: estado,
      estadoEtiqueta: _texto(json['estadoEtiqueta']) ?? estado,
      nota: _texto(json['nota']),
      registradoEn: _fecha(json['registradoEn']),
      documentos: _documentos(json['documentos']),
    );
  }
}

class PaginaWeb<T> {
  const PaginaWeb({
    required this.items,
    required this.total,
    required this.pagina,
    required this.porPagina,
  });

  final List<T> items;
  final int total;
  final int pagina;
  final int porPagina;

  bool get hayMas => pagina * porPagina < total;

  factory PaginaWeb.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) item,
  ) {
    final raw = json['items'];
    final items = raw is List
        ? raw.whereType<Map<String, dynamic>>().map(item).toList()
        : <T>[];
    return PaginaWeb<T>(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? items.length,
      pagina: (json['pagina'] as num?)?.toInt() ?? 1,
      porPagina: (json['porPagina'] as num?)?.toInt() ?? 20,
    );
  }
}
