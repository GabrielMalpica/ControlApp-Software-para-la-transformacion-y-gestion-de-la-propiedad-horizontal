import 'necesidad_herramienta_model.dart';
import 'necesidad_maquinaria_model.dart';

enum TipoRecursoCal { maquinaria, herramienta }

/// Días en que la empresa entrega/recoge maquinaria y herramientas prestadas:
/// lunes, miércoles y sábado. Debe coincidir con `DIAS_ENTREGA_RECOGIDA` del
/// backend (src/utils/reservaMaquinaria.ts) — es solo para la previsualización;
/// la ventana real la calcula el servidor al asignar.
const _diasEntregaRecogida = {1, 3, 6}; // DateTime.weekday: lunes=1 ... domingo=7

DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _buscarDiaPermitido(DateTime fecha, int paso) {
  var cursor = _soloFecha(fecha);
  for (var i = 0; i < 20; i++) {
    cursor = cursor.add(Duration(days: paso));
    if (_diasEntregaRecogida.contains(cursor.weekday)) return cursor;
  }
  return _soloFecha(fecha);
}

/// Ventana de entrega -> recogida para una necesidad de un solo día, con el
/// mismo criterio que `calcularRangoReserva` en el backend.
({DateTime entrega, DateTime recogida}) ventanaReserva(DateTime fecha) {
  return (
    entrega: _buscarDiaPermitido(fecha, -1),
    recogida: _buscarDiaPermitido(fecha, 1),
  );
}

/// Item unificado de calendario: una necesidad de maquinaria o de herramienta
/// para un conjunto y un día concretos. Las páginas de cronograma arman una
/// lista de estos a partir de las respuestas de `CronogramaMaquinariaApi` y
/// `CronogramaHerramientaApi`, y el calendario compartido solo sabe pintarlos.
class RecursoCalendarioItem {
  final TipoRecursoCal tipo;
  final DateTime fecha;
  final String conjuntoId;
  final String conjuntoNombre;
  final String titulo;
  final String unidad;
  final double cantidadRequerida;
  final double asignadas;
  final double pendientes;
  final List<String> tareasResumen;
  final List<int> tareaIds;
  final DateTime entrega;
  final DateTime recogida;

  // Datos crudos, para no tener que volver a pedirlos al asignar.
  final NecesidadMaquinaria? maquinariaRaw;
  final NecesidadHerramienta? herramientaRaw;

  RecursoCalendarioItem({
    required this.tipo,
    required this.fecha,
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.titulo,
    required this.unidad,
    required this.cantidadRequerida,
    required this.asignadas,
    required this.pendientes,
    required this.tareasResumen,
    required this.tareaIds,
    required this.entrega,
    required this.recogida,
    this.maquinariaRaw,
    this.herramientaRaw,
  });

  bool get cubierta => pendientes <= 1e-9;

  factory RecursoCalendarioItem.deMaquinaria(NecesidadMaquinaria n) {
    final ventana = ventanaReserva(n.fecha);
    return RecursoCalendarioItem(
      tipo: TipoRecursoCal.maquinaria,
      fecha: n.fecha,
      conjuntoId: n.conjuntoId,
      conjuntoNombre: n.conjuntoNombre,
      titulo: n.tipoLabel,
      unidad: 'unidad(es)',
      cantidadRequerida: n.cantidadRequerida.toDouble(),
      asignadas: n.asignaciones.length.toDouble(),
      pendientes: n.pendientes.toDouble(),
      tareasResumen: n.tareas
          .map((t) => '${t.descripcion} (${_hhmm(t.fechaInicio)}-${_hhmm(t.fechaFin)})')
          .toList(),
      tareaIds: n.tareas.map((t) => t.tareaId).toList(),
      entrega: ventana.entrega,
      recogida: ventana.recogida,
      maquinariaRaw: n,
    );
  }

  factory RecursoCalendarioItem.deHerramienta(NecesidadHerramienta n) {
    final ventana = ventanaReserva(n.fecha);
    return RecursoCalendarioItem(
      tipo: TipoRecursoCal.herramienta,
      fecha: n.fecha,
      conjuntoId: n.conjuntoId,
      conjuntoNombre: n.conjuntoNombre,
      titulo: n.herramientaNombre,
      unidad: n.herramientaUnidad,
      cantidadRequerida: n.cantidadRequerida,
      asignadas: n.asignadas,
      pendientes: n.pendientes,
      tareasResumen: n.tareas
          .map((t) => '${t.descripcion} (${_hhmm(t.fechaInicio)}-${_hhmm(t.fechaFin)})')
          .toList(),
      tareaIds: n.tareas.map((t) => t.tareaId).toList(),
      entrega: ventana.entrega,
      recogida: ventana.recogida,
      herramientaRaw: n,
    );
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
