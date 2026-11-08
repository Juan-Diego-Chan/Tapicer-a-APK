import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/pedidos/pantalla_pedido.dart';
import 'package:tapiceria/funciones/pedidos/providers.dart';
import 'package:tapiceria/funciones/usuarios/providers.dart';

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
  bool conCambio = false,
  bool conCancelacion = false,
  void Function()? alSuscribirCambios,
  String estadoPedido = 'recibido',
  String estadoMuebles = 'recibido',
}) async {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  final ref = db.collection('pedidos').doc('p1');
  await ref.set({
    'folio': '260101-P1AB',
    'clienteId': 'c1',
    'cliente': {
      'nombre': 'José Pérez',
      'telefono': '5551234567',
      'direccion': 'Calle 1',
    },
    'entrega': 'domicilio',
    'envio': 200,
    'comentarios': 'Urge',
    'fechaIngreso': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'fechaEstimada': Timestamp.fromDate(DateTime(2026, 12, 1)),
    'estado': estadoPedido,
    'creadoPor': 'u1',
  });
  for (final (id, tipo) in [('m1', 'Sillón'), ('m2', 'Silla')]) {
    await ref.collection('muebles').doc(id).set({
      'tipoTrabajo': 'fabricacion',
      'tipoMueble': tipo,
      'plantillaId': null,
      'precio': 650,
      'comentarios': '',
      'estado': estadoMuebles,
      'ultimoCambioId': null,
    });
  }
  if (conCambio) {
    await ref.collection('cambios_precio').add({
      'campo': 'precio',
      'muebleId': 'm1',
      'anterior': 650,
      'nuevo': 600,
      'motivo': 'Descuento',
      'usuarioId': 'u1',
      'fecha': Timestamp.fromDate(DateTime(2026, 1, 5)),
    });
  }
  if (conCancelacion) {
    await ref.collection('cambios_precio').add({
      'campo': 'cancelacion',
      'muebleId': 'm2',
      'anterior': 650,
      'nuevo': 0,
      'motivo': null,
      'usuarioId': 'u1',
      'fecha': Timestamp.fromDate(DateTime(2026, 1, 6)),
    });
  }
  await t.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      estadoSesionProvider
          .overrideWith((ref) => Stream.value(SesionActiva(_usuario(rol)))),
      usuariosProvider
          .overrideWith((ref) => Stream.value([_usuario(Rol.dueno)])),
      if (alSuscribirCambios != null)
        cambiosPrecioProvider.overrideWith((ref, id) {
          alSuscribirCambios();
          return Stream.value(<CambioPrecio>[]);
        }),
    ],
    child: MaterialApp(
      home: Consumer(builder: (context, ref, _) {
        // En la app el router ya mantiene viva la sesión.
        ref.watch(estadoSesionProvider);
        return const PantallaPedido(pedidoId: 'p1');
      }),
    ),
  ));
  await t.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('muestra los datos y el total con dos muebles y envío',
      (t) async {
    await _montar(t, Rol.empleado);
    expect(find.text('Total: \$1,500.00'), findsOneWidget);
    expect(find.textContaining('260101-P1AB'), findsWidgets);
    expect(find.textContaining('José Pérez'), findsOneWidget);
    expect(find.textContaining('5551234567'), findsOneWidget);
    expect(find.textContaining('Calle 1'), findsOneWidget);
    expect(find.textContaining('Sillón'), findsOneWidget);
    expect(find.textContaining('Urge'), findsOneWidget);
  });

  testWidgets('cambiar el precio de un mueble guarda el cambio y el total',
      (t) async {
    final db = await _montar(t, Rol.empleado);
    await t.tap(find.byTooltip('Cambiar precio').first);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Nuevo precio'), '650');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('El precio no cambió'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Nuevo precio'), '600');
    await t.enterText(
        find.widgetWithText(TextFormField, 'Motivo (opcional)'), 'Descuento');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();

    final cambios = await db
        .collection('pedidos')
        .doc('p1')
        .collection('cambios_precio')
        .get();
    expect(cambios.docs.length, 1);
    expect(cambios.docs.single.data()['nuevo'], 600);
    expect(cambios.docs.single.data()['motivo'], 'Descuento');
    expect(find.text('Total: \$1,450.00'), findsOneWidget);
  });

  testWidgets('el empleado no ve el historial ni se suscribe a él',
      (t) async {
    var suscripciones = 0;
    await _montar(t, Rol.empleado,
        conCambio: true, alSuscribirCambios: () => suscripciones++);
    expect(find.text('Historial de precios'), findsNothing);
    expect(suscripciones, 0);
  });

  testWidgets('el dueño ve la bajada de precio en rojo', (t) async {
    await _montar(t, Rol.dueno, conCambio: true);
    expect(find.text('Historial de precios'), findsOneWidget);
    final fila = find.textContaining('Precio de Sillón');
    expect(fila, findsOneWidget);
    expect(t.widget<Text>(fila).data, contains('\$650.00 → \$600.00'));
    final cs = Theme.of(t.element(find.byType(Scaffold).first)).colorScheme;
    expect(t.widget<Text>(fila).style?.color, cs.error);
    expect(find.textContaining('Descuento'), findsOneWidget);
  });

  testWidgets('el historial muestra la cancelación en rojo', (t) async {
    await _montar(t, Rol.dueno, conCancelacion: true);
    final fila = find.text('Mueble cancelado: Silla: \$650.00 → \$0.00');
    expect(fila, findsOneWidget);
    final cs = Theme.of(t.element(find.byType(Scaffold).first)).colorScheme;
    expect(t.widget<Text>(fila).style?.color, cs.error);
  });

  testWidgets('el dueño sin cambios ve "Sin cambios de precio"', (t) async {
    await _montar(t, Rol.dueno);
    expect(find.text('Sin cambios de precio'), findsOneWidget);
  });

  testWidgets('cancelar el pedido cancela los muebles y deja solo el envío',
      (t) async {
    final db = await _montar(t, Rol.empleado);
    await t.tap(find.text('Cancelar pedido'));
    await t.pumpAndSettle();
    expect(
        find.text('¿Cancelar el pedido 260101-P1AB? '
            'Los muebles no entregados quedarán cancelados.'),
        findsOneWidget);
    await t.tap(find.text('Sí, cancelar'));
    await t.pumpAndSettle();

    final muebles =
        await db.collection('pedidos').doc('p1').collection('muebles').get();
    expect(muebles.docs.every((d) => d.data()['estado'] == 'cancelado'), true);
    expect((await db.collection('pedidos').doc('p1').get()).data()!['estado'],
        'cancelado');
    expect(find.text('Cancelado'), findsWidgets);
    expect(find.text('Total: \$200.00'), findsOneWidget);
    expect(find.text('Cancelar pedido'), findsNothing);
  });

  testWidgets('reconcilia el estado del pedido si quedó viejo', (t) async {
    final db = await _montar(t, Rol.empleado,
        estadoPedido: 'en_proceso', estadoMuebles: 'terminado');
    final datos = (await db.collection('pedidos').doc('p1').get()).data()!;
    expect(datos['estado'], 'terminado');
    expect(datos['fechaTerminado'], isNotNull);
  });

  testWidgets('sin diferencia no escribe el pedido', (t) async {
    final db = await _montar(t, Rol.empleado);
    final datos = (await db.collection('pedidos').doc('p1').get()).data()!;
    expect(datos['estado'], 'recibido');
    expect(datos.containsKey('fechaTerminado'), false);
  });

  testWidgets('en un pedido cerrado no se agrega mueble ni se cambia envío',
      (t) async {
    await _montar(t, Rol.empleado,
        estadoPedido: 'cancelado', estadoMuebles: 'cancelado');
    expect(find.text('Agregar mueble'), findsNothing);
    expect(find.text('Cambiar envío'), findsNothing);
    expect(find.text('Cancelar pedido'), findsNothing);
    expect(find.text('Editar'), findsOneWidget);
  });

  testWidgets('en un pedido abierto sí se ofrecen', (t) async {
    await _montar(t, Rol.empleado);
    expect(find.text('Agregar mueble'), findsOneWidget);
    expect(find.text('Cambiar envío'), findsOneWidget);
  });
}
