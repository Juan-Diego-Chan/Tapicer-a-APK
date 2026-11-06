import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'nucleo/firebase_init.dart';
import 'nucleo/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await inicializarFirebase();
  await initializeDateFormatting('es_MX');
  runApp(const ProviderScope(child: _Raiz()));
}

class _Raiz extends ConsumerWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      TapiceriaApp(router: ref.watch(routerProvider));
}
