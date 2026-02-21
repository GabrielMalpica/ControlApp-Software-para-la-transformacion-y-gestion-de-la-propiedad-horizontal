import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/notificacion_model.dart';
import 'package:flutter_application_1/service/notificaciones_center.dart';
import 'package:intl/intl.dart';

class NotificacionesAction extends StatefulWidget {
  final Color iconColor;

  const NotificacionesAction({
    super.key,
    this.iconColor = Colors.white,
  });

  @override
  State<NotificacionesAction> createState() => _NotificacionesActionState();
}

class _NotificacionesActionState extends State<NotificacionesAction> {
  final NotificacionesCenter _center = NotificacionesCenter.instance;

  @override
  void initState() {
    super.initState();
    _center.start();
  }

  Future<void> _abrirPanel() async {
    await _center.refresh();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final alto = MediaQuery.of(ctx).size.height * 0.75;

        return SafeArea(
          child: SizedBox(
            height: alto,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Notificaciones',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await _center.marcarTodasLeidas();
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('Marcar todas'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ValueListenableBuilder<List<NotificacionModel>>(
                    valueListenable: _center.items,
                    builder: (_, lista, __) {
                      if (lista.isEmpty) {
                        return const Center(
                          child: Text('No hay notificaciones por ahora.'),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _center.refresh,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: lista.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final n = lista[i];
                            return ListTile(
                              onTap: () async {
                                if (n.leida) return;
                                try {
                                  await _center.marcarLeida(n.id);
                                } catch (_) {}
                              },
                              leading: Icon(
                                n.leida
                                    ? Icons.notifications_none
                                    : Icons.notifications_active,
                                color: n.leida ? Colors.grey : Colors.orange,
                              ),
                              title: Text(
                                n.titulo,
                                style: TextStyle(
                                  fontWeight: n.leida
                                      ? FontWeight.w500
                                      : FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${n.mensaje}\n${_fechaLegible(n.creadaEn)}',
                              ),
                              isThreeLine: true,
                              trailing: n.leida
                                  ? null
                                  : const Icon(
                                      Icons.brightness_1,
                                      color: Colors.redAccent,
                                      size: 10,
                                    ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fechaLegible(DateTime dt) {
    return DateFormat('dd/MM/yyyy HH:mm', 'es').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _center.totalNoLeidas,
      builder: (_, total, __) {
        return IconButton(
          tooltip: 'Notificaciones',
          onPressed: _abrirPanel,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications, color: widget.iconColor),
              if (total > 0)
                Positioned(
                  right: -6,
                  top: -5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      total > 99 ? '99+' : '$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
