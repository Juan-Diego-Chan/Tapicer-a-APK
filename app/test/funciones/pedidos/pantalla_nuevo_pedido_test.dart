import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';
import 'package:tapiceria/funciones/pedidos/pantalla_nuevo_pedido.dart';
import 'package:tapiceria/funciones/pedidos/providers.dart';
import 'package:tapiceria/funciones/pedidos/servicio_pedidos.dart';

const _usuario = Usuario(
  uid: 'u1',
  nombre: 'Ana',
  email: 'a@x.com',
  rol: Rol.empleado,
  activo: true,
);

const _jose = Cliente(
  id: 'c1',
  nombre: 'José Pérez',
  telefono: '5551234567',
  direccion: 'Calle 1',
);

const _ana = Cliente(
  id: 'c2',
  nombre: 'Ana Ruiz',
  telefono: '5559876543',
  direccion: '',
);

/// Simula el modo sin conexión: el id llega y la confirmación nunca.
class _ServicioSinRed implements ServicioPedidos {
  @override
  ({String pedidoId, Future<void> guardado}) crearPedido({
    String? clienteId,
    required String nombre,
    required String telefono,
    required String direccion,
    required Entrega entrega,
    required double envio,
    required String comentarios,
    required DateTime fechaEstimada,
    required List<NuevoMueble> muebles,
    DateTime? ahora,
  }) =>
      (pedidoId: 'ped-offline', guardado: Completer<void>().future);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<FakeFirebaseFirestore> _montar(WidgetTester t,
    {ServicioPedidos? servicio}) async {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const PantallaNuevoPedido()),
    GoRoute(
        path: '/pedidos/:id',
        builder: (_, s) => Text('detalle ${s.pathParameters['id']}')),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      estadoSesionProvider
          .overrideWith((ref) => Stream.value(const SesionActiva(_usuario))),
      clientesProvider.overrideWith((ref) => Stream.value([_jose, _ana])),
      plantillasProvider.overrideWith((ref) => Stream.value([])),
      materialesProvider.overrideWith((ref) => Stream.value([])),
      if (servicio != null)
        servicioPedidosProvider.overrideWithValue(servicio),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  // En la app la sesión ya está cargada cuando se abre esta pantalla.
  ProviderScope.containerOf(t.element(find.byType(MaterialApp)))
      .listen(estadoSesionProvider, (_, _) {});
  await t.pumpAndSettle();
  return db;
}

Future<void> _agregarMueble(WidgetTester t, String tipo, String precio) async {
  await t.ensureVisible(find.text('Agregar mueble'));
  await t.tap(find.text('Agregar mueble'));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const Key('tipo-mueble')), tipo);
  await t.enterText(find.byKey(const Key('precio')), precio);
  await t.tap(find.text('Agregar'));
  await t.pumpAndSettle();
}

Future<void> _guardar(WidgetTester t) async {
  await t.ensureVisible(find.text('Guardar pedido'));
  await t.tap(find.text('Guardar pedido'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('crea un pedido con cliente nuevo, domicilio y dos muebles',
      (t) async {
    final db = await _montar(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Luis');
    await t.tap(find.text('A domicilio'));
    await t.pumpAndSettle();
    await t.enterText(
        find.widgetWithText(TextFormField, 'Dirección'), 'Av. Sur 5');
    await t.enterText(find.widgetWithText(TextFormField, 'Envío'), '200');
    await _agregarMueble(t, 'Sillón', '650');
    await _agregarMueble(t, 'Silla', '650');
    expect(find.text('Total: \$1,500.00'), findsOneWidget);

    await _guardar(t);

    final pedidos = (await db.collection('pedidos').get()).docs;
    expect(pedidos.length, 1);
    expect(pedidos.single.data()['envio'], 200);
    expect(pedidos.single.data()['entrega'], 'domicilio');
    final muebles = await pedidos.single.reference.collection('muebles').get();
    expect(muebles.docs.length, 2);
    expect((await db.collection('clientes').get()).docs.length, 1);
    expect(find.text('detalle ${pedidos.single.id}'), findsOneWidget);
  });

  testWidgets('elegir un cliente existente no crea otro', (t) async {
    final db = await _montar(t);
    await t.enterText(find.byKey(const Key('buscar-cliente')), 'pér');
    await t.pumpAndSettle();
    await t.tap(find.text('José Pérez'));
    await t.pumpAndSettle();
    expect(find.text('Cambiar'), findsOneWidget);
    await _agregarMueble(t, 'Sillón', '650');
    await _guardar(t);

    final pedidos = (await db.collection('pedidos').get()).docs;
    expect(pedidos.single.data()['clienteId'], 'c1');
    expect((await db.collection('clientes').get()).docs, isEmpty);
  });

  testWidgets('cliente sin dirección permite escribirla a domicilio',
      (t) async {
    final db = await _montar(t);
    await t.enterText(find.byKey(const Key('buscar-cliente')), 'Ana');
    await t.pumpAndSettle();
    await t.tap(find.text('Ana Ruiz'));
    await t.pumpAndSettle();
    await t.tap(find.text('A domicilio'));
    await t.pumpAndSettle();
    await t.enterText(
        find.widgetWithText(TextFormField, 'Dirección'), 'Av. Norte 9');
    await t.enterText(find.widgetWithText(TextFormField, 'Envío'), '100');
    await _agregarMueble(t, 'Sillón', '650');
    await _guardar(t);

    final pedidos = (await db.collection('pedidos').get()).docs;
    expect(pedidos.single.data()['clienteId'], 'c2');
    expect(pedidos.single.data()['cliente']['direccion'], 'Av. Norte 9');
    expect((await db.collection('clientes').get()).docs, isEmpty);
  });

  testWidgets('sin muebles pide agregar uno', (t) async {
    final db = await _montar(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Luis');
    await _guardar(t);
    expect(find.text('Agrega al menos un mueble'), findsOneWidget);
    expect((await db.collection('pedidos').get()).docs, isEmpty);
  });

  testWidgets('sin nombre pide el nombre', (t) async {
    await _montar(t);
    await _agregarMueble(t, 'Sillón', '650');
    await _guardar(t);
    expect(find.text('Escribe el nombre del cliente'), findsOneWidget);
  });

  testWidgets('domicilio sin dirección pide la dirección', (t) async {
    final db = await _montar(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Luis');
    await t.tap(find.text('A domicilio'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Envío'), '100');
    await _agregarMueble(t, 'Sillón', '650');
    await _guardar(t);
    expect(find.text('Escribe la dirección de entrega'), findsOneWidget);
    expect((await db.collection('pedidos').get()).docs, isEmpty);
  });

  testWidgets('sin conexión navega aunque guardado nunca termine', (t) async {
    await _montar(t, servicio: _ServicioSinRed());
    await t.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Luis');
    await _agregarMueble(t, 'Sillón', '650');
    await _guardar(t);
    expect(find.text('detalle ped-offline'), findsOneWidget);
  });
}
