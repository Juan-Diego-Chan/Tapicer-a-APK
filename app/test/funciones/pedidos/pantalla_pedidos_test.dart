import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/pedidos/pantalla_pedidos.dart';

const _usuario = Usuario(
  uid: 'u1',
  nombre: 'Ana',
  email: 'a@x.com',
  rol: Rol.empleado,
  activo: true,
);

Future<void> _pedido(FakeFirebaseFirestore db, String id, String folio,
    String estado, DateTime estimada) {
  return db.collection('pedidos').doc(id).set({
    'folio': folio,
    'clienteId': 'c1',
    'cliente': {'nombre': 'Cliente $folio', 'telefono': '555', 'direccion': ''},
    'entrega': 'recoge',
    'envio': 0,
    'comentarios': '',
    'fechaIngreso': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'fechaEstimada': Timestamp.fromDate(estimada),
    'estado': estado,
    'creadoPor': 'u1',
  });
}

Future<void> _montar(WidgetTester t, FakeFirebaseFirestore db) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const PantallaPedidos()),
    GoRoute(
        path: '/pedidos/nuevo', builder: (_, _) => const Text('pantalla nuevo')),
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

String _f(DateTime d) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year}';
}

void main() {
  testWidgets('un pedido activo vencido muestra la fecha en rojo', (t) async {
    final db = FakeFirebaseFirestore();
    final ayer = DateTime.now().subtract(const Duration(days: 3));
    final futuro = DateTime.now().add(const Duration(days: 3));
    await _pedido(db, 'a', '260101-AAAA', 'recibido', ayer);
    await _pedido(db, 'b', '260101-BBBB', 'en_proceso', futuro);
    await _montar(t, db);

    final cs = Theme.of(t.element(find.byType(Scaffold).first)).colorScheme;
    Color? colorDe(String texto) =>
        t.widget<Text>(find.text(texto)).style?.color;
    expect(colorDe('Entrega: ${_f(ayer)}'), cs.error);
    expect(colorDe('Entrega: ${_f(futuro)}'), isNot(cs.error));
    expect(find.text('260101-AAAA'), findsOneWidget);
    expect(find.text('Cliente 260101-AAAA'), findsOneWidget);
    expect(find.text('Recibido'), findsOneWidget);
  });

  testWidgets('un pedido entregado solo aparece en Recientes', (t) async {
    final db = FakeFirebaseFirestore();
    await _pedido(db, 'a', '260101-AAAA', 'entregado', DateTime(2026, 2, 1));
    await _montar(t, db);
    expect(find.text('260101-AAAA'), findsNothing);
    expect(find.text('No hay pedidos activos'), findsOneWidget);

    await t.tap(find.text('Recientes'));
    await t.pumpAndSettle();
    expect(find.text('260101-AAAA'), findsOneWidget);
    expect(find.text('Entregado'), findsOneWidget);
  });

  testWidgets('Recientes vacío y botón Nuevo pedido', (t) async {
    final db = FakeFirebaseFirestore();
    await _montar(t, db);
    await t.tap(find.text('Recientes'));
    await t.pumpAndSettle();
    expect(find.text('No hay pedidos'), findsOneWidget);

    await t.tap(find.text('Nuevo pedido'));
    await t.pumpAndSettle();
    expect(find.text('pantalla nuevo'), findsOneWidget);
  });
}
