import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

/// Insumo que la persona dice haber usado, tal como lo escribió (en la
/// medida real del insumo cuando la tiene, ej. litros).
class InsumoUsadoEntrada {
  final int insumoId;
  final num cantidad;

  const InsumoUsadoEntrada(this.insumoId, this.cantidad);
}

/// Convierte lo escrito a la unidad de conteo que se descuenta del stock
/// (ej. 3,6 L de un insumo de 1,8 L por tarro = 2 tarros). Ignora filas sin
/// insumo o con cantidad <= 0. Es la misma regla que usa la hoja de cierre.
List<Map<String, num>> insumosParaCierre(
  Iterable<InsumoUsadoEntrada> entradas,
  List<InventarioItemResponse> inventario,
) {
  final out = <Map<String, num>>[];
  for (final e in entradas) {
    if (e.cantidad <= 0) continue;
    InventarioItemResponse? item;
    for (final x in inventario) {
      if (x.insumoId == e.insumoId) {
        item = x;
        break;
      }
    }
    final contenido = item?.contenidoPorUnidad;
    final cantidad = (contenido != null && contenido > 0)
        ? e.cantidad / contenido
        : e.cantidad;
    out.add({'insumoId': e.insumoId, 'cantidad': cantidad});
  }
  return out;
}

/// "7.2 L (4 tarros)" si el insumo tiene contenido medible; si no, el conteo.
String etiquetaStock(InventarioItemResponse item) {
  final total = item.totalDisponibleTexto;
  if (total == null) return item.disponibleTexto;
  return '$total (${item.disponibleTexto})';
}

/// Unidad en la que se escribe la cantidad usada de [item].
String unidadEntrada(InventarioItemResponse item) =>
    item.contenidoPorUnidad != null
    ? (item.unidadContenido ?? item.unidad)
    : item.unidad;

/// Archivos elegidos → adjuntos listos para multipart (web: bytes; móvil y
/// escritorio: ruta).
List<EvidenciaAdjunto> evidenciasDesdeArchivos(
  Iterable<SelectedUploadFile> archivos,
) {
  final out = <EvidenciaAdjunto>[];
  for (final a in archivos) {
    final nombre = a.name.trim().isEmpty ? 'foto.jpg' : a.name.trim();
    if (kIsWeb) {
      if (a.hasBytes) {
        out.add(
          EvidenciaAdjunto(nombre: nombre, bytes: a.bytes, captura: a.captura),
        );
      }
      continue;
    }
    if (a.hasPath) {
      out.add(
        EvidenciaAdjunto(
          nombre: nombre,
          path: a.path!.trim(),
          captura: a.captura,
        ),
      );
    } else if (a.hasBytes) {
      out.add(
        EvidenciaAdjunto(nombre: nombre, bytes: a.bytes, captura: a.captura),
      );
    }
  }
  return out;
}

/// Evita adjuntar dos veces el mismo archivo.
bool mismaEvidencia(EvidenciaAdjunto a, EvidenciaAdjunto b) {
  if ((a.path ?? '').isNotEmpty || (b.path ?? '').isNotEmpty) {
    return (a.path ?? '') == (b.path ?? '');
  }
  final la = a.bytes?.length ?? 0;
  final lb = b.bytes?.length ?? 0;
  return a.nombre == b.nombre && la == lb && la > 0;
}

/// Motivos frecuentes para "no pude hacerla" (se guardan como texto en las
/// observaciones; el servidor exige al menos 3 caracteres).
const List<String> kMotivosNoRealizada = [
  'Llovió',
  'Faltaron insumos',
  'El área estaba ocupada',
  'Faltó herramienta o máquina',
  'Otro motivo',
];
