import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/points_api.dart';
import 'package:flutter_application_1/model/points_models.dart';
import 'package:flutter_application_1/pages/points_page.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';

class PointsCheckoutCard extends StatefulWidget {
  const PointsCheckoutCard({super.key, this.conjuntoId});

  final String? conjuntoId;

  @override
  State<PointsCheckoutCard> createState() => _PointsCheckoutCardState();
}

class _PointsCheckoutCardState extends State<PointsCheckoutCard> {
  final _api = PointsApi();
  PointsSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PointsCheckoutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conjuntoId != widget.conjuntoId) _load();
  }

  Future<void> _load() async {
    try {
      final summary = await _api.obtenerResumen(conjuntoId: widget.conjuntoId);
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      if (mounted) setState(() => _summary = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null || !summary.config.activo) {
      return const SizedBox.shrink();
    }
    final available = summary.beneficios
        .where((item) => item.disponible)
        .length;
    return CommerceClayCard(
      color: const Color(0xFFFFF4D8),
      child: Row(
        children: <Widget>[
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(Icons.stars_rounded, color: Color(0xFFA66B00)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${summary.saldo} puntos disponibles',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  available > 0
                      ? '$available canjes aplicables antes de finalizar.'
                      : 'Sigue acumulando al completar tus pedidos.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    PointsPage(initialConjuntoId: summary.conjuntoId),
              ),
            ).then((_) => _load()),
            child: const Text('Ver'),
          ),
        ],
      ),
    );
  }
}
