import 'package:flutter/material.dart';
import '../../model/usuario_model.dart';
import '../../service/theme.dart';

class DetalleUsuarioPage extends StatelessWidget {
  final Usuario usuario;

  const DetalleUsuarioPage({super.key, required this.usuario});

  String _prettyEnum(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final withSpaces = raw.toLowerCase().replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          'Detalle usuario - ${usuario.nombre}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ───────────── RESUMEN PRINCIPAL ─────────────
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppTheme.primary.withOpacity(0.1),
                      child: Text(
                        usuario.nombre.isNotEmpty
                            ? usuario.nombre[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 24,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
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
                          const SizedBox(height: 4),
                          Text(
                            'Rol: ${_prettyEnum(usuario.rol)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cédula: ${usuario.cedula}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ───────────── DATOS DE CONTACTO ─────────────
            _cardSeccion(
              titulo: "Datos de contacto",
              children: [
                _rowDato("Correo", usuario.correo),
                _rowDato("Teléfono", usuario.telefono.toString()),
                _rowDato(
                  "Dirección",
                  (usuario.direccion == null || usuario.direccion!.isEmpty)
                      ? "-"
                      : usuario.direccion!,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ───────────── DATOS PERSONALES ─────────────
            _cardSeccion(
              titulo: "Datos personales",
              children: [
                _rowDato(
                  "Fecha nacimiento",
                  usuario.fechaNacimiento != null
                      ? "${usuario.fechaNacimiento.day}/${usuario.fechaNacimiento.month}/${usuario.fechaNacimiento.year}"
                      : "-",
                ),
                _rowDato(
                  "Estado civil",
                  _prettyEnum(usuario.estadoCivil ?? ''),
                ),
                _rowDato("Número de hijos", "${usuario.numeroHijos}"),
                _rowDato(
                  "Padres vivos",
                  usuario.padresVivos == null
                      ? "-"
                      : (usuario.padresVivos! ? "Sí" : "No"),
                ),

                _rowDato("Tipo de sangre", usuario.tipoSangre ?? "-"),
              ],
            ),

            const SizedBox(height: 16),

            // ───────────── SALUD Y SEGURIDAD SOCIAL ─────────────
            _cardSeccion(
              titulo: "Salud y seguridad social",
              children: [
                _rowDato("EPS", usuario.eps ?? "-"),
                _rowDato("Fondo pensiones", usuario.fondoPensiones ?? "-"),
              ],
            ),

            const SizedBox(height: 16),

            // ───────────── DOTACIÓN ─────────────
            _cardSeccion(
              titulo: "Dotación",
              children: [
                _rowDato("Talla camisa", usuario.tallaCamisa ?? "-"),
                _rowDato("Talla pantalón", usuario.tallaPantalon ?? "-"),
                _rowDato("Talla calzado", usuario.tallaCalzado ?? "-"),
              ],
            ),

            const SizedBox(height: 16),

            // ───────────── INFORMACIÓN LABORAL ─────────────
            _cardSeccion(
              titulo: "Información laboral",
              children: [
                _rowDato("Tipo contrato", _prettyEnum(usuario.tipoContrato)),
                _rowDato(
                  "Jornada laboral",
                  _prettyEnum(usuario.jornadaLaboral),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardSeccion({
    required String titulo,
    required List<Widget> children,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _rowDato(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
