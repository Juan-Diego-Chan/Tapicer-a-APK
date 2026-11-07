import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/trabajo/pantalla_trabajo.dart';

const _usuario = Usuario(
  uid: 'u1',
  nombre: 'Ana',
  email: 'a@x.com',
  rol: Rol.empleado,
  activo: true,
);

Future<void> _pedido(
    FakeFirebaseFirestore db, String id, String cliente, DateTime estimada) {
  return db.collection('pedidos').doc(id).set({
    'folio': 'F-$id',
    'clienteId': 'c1',
    'cliente': {'nombre': cliente, 'telefono': '555', 'direccion': ''},
    'entrega': 'recoge',
    'envio': 0,
    'comentarios': '',
    'fechaIngreso': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'fechaEstimada': Timestamp.fromDate(estimada),
    'estado': 'recibido',
    'creadoPor': 'u1',
  });
}

Future<void> _mueble(FakeFirebaseFirestore db, String pedido, String id,
    String tipoTrabajo, String tipoMueble, String estado) {
  return db
      .collection('pedidos')
      .doc(pedido)
      .collection('muebles')
      .doc(id)
      .set({
    'tipoTrabajo': tipoTrabajo,
    'tipoMueble': tipoMueble,
    'plantillaId': null,
    'precio': 100,
    'comentarios': '',
    'estado': estado,
  });
}

Future<void> _montar(WidgetTester t, FakeFirebaseFirestore db,
    {TipoTrabajo tipo = TipoTrabajo.fabricacion}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => PantallaTrabajo(tipo: tipo)),
    GoRoute(
      path: '/pedidos/:id/muebles/:muebleId',
      builder: (_, s) => Text(
          'mueble ${s.pathParameters['id']}/${s.pathParameters['muebleId']}'),
    ),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      estadoSesionProvider
          .overrideWith((ref) => Stream.value(const SesionActiva(_usuario))),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Fabricación muestra solo fabricación activa, por fecha estimada',
      (t) async {
    final db = FakeFirebaseFirestore();
    await _pedido(db, 'p1', 'Luis', DateTime(2026, 3, 10));
    await _pedido(db, 'p2', 'María', DateTime(2026, 3, 1));
    await _mueble(db, 'p1', 'm1', 'fabricacion', 'Comedor', 'recibido');
    await _mueble(db, 'p2', 'm2', 'fabricacion', 'Sillón', 'en_proceso');
    await _mueble(db, 'p2', 'm3', 'reparacion', 'Silla', 'recibido');
    await _mueble(db, 'p1', 'm4', 'fabricacion', 'Banco', 'entregado');
    await _montar(t, db);

    expect(find.text('Fabricación'), findsOneWidget);
    expect(find.text('Sillón'), findsOneWidget);
    expect(find.text('Comedor'), findsOneWidget);
    expect(find.text('Silla'), findsNothing);
    expect(find.text('Banco'), findsNothing);
    expect(find.text('Entrega: 01/03/2026'), findsOneWidget);
    expect(find.text('María'), findsOneWidget);
    expect(find.text('F-p2'), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
    expect(t.getTopLeft(find.text('Sillón')).dy,
        lessThan(t.getTopLeft(find.text('Comedor')).dy));
  });

  testWidgets('tocar una fila abre el mueble', (t) async {
    final db = FakeFirebaseFirestore();
    await _pedido(db, 'p1', 'Luis', DateTime(2026, 3, 10));
    await _mueble(db, 'p1', 'm1', 'fabricacion', 'Comedor', 'recibido');
    await _montar(t, db);

    await t.tap(find.text('Comedor'));
    await t.pumpAndSettle();
    expect(find.text('mueble p1/m1'), findsOneWidget);
  });

  testWidgets('mueble sin pedido activo: "Pedido sin cargar" al final',
      (t) async {
    final db = FakeFirebaseFirestore();
    await _pedido(db, 'p1', 'Luis', DateTime(2026, 3, 10));
    await _mueble(db, 'p1', 'm1', 'fabricacion', 'Comedor', 'recibido');
    await _mueble(db, 'huerfano', 'm9', 'fabricacion', 'Sofá', 'recibido');
    await _montar(t, db);

    expect(find.text('Pedido sin cargar'), findsOneWidget);
    expect(t.getTopLeft(find.text('Sofá')).dy,
        greaterThan(t.getTopLeft(find.text('Comedor')).dy));
  });

  testWidgets('lista vacía', (t) async {
    await _montar(t, FakeFirebaseFirestore(), tipo: TipoTrabajo.reparacion);
    expect(find.text('No hay muebles en Reparación'), findsOneWidget);
  });
}
