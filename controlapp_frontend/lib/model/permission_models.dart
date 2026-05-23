class PermissionItem {
  final String key;
  final String label;
  final String description;
  final String module;
  final String moduleLabel;

  const PermissionItem({
    required this.key,
    required this.label,
    required this.description,
    required this.module,
    required this.moduleLabel,
  });

  factory PermissionItem.fromJson(Map<String, dynamic> json) {
    return PermissionItem(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      module: json['module']?.toString() ?? '',
      moduleLabel: json['moduleLabel']?.toString() ?? '',
    );
  }
}

class PermissionModule {
  final String key;
  final String label;
  final List<PermissionItem> permissions;

  const PermissionModule({
    required this.key,
    required this.label,
    required this.permissions,
  });

  factory PermissionModule.fromJson(Map<String, dynamic> json) {
    final permissions = (json['permissions'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => PermissionItem.fromJson(item.cast<String, dynamic>()))
        .toList();

    return PermissionModule(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      permissions: permissions,
    );
  }
}

class PermissionMatrixResponse {
  final List<String> roles;
  final List<String> managedRoles;
  final List<PermissionModule> modules;
  final Map<String, Map<String, bool>> matrix;

  const PermissionMatrixResponse({
    required this.roles,
    required this.managedRoles,
    required this.modules,
    required this.matrix,
  });

  factory PermissionMatrixResponse.fromJson(Map<String, dynamic> json) {
    final rawMatrix = json['matrix'] as Map<String, dynamic>? ?? const {};
    final matrix = <String, Map<String, bool>>{};

    rawMatrix.forEach((role, value) {
      final entries = value is Map
          ? value.cast<String, dynamic>()
          : <String, dynamic>{};
      matrix[role] = {
        for (final entry in entries.entries) entry.key: entry.value == true,
      };
    });

    return PermissionMatrixResponse(
      roles: (json['roles'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      managedRoles: (json['managedRoles'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      modules: (json['modules'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => PermissionModule.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
      matrix: matrix,
    );
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'matrix': {
        for (final roleEntry in matrix.entries)
          roleEntry.key: {
            for (final permissionEntry in roleEntry.value.entries)
              permissionEntry.key: permissionEntry.value,
          },
      },
    };
  }
}
