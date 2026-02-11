import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class TiposDonutChart extends StatelessWidget {
  final int preventivas;
  final int correctivas;

  const TiposDonutChart({
    super.key,
    required this.preventivas,
    required this.correctivas,
  });

  @override
  Widget build(BuildContext context) {
    final total = (preventivas + correctivas).clamp(1, 1 << 30);
    final pPct = (preventivas / total) * 100.0;
    final cPct = (correctivas / total) * 100.0;

    return AspectRatio(
      aspectRatio: 2.2,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 48,
                    sectionsSpace: 2,
                    startDegreeOffset: -90,
                    sections: [
                      PieChartSectionData(
                        value: preventivas.toDouble(),
                        title: '${pPct.toStringAsFixed(0)}%',
                        radius: 62,
                        titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        color: const Color(0xFF22C55E),
                      ),
                      PieChartSectionData(
                        value: correctivas.toDouble(),
                        title: '${cPct.toStringAsFixed(0)}%',
                        radius: 62,
                        titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        color: const Color(0xFFEF4444),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 210,
                child: _Legend(
                  rows: [
                    _LegendRow(
                      'Preventivas',
                      preventivas,
                      const Color(0xFF22C55E),
                    ),
                    _LegendRow(
                      'Correctivas',
                      correctivas,
                      const Color(0xFFEF4444),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final List<_LegendRow> rows;
  const _Legend({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: rows
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: r.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${r.value}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _LegendRow {
  final String label;
  final int value;
  final Color color;
  _LegendRow(this.label, this.value, this.color);
}
