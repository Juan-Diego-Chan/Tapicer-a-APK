import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/compras/pantalla_lista_compras.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';
import 'package:tapiceria/funciones/inventario/servicio_inventario.dart';

const _dueno = Usuario(
  uid: 'dueno1',
  nombre: 'Ana',
  email: 'a@x.com',
  rol: Rol.dueno,
  activo: true,
);

Map<String, dynamic> _mat(String nombre, double existencia, double minimo,
        {bool marcado = false}) =>
    {
      'nombre': nombre,
      'categoria': 'guata',
      'unidad': 'kg',
      'stockMinimo': minimo,
      'existencia': existencia,
      'usaRollos': false,
      'marcadoAgotandose': marcado,
    };

Future<FakeFirebaseFirestore> _montar(
  WidgetTester t,
  Map<String, Map<String, dynamic>> materiales,
) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  for (final e in materiales.entries) {
    await db.collection('materiales').doc(e.key).set(e.value);
  }
  await t.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      estadoSesionProvider
          .overrideWith((ref) => Stream.value(const SesionActiva(_dueno))),
      servicioInventarioProvider
          .overrideWithValue(ServicioInventario(db, 'dueno1')),
    ],
    child: const MaterialApp(home: PantallaListaCompras()),
  ));
  await t.pumpAndSettle();
  return db;
}

void main() {
  final cuatro = {
    'a': _mat('A', 2, 5),
    'b': _mat('B', 5, 5),
    'c': _mat('C', 50, 5, marcado: true),
    'd': _mat('D', -1, 0),
  };

  testWidgets('muestra solo los que necesitan compra, marcados primero',
      (t) async {
    await _montar(t, cuatro);
    expect(find.text('B'), findsNothing);
    final ys = [for (final n in ['C', 'A', 'D']) t.getTopLeft(find.text(n)).dy];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
    expect(find.text('Hay 2 kg · mínimo 5 kg'), findsOneWidget);
    expect(find.text('Marcado por un empleado'), findsOneWidget);
    expect(find.text('Registrar compra'), findsNWidgets(3));
  });

  testWidgets('lista vacía', (t) async {
    await _montar(t, {'b': _mat('B', 5, 5)});
    expect(find.text('No hace falta comprar nada'), findsOneWidget);
  });

  testWidgets('registrar compra de C la quita de la lista', (t) async {
    await _montar(t, cuatro);
    final fila = find.ancestor(
        of: find.text('C'), matching: find.byType(ListTile));
    await t.tap(find.descendant(
        of: fila, matching: find.text('Registrar compra')));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Cantidad (kg)'), '10');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Precio total pagado'), '100');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('C'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });
}
