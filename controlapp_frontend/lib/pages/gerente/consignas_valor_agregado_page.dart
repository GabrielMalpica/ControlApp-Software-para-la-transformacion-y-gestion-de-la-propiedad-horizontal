import 'package:flutter/material.dart';

import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/dashboard_shell.dart';

class ConsignasValorAgregadoPage extends StatelessWidget {
  const ConsignasValorAgregadoPage({super.key, required this.conjunto});

  final Conjunto conjunto;

  @override
  Widget build(BuildContext context) {
    final consignas = conjunto.consignasEspeciales
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final valoresAgregados = conjunto.valorAgregado
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Consignas y valor agregado'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: DashboardScaffold(
        title: 'Consignas y valor agregado',
        headline: conjunto.nombre,
        description:
            'Consulta las consignas especiales y los valores agregados del conjunto activo.',
        leadingBadge: 'NIT ${conjunto.nit}',
        child: _TextoMatrizCard(
          consignas: consignas,
          valoresAgregados: valoresAgregados,
        ),
      ),
    );
  }
}

class _TextoMatrizCard extends StatelessWidget {
  const _TextoMatrizCard({
    required this.consignas,
    required this.valoresAgregados,
  });

  final List<String> consignas;
  final List<String> valoresAgregados;

  @override
  Widget build(BuildContext context) {
    final totalRows = consignas.length > valoresAgregados.length
        ? consignas.length
        : valoresAgregados.length;

    return DashboardSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.fact_check_outlined,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Matriz de consignas y valor agregado',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(),
              1: FlexColumnWidth(),
            },
            border: TableBorder(
              horizontalInside: BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.08),
              ),
              verticalInside: BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.08),
              ),
            ),
            children: <TableRow>[
              TableRow(
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.06),
                ),
                children: const <Widget>[
                  _HeaderCell(
                    title: 'Consignas especiales',
                    icon: Icons.fact_check_outlined,
                    color: AppTheme.primary,
                  ),
                  _HeaderCell(
                    title: 'Valor agregado',
                    icon: Icons.workspace_premium_outlined,
                    color: AppTheme.accent,
                  ),
                ],
              ),
              ...List<TableRow>.generate(totalRows, (index) {
                final zebra = index.isEven
                    ? Colors.white
                    : AppTheme.surfaceSoft.withValues(alpha: 0.45);
                return TableRow(
                  decoration: BoxDecoration(color: zebra),
                  children: <Widget>[
                    _BodyCell(
                      text: index < consignas.length ? consignas[index] : '',
                    ),
                    _BodyCell(
                      text: index < valoresAgregados.length
                          ? valoresAgregados[index]
                          : '',
                    ),
                  ],
                );
              }),
              if (totalRows == 0)
                const TableRow(
                  children: <Widget>[
                    _EmptyCell(message: 'Sin consignas registradas'),
                    _EmptyCell(message: 'Sin valores agregados registrados'),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Text(
        text.isEmpty ? '-' : text,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _EmptyCell extends StatelessWidget {
  const _EmptyCell({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
      ),
    );
  }
}
