import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'theme.dart';

/// Estilo unico para todas las graficas del dashboard de reportes.
///
/// Paleta categorica validada (skill dataviz: banda de luminosidad, piso de
/// croma, separacion CVD y de vision normal, todo PASS en modo claro sobre
/// fondo blanco). El orden de los slots es el mecanismo de seguridad CVD: no
/// reordenar ni ciclar.
class ChartStyle {
  ChartStyle._();

  static const Color slot1 = AppTheme.primary; // 0xFF0C6B43
  static const Color slot2 = Color(0xFF2A78D6);
  static const Color slot3 = Color(0xFFEB6834);
  static const Color slot4 = Color(0xFF1BAF7A);
  static const Color slot5 = Color(0xFFEDA100);
  static const Color slot6 = Color(0xFFE87BA4);
  static const Color slot7 = Color(0xFF4A3AA7);
  static const Color slot8 = Color(0xFFE34948);

  static const List<Color> series = [
    slot1,
    slot2,
    slot3,
    slot4,
    slot5,
    slot6,
    slot7,
    slot8,
  ];

  // Paleta de estado (semaforo), fija: nunca se reusa para series.
  static const Color good = Color(0xFF0CA30C);
  static const Color warning = Color(0xFFFAB219);
  static const Color serious = Color(0xFFEC835A);
  static const Color critical = Color(0xFFD03B3B);

  // Cromo del grafico.
  static const Color grid = Color(0xFFE4E8E5);
  static const Color baseline = Color(0xFFC6CFC9);
  static Color get axisInk => AppTheme.textMuted;

  static const TextStyle axisLabelStyle = TextStyle(
    fontSize: 11,
    color: AppTheme.textMuted,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle tooltipTextStyle = TextStyle(
    color: AppTheme.text,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle tooltipLabelStyle = TextStyle(
    color: AppTheme.textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// Orden fijo de estados -> slot de color (identidad, nunca por rango).
  static const Map<String, Color> _estadoSlots = {
    'APROBADA': slot1,
    'ASIGNADA': slot2,
    'PENDIENTE_REPROGRAMACION': slot3,
    'COMPLETADA': slot4,
    'PENDIENTE_APROBACION': slot5,
    'NO_COMPLETADA': slot6,
    'EN_PROCESO': slot7,
    'RECHAZADA': slot8,
  };

  static const Map<String, String> _estadoLabels = {
    'APROBADA': 'Aprobada',
    'ASIGNADA': 'Asignada',
    'PENDIENTE_REPROGRAMACION': 'Pend. reprogramación',
    'COMPLETADA': 'Completada',
    'PENDIENTE_APROBACION': 'Pend. aprobación',
    'NO_COMPLETADA': 'No completada',
    'EN_PROCESO': 'En proceso',
    'RECHAZADA': 'Rechazada',
  };

  static Color estadoColor(String estadoKey) =>
      _estadoSlots[estadoKey] ?? slot7;

  static String estadoLabel(String estadoKey) =>
      _estadoLabels[estadoKey] ??
      estadoKey
          .replaceAll('_', ' ')
          .toLowerCase()
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .join(' ');

  /// Orden de estados usado por leyendas/donuts (sigue el orden de slot).
  static const List<String> estadoOrder = [
    'APROBADA',
    'ASIGNADA',
    'PENDIENTE_REPROGRAMACION',
    'COMPLETADA',
    'PENDIENTE_APROBACION',
    'NO_COMPLETADA',
    'EN_PROCESO',
    'RECHAZADA',
  ];

  /// Rampa secuencial para el calendario de calor (0 = sin datos, 3 = maximo).
  static Color heat(int count, int max) {
    if (count <= 0 || max <= 0) return Colors.white;
    final steps = <Color>[
      slot1.withValues(alpha: 0.14),
      slot1.withValues(alpha: 0.34),
      slot1.withValues(alpha: 0.58),
      slot1.withValues(alpha: 0.86),
    ];
    final ratio = count / max;
    final idx = (ratio * (steps.length - 1)).round().clamp(0, steps.length - 1);
    return steps[idx];
  }

  // ---------------------------------------------------------------------
  // fl_chart helpers
  // ---------------------------------------------------------------------

  /// Rejilla recesiva: solo horizontal, hairline, nunca vertical.
  static FlGridData flGrid({double? interval}) {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: grid, strokeWidth: 1),
    );
  }

  static BarChartRodData flRod({
    required double value,
    Color color = slot1,
    double width = 28,
    double maxWidth = 34,
  }) {
    return BarChartRodData(
      toY: value,
      width: width > maxWidth ? maxWidth : width,
      color: color,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(5),
        topRight: Radius.circular(5),
      ),
    );
  }

