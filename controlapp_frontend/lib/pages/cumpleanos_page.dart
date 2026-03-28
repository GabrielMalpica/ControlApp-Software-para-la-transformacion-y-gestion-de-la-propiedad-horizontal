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
      final items = await _api.listarCumpleanosMesActual();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _prettyRol(String raw) {
    final withSpaces = raw.toLowerCase().replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final mes = DateFormat.MMMM('es').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Cumpleanos del mes'),
        actions: [
          IconButton(onPressed: _loading ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                'Personas que cumplen anos en ${mes[0].toUpperCase()}${mes.substring(1)}.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_items.isEmpty) {
      return const Center(child: Text('No hay cumpleanos registrados para este mes.'));
    }

    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final item = _items[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.esHoy ? AppTheme.accent.withValues(alpha: 0.55) : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: item.esHoy
                    ? AppTheme.accent.withValues(alpha: 0.25)
                    : AppTheme.primary.withValues(alpha: 0.12),
                child: Icon(
                  item.esHoy ? Icons.cake : Icons.celebration_outlined,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('${item.dia.toString().padLeft(2, '0')}/${item.mes.toString().padLeft(2, '0')} • ${_prettyRol(item.rol)}'),
                    const SizedBox(height: 2),
                    Text(item.correo, style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              if (item.esHoy)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('Hoy', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        );
      },
    );
  }
}
