import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/service/theme.dart';

class DetalleUsuarioPage extends StatelessWidget {
  final Usuario usuario;

  const DetalleUsuarioPage({super.key, required this.usuario});

  String _prettyEnum(String? raw) {
    if (raw == null || raw.isEmpty) return "-";
    final withSpaces = raw.toLowerCase().replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  Widget _rowDato(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? "-" : value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardSeccion({
    required String titulo,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
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
          "Detalle usuario",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ───────── RESUMEN PRINCIPAL ─────────
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppTheme.primary.withOpacity(0.1),
                      child: Icon(Icons.person, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            usuario.nombre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Rol: ${_prettyEnum(usuario.rol)}",
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Cédula: ${usuario.cedula}",
                            style: const TextStyle(fontSize: 13),
                          ),

                          // ✅ NUEVO: Estado activo/inactivo (resumen)
                          const SizedBox(height: 4),
                          Text(
                            'Estado: ${usuario.activo ? "Activo" : "Inactivo"}',
                            style: TextStyle(
                              fontSize: 13,
                              color: usuario.activo ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ───────── CUENTA (OPCIONAL PERO RECOMENDADO) ─────────
            _cardSeccion(
              titulo: "Cuenta",
              children: [
                _rowDato("Rol", _prettyEnum(usuario.rol)),
                _rowDato("Estado", usuario.activo ? "Activo" : "Inactivo"),
                _rowDato("Cédula", usuario.cedula),
                _rowDato("Correo", usuario.correo),
              ],
            ),

            const SizedBox(height: 12),

            // ───────── INFORMACIÓN PERSONAL ─────────
            _cardSeccion(
              titulo: "Información personal",
              children: [
                _rowDato("Teléfono", usuario.telefono.toString()),
                _rowDato("Dirección", usuario.direccion ?? "-"),
                _rowDato(
                  "Fecha nacimiento",
                  usuario.fechaNacimiento == null
                      ? "-"
                      : "${usuario.fechaNacimiento!.day}/${usuario.fechaNacimiento!.month}/${usuario.fechaNacimiento!.year}",
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ───────── INFORMACIÓN FAMILIAR Y SALUD ─────────
            _cardSeccion(
              titulo: "Información familiar y salud",
              children: [
                _rowDato("Estado civil", _prettyEnum(usuario.estadoCivil)),
                _rowDato(
                  "Número de hijos",
                  usuario.numeroHijos == null ? "-" : "${usuario.numeroHijos}",
                ),
                _rowDato(
                  "Padres vivos",
                  (usuario.padresVivos == null)
                      ? "-"
                      : (usuario.padresVivos! ? "Sí" : "No"),
                ),
                _rowDato("Tipo de sangre", _prettyEnum(usuario.tipoSangre)),
                _rowDato("EPS", _prettyEnum(usuario.eps)),
                _rowDato(
                  "Fondo pensiones",
                  _prettyEnum(usuario.fondoPensiones),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ───────── INFORMACIÓN LABORAL ─────────
            _cardSeccion(
              titulo: "Información laboral",
              children: [
                // (Opcional) también mostrar activo aquí
                _rowDato("Usuario activo", usuario.activo ? "Sí" : "No"),

                _rowDato("Tipo contrato", _prettyEnum(usuario.tipoContrato)),
                _rowDato(
                  "Jornada laboral",
                  _prettyEnum(usuario.jornadaLaboral),
                ),

                // ✅ NUEVO: patrón jornada
                _rowDato("Patrón jornada", _prettyEnum(usuario.patronJornada)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
