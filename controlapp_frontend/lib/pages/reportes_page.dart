import 'package:flutter/material.dart';

import 'compartidos/reportes_dashboard_page.dart';

class ReportesPage extends StatelessWidget {
  final String nit;
  final bool soloResumenTipos;
  final bool? mostrarInformes;
  final bool mostrarAnalisisInformes;
  final bool mostrarDescargaInformes;

  const ReportesPage({
    super.key,
    required this.nit,
    this.soloResumenTipos = false,
    this.mostrarInformes,
    this.mostrarAnalisisInformes = true,
    this.mostrarDescargaInformes = true,
  });

  @override
  Widget build(BuildContext context) {
    return ReportesDashboardPage(
      conjuntoIdInicial: nit,
      permitirInformesPdf: mostrarInformes ?? !soloResumenTipos,
      soloResumenTipos: soloResumenTipos,
      mostrarAnalisisInformes: mostrarAnalisisInformes,
      mostrarDescargaInformes: mostrarDescargaInformes,
    );
  }
}
