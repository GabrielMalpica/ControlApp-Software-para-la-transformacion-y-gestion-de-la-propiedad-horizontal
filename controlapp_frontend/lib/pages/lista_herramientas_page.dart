// lib/pages/gerente/lista_herramientas_page.dart
import 'package:flutter/material.dart';
import '../../api/herramienta_api.dart';
import '../../model/herramienta_model.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

/// ✅ Lista del CATÁLOGO de herramientas (empresa).
/// Esto NO es el inventario del conjunto.
/// - Se crea/edita/elimina "Martillo, Escoba, Alicate..."
/// - Luego, en otra pantalla, se asignan cantidades al conjunto (stock).
class ListaHerramientasPage extends StatefulWidget {
  final String empresaId;

  const ListaHerramientasPage({super.key, required this.empresaId});

  @override
  State<ListaHerramientasPage> createState() => _ListaHerramientasPageState();
}

class _ListaHerramientasPageState extends State<ListaHerramientasPage> {
  final _api = HerramientaApi();

  bool _cargando = false;
  String? _error;

  final _searchCtrl = TextEditingController();
  String _search = "";

  List<HerramientaResponse> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final out = await _api.listarHerramientas(
        empresaId: widget.empresaId,
        nombre: _search.trim().isEmpty ? null : _search.trim(),
        take: 100,
        skip: 0,
      );

      final data = (out["data"] as List?) ?? [];
      final parsed = data
          .whereType<Map>()
          .map((e) => HerramientaResponse.fromJson(e.cast<String, dynamic>()))
          .toList();

      if (!mounted) return;
      setState(() => _items = parsed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _confirmDelete(HerramientaResponse h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar herramienta"),
        content: Text(
          "Vas a eliminar “${h.nombre}”.\n"
          "Si está relacionada con stock/solicitudes/usos, el backend no la dejará.\n\n"
          "¿Continuamos o le perdonamos la vida? 😄",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _api.eliminarHerramienta(herramientaId: h.id);
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text("🧹 Herramienta eliminada.")),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text("❌ ${e.toString()}")),
      );
    }
  }

  String _modoLabel(ModoControlHerramienta m) => m.label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Catálogo de herramientas"),
        actions: [
          IconButton(
            tooltip: "Refrescar",
            onPressed: _cargando ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header: Empresa + Buscador
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Empresa: ${widget.empresaId}",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      labelText: "Buscar",
                      hintText: "Escribe: martillo, escoba, alicate...",
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.trim().isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = "");
                                _load();
                              },
                            ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 8),
                  _InfoBanner(),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Contenido
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : _items.isEmpty
                  ? _EmptyView(
                      onCreatePressed: () {
                        // Aquí navegas a tu CrearHerramientaPage
                        // y al volver, refrescas:
                        // final changed = await Navigator.push(...);
                        // if (changed == true) _load();
                        AppFeedback.showFromSnackBar(
                          context,
                          const SnackBar(
                            content: Text(
                              "Abre tu CrearHerramientaPage desde aquí 👍",
                            ),
                          ),
                        );
                      },
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final h = _items[index];

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: Colors.black12),
                            ),
                            child: ListTile(
                              title: Text(
                                h.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        _ChipInfo(
                                          icon: Icons.straighten,
                                          text: "Unidad: ${h.unidad}",
                                        ),
                                        _ChipInfo(
                                          icon: Icons.settings_suggest,
                                          text:
                                              "Control: ${_modoLabel(h.modoControl)}",
                                        ),
                                        if (h.vidaUtilDias != null)
                                          _ChipInfo(
                                            icon: Icons.timer_outlined,
                                            text:
                                                "Vida útil: ${h.vidaUtilDias} días",
                                          ),
                                        if (h.umbralBajo != null)
                                          _ChipInfo(
                                            icon: Icons.warning_amber_rounded,
                                            text: "Umbral: ${h.umbralBajo}",
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == "delete") {
                                    await _confirmDelete(h);
                                  } else if (v == "edit") {
                                    AppFeedback.showFromSnackBar(
                                      context,
                                      const SnackBar(
                                        content: Text(
                                          "Aquí conectas tu EditarHerramientaPage ✍️",
                                        ),
                                      ),
                                    );
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: "edit",
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 18),
                                        SizedBox(width: 8),
                                        Text("Editar"),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: "delete",
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 18),
                                        SizedBox(width: 8),
                                        Text("Eliminar"),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                // Si quieres, al tocar podrías ir al detalle
                              },
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Ejemplo:
          // final changed = await Navigator.push(
          //   context,
          //   MaterialPageRoute(builder: (_) => CrearHerramientaPage(empresaId: widget.empresaId)),
          // );
          // if (changed == true) _load();

          AppFeedback.showFromSnackBar(
            context,
            const SnackBar(
              content: Text("Conecta aquí tu CrearHerramientaPage ✅"),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("Nueva"),
      ),
    );
  }
}

// =========================
// Widgets auxiliares
// =========================

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: const Text(
        "Esto es el CATÁLOGO (tipo de herramienta).\n"
        "Aquí defines “Martillo, Escoba…” con su modo de control.\n"
        "El INVENTARIO del conjunto (cantidades) es otra pantalla aparte.",
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ChipInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(text)],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onCreatePressed;

  const _EmptyView({required this.onCreatePressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_circle_outlined, size: 54),
            const SizedBox(height: 10),
            const Text(
              "No hay herramientas en el catálogo",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              "Crea la primera (ej: Martillo) y luego la asignas a los conjuntos con cantidades.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onCreatePressed,
              icon: const Icon(Icons.add),
              label: const Text("Crear herramienta"),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 54),
            const SizedBox(height: 10),
            const Text(
              "Algo salió mal",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text("Reintentar"),
            ),
          ],
        ),
      ),
    );
  }
}
