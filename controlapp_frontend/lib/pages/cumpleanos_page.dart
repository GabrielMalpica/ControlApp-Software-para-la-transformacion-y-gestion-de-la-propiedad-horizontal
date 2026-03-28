import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/api/notificacion_api.dart';
import 'package:flutter_application_1/model/cumpleanos_model.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';

class CumpleanosPage extends StatefulWidget {
  const CumpleanosPage({super.key});

  @override
  State<CumpleanosPage> createState() => _CumpleanosPageState();
}

class _CumpleanosPageState extends State<CumpleanosPage> {
  final NotificacionApi _api = NotificacionApi();

  bool _loading = true;
  String? _error;
  List<CumpleaneroModel> _items = [];
  int _selectedMonth = DateTime.now().month;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _api.listarCumpleanosAnio();
      if (!mounted) return;
      setState(() {
        _items = items;
        if (_monthItems(_selectedMonth).isEmpty) {
          final firstMonth = _monthsWithBirthdays.isEmpty
              ? DateTime.now().month
              : _monthsWithBirthdays.first;
          _selectedMonth = firstMonth;
        }
        _selectedDay = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<int> get _monthsWithBirthdays {
    final months = _items.map((item) => item.mes).toSet().toList()..sort();
    return months;
  }

  List<CumpleaneroModel> _monthItems(int month) {
    final items = _items.where((item) => item.mes == month).toList()
      ..sort((a, b) {
        final byDay = a.dia.compareTo(b.dia);
        if (byDay != 0) return byDay;
        return a.nombre.compareTo(b.nombre);
      });
    return items;
  }

  Map<int, List<CumpleaneroModel>> _groupByDay(int month) {
    final grouped = <int, List<CumpleaneroModel>>{};
    for (final item in _monthItems(month)) {
      grouped.putIfAbsent(item.dia, () => <CumpleaneroModel>[]).add(item);
    }
    return grouped;
  }

  String _monthName(int month) =>
      DateFormat.MMMM('es').format(DateTime(2026, month));

  String _prettyRol(String raw) {
    final withSpaces = raw.toLowerCase().replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final monthItems = _monthItems(_selectedMonth);
    final groupedByDay = _groupByDay(_selectedMonth);
    final selectedPeople = _selectedDay == null
        ? const <CumpleaneroModel>[]
        : (groupedByDay[_selectedDay] ?? const <CumpleaneroModel>[]);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Cumpleanos'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _cargar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : monthItems.isEmpty && _items.isEmpty
          ? const Center(child: Text('No hay cumpleanos registrados.'))
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1040;
                final content = <Widget>[
                  _HeaderSummary(
                    monthLabel: _monthName(_selectedMonth),
                    totalMonth: monthItems.length,
                    totalDays: groupedByDay.length,
                    selectedDay: _selectedDay,
                  ),
                  const SizedBox(height: 18),
                  _MonthOverview(
                    months: List<int>.generate(12, (index) => index + 1),
                    selectedMonth: _selectedMonth,
                    countForMonth: (month) => _monthItems(month).length,
                    onTap: (month) {
                      setState(() {
                        _selectedMonth = month;
                        _selectedDay = null;
                      });
                    },
                    monthName: _monthName,
                  ),
                  const SizedBox(height: 18),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _BirthdayCalendarCard(
                            month: _selectedMonth,
                            groupedByDay: groupedByDay,
                            selectedDay: _selectedDay,
                            onSelectDay: (day) {
                              setState(() {
                                _selectedDay = _selectedDay == day ? null : day;
                              });
                            },
                            monthName: _monthName(_selectedMonth),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 5,
                          child: _DayDetailCard(
                            month: _selectedMonth,
                            selectedDay: _selectedDay,
                            people: selectedPeople,
                            prettyRol: _prettyRol,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _BirthdayCalendarCard(
                      month: _selectedMonth,
                      groupedByDay: groupedByDay,
                      selectedDay: _selectedDay,
                      onSelectDay: (day) {
                        setState(() {
                          _selectedDay = _selectedDay == day ? null : day;
                        });
                      },
                      monthName: _monthName(_selectedMonth),
                    ),
                    const SizedBox(height: 18),
                    _DayDetailCard(
                      month: _selectedMonth,
                      selectedDay: _selectedDay,
                      people: selectedPeople,
                      prettyRol: _prettyRol,
                    ),
                  ],
                ];

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: content,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({
    required this.monthLabel,
    required this.totalMonth,
    required this.totalDays,
    required this.selectedDay,
  });

  final String monthLabel;
  final int totalMonth;
  final int totalDays;
  final int? selectedDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12084D31),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calendario de cumpleanos',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Explora por mes, ubica el dia con cumpleanos y abre el detalle de las personas celebradas.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryPill(label: 'Mes', value: monthLabel),
              _SummaryPill(label: 'Cumpleanos', value: totalMonth.toString()),
              _SummaryPill(
                label: 'Dias con eventos',
                value: totalDays.toString(),
              ),
              _SummaryPill(
                label: 'Dia seleccionado',
                value: selectedDay == null
                    ? 'Ninguno'
                    : selectedDay.toString().padLeft(2, '0'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: AppTheme.primaryDark),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthOverview extends StatelessWidget {
  const _MonthOverview({
    required this.months,
    required this.selectedMonth,
    required this.countForMonth,
    required this.onTap,
    required this.monthName,
  });

  final List<int> months;
  final int selectedMonth;
  final int Function(int month) countForMonth;
  final ValueChanged<int> onTap;
  final String Function(int month) monthName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Meses',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final count = width >= 1100
                ? 4
                : width >= 760
                ? 3
                : width >= 520
                ? 2
                : 1;
            return GridView.builder(
              itemCount: months.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                childAspectRatio: width < 520 ? 2.8 : 1.65,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final month = months[index];
                final selected = month == selectedMonth;
                final total = countForMonth(month);
                return InkWell(
                  onTap: () => onTap(month),
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primaryDark.withValues(alpha: 0.18)
                            : Colors.black12,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.22)
                                : AppTheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.calendar_month_rounded,
                            color: selected ? Colors.white : AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                monthName(month),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                total == 1
                                    ? '1 cumpleanos'
                                    : '$total cumpleanos',
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white.withValues(alpha: 0.86)
                                      : Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _BirthdayCalendarCard extends StatelessWidget {
  const _BirthdayCalendarCard({
    required this.month,
    required this.groupedByDay,
    required this.selectedDay,
    required this.onSelectDay,
    required this.monthName,
  });

  final int month;
  final Map<int, List<CumpleaneroModel>> groupedByDay;
  final int? selectedDay;
  final ValueChanged<int> onSelectDay;
  final String monthName;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(2026, month + 1, 0).day;
    final firstWeekday = DateTime(2026, month, 1).weekday;
    final cells = <Widget>[];

    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final people = groupedByDay[day] ?? const <CumpleaneroModel>[];
      final selected = selectedDay == day;
      cells.add(
        InkWell(
          onTap: people.isEmpty ? null : () => onSelectDay(day),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary
                  : people.isNotEmpty
                  ? AppTheme.accent.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppTheme.primaryDark.withValues(alpha: 0.18)
                    : people.isNotEmpty
                    ? AppTheme.accent.withValues(alpha: 0.40)
                    : Colors.black12,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                if (people.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.20)
                          : AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      people.length == 1
                          ? '1 persona'
                          : '${people.length} personas',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppTheme.primaryDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    const weekDays = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calendario de ${monthName[0].toUpperCase()}${monthName.substring(1)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: weekDays.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 2.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (_, index) => Center(
              child: Text(
                weekDays[index],
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.black54,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.02,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (_, index) => cells[index],
          ),
        ],
      ),
    );
  }
}

class _DayDetailCard extends StatelessWidget {
  const _DayDetailCard({
    required this.month,
    required this.selectedDay,
    required this.people,
    required this.prettyRol,
  });

  final int month;
  final int? selectedDay;
  final List<CumpleaneroModel> people;
  final String Function(String raw) prettyRol;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detalle del dia',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (selectedDay == null)
            const Text(
              'Selecciona un dia del calendario para ver quienes cumplen anos.',
              style: TextStyle(color: Colors.black54),
            )
          else ...[
            Text(
              'Dia ${selectedDay.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryDark,
              ),
            ),
            const SizedBox(height: 12),
            if (people.isEmpty)
              const Text(
                'No hay cumpleanos registrados para este dia.',
                style: TextStyle(color: Colors.black54),
              )
            else
              ...people.map(
                (person) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: person.esHoy
                          ? AppTheme.accent.withValues(alpha: 0.12)
                          : AppTheme.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: person.esHoy
                            ? AppTheme.accent.withValues(alpha: 0.40)
                            : AppTheme.primary.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white,
                          child: Icon(
                            person.esHoy
                                ? Icons.cake_rounded
                                : Icons.celebration_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                person.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                prettyRol(person.rol),
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                person.correo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        if (person.esHoy)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Hoy',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
