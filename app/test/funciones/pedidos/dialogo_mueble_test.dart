import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/inventario.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';
import 'package:tapiceria/funciones/pedidos/dialogo_mueble.dart';
import 'package:tapiceria/funciones/pedidos/providers.dart';
import 'package:tapiceria/funciones/pedidos/servicio_pedidos.dart';

Usuario _usuario(Rol rol) => Usuario(
      uid: 'u1',
      nombre: 'Ana',
      email: 'a@x.com',
      rol: rol,
      activo: true,
    );

Material _tela(double existencia) => Material(
      id: 'm1',
      nombre: 'Tela lino gris',
      categoria: Categoria.tela,
      unidad: Unidad.m,
      stockMinimo: 0,
      existencia: existencia,
      usaRollos: true,
      marcadoAgotandose: false,
    );

const _sillon = Plantilla(
  id: 'p1',
  tipoMueble: 'Sillón 3 plazas',
  lineas: [LineaPlantilla(materialId: 'm1', cantidad: 6)],
);

NuevoMueble? _resultado;
int _suscripcionesCosto = 0;

Future<void> _montar(WidgetTester t, Rol rol, {double existencia = 4}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _resultado = null;
  _suscripcionesCosto = 0;
  await t.pumpWidget(ProviderScope(
    overrides: [
      estadoSesionProvider
          .overrideWith((ref) => Stream.value(SesionActiva(_usuario(rol)))),
      plantillasProvider.overrideWith((ref) => Stream.value([_sillon])),
      materialesProvider
          .overrideWith((ref) => Stream.value([_tela(existencia)])),
      costoPromedioProvider.overrideWith((ref, id) {
        _suscripcionesCosto++;
        return Stream.value(100.0);
      }),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                _resultado = await mostrarDialogoMueble(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('escribir el tipo de una plantilla la preselecciona',
      (t) async {
    await _montar(t, Rol.empleado);
    await t.enterText(find.byKey(const Key('tipo-mueble')), 'Sillón 3 plazas');
    await t.pumpAndSettle();
    final menu = t.widget<DropdownButtonFormField<String?>>(
        find.byKey(const Key('plantilla')));
    expect(menu.initialValue, 'p1');
  });

  testWidgets('avisa lo que no alcanza sin bloquear', (t) async {
    await _montar(t, Rol.empleado);
    await t.enterText(find.byKey(const Key('tipo-mueble')), 'Sillón 3 plazas');
    await t.enterText(find.byKey(const Key('precio')), '650');
    await t.pumpAndSettle();
    expect(find.text('No alcanza: Tela lino gris (necesita 6 m, hay 4 m)'),
        findsOneWidget);
    await t.tap(find.text('Agregar'));
    await t.pumpAndSettle();
    expect(_resultado, isNotNull);
    expect(_resultado!.plantillaId, 'p1');
    expect(_resultado!.precio, 650);
  });

  testWidgets('con existencia suficiente no avisa', (t) async {
    await _montar(t, Rol.empleado, existencia: 10);
    await t.enterText(find.byKey(const Key('tipo-mueble')), 'Sillón 3 plazas');
    await t.pumpAndSettle();
    expect(find.textContaining('No alcanza'), findsNothing);
  });

  testWidgets('el empleado no ve el costo estimado ni lo consulta',
      (t) async {
    await _montar(t, Rol.empleado);
    await t.enterText(find.byKey(const Key('tipo-mueble')), 'Sillón 3 plazas');
    await t.pumpAndSettle();
    expect(find.textContaining('Costo estimado'), findsNothing);
    expect(_suscripcionesCosto, 0);
  });

  testWidgets('el dueño ve el costo estimado', (t) async {
    await _montar(t, Rol.dueno);
    await t.enterText(find.byKey(const Key('tipo-mueble')), 'Sillón 3 plazas');
    await t.pumpAndSettle();
    expect(find.text('Costo estimado: \$600.00'), findsOneWidget);
  });

  testWidgets('valida tipo de mueble y precio', (t) async {
    await _montar(t, Rol.empleado);
    await t.tap(find.text('Agregar'));
    await t.pumpAndSettle();
    expect(find.text('Escribe el tipo de mueble'), findsOneWidget);
    expect(find.text('Escribe el precio'), findsOneWidget);
    expect(_resultado, isNull);
  });
}
