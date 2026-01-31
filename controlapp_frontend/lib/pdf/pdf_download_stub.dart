Future<void> downloadPdfWeb(List<int> bytes, String filename) async {
  // En móvil/desktop NO descargamos así. Se maneja con Printing.layoutPdf.
  throw UnsupportedError('downloadPdfWeb solo funciona en Web');
}