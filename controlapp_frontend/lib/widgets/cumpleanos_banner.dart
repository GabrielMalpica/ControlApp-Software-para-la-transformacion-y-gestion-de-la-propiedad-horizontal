import 'package:flutter/material.dart';

import 'package:flutter_application_1/api/notificacion_api.dart';
import 'package:flutter_application_1/model/cumpleanos_model.dart';
import 'package:flutter_application_1/service/theme.dart';

class CumpleanosBanner extends StatefulWidget {
  const CumpleanosBanner({super.key});

  @override
  State<CumpleanosBanner> createState() => _CumpleanosBannerState();
}

class _CumpleanosBannerState extends State<CumpleanosBanner> {
  final NotificacionApi _api = NotificacionApi();
  CumpleanosHoyModel? _info;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final info = await _api.obtenerCumpleanosHoy();
      if (!mounted) return;
      setState(() => _info = info);
    } catch (_) {
      if (!mounted) return;
      setState(() => _info = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || !info.esCumpleanosHoy) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.accent.withValues(alpha: 0.22), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.cake_outlined, color: AppTheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feliz cumpleanos, ${info.nombre}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  info.mensaje ?? 'La empresa te desea un excelente dia.',
                  style: const TextStyle(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
