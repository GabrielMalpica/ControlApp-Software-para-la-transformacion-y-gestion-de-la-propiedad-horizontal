String formatHoursMinutes(int totalMinutes) {
  final safeMinutes = totalMinutes < 0 ? 0 : totalMinutes;
  final hours = safeMinutes / 60.0;
  return '${hours.toStringAsFixed(1)}h (${safeMinutes}m)';
}
