import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/enums/hoja_vida_etiquetas.dart';
import 'package:flutter_application_1/widgets/searchable_select_field.dart';

/// Campos de hoja de vida que comparten crear y editar usuario: ARL, caja de
/// compensación y contacto de emergencia. Todos son opcionales.

/// ARL y caja de compensación, con buscador (hay más de 40 cajas) y opción
/// para dejarlas sin dato.
class ArlCajaCampos extends StatelessWidget {
  final List<String> opcionesArl;
  final List<String> opcionesCaja;
  final String? arl;
  final String? cajaCompensacion;
  final ValueChanged<String?> onArl;
  final ValueChanged<String?> onCajaCompensacion;

  const ArlCajaCampos({
    super.key,
    required this.opcionesArl,
    required this.opcionesCaja,
    required this.arl,
    required this.cajaCompensacion,
    required this.onArl,
    required this.onCajaCompensacion,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SearchableSelectField<String>(
          label: 'ARL (opcional)',
          prefixIcon: const Icon(Icons.health_and_safety_outlined),
          searchHint: 'Buscar ARL',
          value: arl,
          clearLabel: 'Sin ARL registrada',
          options: [
            for (final v in opcionesArl)
              SearchableSelectOption(value: v, label: etiquetaArl(v)),
          ],
          onChanged: onArl,
        ),
        const SizedBox(height: 8),
        SearchableSelectField<String>(
          label: 'Caja de compensación (opcional)',
          prefixIcon: const Icon(Icons.family_restroom_outlined),
          searchHint: 'Buscar caja de compensación',
          value: cajaCompensacion,
          clearLabel: 'Sin caja registrada',
          options: [
            for (final v in opcionesCaja)
              SearchableSelectOption(
                value: v,
                label: etiquetaCajaCompensacion(v),
              ),
          ],
          onChanged: onCajaCompensacion,
        ),
      ],
    );
  }
}

/// Teléfono del contacto de emergencia: opcional; si se escribe, solo
/// números, espacios, `+`, `-` o paréntesis y entre 7 y 15 números (igual
/// que valida el backend).
String? validarTelefonoEmergencia(String? valor) {
  final v = valor?.trim() ?? '';
  if (v.isEmpty) return null;
  if (!RegExp(r'^[0-9+()\s-]+$').hasMatch(v)) {
    return 'Use solo números, espacios, +, - o paréntesis';
  }
  final digitos = v.replaceAll(RegExp(r'\D'), '').length;
  if (digitos < 7 || digitos > 15) return 'Debe tener entre 7 y 15 números';
  return null;
}

/// Texto recortado, o null si quedó vacío (así se borra el dato guardado).
String? textoOpcional(TextEditingController ctrl) {
  final v = ctrl.text.trim();
  return v.isEmpty ? null : v;
}

/// Tarjeta "Contacto de emergencia": nombre, parentesco y teléfono. Si se
/// llena el nombre hay que poner el teléfono, y al revés.
class ContactoEmergenciaCard extends StatelessWidget {
  final TextEditingController nombreCtrl;
  final TextEditingController parentescoCtrl;
  final TextEditingController telefonoCtrl;

  const ContactoEmergenciaCard({
    super.key,
    required this.nombreCtrl,
    required this.parentescoCtrl,
    required this.telefonoCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.contact_phone_outlined, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Contacto de emergencia',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Opcional. A quién llamar si a esta persona le pasa algo.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: nombreCtrl,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              decoration: const InputDecoration(
                labelText: 'Nombre del contacto (opcional)',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty &&
                      telefonoCtrl.text.trim().isNotEmpty
                  ? 'Escriba a quién llamar'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: parentescoCtrl,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              decoration: const InputDecoration(
                labelText: 'Parentesco (opcional)',
                hintText: 'Ej.: madre, esposo, hermana, amigo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: telefonoCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              decoration: const InputDecoration(
                labelText: 'Teléfono del contacto (opcional)',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if ((v ?? '').trim().isEmpty &&
                    nombreCtrl.text.trim().isNotEmpty) {
                  return 'Escriba el teléfono del contacto';
                }
                return validarTelefonoEmergencia(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}
