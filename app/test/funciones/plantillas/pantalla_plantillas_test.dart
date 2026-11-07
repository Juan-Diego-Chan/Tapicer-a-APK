import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/inventario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';
import 'package:tapiceria/funciones/plantillas/pantalla_plantillas.dart';

Material _mat(String id, String nombre, Unidad u) => Material(
  id: id,
  nombre: nombre,
  categoria: Categoria.otros,
  unidad: u,
  stockMinimo: 0,
  existencia: 0,
  usaRollos: false,
  marcadoAgotandose: false,
);

Future<FakeFirebaseFirestore> _montar(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        materialesProvider.overrideWith(
          (ref) => Stream.value([
            _mat('m1', 'Tela', Unidad.m),
            _mat('m2', 'Guata', Unidad.kg),
          ]),
        ),
      ],
      child: const MaterialApp(home: PantallaPlantillas()),
    ),
  );
  await t.pumpAndSettle();
  return db;
}

Future<void> _elegirMaterial(WidgetTester t, int i, String nombre) async {
  await t.tap(find.byKey(Key('material-$i')));
  await t.pumpAndSettle();
  await t.tap(find.text(nombre).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('lista vacía muestra el aviso', (t) async {
    await _montar(t);
    expect(find.text('Aún no hay plantillas'), findsOneWidget);
  });

  testWidgets('crea una plantilla con dos líneas', (t) async {
    final db = await _montar(t);
    await t.tap(find.text('Nueva plantilla'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Tipo de mueble'),
      'Sillón 3 plazas',
    );
    await t.tap(find.text('Agregar material'));
    await t.pumpAndSettle();
    await _elegirMaterial(t, 0, 'Tela');
    await t.enterText(find.byKey(const Key('cantidad-0')), '6');
    await t.tap(find.text('Agregar material'));
    await t.pumpAndSettle();
    await _elegirMaterial(t, 1, 'Guata');
    await t.enterText(find.byKey(const Key('cantidad-1')), '1,5');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    final docs = (await db.collection('plantillas').get()).docs;
    expect(docs.single.data()['tipoMueble'], 'Sillón 3 plazas');
    final lineas = docs.single.data()['lineas'] as List;
    expect(lineas.length, 2);
    expect(lineas[0]['materialId'], 'm1');
    expect(lineas[0]['cantidad'], 6);
    expect(lineas[1]['materialId'], 'm2');
    expect(lineas[1]['cantidad'], 1.5);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Sillón 3 plazas'), findsOneWidget);
    expect(find.text('2 materiales'), findsOneWidget);
  });

  testWidgets('sin líneas muestra el error', (t) async {
    final db = await _montar(t);
    await t.tap(find.text('Nueva plantilla'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Tipo de mueble'),
      'Silla',
    );
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Agrega al menos un material'), findsOneWidget);
    expect((await db.collection('plantillas').get()).docs, isEmpty);
  });

  testWidgets('tipo vacío y cantidad inválida muestran errores', (t) async {
    await _montar(t);
    await t.tap(find.text('Nueva plantilla'));
    await t.pumpAndSettle();
    await t.tap(find.text('Agregar material'));
    await t.pumpAndSettle();
    await _elegirMaterial(t, 0, 'Tela');
    await t.enterText(find.byKey(const Key('cantidad-0')), '0');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe el tipo de mueble'), findsOneWidget);
    expect(find.text('Escribe una cantidad mayor a 0'), findsOneWidget);
  });

  testWidgets('material repetido muestra el error', (t) async {
    final db = await _montar(t);
    await t.tap(find.text('Nueva plantilla'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Tipo de mueble'),
      'Silla',
    );
    for (var i = 0; i < 2; i++) {
      await t.tap(find.text('Agregar material'));
      await t.pumpAndSettle();
      await _elegirMaterial(t, i, 'Tela');
      await t.enterText(find.byKey(Key('cantidad-$i')), '2');
    }
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Ese material ya está en la plantilla'), findsOneWidget);
    expect((await db.collection('plantillas').get()).docs, isEmpty);
  });

  testWidgets('borrar pide confirmación', (t) async {
    final db = await _montar(t);
    await db.collection('plantillas').doc('p1').set({
      'tipoMueble': 'Silla',
      'lineas': [
        {'materialId': 'm1', 'cantidad': 2},
      ],
    });
    await t.pumpAndSettle();
    await t.tap(find.text('Silla'));
    await t.pumpAndSettle();
    await t.tap(find.text('Borrar'));
    await t.pumpAndSettle();
    expect(find.text('¿Borrar la plantilla Silla?'), findsOneWidget);
    await t.tap(find.text('Borrar').last);
    await t.pumpAndSettle();
    expect((await db.collection('plantillas').get()).docs, isEmpty);
  });
}
