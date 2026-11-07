import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/inventario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/inventario/dialogo_movimiento.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';
import 'package:tapiceria/funciones/inventario/servicio_inventario.dart';

class _ServicioSinConexion extends ServicioInventario {
  _ServicioSinConexion(super.db, super.uid);

  @override
  Future<void> registrarCompra({
    required Material material,
    required double cantidad,
    required double precioTotal,
    String? codigoRollo,
    DateTime? fecha,
  }) =>
      Completer<void>().future;
}

Material _mat(String id, Categoria c, Unidad u) => Material(
      id: id,
      nombre: 'Mat $id',
      categoria: c,
      unidad: u,
      stockMinimo: 1,
      existencia: 0,
      usaRollos: c == Categoria.tela,
      marcadoAgotandose: false,
    );

Future<FakeFirebaseFirestore> _montar(
  WidgetTester t,
  Material m,
  TipoCaptura tipo, {
  bool sinConexion = false,
}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  await db.collection('materiales').doc(m.id).set({
    ...m.aMapaAlta(),
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        servicioInventarioProvider.overrideWithValue(sinConexion
            ? _ServicioSinConexion(db, 'dueno1')
            : ServicioInventario(db, 'dueno1')),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  mostrarDialogoMovimiento(context, material: m, tipo: tipo),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  return db;
}

Future<void> _abrir(WidgetTester t) async {
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

Future<void> _rollo(FakeFirebaseFirestore db, String id, String materialId,
    String codigo, double existencia) {
  return db.collection('rollos').doc(id).set({
    'materialId': materialId,
    'codigo': codigo,
    'cantidadInicial': existencia,
    'existencia': existencia,
    'fechaCompra': Timestamp.fromDate(DateTime(2026, 1, int.parse(id))),
  });
}

Future<double> _existencia(
    FakeFirebaseFirestore db, String col, String id) async {
  final d = await db.collection(col).doc(id).get();
  return (d.data()!['existencia'] as num).toDouble();
}

void main() {
  testWidgets('compra de "2,5" con precio 300 suma 2.5', (t) async {
    final db = await _montar(
        t, _mat('m1', Categoria.espuma, Unidad.kg), TipoCaptura.compra);
    await _abrir(t);
    expect(find.text('Registrar compra: Mat m1'), findsOneWidget);
    await t.enterText(
        find.widgetWithText(TextFormField, 'Cantidad (kg)'), '2,5');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Precio total pagado'), '300');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(await _existencia(db, 'materiales', 'm1'), 2.5);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('compra con 0 muestra error y no guarda', (t) async {
    final db = await _montar(
        t, _mat('m1', Categoria.espuma, Unidad.kg), TipoCaptura.compra);
    await _abrir(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Cantidad (kg)'), '0');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Precio total pagado'), '300');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe una cantidad mayor a 0'), findsOneWidget);
    expect((await db.collection('movimientos').get()).docs, isEmpty);
  });

  testWidgets('precio vacío muestra error', (t) async {
    await _montar(
        t, _mat('m1', Categoria.espuma, Unidad.kg), TipoCaptura.compra);
    await _abrir(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Cantidad (kg)'), '1');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe el precio pagado'), findsOneWidget);
  });

  testWidgets('código de rollo precargado con #8', (t) async {
    final m = _mat('t1', Categoria.tela, Unidad.m);
    final db = await _montar(t, m, TipoCaptura.compra);
    await _rollo(db, '1', 't1', '#3', 5);
    await _rollo(db, '2', 't1', '#7', 5);
    await _abrir(t);
    final campo = t.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Código del rollo'));
    expect(campo.controller!.text, '#8');
  });

  testWidgets('carga inicial con costo vacío no crea materiales_costos',
      (t) async {
    final db = await _montar(
        t, _mat('m1', Categoria.guata, Unidad.m), TipoCaptura.inicial);
    await _abrir(t);
    expect(find.text('Inventario inicial: Mat m1'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Cantidad (m)'), '4');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(await _existencia(db, 'materiales', 'm1'), 4);
    expect((await db.collection('materiales_costos').get()).docs, isEmpty);
  });

  testWidgets('ajuste de 0 muestra error', (t) async {
    await _montar(
        t, _mat('m1', Categoria.espuma, Unidad.kg), TipoCaptura.ajuste);
    await _abrir(t);
    await t.enterText(
        find.widgetWithText(TextFormField, 'Cantidad (+ entra, − sale)'), '0');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('El ajuste no puede ser 0'), findsOneWidget);
  });

  testWidgets('ajuste de -1,5 en tela baja el rollo elegido', (t) async {
    final m = _mat('t1', Categoria.tela, Unidad.m);
    final db = await _montar(t, m, TipoCaptura.ajuste);
    await db.collection('materiales').doc('t1').update({'existencia': 10});
    await _rollo(db, '1', 't1', '#1', 10);
    await _abrir(t);
    await t.enterText(
        find.widgetWithText(TextFormField, 'Cantidad (+ entra, − sale)'),
        '-1,5');
    await t.tap(find.byKey(const Key('rollo')));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('#1').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(await _existencia(db, 'rollos', '1'), 8.5);
    expect(await _existencia(db, 'materiales', 't1'), 8.5);
  });

  testWidgets('sin conexión el diálogo cierra igual', (t) async {
    await _montar(t, _mat('m1', Categoria.espuma, Unidad.kg),
        TipoCaptura.compra,
        sinConexion: true);
    await _abrir(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Cantidad (kg)'), '1');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Precio total pagado'), '10');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
