import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/dinero.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/dinero/pantalla_dinero.dart';
import 'package:tapiceria/funciones/dinero/providers.dart';
import 'package:tapiceria/funciones/usuarios/providers.dart';

Usuario _usuario(String uid, String nombre, Rol rol) => Usuario(
    uid: uid, nombre: nombre, email: '$uid@x.com', rol: rol, activo: true);

EntregaDinero _entrega(String id, String emp, double monto,
        [EstadoEntrega estado = EstadoEntrega.pendiente]) =>
    EntregaDinero(
      id: id,
      empleadoId: emp,
      monto: monto,
      forma: FormaPago.efectivo,
      fecha: DateTime(2026, 1, 5),
      estado: estado,
      revisadoEn: null,
    );

Future<FakeFirebaseFirestore> _montar(
  WidgetTester t, {
  required Usuario sesion,
  Widget pantalla = const PantallaDinero(),
  List<EntregaDinero> entregas = const [],
  double enMano = 0,
  Map<String, double> cajas = const {},
  bool lanzaDueno = false,
}) async {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  for (final e in entregas) {
    await db.collection('entregas').doc(e.id).set({
      'empleadoId': e.empleadoId,
      'monto': e.monto,
      'estado': e.estado.clave,
    });
  }
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        estadoSesionProvider
            .overrideWith((ref) => Stream.value(SesionActiva(sesion))),
        usuariosProvider.overrideWith(
          (ref) => Stream.value([
            _usuario('d1', 'Dueña', Rol.dueno),
            _usuario('u1', 'Ana', Rol.empleado),
            _usuario('u2', 'Beto', Rol.empleado),
          ]),
        ),
        enManoProvider.overrideWith((ref, uid) => Stream.value(enMano)),
        entregasDeProvider.overrideWith((ref, uid) => Stream.value(
            entregas.where((e) => e.empleadoId == uid).toList())),
        if (lanzaDueno) ...[
          cajasProvider.overrideWith((ref) => throw StateError('no')),
          entregasPendientesProvider
              .overrideWith((ref) => throw StateError('no')),
        ] else ...[
          cajasProvider.overrideWith((ref) => Stream.value(cajas)),
          entregasPendientesProvider.overrideWith((ref) => Stream.value(
              entregas
                  .where((e) => e.estado == EstadoEntrega.pendiente)
                  .toList())),
        ],
      ],
      child: MaterialApp(home: pantalla),
    ),
  );
  await t.pumpAndSettle();
  return db;
}

void main() {
  final ana = _usuario('u1', 'Ana', Rol.empleado);
  final dueno = _usuario('d1', 'Dueña', Rol.dueno);

  group('empleado', () {
    testWidgets('muestra en manos y por confirmar sin leer lo del dueño',
        (t) async {
      await _montar(t,
          sesion: ana,
          enMano: 1000,
          entregas: [_entrega('e1', 'u1', 300)],
          lanzaDueno: true);
      expect(find.text('En tus manos: \$1,000.00'), findsOneWidget);
      expect(find.text('Por confirmar: \$300.00'), findsOneWidget);
      expect(find.text('Tus entregas'), findsOneWidget);
      expect(find.text('\$300.00 · Efectivo'), findsOneWidget);
      expect(find.text('05/01/2026 · Pendiente'), findsOneWidget);
    });

    testWidgets('rechaza una entrega mayor a lo que tiene por entregar',
        (t) async {
      await _montar(t,
          sesion: ana,
          enMano: 1000,
          entregas: [_entrega('e1', 'u1', 300)],
          lanzaDueno: true);
      await t.tap(find.text('Registrar entrega'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Monto'), '800');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(
        find.text(
            'La entrega es mayor que lo que tienes por entregar (\$700.00)'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('registra una entrega pendiente por el máximo', (t) async {
      final db = await _montar(t,
          sesion: ana,
          enMano: 1000,
          entregas: [_entrega('e1', 'u1', 300)],
          lanzaDueno: true);
      await t.tap(find.text('Registrar entrega'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Monto'), '700');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final docs = (await db.collection('entregas').get())
          .docs
          .where((d) => d.id != 'e1');
      expect(docs.length, 1);
      expect(docs.single.data()['monto'], 700);
      expect(docs.single.data()['estado'], 'pendiente');
      expect(docs.single.data()['empleadoId'], 'u1');
    });

    testWidgets('la ruta del dueño no muestra nada a un empleado', (t) async {
      await _montar(t,
          sesion: ana,
          pantalla: const PantallaEntregasEmpleado(uid: 'u2'),
          enMano: 1000,
          lanzaDueno: true);
      expect(find.textContaining('En sus manos'), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('dueño', () {
    testWidgets('confirma una entrega y baja la caja', (t) async {
      final db = await _montar(t,
          sesion: dueno,
          entregas: [_entrega('e1', 'u1', 300)],
          cajas: {'u1': 1000});
      expect(find.text('Ana: \$300.00 · Efectivo'), findsOneWidget);
      await t.tap(find.text('Confirmar'));
      await t.pumpAndSettle();
      expect(
          (await db.collection('entregas').doc('e1').get()).data()!['estado'],
          'confirmada');
      expect((await db.collection('cajas').doc('u1').get()).data()!['enMano'],
          -300);
    });

    testWidgets('rechazar pide confirmación', (t) async {
      final db = await _montar(t,
          sesion: dueno,
          entregas: [_entrega('e1', 'u1', 300)],
          cajas: {'u1': 1000});
      await t.tap(find.text('Rechazar'));
      await t.pumpAndSettle();
      expect(
        find.text('¿Rechazar la entrega de \$300.00 de Ana? '
            'Su dinero en manos no cambia.'),
        findsOneWidget,
      );
      await t.tap(find.text('Sí, rechazar'));
      await t.pumpAndSettle();
      expect(
          (await db.collection('entregas').doc('e1').get()).data()!['estado'],
          'rechazada');
    });

    testWidgets('un empleado sin caja sale con 0 y nada por confirmar',
        (t) async {
      await _montar(t, sesion: dueno, cajas: {'u1': 500});
      expect(find.text('Nada por confirmar'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('\$500.00'), findsOneWidget);
      expect(find.text('Beto'), findsOneWidget);
      expect(find.text('\$0.00'), findsOneWidget);
    });
  });
}
