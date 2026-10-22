import 'package:flutter/material.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../model/planilla_usuario_model.dart';
import '../../service/app_error.dart';
import '../../service/theme.dart';
import '../../utils/planilla/planilla_tabla.dart';
import '../../widgets/planilla/tabla_planilla.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

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

  // Vista de tabla tipo Excel: se carga la primera vez que se abre.
  bool _vistaTabla = false;
  Future<List<PlanillaUsuario>>? _futurePlanilla;

  @override
  void initState() {
    super.initState();
    _futureConjunto = _api.obtenerConjunto(widget.conjuntoNit);
  }

  void _cambiarVista(bool tabla) {
    setState(() {
      _vistaTabla = tabla;
      if (tabla) _futurePlanilla ??= _cargarPlanilla();
    });
  }

  Future<List<PlanillaUsuario>> _cargarPlanilla() =>
      _api.planillaUsuarios(conjuntoId: widget.conjuntoNit);

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
            return const SkeletonList();
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${AppError.messageOf(snapshot.error)}'),
            );
          }

          final conjunto = snapshot.data!;
          if (_vistaTabla) return _tabla(conjunto);

          // ✅ FILTRAR: SOLO OPERARIOS ACTIVOS
          // (Tu Operario dentro de Conjunto debe traer "activo")
          final operariosActivos = conjunto.operarios
              .where((o) => o.activo == true)
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _selectorVista(),
                const SizedBox(height: 12),
                _tarjetaConjunto(conjunto),
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

  Widget _selectorVista() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.view_list_rounded),
            label: Text('Lista'),
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.table_chart_outlined),
            label: Text('Tabla (todos los datos)'),
          ),
        ],
        selected: {_vistaTabla},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _cambiarVista(s.first),
      ),
    );
  }

  Widget _tarjetaConjunto(Conjunto conjunto) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: ListTile(
        title: Text(
          conjunto.nombre,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('NIT: ${conjunto.nit}'),
      ),
    );
  }

  /// Vista de tabla: el administrador y las personas activas del conjunto
  /// (las mismas de la lista), con un solo scroll para toda la pantalla.
  Widget _tabla(Conjunto conjunto) {
    return SelectionArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SelectionContainer.disabled(child: _selectorVista()),
                      const SizedBox(height: 12),
                      _tarjetaConjunto(conjunto),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                FutureBuilder<List<PlanillaUsuario>>(
                  future: _futurePlanilla,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const SliverToBoxAdapter(child: SkeletonList());
                    }
                    if (snapshot.hasError) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(
                                'No se pudieron cargar los datos del personal:\n'
                                '${AppError.messageOf(snapshot.error)}',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => setState(
                                  () => _futurePlanilla = _cargarPlanilla(),
                                ),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Intentar de nuevo'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final activos = (snapshot.data ?? const [])
                        .where((p) => p.activo)
                        .toList();
                    return TablaPlanillaSliver(
                      filas: activos,
                      contexto: 'conjunto',
                      agrupacionPorDefecto: AgrupacionPlanilla.rol,
                      textoVacio: 'No hay personas activas en este conjunto.',
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
