import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/inventario/pantalla_material.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';

Usuario _usuario(Rol rol) => Usuario(
      uid: 'u1',
      nombre: 'Ana',
      email: 'a@x.com',
      rol: rol,
      activo: true,
    );

Future<FakeFirebaseFirestore> _montar(
  WidgetTester t,
  Rol rol, {
  String cat = 'guata',
  String unidad = 'kg',
  bool agotandose = false,
  bool conCosto = true,
  List<Override> extra = const [],
}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  await db.collection('materiales').doc('m1').set({
    'nombre': 'Material uno',
    'categoria': cat,
    'unidad': unidad,
    'stockMinimo': 5,
    'existencia': 25,
    'usaRollos': cat == 'tela',
    'marcadoAgotandose': agotandose,
  });
  if (conCosto && cat != 'tela') {
    await db
        .collection('materiales_costos')
        .doc('m1')
        .set({'cantidadComprada': 10, 'costoTotalComprado': 500});
  }
  if (cat == 'tela') {
    await db.collection('rollos').doc('r1').set({
      'materialId': 'm1',
      'codigo': '#4',
      'cantidadInicial': 25,
      'existencia': 25,
      'fechaCompra': Timestamp.fromDate(DateTime(2026, 1, 2)),
    });
    if (conCosto) {
      await db
          .collection('rollos_costos')
          .doc('r1')
          .set({'costoPorUnidad': 80});
    }
  }
  await db.collection('movimientos').add({
    'tipo': 'compra',
    'materialId': 'm1',
    'rolloId': null,
    'cantidad': 10,
    'usuarioId': 'u1',
    'fecha': Timestamp.fromDate(DateTime(2026, 3, 4)),
  });
  await db.collection('movimientos').add({
    'tipo': 'consumo',
    'materialId': 'm1',
    'rolloId': null,
    'cantidad': -3.5,
    'usuarioId': 'u1',
    'fecha': Timestamp.fromDate(DateTime(2026, 3, 5)),
  });
  await t.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      estadoSesionProvider.overrideWith(
          (ref) => Stream.value(SesionActiva(_usuario(rol)))),
      ...extra,
    ],
    child: const MaterialApp(home: PantallaMaterial(materialId: 'm1')),
  ));
  await t.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('empleado ve datos básicos y movimientos con signo', (t) async {
    await _montar(t, Rol.empleado);
    expect(find.text('Material uno'), findsWidgets);
    expect(find.text('Guata'), findsOneWidget);
    expect(find.text('Existencia: 25 kg'), findsOneWidget);
    expect(find.text('Stock mínimo: 5 kg'), findsOneWidget);
    expect(find.text('Últimos movimientos'), findsOneWidget);
    expect(find.text('Compra'), findsOneWidget);
    expect(find.text('Consumo'), findsOneWidget);
    expect(find.text('+10 kg'), findsOneWidget);
    expect(find.text('-3.5 kg'), findsOneWidget);
    expect(find.text('04/03/2026'), findsOneWidget);
  });

  testWidgets('empleado no ve costos ni botones del dueño', (t) async {
    await _montar(t, Rol.empleado);
    expect(find.textContaining('Costo'), findsNothing);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Registrar compra'), findsNothing);
    expect(find.text('Ajuste'), findsNothing);
  });

  testWidgets('empleado nunca lee providers de costo', (t) async {
    var lecturas = 0;
    await _montar(t, Rol.empleado, cat: 'tela', unidad: 'm', extra: [
      costoPromedioProvider.overrideWith((ref, id) {
        lecturas++;
        return Stream.value(null);
      }),
      costoRolloProvider.overrideWith((ref, id) {
        lecturas++;
        return Stream.value(null);
      }),
    ]);
    expect(find.text('#4'), findsOneWidget);
    expect(lecturas, 0);
  });

  testWidgets('Se está acabando marca el material', (t) async {
    final db = await _montar(t, Rol.empleado);
    await t.tap(find.text('Se está acabando'));
    await t.pumpAndSettle();
    final d = await db.collection('materiales').doc('m1').get();
    expect(d.data()!['marcadoAgotandose'], true);
    expect(find.text('Marcado como por acabarse'), findsOneWidget);
  });

  testWidgets('ya marcado: botón deshabilitado', (t) async {
    await _montar(t, Rol.empleado, agotandose: true);
    final b = find.widgetWithText(FilledButton, 'Marcado como por acabarse');
    expect(t.widget<FilledButton>(b).onPressed, isNull);
    expect(find.text('Se está acabando'), findsNothing);
  });

  testWidgets('dueño no ve Se está acabando y ve costo promedio', (t) async {
    await _montar(t, Rol.dueno);
    expect(find.text('Se está acabando'), findsNothing);
    expect(find.text(r'Costo promedio: $50.00 / kg'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Registrar compra'), findsOneWidget);
    expect(find.text('Inventario inicial'), findsOneWidget);
    expect(find.text('Ajuste'), findsOneWidget);
  });

  testWidgets('dueño sin costo ve Sin costo', (t) async {
    await _montar(t, Rol.dueno, conCosto: false);
    expect(find.text('Sin costo'), findsOneWidget);
  });

  testWidgets('tela lista rollos con existencia y costo por metro', (t) async {
    await _montar(t, Rol.dueno, cat: 'tela', unidad: 'm');
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('25 m / 25 m'), findsOneWidget);
    expect(find.text(r'$80.00 / m'), findsOneWidget);
  });

  testWidgets('tela: rollo sin costo ve Sin costo', (t) async {
    await _montar(t, Rol.dueno, cat: 'tela', unidad: 'm', conCosto: false);
    expect(find.text('Sin costo'), findsWidgets);
  });

  testWidgets('empleado ve rollo sin costo', (t) async {
    await _montar(t, Rol.empleado, cat: 'tela', unidad: 'm');
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('25 m / 25 m'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
  });
}
