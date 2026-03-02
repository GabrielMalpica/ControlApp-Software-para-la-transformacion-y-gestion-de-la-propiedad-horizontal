import 'package:flutter/material.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../service/theme.dart';

class UsuariosConjuntoPage extends StatefulWidget {
  final String conjuntoNit;
  final Conjunto? conjuntoInicial;

  const UsuariosConjuntoPage({
    super.key,
    required this.conjuntoNit,
    this.conjuntoInicial,
  });

  @override
  State<UsuariosConjuntoPage> createState() => _UsuariosConjuntoPageState();
}

class _UsuariosConjuntoPageState extends State<UsuariosConjuntoPage> {
  final GerenteApi _api = GerenteApi();
  late Future<Conjunto> _futureConjunto;

  @override
  void initState() {
    super.initState();
    if (widget.conjuntoInicial != null) {
      _futureConjunto = Future.value(widget.conjuntoInicial!);
    } else {
      _futureConjunto = _api.obtenerConjunto(widget.conjuntoNit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Usuarios del conjunto',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: FutureBuilder<Conjunto>(
        future: _futureConjunto,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final conjunto = snapshot.data!;

          // ✅ FILTRAR: SOLO OPERARIOS ACTIVOS
          // (Tu Operario dentro de Conjunto debe traer "activo")
          final operariosActivos = conjunto.operarios
              .where((o) => o.activo == true)
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                  child: ListTile(
                    title: Text(
                      conjunto.nombre,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('NIT: ${conjunto.nit}'),
                  ),
                ),
                const SizedBox(height: 16),

                // ───────── ADMINISTRADOR ─────────
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Administrador",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (conjunto.administradorNombre == null)
                          const Text(
                            "No hay administrador asignado.",
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          ListTile(
                            leading: const Icon(Icons.admin_panel_settings),
                            title: Text(conjunto.administradorNombre!),
                            subtitle: conjunto.administradorId != null
                                ? Text('CC: ${conjunto.administradorId!}')
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ───────── OPERARIOS (SOLO ACTIVOS) ─────────
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Operarios vinculados (activos)",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (operariosActivos.isEmpty)
                          const Text(
                            "No hay operarios activos asignados a este conjunto.",
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          ...operariosActivos.map(
                            (o) => ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(o.nombre),
                              subtitle: Text('CC: ${o.cedula}'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
