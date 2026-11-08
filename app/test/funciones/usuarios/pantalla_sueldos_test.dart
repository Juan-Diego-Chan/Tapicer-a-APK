import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/usuarios/pantalla_sueldos.dart';
import 'package:tapiceria/funciones/usuarios/pantalla_usuarios.dart';

const _dueno = Usuario(
    uid: 'd1', nombre: 'Rosa', email: 'r@x.com', rol: Rol.dueno, activo: true);
const _luis = Usuario(
    uid: 'e1', nombre: 'Luis', email: 'l@x.com', rol: Rol.empleado, activo: true);

Future<FakeFirebaseFirestore> _preparar({double? sueldo}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('usuarios').doc('d1').set(_dueno.aMapa());
  await db.collection('usuarios').doc('e1').set(_luis.aMapa());
  if (sueldo != null) {
    await db.collection('usuarios_privado').doc('e1').set({
      'sueldoSemanal': sueldo,
    });
  }
  return db;
}

Future<void> _montar(
  WidgetTester t,
  FakeFirebaseFirestore db, {
  Usuario sesion = _dueno,
  Widget? home,
  GoRouter? router,
}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final overrides = [
    firestoreProvider.overrideWithValue(db),
    estadoSesionProvider
        .overrideWith((ref) => Stream.value(SesionActiva(sesion))),
  ];
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: router != null
        ? MaterialApp.router(routerConfig: router)
        : MaterialApp(home: home),
  ));
  await t.pumpAndSettle();
}

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

void main() {
  testWidgets('muestra nombre y sueldo semanal', (t) async {
    final db = await _preparar(sueldo: 1800);
    await _montar(t, db, home: const PantallaSueldos(uid: 'e1'));
    expect(find.text('Luis'), findsOneWidget);
    expect(find.text('Sueldo semanal: \$1,800.00'), findsOneWidget);
  });

  testWidgets('sin sueldo muestra Sin sueldo', (t) async {
    final db = await _preparar();
    await _montar(t, db, home: const PantallaSueldos(uid: 'e1'));
    expect(find.text('Sin sueldo'), findsOneWidget);
  });

  testWidgets('el diálogo abre con el sueldo y guarda con la fecha de hoy',
      (t) async {
    final db = await _preparar(sueldo: 1800);
    await _montar(t, db, home: const PantallaSueldos(uid: 'e1'));
    await t.tap(find.text('Registrar pago de sueldo'));
    await t.pumpAndSettle();
    final campo = t.widget<TextField>(find.widgetWithText(TextField, 'Monto'));
    expect(campo.controller!.text, '1800');
    final hoy = DateTime.now();
    final d = hoy.day.toString().padLeft(2, '0');
    final m = hoy.month.toString().padLeft(2, '0');
    expect(find.text('Fecha: $d/$m/${hoy.year}'), findsOneWidget);
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    final docs = (await db.collection('pagos_sueldo').get()).docs;
    expect(docs, hasLength(1));
    expect(docs.single['usuarioId'], 'e1');
    expect(docs.single['monto'], 1800);
    expect(
        _mismoDia((docs.single['fecha'] as Timestamp).toDate(), DateTime.now()),
        isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('\$1,800.00'), findsOneWidget);
  });

  testWidgets('monto inválido deja el diálogo abierto con el error',
      (t) async {
    final db = await _preparar();
    await _montar(t, db, home: const PantallaSueldos(uid: 'e1'));
    await t.tap(find.text('Registrar pago de sueldo'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Monto'), '0');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(find.text('El monto debe ser mayor a 0'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await db.collection('pagos_sueldo').get()).docs, isEmpty);
  });

  testWidgets('borrar pide confirmación y elimina el documento', (t) async {
    final db = await _preparar(sueldo: 1800);
    await db.collection('pagos_sueldo').doc('p1').set({
      'usuarioId': 'e1',
      'monto': 1800,
      'fecha': Timestamp.fromDate(DateTime(2026, 1, 5)),
    });
    await _montar(t, db, home: const PantallaSueldos(uid: 'e1'));
    expect(find.text('Pagos de sueldo'), findsOneWidget);
    expect(find.text('05/01/2026'), findsOneWidget);
    await t.tap(find.byTooltip('Borrar pago de sueldo'));
    await t.pumpAndSettle();
    expect(find.text('¿Borrar el pago de sueldo de \$1,800.00?'),
        findsOneWidget);
    await t.tap(find.text('Sí, borrar'));
    await t.pumpAndSettle();
    expect((await db.collection('pagos_sueldo').get()).docs, isEmpty);
  });

  testWidgets('un no dueño no ve nada', (t) async {
    final db = await _preparar(sueldo: 1800);
    await _montar(t, db, sesion: _luis, home: const PantallaSueldos(uid: 'e1'));
    expect(find.text('Registrar pago de sueldo'), findsNothing);
    expect(find.textContaining('1,800'), findsNothing);
  });

  group('navegación desde Usuarios', () {
    GoRouter router() => GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const PantallaUsuarios(),
            routes: [
              GoRoute(
                path: 'usuarios/:uid',
                builder: (_, s) =>
                    Text('sueldos ${s.pathParameters['uid']}'),
              ),
            ],
          ),
        ]);

    testWidgets('tocar a un empleado abre su pantalla', (t) async {
      final db = await _preparar(sueldo: 1800);
      await _montar(t, db, router: router());
      await t.tap(find.text('Luis'));
      await t.pumpAndSettle();
      expect(find.text('sueldos e1'), findsOneWidget);
    });

    testWidgets('tocar al dueño no navega', (t) async {
      final db = await _preparar(sueldo: 1800);
      await _montar(t, db, router: router());
      await t.tap(find.text('Rosa'));
      await t.pumpAndSettle();
      expect(find.textContaining('sueldos'), findsNothing);
      expect(find.byType(PantallaUsuarios), findsOneWidget);
    });
  });
}
