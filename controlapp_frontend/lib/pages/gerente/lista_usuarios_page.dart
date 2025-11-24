import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/repositories/usuario_repository.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/pages/gerente/crear_usuario_page.dart';
import 'editar_usuario_page.dart';

class ListaUsuariosPage extends StatefulWidget {
  final String nitProyecto; // para crear admin vinculados al conjunto/empresa

  const ListaUsuariosPage({super.key, required this.nitProyecto});

  @override
  State<ListaUsuariosPage> createState() => _ListaUsuariosPageState();
}

class _ListaUsuariosPageState extends State<ListaUsuariosPage> {
  final UsuarioRepository _usuarioRepository = UsuarioRepository();

  List<Usuario> _usuarios = [];
  bool _cargando = true;
  String? _error;

  // Filtro por rol
  String _filtroRol = 'todos';

  // Roles disponibles (los mismos del enum del back)
  final List<String> _rolesDisponibles = [
    'todos',
    'gerente',
    'administrador',
    'jefe_operaciones',
    'supervisor',
    'operario',
  ];

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  Future<void> _cargarUsuarios() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final lista = await _usuarioRepository.obtenerUsuarios();
      setState(() {
        _usuarios = lista;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _cargando = false;
      });
    }
  }

  // Filtra en memoria por rol
  List<Usuario> get _usuariosFiltrados {
    if (_filtroRol == 'todos') return _usuarios;
    return _usuarios.where((u) => u.rol == _filtroRol).toList();
  }

  String _prettyRol(String rol) {
    if (rol.isEmpty) return rol;
    final withSpaces = rol.toLowerCase().replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  Future<void> _irACrearUsuario() async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CrearUsuarioPage(nit: widget.nitProyecto),
      ),
    );

    // Si en la página de creación devolvemos true al guardar, recargamos lista
    if (resultado == true) {
      _cargarUsuarios();
    }
  }

  Future<void> _irAEditarUsuario(Usuario usuario) async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditarUsuarioPage(usuario: usuario)),
    );

    if (resultado == true) {
      _cargarUsuarios();
    }
  }

  Future<void> _confirmarEliminarUsuario(Usuario usuario) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Eliminar usuario"),
        content: Text(
          "¿Seguro que deseas eliminar al usuario ${usuario.nombre} (${usuario.cedula})?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Eliminar", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _usuarioRepository.eliminarUsuario(usuario.cedula);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Usuario eliminado correctamente"),
          backgroundColor: Colors.green,
        ),
      );
      _cargarUsuarios();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Error al eliminar usuario: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Gestión de usuarios",
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.person_add),
        label: const Text("Nuevo usuario"),
        onPressed: _irACrearUsuario,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ───────── Filtro por rol ─────────
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list),
                    const SizedBox(width: 8),
                    const Text(
                      "Filtrar por rol:",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _rolesDisponibles.map((rol) {
                            final seleccionado = _filtroRol == rol;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ChoiceChip(
                                label: Text(
                                  rol == 'todos' ? "Todos" : _prettyRol(rol),
                                ),
                                selected: seleccionado,
                                onSelected: (_) {
                                  setState(() {
                                    _filtroRol = rol;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ───────── Contenido ─────────
            Expanded(child: _cuerpo()),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          "Error cargando usuarios:\n$_error",
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_usuariosFiltrados.isEmpty) {
      return const Center(
        child: Text("No hay usuarios para el filtro seleccionado."),
      );
    }

    return ListView.separated(
      itemCount: _usuariosFiltrados.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final u = _usuariosFiltrados[index];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withOpacity(0.1),
              child: Text(
                u.nombre.isNotEmpty ? u.nombre[0].toUpperCase() : '?',
                style: TextStyle(color: AppTheme.primary),
              ),
            ),
            title: Text(
              u.nombre,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "Cédula: ${u.cedula} · Rol: ${_prettyRol(u.rol)}\nCorreo: ${u.correo}",
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: "Editar",
                  icon: const Icon(Icons.edit, color: Colors.blueGrey),
                  onPressed: () => _irAEditarUsuario(u),
                ),
                IconButton(
                  tooltip: "Eliminar",
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmarEliminarUsuario(u),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
