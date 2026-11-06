import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tapiceria/app.dart';

void main() {
  testWidgets('TapiceriaApp muestra la ruta inicial', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Text('ok')),
      ],
    );
    await tester.pumpWidget(TapiceriaApp(router: router));
    await tester.pumpAndSettle();
    expect(find.text('ok'), findsOneWidget);
  });
}
