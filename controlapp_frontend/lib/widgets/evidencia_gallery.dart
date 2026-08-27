import 'package:flutter/material.dart';

import '../service/app_constants.dart';
import '../service/session_service.dart';
import '../utils/evidence_utils.dart';

/// Carga una imagen probando, en orden, cada URL candidata en [urls].
/// Al fallar una URL (por ejemplo un enlace de Drive que no responde con
/// una imagen directa) reintenta con la siguiente hasta agotar la lista.
class EvidenceImage extends StatefulWidget {
  final List<String> urls;
  final BoxFit fit;
  final Widget fallback;

  const EvidenceImage({
    super.key,
    required this.urls,
    required this.fit,
    required this.fallback,
  });

  @override
  State<EvidenceImage> createState() => _EvidenceImageState();
}

class _EvidenceImageState extends State<EvidenceImage> {
  int _index = 0;
  bool _advanceScheduled = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await SessionService().getToken();
    if (!mounted) return;
    setState(() => _token = token);
  }

  void _tryNext() {
    if (_advanceScheduled) return;
    _advanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _index++;
        _advanceScheduled = false;
      });
    });
  }

  @override
  void didUpdateWidget(covariant EvidenceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrls = widget.urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();

    if (cleanUrls.isEmpty || _index >= cleanUrls.length) {
      return widget.fallback;
    }

    // El proxy de evidencias vive en nuestro propio backend y requiere el
    // bearer token de sesión; las URLs externas (si las hay) no lo llevan.
    final url = cleanUrls[_index];
    final needsAuth = url.startsWith(AppConstants.baseUrl);
    if (needsAuth && _token == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Image.network(
      url,
      fit: widget.fit,
      headers: needsAuth ? {'Authorization': 'Bearer $_token'} : null,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (_, __, ___) {
        _tryNext();
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}

void mostrarEvidenciaPreview(BuildContext context, List<String> urls) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Evidencia',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: InteractiveViewer(
                child: Container(
                  width: double.infinity,
                  height: 500,
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: EvidenceImage(
                    urls: urls,
                    fit: BoxFit.contain,
                    fallback: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Muestra las evidencias de una tarea como miniaturas; al tocarlas abre
/// una previsualización ampliada. Los archivos que no son imágenes se
/// muestran como un chip descargable/enlazable.
class EvidenciaGallery extends StatelessWidget {
  final List<String> evidencias;

  const EvidenciaGallery({super.key, required this.evidencias});

  @override
  Widget build(BuildContext context) {
    final items = evidencias
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (items.isEmpty) {
      return const Text('Sin evidencias', style: TextStyle(fontSize: 13));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((raw) {
        final candidates = evidenceUrlCandidates(raw);
        final isImg = isLikelyImageEvidence(raw);

        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.grey.shade50,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: candidates.isEmpty
                ? null
                : () => mostrarEvidenciaPreview(context, candidates),
            child: isImg
                ? EvidenceImage(
                    urls: candidates,
                    fit: BoxFit.cover,
                    fallback: Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.insert_drive_file_outlined,
                      color: Colors.grey.shade700,
                    ),
                  ),
          ),
        );
      }).toList(),
    );
  }
}
