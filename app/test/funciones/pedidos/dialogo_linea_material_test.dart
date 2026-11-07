import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/pedidos/dialogo_dias.dart';
import 'package:tapiceria/funciones/pedidos/dialogo_linea_material.dart';
import 'package:tapiceria/funciones/usuarios/providers.dart';

Usuario _usuario(Rol rol, String uid) => Usuario(
  uid: uid,
  nombre: uid == 'u1' ? 'Ana' : 'Beto',
  email: 'a@x.com',
  rol: rol,
  activo: true,
);

Future<FakeFirebaseFirestore> _montar(
  WidgetTester t, {
  bool conRollos = true,
  Rol rol = Rol.empleado,
  bool dias = false,
}) async {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  await db.collection('materiales').doc('tela').set({
    'nombre': 'Tela',
    'categoria': 'tela',
    'unidad': 'm',
    'stockMinimo': 5,
    'existencia': 50,
    'usaRollos': true,
    'marcadoAgotandose': false,
  });
  await db.collection('materiales').doc('grapa').set({
    'nombre': 'Grapas',
    'categoria': 'grapas',
    'unidad': 'pza',
    'stockMinimo': 5,
    'existencia': 100,
    'usaRollos': false,
    'marcadoAgotandose': false,
  });
  if (conRollos) {
    await db.collection('rollos').doc('viejo').set({
      'materialId': 'tela',
      'codigo': '#1',
      'cantidadInicial': 20,
      'existencia': 20,
      'fechaCompra': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    await db.collection('rollos').doc('nuevo').set({
      'materialId': 'tela',
      'codigo': '#2',
      'cantidadInicial': 30,
      'existencia': 30,
      'fechaCompra': Timestamp.fromDate(DateTime(2026, 6, 1)),
    });
  }
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        estadoSesionProvider.overrideWith(
          (ref) => Stream.value(SesionActiva(_usuario(rol, 'u1'))),
        ),
        usuariosProvider.overrideWith(
          (ref) => Stream.value([
            _usuario(Rol.dueno, 'u1'),
            _usuario(Rol.empleado, 'u2'),
          ]),
        ),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            // En la app el router ya mantiene viva la sesión.
            ref.watch(estadoSesionProvider);
            return Scaffold(
              body: TextButton(
                onPressed: () => dias
                    ? mostrarDialogoDias(
                        context,
                        pedidoId: 'p1',
                        muebleId: 'm1',
                      )
                    : mostrarDialogoLineaMaterial(
                        context,
                        pedidoId: 'p1',
                        muebleId: 'm1',
                      ),
                child: const Text('abrir'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
  return db;
}

Future<void> _elegirMaterial(WidgetTester t, String nombre) async {
  await t.tap(find.byKey(const Key('material')));
  await t.pumpAndSettle();
  await t.tap(find.text(nombre).last);
  await t.pumpAndSettle();
}

Future<double> _existencia(
  FakeFirebaseFirestore db,
  String c,
  String id,
) async => ((await db.collection(c).doc(id).get()).data()!['existencia'] as num)
    .toDouble();

CollectionReference<Map<String, dynamic>> _lineas(FakeFirebaseFirestore db) =>
    db
        .collection('pedidos')
        .doc('p1')
        .collection('muebles')
        .doc('m1')
        .collection('materiales');

CollectionReference<Map<String, dynamic>> _dias(FakeFirebaseFirestore db) => db
    .collection('pedidos')
    .doc('p1')
    .collection('muebles')
    .doc('m1')
    .collection('dias');

void main() {
  testWidgets('2,5 de tela con el rollo más reciente preseleccionado', (
    t,
  ) async {
    final db = await _montar(t);
    await _elegirMaterial(t, 'Tela');
    expect(find.textContaining('#2 · quedan 30'), findsOneWidget);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Cantidad (m)'),
      '2,5',
    );
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    final ls = await _lineas(db).get();
    expect(ls.size, 1);
    expect(ls.docs.single.data()['cantidad'], 2.5);
    expect(ls.docs.single.data()['rolloId'], 'nuevo');
    expect(await _existencia(db, 'rollos', 'nuevo'), 27.5);
    expect(await _existencia(db, 'rollos', 'viejo'), 20);
  });

  testWidgets('"Lo trajo el cliente" oculta el rollo y no toca la existencia', (
    t,
  ) async {
    final db = await _montar(t);
    await _elegirMaterial(t, 'Tela');
    await t.tap(find.text('Lo trajo el cliente'));
    await t.pumpAndSettle();
    expect(find.textContaining('quedan'), findsNothing);
    await t.enterText(find.widgetWithText(TextFormField, 'Cantidad (m)'), '2');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    final l = (await _lineas(db).get()).docs.single.data();
    expect(l['delCliente'], true);
    expect(l['rolloId'], isNull);
    expect(await _existencia(db, 'rollos', 'nuevo'), 30);
    expect(await _existencia(db, 'materiales', 'tela'), 50);
  });

  testWidgets('tela sin rollos y sin casilla: "Elige el rollo"', (t) async {
    final db = await _montar(t, conRollos: false);
    await _elegirMaterial(t, 'Tela');
    await t.enterText(find.widgetWithText(TextFormField, 'Cantidad (m)'), '2');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Elige el rollo'), findsOneWidget);
    expect((await _lineas(db).get()).size, 0);
  });

  testWidgets('validaciones de material y cantidad', (t) async {
    await _montar(t);
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Elige el material'), findsOneWidget);
    await _elegirMaterial(t, 'Grapas');
    expect(find.textContaining('quedan'), findsNothing);
    expect(find.text('Lo trajo el cliente'), findsOneWidget);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Cantidad (pza)'),
      '0',
    );
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe una cantidad mayor a 0'), findsOneWidget);
  });

  testWidgets('el empleado registra 1,5 días con su uid; 0,3 es error', (
    t,
  ) async {
    final db = await _montar(t, dias: true);
    expect(find.text('Trabajador'), findsNothing);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Días (0.5 = medio día)'),
      '0,3',
    );
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(
      find.text('Escribe días en múltiplos de 0.5, hasta 7'),
      findsOneWidget,
    );
    await t.enterText(
      find.widgetWithText(TextFormField, 'Días (0.5 = medio día)'),
      '1,5',
    );
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    final ds = await _dias(db).get();
    expect(ds.size, 1);
    expect(ds.docs.single.data()['usuarioId'], 'u1');
    expect(ds.docs.single.data()['dias'], 1.5);
  });

  testWidgets('el dueño elige trabajador', (t) async {
    final db = await _montar(t, dias: true, rol: Rol.dueno);
    expect(find.text('Trabajador'), findsOneWidget);
    await t.tap(find.byKey(const Key('trabajador')));
    await t.pumpAndSettle();
    await t.tap(find.text('Beto').last);
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Días (0.5 = medio día)'),
      '1',
    );
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    final ds = await _dias(db).get();
    expect(ds.docs.single.data()['usuarioId'], 'u2');
  });
}
