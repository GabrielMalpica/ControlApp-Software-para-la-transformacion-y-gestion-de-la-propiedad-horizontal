class AuthUser {
  final String id;
  final String nombre;
  final String correo;
  final String rol;
  final String empresaId;
  final List<String> permissions;

  AuthUser({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    this.empresaId = '',
    this.permissions = const [],
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      correo: json['correo']?.toString() ?? '',
      rol: json['rol']?.toString() ?? '',
      empresaId: json['empresaId']?.toString() ?? '',
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class LoginResponse {
  final String token;
  final AuthUser user;

  LoginResponse({required this.token, required this.user});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token']?.toString() ?? '',
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
