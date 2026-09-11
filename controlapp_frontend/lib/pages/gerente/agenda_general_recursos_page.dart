import 'package:flutter/material.dart';

import 'cronograma_recursos_page.dart';

/// Agenda general de recursos: maquinaria y herramientas de TODOS los
/// conjuntos de la empresa en un solo calendario. Muestra dónde va a estar
/// cada máquina/herramienta y deja asignar lo pendiente desde ahí mismo.
///
/// Solo debe enlazarse desde menús ya protegidos por permiso de asignar
/// maquinaria o herramientas (gerente y jefe de operaciones, hoy).
class AgendaGeneralRecursosPage extends StatelessWidget {
  final String empresaNit;

  const AgendaGeneralRecursosPage({super.key, required this.empresaNit});

  @override
  Widget build(BuildContext context) {
    return CronogramaRecursosPage(
      empresaNit: empresaNit,
      todosLosConjuntos: true,
      titulo: 'Agenda general de recursos',
    );
  }
}
