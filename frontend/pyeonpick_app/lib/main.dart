import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  runApp(const PyeonPickApp());
}
