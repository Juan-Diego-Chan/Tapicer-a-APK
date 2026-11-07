import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/pedidos/pantalla_mueble.dart';
import 'package:tapiceria/funciones/usuarios/providers.dart';

Usuario _usuario(Rol rol) =>
    Usuario(uid: 'u1', nombre: 'Ana', email: 'a@x.com', rol: rol, activo: true);

Future<FakeFirebaseFirestore> _montar(WidgetTester t, Rol rol) async {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  final ped = db.collection('pedidos').doc('p1');
  await ped.set({
    'folio': '260101-P1AB',
    'clienteId': 'c1',
    'cliente': {'nombre': 'José', 'telefono': '', 'direccion': ''},
    'entrega': 'recoge',
    'envio': 0,
    'comentarios': '',
    'fechaIngreso': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'fechaEstimada': Timestamp.fromDate(DateTime(2026, 12, 1)),
    'estado': 'recibido',
    'creadoPor': 'u1',
  });
  final mueble = ped.collection('muebles').doc('m1');
  await mueble.set({
    'tipoTrabajo': 'fabricacion',
    'tipoMueble': 'Sillón',
    'plantillaId': null,
    'precio': 650,
    'comentarios': 'Verde',
    'estado': 'recibido',
    'ultimoCambioId': null,
  });
  await db.collection('materiales').doc('tela').set({
    'nombre': 'Tela',
    'categoria': 'tela',
    'unidad': 'm',
    'stockMinimo': 5,
    'existencia': 47.5,
    'usaRollos': true,
    'marcadoAgotandose': false,
  });
  await db.collection('rollos').doc('r1').set({
    'materialId': 'tela',
    'codigo': '#1',
    'cantidadInicial': 30,
    'existencia': 27.5,
    'fechaCompra': Timestamp.fromDate(DateTime(2026, 1, 1)),
  });
  await mueble.collection('materiales').doc('l1').set({
    'materialId': 'tela',
    'rolloId': 'r1',
    'cantidad': 2.5,
    'delCliente': false,
    'usuarioId': 'u1',
    'fecha': Timestamp.fromDate(DateTime(2026, 2, 1)),
  });
  await mueble.collection('dias').doc('d1').set({
    'usuarioId': 'u1',
    'dias': 1.5,
    'fecha': Timestamp.fromDate(DateTime(2026, 2, 2)),
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        estadoSesionProvider.overrideWith(
          (ref) => Stream.value(SesionActiva(_usuario(rol))),
        ),
        usuariosProvider.overrideWith(
          (ref) => Stream.value([_usuario(Rol.dueno)]),
        ),
      ],
      child: const MaterialApp(
        home: PantallaMueble(pedidoId: 'p1', muebleId: 'm1'),
      ),
    ),
  );
  await t.pumpAndSettle();
  return db;
}

Future<Map<String, dynamic>> _pedido(FakeFirebaseFirestore db) async =>
    (await db.collection('pedidos').doc('p1').get()).data()!;

CollectionReference<Map<String, dynamic>> _sub(
  FakeFirebaseFirestore db,
  String nombre,
) => db
    .collection('pedidos')
    .doc('p1')
    .collection('muebles')
    .doc('m1')
    .collection(nombre);

void main() {
  testWidgets('muestra encabezado, materiales y días', (t) async {
    await _montar(t, Rol.empleado);
    expect(find.textContaining('Sillón'), findsWidgets);
    expect(find.textContaining('260101-P1AB'), findsWidgets);
    expect(find.textContaining('Verde'), findsOneWidget);
    expect(find.text('Tela'), findsOneWidget);
    expect(find.textContaining('2.5 m'), findsOneWidget);
    expect(find.textContaining('Rollo #1'), findsOneWidget);
    expect(find.textContaining('1.5 días'), findsOneWidget);
    expect(find.textContaining('Ana'), findsOneWidget);
  });

  testWidgets('el empleado no ve botones de borrar', (t) async {
    await _montar(t, Rol.empleado);
    expect(find.byTooltip('Borrar línea'), findsNothing);
    expect(find.byTooltip('Borrar días'), findsNothing);
  });

  testWidgets('el dueño borra una línea y la existencia regresa', (t) async {
    final db = await _montar(t, Rol.dueno);
    await t.tap(find.byTooltip('Borrar línea'));
    await t.pumpAndSettle();
    expect(
      find.text('¿Borrar esta línea? La cantidad regresa al inventario.'),
      findsOneWidget,
    );
    await t.tap(find.text('Borrar'));
    await t.pumpAndSettle();
    final r = await db.collection('rollos').doc('r1').get();
    expect(r.data()!['existencia'], 30);
    expect((await _sub(db, 'materiales').get()).size, 0);
  });

  testWidgets('el dueño borra un registro de días', (t) async {
    final db = await _montar(t, Rol.dueno);
    await t.tap(find.byTooltip('Borrar días'));
    await t.pumpAndSettle();
    expect(find.text('¿Borrar este registro de días?'), findsOneWidget);
    await t.tap(find.text('Borrar'));
    await t.pumpAndSettle();
    expect((await _sub(db, 'dias').get()).size, 0);
  });

  testWidgets('tocar Terminado en el único mueble termina el pedido', (
    t,
  ) async {
    final db = await _montar(t, Rol.empleado);
    await t.tap(find.widgetWithText(ChoiceChip, 'Terminado'));
    await t.pumpAndSettle();
    expect((await _pedido(db))['estado'], 'terminado');
  });

  testWidgets('Cancelado pide confirmación', (t) async {
    final db = await _montar(t, Rol.empleado);
    await t.tap(find.widgetWithText(ChoiceChip, 'Cancelado'));
    await t.pumpAndSettle();
    expect((await _pedido(db))['estado'], 'recibido');
    await t.tap(find.text('Sí, cancelar'));
    await t.pumpAndSettle();
    expect((await _pedido(db))['estado'], 'cancelado');
  });
}
