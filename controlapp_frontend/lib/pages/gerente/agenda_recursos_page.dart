import 'package:flutter/material.dart';

import '../../model/recurso_calendario_item.dart';
import 'cronograma_recursos_page.dart';

/// Agenda de recursos de un conjunto, en calendario: alterna entre
/// maquinaria y herramientas con las pestañas de arriba, en vez de ser dos
/// páginas separadas.
///
/// Las preventivas declaran la necesidad (tipo de máquina, o herramienta +
/// cantidad); aquí se ve día a día lo pendiente por cubrir y se asigna:
/// primero lo propio del conjunto y, si falta, en préstamo de la empresa.
class AgendaRecursosPage extends StatelessWidget {
  final String empresaNit;
  final String? conjuntoId;
  final TipoRecursoCal tipoInicial;

  const AgendaRecursosPage({
    super.key,
    required this.empresaNit,
    this.conjuntoId,
    this.tipoInicial = TipoRecursoCal.maquinaria,
  });

  @override
  Widget build(BuildContext context) {
    return CronogramaRecursosPage(
      empresaNit: empresaNit,
      conjuntoIdInicial: conjuntoId,
      tipoInicial: tipoInicial,
      titulo: 'Agenda de recursos',
    );
  }
}
