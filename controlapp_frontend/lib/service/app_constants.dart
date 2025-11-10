class AppConstants {
  static const String baseUrl = "http://localhost:3000";
  static const String apiUrl = baseUrl; // 👈 alias compatible

  static const String conjuntos = "$baseUrl/conjuntos";
  static const String ping = "$baseUrl/ping";

  static String operariosPorConjunto(String nit) => "$conjuntos/$nit/operarios";
  static String administradorPorConjunto(String nit) => "$conjuntos/$nit/administrador";
  static String maquinariaPorConjunto(String nit) => "$conjuntos/$nit/maquinaria";
  static String inventarioPorConjunto(String nit) => "$conjuntos/$nit/inventario";
}
