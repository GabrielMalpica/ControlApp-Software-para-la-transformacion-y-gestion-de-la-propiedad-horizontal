import 'package:flutter/material.dart';

import 'compartidos/reportes_dashboard_page.dart';

class ReportesPage extends StatelessWidget {
  final String nit;

  const ReportesPage({super.key, required this.nit});

  @override
  Widget build(BuildContext context) {
    return ReportesDashboardPage(conjuntoIdInicial: nit);
  }
}
