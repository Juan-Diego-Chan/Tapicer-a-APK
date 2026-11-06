import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/funciones/auth/pantalla_inicio_sesion.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';

class _Falso implements ServicioSesion {
  _Falso(this.alIniciar);
  final Future<void> Function() alIniciar;
  @override
  Future<void> iniciarSesion(String email, String contrasena) => alIniciar();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _app(ServicioSesion s) => ProviderScope(
      overrides: [servicioSesionProvider.overrideWithValue(s)],
      child: const MaterialApp(home: PantallaInicioSesion()),
    );

void main() {
  testWidgets('correo vacío muestra error', (t) async {
    await t.pumpWidget(_app(_Falso(() async {})));
    await t.tap(find.text('Entrar'));
    await t.pump();
    expect(find.text('Escribe tu correo'), findsOneWidget);
  });

  testWidgets('muestra el mensaje de ErrorSesion', (t) async {
    await t.pumpWidget(_app(_Falso(() async => throw const ErrorSesion(
        'Se necesita internet para iniciar sesión por primera vez'))));
    await t.enterText(find.byType(TextFormField).first, 'a@b.c');
    await t.enterText(find.byType(TextFormField).last, 'secreto');
    await t.tap(find.text('Entrar'));
    await t.pumpAndSettle();
    expect(
        find.text('Se necesita internet para iniciar sesión por primera vez'),
        findsOneWidget);
  });

  testWidgets('botón deshabilitado mientras espera', (t) async {
    final c = Completer<void>();
    await t.pumpWidget(_app(_Falso(() => c.future)));
    await t.enterText(find.byType(TextFormField).first, 'a@b.c');
    await t.enterText(find.byType(TextFormField).last, 'secreto');
    await t.tap(find.text('Entrar'));
    await t.pump();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    c.complete();
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