  static AxisTitles flValueTitles({int? decimals}) {
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 36,
        getTitlesWidget: (v, meta) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            decimals == null || decimals == 0
                ? v.toInt().toString()
                : v.toStringAsFixed(decimals),
            style: axisLabelStyle,
          ),
        ),
      ),
    );
  }

  static AxisTitles flCategoryTitles(
    List<String> labels, {
    double width = 62,
    bool rotate = false,
  }) {
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: rotate ? 46 : 30,
        getTitlesWidget: (v, meta) {
          final i = v.toInt();
          if (i < 0 || i >= labels.length) return const SizedBox.shrink();
          final text = Text(
            labels[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: axisLabelStyle,
          );
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: rotate
                ? Transform.rotate(
                    angle: -0.5,
                    child: SizedBox(width: width, child: text),
                  )
                : SizedBox(width: width, child: text),
          );
        },
      ),
    );
  }

  static BarTouchData flBarTooltip({
    required List<String> labels,
    int decimals = 0,
    String? suffix,
  }) {
    return BarTouchData(
      enabled: true,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => Colors.white,
        tooltipBorder: const BorderSide(color: grid),
        tooltipRoundedRadius: 10,
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final idx = group.x;
          final label = (idx >= 0 && idx < labels.length) ? labels[idx] : '';
          final value = rod.toY.toStringAsFixed(decimals);
          final extra = (suffix == null || suffix.isEmpty) ? '' : ' $suffix';
          return BarTooltipItem(
            '$label\n',
            tooltipLabelStyle,
            children: [TextSpan(text: '$value$extra', style: tooltipTextStyle)],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Syncfusion helpers
  // ---------------------------------------------------------------------

  static NumericAxis sfNumericAxis({double? minimum, double? maximum}) {
    return NumericAxis(
      minimum: minimum,
      maximum: maximum,
      axisLine: const AxisLine(width: 0),
      majorTickLines: const MajorTickLines(size: 0),
      majorGridLines: const MajorGridLines(width: 1, color: grid),
      labelStyle: axisLabelStyle,
    );
  }

  static CategoryAxis sfCategoryAxis({
    int labelRotation = 0,
    double? interval,
  }) {
    return CategoryAxis(
      axisLine: const AxisLine(width: 0),
      majorTickLines: const MajorTickLines(size: 0),
      majorGridLines: const MajorGridLines(width: 0),
      labelRotation: labelRotation,
      interval: interval,
      labelStyle: axisLabelStyle,
    );
  }

  static TooltipBehavior sfTooltip({bool shared = false}) {
    return TooltipBehavior(
      enable: true,
      shared: shared,
      color: Colors.white,
      borderColor: grid,
      borderWidth: 1,
      textStyle: tooltipTextStyle,
      elevation: 6,
    );
  }

  static const DataLabelSettings sfDonutLabels = DataLabelSettings(
    isVisible: true,
    labelPosition: ChartDataLabelPosition.outside,
    connectorLineSettings: ConnectorLineSettings(
      type: ConnectorType.curve,
      color: baseline,
    ),
    textStyle: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.text,
    ),
  );

  static Widget donutCenter(String value, String caption) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        Text(
          caption,
          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ],
    );
  }
}
