import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart'; // tu archivo principal o MyApp

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null); // ✅ Inicializa el locale español
  runApp(const MyApp());
}
