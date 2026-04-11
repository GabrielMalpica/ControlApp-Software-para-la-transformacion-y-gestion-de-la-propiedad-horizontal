import 'package:flutter/material.dart';

import 'compartidos/reportes_dashboard_page.dart';

class ReportesPage extends StatelessWidget {
  final String nit;
  final bool soloResumenTipos;

  const ReportesPage({
    super.key,
    required this.nit,
    this.soloResumenTipos = false,
  });

  @override
  Widget build(BuildContext context) {
    return ReportesDashboardPage(
      conjuntoIdInicial: nit,
      permitirInformesPdf: !soloResumenTipos,
      soloResumenTipos: soloResumenTipos,
    );
  }
}
