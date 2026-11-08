import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/dinero.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/dinero/providers.dart';
import 'package:tapiceria/funciones/dinero/seccion_pagos.dart';
import 'package:tapiceria/funciones/usuarios/providers.dart';

Usuario _usuario(String uid, String nombre, Rol rol) => Usuario(
    uid: uid, nombre: nombre, email: '$uid@x.com', rol: rol, activo: true);

Pedido _pedido({
  double pagado = 0,
  EstadoMueble estado = EstadoMueble.recibido,
}) => Pedido(
  id: 'p1',
  folio: 'F1',
  cliente: const Cliente(id: 'c1', nombre: 'X', telefono: '', direccion: ''),
  entrega: Entrega.recoge,
  envio: 0,
  comentarios: '',
  fechaIngreso: DateTime(2026, 1, 1),
  fechaEstimada: DateTime(2026, 2, 1),
  fechaTerminado: null,
  fechaEntregado: null,
  estado: estado,
  creadoPor: 'u1',
  pagado: pagado,
);

Pago _pago(String id, double monto, String por) => Pago(
  id: id,
  pedidoId: 'p1',
  monto: monto,
  forma: FormaPago.efectivo,
  recibidoPor: por,
  fecha: DateTime(2026, 1, 5),
);

Future<FakeFirebaseFirestore> _montar(
  WidgetTester t,
  Rol rol,
  Pedido pedido, {
  double total = 1500,
  List<Pago> pagos = const [],
  Map<String, double> cajas = const {},
  bool lanzaDueno = false,
  bool cajasNuncaCargan = false,
}) async {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  await db.collection('pedidos').doc('p1').set({'pagado': pedido.pagado});
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        estadoSesionProvider.overrideWith(
          (ref) => Stream.value(SesionActiva(_usuario('u1', 'Ana', rol))),
        ),
        usuariosProvider.overrideWith(
          (ref) => Stream.value([
            _usuario('u1', 'Ana', Rol.dueno),
            _usuario('u2', 'Beto', Rol.empleado),
          ]),
        ),
        if (lanzaDueno) ...[
          pagosPedidoProvider.overrideWith((ref, id) => throw StateError('no')),
          cajasProvider.overrideWith((ref) => throw StateError('no')),
        ] else ...[
          pagosPedidoProvider.overrideWith((ref, id) => Stream.value(pagos)),
          cajasProvider.overrideWith(
            (ref) => cajasNuncaCargan
                ? const Stream<Map<String, double>>.empty()
                : Stream.value(cajas),
          ),
        ],
        misPagosPedidoProvider.overrideWith((ref, id) => Stream.value(pagos)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(estadoSesionProvider);
              return SingleChildScrollView(
                child: SeccionPagos(pedido: pedido, total: total),
              );
            },
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('muestra el saldo y permite registrar pago', (t) async {
    await _montar(t, Rol.empleado, _pedido(pagado: 500));
    expect(find.text('Saldo: \$1,000.00'), findsOneWidget);
    expect(find.text('Pagado: \$500.00'), findsOneWidget);
    expect(find.text('Registrar pago'), findsOneWidget);
  });

  testWidgets('pedido cancelado retiene el anticipo y no deja pagar', (
    t,
  ) async {
    await _montar(
      t,
      Rol.empleado,
      _pedido(pagado: 500, estado: EstadoMueble.cancelado),
      total: 0,
    );
    expect(find.text('Anticipo retenido: \$500.00'), findsOneWidget);
    expect(find.text('Registrar pago'), findsNothing);
  });

  testWidgets(
    'el empleado no ve Devolución ni Borrar pago ni lee lo del dueño',
    (t) async {
      await _montar(
        t,
        Rol.empleado,
        _pedido(pagado: 500),
        pagos: [_pago('a', 500, 'u2')],
        lanzaDueno: true,
      );
      expect(find.text('Devolución'), findsNothing);
      expect(find.byTooltip('Borrar pago'), findsNothing);
      expect(find.textContaining('Tus cobros'), findsOneWidget);
      expect(find.text('\$500.00 · Efectivo'), findsOneWidget);
    },
  );

  testWidgets('el dueño ve la devolución en negativo y en color de error', (
    t,
  ) async {
    await _montar(
      t,
      Rol.dueno,
      _pedido(pagado: 300),
      pagos: [_pago('a', 500, 'u2'), _pago('b', -200, 'u1')],
    );
    final fila = find.text('-\$200.00 · Efectivo');
    expect(fila, findsOneWidget);
    final cs = Theme.of(t.element(fila)).colorScheme;
    expect(t.widget<Text>(fila).style?.color, cs.error);
    expect(find.textContaining('Beto · 05/01/2026'), findsOneWidget);
    expect(find.text('Devolución'), findsOneWidget);
  });

  testWidgets('el dueño borra un pago de empleado y descuenta su caja', (
    t,
  ) async {
    final db = await _montar(
      t,
      Rol.dueno,
      _pedido(pagado: 500),
      pagos: [_pago('a', 500, 'u2')],
      cajas: {'u2': 500},
    );
    await db.collection('pagos').doc('a').set({'monto': 500});
    await t.tap(find.byTooltip('Borrar pago'));
    await t.pumpAndSettle();
    expect(
      find.text(
        '¿Borrar el pago de \$500.00? Esto cambia el saldo del pedido.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Sí, borrar'));
    await t.pumpAndSettle();
    expect((await db.collection('pagos').doc('a').get()).exists, false);
    expect(
      (await db.collection('cajas').doc('u2').get()).data()!['enMano'],
      -500,
    );
  });

  testWidgets('el diálogo rechaza un pago mayor al saldo y no cierra', (
    t,
  ) async {
    await _montar(t, Rol.empleado, _pedido(pagado: 500));
    await t.tap(find.text('Registrar pago'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Monto'), '1,200');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(
      find.text('El pago es mayor que el saldo (\$1,000.00)'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('el diálogo avisa de un monto ilegible', (t) async {
    await _montar(t, Rol.empleado, _pedido(pagado: 500));
    await t.tap(find.text('Registrar pago'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Monto'), 'abc');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe un monto válido'), findsOneWidget);
  });

  testWidgets('el diálogo guarda el pago por el saldo exacto', (t) async {
    final db = await _montar(t, Rol.empleado, _pedido(pagado: 500));
    await t.tap(find.text('Registrar pago'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Monto'), '1,000');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final pagos = await db.collection('pagos').get();
    expect(pagos.docs.length, 1);
    expect(pagos.docs.single.data()['monto'], 1000);
    expect(pagos.docs.single.data()['forma'], 'efectivo');
  });

  testWidgets('sin cajas cargadas el botón de borrar está deshabilitado', (
    t,
  ) async {
    await _montar(
      t,
      Rol.dueno,
      _pedido(pagado: 500),
      pagos: [_pago('a', 500, 'u2')],
      cajasNuncaCargan: true,
    );
    final boton = t.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(boton.onPressed, isNull);
  });

  testWidgets('saldo 0 muestra pagado por completo y no deja pagar', (t) async {
    await _montar(t, Rol.empleado, _pedido(pagado: 1500));
    expect(find.text('Pagado por completo'), findsOneWidget);
    expect(find.text('Registrar pago'), findsNothing);
  });
}
