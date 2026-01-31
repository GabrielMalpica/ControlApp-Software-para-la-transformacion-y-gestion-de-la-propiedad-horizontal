class AuthUser {
  final String id;
  final String nombre;
  final String correo;
  final String rol;

  AuthUser({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      correo: json['correo']?.toString() ?? '',
      rol: json['rol']?.toString() ?? '',
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
