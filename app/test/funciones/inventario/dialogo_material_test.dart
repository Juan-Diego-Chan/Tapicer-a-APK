import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/inventario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/inventario/dialogo_material.dart';

Future<FakeFirebaseFirestore> _montar(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  await t.pumpWidget(
    ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => mostrarDialogoMaterial(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('material sin nombre muestra el error', (t) async {
    final db = await _montar(t);
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe el nombre'), findsOneWidget);
    expect((await db.collection('materiales').get()).docs, isEmpty);
  });

  testWidgets('stock mínimo negativo muestra el error', (t) async {
    await _montar(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Hilo');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Stock mínimo'), '-1');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe un número mayor o igual a 0'), findsOneWidget);
  });

  testWidgets('elegir Tela fija la unidad en Metros (m)', (t) async {
    await _montar(t);
    await t.tap(find.byKey(const Key('categoria')));
    await t.pumpAndSettle();
    await t.tap(find.text('Tela').last);
    await t.pumpAndSettle();
    expect(find.text('Metros (m)'), findsOneWidget);
  });

  testWidgets('guarda un material nuevo y cierra', (t) async {
    final db = await _montar(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Hilo');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Stock mínimo'), '2,5');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    final docs = (await db.collection('materiales').get()).docs;
    expect(docs.single.data()['nombre'], 'Hilo');
    expect(docs.single.data()['stockMinimo'], 2.5);
    expect(find.byType(AlertDialog), findsNothing);
  });

  Future<void> abrirEdicion(WidgetTester t, double existencia) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final m = Material(
      id: 'g1',
      nombre: 'Guata',
      categoria: Categoria.guata,
      unidad: Unidad.kg,
      stockMinimo: 1,
      existencia: existencia,
      usaRollos: false,
      marcadoAgotandose: false,
    );
    await t.pumpWidget(ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(FakeFirebaseFirestore())],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => mostrarDialogoMaterial(context, existente: m),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
  }

  testWidgets('con existencia la unidad queda bloqueada', (t) async {
    await abrirEdicion(t, 5);
    expect(find.text('No se puede cambiar la unidad con existencia'),
        findsOneWidget);
    final dd = t.widget<DropdownButtonFormField<Unidad>>(
        find.byType(DropdownButtonFormField<Unidad>));
    expect(dd.onChanged, isNull);
  });

  testWidgets('sin existencia la unidad se puede cambiar', (t) async {
    await abrirEdicion(t, 0);
    expect(find.text('No se puede cambiar la unidad con existencia'),
        findsNothing);
    final dd = t.widget<DropdownButtonFormField<Unidad>>(
        find.byType(DropdownButtonFormField<Unidad>));
    expect(dd.onChanged, isNotNull);
  });
}
