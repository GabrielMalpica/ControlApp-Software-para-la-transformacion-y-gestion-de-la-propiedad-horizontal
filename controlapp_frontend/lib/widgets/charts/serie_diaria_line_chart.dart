import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SerieDiariaLineChart extends StatelessWidget {
  final List<String> days; // yyyy-MM-dd
  final Map<String, Map<String, int>> seriesByDayEstado;

  const SerieDiariaLineChart({
    super.key,
    required this.days,
    required this.seriesByDayEstado,
  });

  @override
  Widget build(BuildContext context) {
    final values = <double>[];
    for (final d in days) {
      final m = seriesByDayEstado[d] ?? {};
      final total = m.values.fold<int>(0, (a, b) => a + b);
      values.add(total.toDouble());
    }

    final maxY = (values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b)).clamp(1.0, double.infinity);

    final spots = List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i]));

    String shortDay(String ymd) {
      // yyyy-MM-dd -> dd/MM
      if (ymd.length >= 10) {
        final dd = ymd.substring(8, 10);
        final mm = ymd.substring(5, 7);
        return '$dd/$mm';
      }
      return ymd;
    }

    return AspectRatio(
      aspectRatio: 2.2,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (values.length - 1).toDouble().clamp(0, double.infinity),
              minY: 0,
              maxY: maxY * 1.25,
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: (values.length <= 10) ? 1 : (values.length / 6).ceilToDouble(),
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= days.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(shortDay(days[i]), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: const Color(0xFF60A5FA).withOpacity(0.15)),
                  color: const Color(0xFF2563EB),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}