import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/inventario/pantalla_inventario.dart';

Usuario _usuario(Rol rol) => Usuario(
      uid: 'u1',
      nombre: 'Ana',
      email: 'a@x.com',
      rol: rol,
      activo: true,
    );

Map<String, dynamic> _mat(String nombre, String cat, String unidad,
        double existencia, double minimo) =>
    {
      'nombre': nombre,
      'categoria': cat,
      'unidad': unidad,
      'stockMinimo': minimo,
      'existencia': existencia,
      'usaRollos': cat == 'tela',
      'marcadoAgotandose': false,
    };

Future<void> _montar(WidgetTester t, Rol rol) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  await db
      .collection('materiales')
      .doc('m1')
      .set(_mat('Lino gris', 'tela', 'm', -1.5, 5));
  await db
      .collection('materiales')
      .doc('m2')
      .set(_mat('Guata fina', 'guata', 'kg', 20, 5));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const PantallaInventario()),
    GoRoute(path: '/inventario/:id', builder: (_, _) => const Text('detalle')),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      estadoSesionProvider.overrideWith(
          (ref) => Stream.value(SesionActiva(_usuario(rol)))),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('empleado no ve Agregar material', (t) async {
    await _montar(t, Rol.empleado);
    expect(find.text('Agregar material'), findsNothing);
  });

  testWidgets('dueño ve Agregar material', (t) async {
    await _montar(t, Rol.dueno);
    expect(find.text('Agregar material'), findsOneWidget);
  });

  testWidgets('agrupa por categoría y marca existencia negativa en rojo',
      (t) async {
    await _montar(t, Rol.empleado);
    expect(find.text('Tela'), findsOneWidget);
    expect(find.text('Guata'), findsOneWidget);
    final error = Theme.of(t.element(find.text('-1.5 m'))).colorScheme.error;
    expect(t.widget<Text>(find.text('-1.5 m')).style?.color, error);
    expect(t.widget<Text>(find.text('20 kg')).style?.color, isNot(error));
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  testWidgets('tocar una fila abre el detalle', (t) async {
    await _montar(t, Rol.empleado);
    await t.tap(find.text('Lino gris'));
    await t.pumpAndSettle();
    expect(find.text('detalle'), findsOneWidget);
  });
}
