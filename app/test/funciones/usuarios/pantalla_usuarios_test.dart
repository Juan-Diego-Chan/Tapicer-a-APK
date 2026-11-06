import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/usuarios/pantalla_usuarios.dart';

const _dueno = Usuario(
  uid: 'd1',
  nombre: 'Rosa',
  email: 'r@x.com',
  rol: Rol.dueno,
  activo: true,
);

Future<FakeFirebaseFirestore> _montar(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final db = FakeFirebaseFirestore();
  await db.collection('usuarios').doc('d1').set(_dueno.aMapa());
  await db.collection('usuarios').doc('e1').set({
    'nombre': 'Luis',
    'email': 'l@x.com',
    'rol': 'empleado',
    'activo': true,
  });
  await db.collection('usuarios').doc('e2').set({
    'nombre': 'Marta',
    'email': 'm@x.com',
    'rol': 'empleado',
    'activo': true,
  });
  await db.collection('usuarios_privado').doc('e1').set({
    'sueldoSemanal': 2100,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        estadoSesionProvider.overrideWith(
          (ref) => Stream.value(const SesionActiva(_dueno)),
        ),
      ],
      child: const MaterialApp(home: PantallaUsuarios()),
    ),
  );
  await t.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('lista usuarios con rol, sueldo e interruptor salvo el dueño', (
    t,
  ) async {
    await _montar(t);
    expect(find.text('Rosa'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);
    expect(find.text('Dueño'), findsOneWidget);
    expect(find.text('Empleado'), findsNWidgets(2));
    expect(find.text(r'$2,100.00'), findsOneWidget);
    expect(find.text('Sin sueldo'), findsOneWidget);
    // 2 empleados con interruptor; el dueño no tiene.
    expect(find.byType(Switch), findsNWidgets(2));
    expect(find.text('Activo'), findsNWidgets(2));
  });

  testWidgets('desactivar pide confirmación y desactiva', (t) async {
    final db = await _montar(t);
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(
      find.text('¿Desactivar a Luis? Ya no podrá entrar a la app.'),
      findsOneWidget,
    );
    await t.tap(find.text('Desactivar'));
    await t.pumpAndSettle();
    expect(
      (await db.collection('usuarios').doc('e1').get()).data()!['activo'],
      false,
    );
  });

  testWidgets('cancelar la confirmación no desactiva', (t) async {
    final db = await _montar(t);
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(
      (await db.collection('usuarios').doc('e1').get()).data()!['activo'],
      true,
    );
  });

  testWidgets('reactivar no pide confirmación', (t) async {
    final db = await _montar(t);
    await db.collection('usuarios').doc('e1').update({'activo': false});
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(find.textContaining('¿Desactivar'), findsNothing);
    expect(
      (await db.collection('usuarios').doc('e1').get()).data()!['activo'],
      true,
    );
  });

  testWidgets('días laborales acepta solo 1 a 7', (t) async {
    final db = await _montar(t);
    final campo = find.widgetWithText(
      TextFormField,
      'Días laborales por semana',
    );
    expect(campo, findsOneWidget);
    expect(find.text('6'), findsOneWidget);

    for (final malo in ['0', '8', '']) {
      await t.enterText(campo, malo);
      await t.tap(find.text('Guardar días'));
      await t.pumpAndSettle();
      expect(find.text('Escribe un número del 1 al 7'), findsOneWidget);
      expect(
        (await db.collection('config').doc('general').get()).exists,
        false,
      );
    }

    await t.enterText(campo, '5');
    await t.tap(find.text('Guardar días'));
    await t.pumpAndSettle();
    expect(
      (await db.collection('config').doc('general').get())
          .data()!['diasLaborales'],
      5,
    );
  });
}
