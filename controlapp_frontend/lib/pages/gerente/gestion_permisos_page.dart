import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/permission_api.dart';
import 'package:flutter_application_1/model/permission_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';

class GestionPermisosPage extends StatefulWidget {
  const GestionPermisosPage({super.key});

  @override
  State<GestionPermisosPage> createState() => _GestionPermisosPageState();
}

class _GestionPermisosPageState extends State<GestionPermisosPage> {
  final PermissionApi _api = PermissionApi();

  PermissionMatrixResponse? _matrix;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final matrix = await _api.obtenerMatriz();
      if (!mounted) return;
      setState(() => _matrix = matrix);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _prettyRole(String role) {
    switch (role) {
      case 'gerente':
        return 'Gerente';
      case 'administrador':
        return 'Administrador';
      case 'jefe_operaciones':
        return 'Jefe operaciones';
      case 'supervisor':
        return 'Supervisor';
      case 'operario':
        return 'Operario';
      default:
        return role;
    }
  }

  void _toggle(String role, String permission, bool value) {
    final matrix = _matrix;
    if (matrix == null) return;
    if (!matrix.managedRoles.contains(role)) return;

    final current = Map<String, Map<String, bool>>.from(matrix.matrix);
    final rolePermissions = Map<String, bool>.from(current[role] ?? const {});
    rolePermissions[permission] = value;
    current[role] = rolePermissions;

    setState(() {
      _matrix = PermissionMatrixResponse(
        roles: matrix.roles,
        managedRoles: matrix.managedRoles,
        modules: matrix.modules,
        matrix: current,
      );
    });
  }

  Future<void> _save() async {
    final matrix = _matrix;
    if (matrix == null || _saving) return;

    setState(() => _saving = true);
    try {
      final updated = await _api.guardarMatriz(matrix);
      if (!mounted) return;
      setState(() => _matrix = updated);
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Permisos actualizados correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildGrid(PermissionModule module) {
    final matrix = _matrix!;
    final roles = matrix.roles;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        dataRowMinHeight: 72,
        dataRowMaxHeight: 88,
        headingRowColor: WidgetStatePropertyAll(
          AppTheme.primary.withValues(alpha: 0.08),
        ),
        columns: [
          const DataColumn(label: Text('Permiso')),
          for (final role in roles) DataColumn(label: Text(_prettyRole(role))),
        ],
        rows: [
          for (final item in module.permissions)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 260,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final role in roles)
                  DataCell(
                    Center(
                      child: Switch.adaptive(
                        value: matrix.matrix[role]?[item.key] == true,
                        onChanged: matrix.managedRoles.contains(role)
                            ? (value) => _toggle(role, item.key, value)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Gestion de permisos',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _loading || _saving || _matrix == null ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando' : 'Guardar'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 52,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : _matrix == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Control global por rol',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Desde aqui el gerente define que pantallas y acciones internas puede usar cada rol. La columna del gerente queda fija para evitar bloquear la administracion del sistema.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final module in _matrix!.modules)
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: Colors.black12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
                            child: Text(
                              module.label,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _buildGrid(module),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
