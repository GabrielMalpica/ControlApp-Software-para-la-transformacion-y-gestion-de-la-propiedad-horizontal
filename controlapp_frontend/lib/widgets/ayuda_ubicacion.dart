import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_application_1/service/evidencia_camara_service.dart';
import 'package:flutter_application_1/service/theme.dart';

/// Pasos para dar permiso de ubicación cuando el navegador o el celular ya
/// no vuelve a preguntar (alguien tocó "Bloquear" o "No permitir").
Future<void> mostrarAyudaUbicacion(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cómo activar la ubicación',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (kIsWeb) ...const [
              _Pasos(
                titulo: 'Android (Chrome)',
                pasos: [
                  'Toca el ícono que está a la izquierda de la dirección de la página (candado o ajustes).',
                  'Entra a "Permisos" y deja "Ubicación" en "Permitir".',
                  'Revisa que la ubicación del celular esté encendida: desliza desde arriba y toca "Ubicación".',
                ],
              ),
              _Pasos(
                titulo: 'iPhone (Safari)',
                pasos: [
                  'Toca "aA" en la barra de la dirección y luego "Configuración del sitio web".',
                  'En "Ubicación" elige "Permitir".',
                  'Si no aparece: Ajustes > Privacidad y seguridad > Localización. Actívala y en "Sitios web de Safari" elige "Al usar la app".',
                ],
              ),
            ] else
              const _Pasos(
                titulo: 'En el celular',
                pasos: [
                  'Abre Ajustes > Aplicaciones > ControlApp > Permisos.',
                  'En "Ubicación" elige "Permitir mientras se usa la app".',
                  'Revisa que la ubicación del celular esté encendida.',
                ],
              ),
            const Text(
              'Después vuelve a ControlApp y toca "Intentar de nuevo".',
              style: TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Pasos extends StatelessWidget {
  const _Pasos({required this.titulo, required this.pasos});

  final String titulo;
  final List<String> pasos;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (var i = 0; i < pasos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${i + 1}. ${pasos[i]}'),
            ),
        ],
      ),
    );
  }
}

/// Aviso en los cierres de tarea cuando el permiso de ubicación está negado:
/// las fotos se pueden agregar igual, pero su marca de agua quedará sin
/// dirección ni distancia al conjunto. No aparece mientras haya permiso.
class AvisoUbicacionEvidencias extends StatelessWidget {
  const AvisoUbicacionEvidencias({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EvidenciaCamara.ubicacionNegada,
      builder: (context, negada, _) {
        if (!negada) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_off_rounded, color: Colors.orange),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Sin permiso de ubicación: tus fotos quedarán sin dirección en la marca de agua.',
                ),
              ),
              TextButton(
                onPressed: () async {
                  await mostrarAyudaUbicacion(context);
                  EvidenciaCamara.precalentarUbicacion();
                },
                child: const Text('Activar'),
              ),
            ],
          ),
        );
      },
    );
  }
}
