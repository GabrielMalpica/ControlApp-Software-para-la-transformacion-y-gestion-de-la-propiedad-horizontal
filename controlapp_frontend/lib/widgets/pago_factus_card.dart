import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/commerce_clay.dart';
import 'package:intl/intl.dart';

/// QR de Factus Pay: metodo de pago por defecto. El pago se confirma solo
/// (aviso de Factus), así que al principio solo se espera; "Ya pagué" aparece
/// como respaldo pasados kEsperaVerificacionManual, y "Generar código nuevo"
/// si el actual falló o venció.
class PagoFactusCard extends StatelessWidget {
  const PagoFactusCard({
    super.key,
    required this.pago,
    required this.money,
    required this.busy,
    required this.error,
    required this.onVerificar,
    required this.onGenerarNuevo,
    this.titulo = 'Pagar',
    this.textoGenerar = 'Generar código nuevo',
  });

  final PagoCobroInfo? pago;
  final NumberFormat money;
  final bool busy;
  final String? error;
  final VoidCallback onVerificar;
  final VoidCallback onGenerarNuevo;

  /// Título de la tarjeta ("Pagar", "Pagar saldo").
  final String titulo;

  /// Botón cuando aún no hay código o el anterior venció.
  final String textoGenerar;

  @override
  Widget build(BuildContext context) {
    final qrBytes = pago?.qrBytes;
    final vencidoOFallo = pago != null && (pago!.vencidoLocal || pago!.fallo);

    return CommerceClayCard(
      color: pago != null && pago!.fallo
          ? CommerceClayTokens.orangeSoft
          : CommerceClayTokens.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.qr_code_2_rounded, color: AppTheme.primaryDark),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Escanea el código desde tu app bancaria o Nequi.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (pago != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Monto: ${money.format(pago!.montoEsperado)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (!vencidoOFallo && pago!.expiraLocalEn != null)
              Text(
                'Puedes pagar este código hasta el '
                '${DateFormat('dd/MM/yyyy · h:mm a').format(pago!.expiraLocalEn!.toLocal())}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: 12),
          if (error != null) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppTheme.red,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppTheme.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (qrBytes != null && !vencidoOFallo)
            Column(
              children: <Widget>[
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      qrBytes,
                      height: 220,
                      width: 220,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (pago!.brebKey != null)
                  LlaveBrebRow(
                    llave: pago!.brebKey!,
                    monto: money.format(pago!.montoEsperado),
                  ),
              ],
            )
          else if (vencidoOFallo)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                pago!.fallo
                    ? 'El pago no se pudo confirmar con este código.'
                    : 'Este código ya venció.',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.red,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: _accion()),
        ],
      ),
    );
  }

  Widget _accion() {
    final pago = this.pago;
    if (pago == null) {
      // No se pudo traer ni generar el código: reintentar.
      if (error == null) return const SizedBox.shrink();
      return FilledButton.icon(
        onPressed: busy ? null : onGenerarNuevo,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Intentar de nuevo'),
      );
    }
    if (pago.vencidoLocal || pago.fallo) {
      return FilledButton.icon(
        onPressed: busy ? null : onGenerarNuevo,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(textoGenerar),
      );
    }
    // Recién generado: el pago se confirma solo; "Ya pagué" (consultar a
    // mano) solo aparece como respaldo si pasado un rato no se confirmó.
    if (!pago.puedeVerificarManual(DateTime.now())) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Esperando tu pago…'),
        ],
      );
    }
    return FilledButton.icon(
      onPressed: busy ? null : onVerificar,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check_circle_outline_rounded),
      label: Text(busy ? 'Verificando…' : 'Ya pagué'),
    );
  }
}

/// Alternativa al QR: transferir a la llave Bre-B del código. Solo sirve por
/// el monto exacto y mientras el código esté vigente.
class LlaveBrebRow extends StatelessWidget {
  const LlaveBrebRow({super.key, required this.llave, required this.monto});

  final String llave;
  final String monto;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'O transfiere exactamente $monto a esta llave Bre-B:',
            style: textTheme.bodySmall,
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  llave,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Copiar llave',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: llave));
                  if (!context.mounted) return;
                  AppFeedback.showInfo(
                    context,
                    title: 'Llave copiada',
                    message:
                        'Pégala en tu app bancaria y paga el monto exacto.',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
