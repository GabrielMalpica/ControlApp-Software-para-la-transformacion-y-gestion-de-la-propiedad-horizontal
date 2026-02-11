import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class EstadoBarChart extends StatelessWidget {
  final Map<String, int> byEstado;
  final int maxItems;

  const EstadoBarChart({super.key, required this.byEstado, this.maxItems = 8});

  @override
  Widget build(BuildContext context) {
    final items = byEstado.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = items.take(maxItems).toList();
    final maxV = (top.isEmpty ? 1 : top.first.value).toDouble();

    return AspectRatio(
      aspectRatio: 2.2,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (maxV * 1.25).clamp(1, double.infinity),
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= top.length)
                        return const SizedBox.shrink();
                      final label = top[i].key.replaceAll('_', ' ');
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: List.generate(top.length, (i) {
                final v = top[i].value.toDouble();
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: v,
                      width: 18,
                      borderRadius: BorderRadius.circular(6),
                      color: const Color(0xFF3B82F6),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
