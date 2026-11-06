import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/inicio/pantalla_inicio.dart';

Future<void> _montar(WidgetTester t, Rol rol) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      estadoSesionProvider.overrideWith((ref) => Stream.value(SesionActiva(
          Usuario(
              uid: 'u',
              nombre: 'Ana López',
              email: 'a@b.c',
              rol: rol,
              activo: true)))),
    ],
    child: const MaterialApp(home: PantallaInicio()),
  ));
  await t.pump();
}

void main() {
  test('hay 8 entradas', () => expect(entradasMenu.length, 8));

  testWidgets('empleado no ve entradas de dueño', (t) async {
    await _montar(t, Rol.empleado);
    for (final x in ['Contabilidad', 'Lista de compras', 'Usuarios']) {
      expect(find.text(x), findsNothing);
    }
    expect(find.text('Pedidos'), findsOneWidget);
    expect(find.text('Ana López'), findsOneWidget);
  });

  testWidgets('dueño ve las 8', (t) async {
    await _montar(t, Rol.dueno);
    for (final e in entradasMenu) {
      expect(find.text(e.titulo), findsOneWidget);
    }
    expect(find.text('Ana López'), findsOneWidget);
  });
}
