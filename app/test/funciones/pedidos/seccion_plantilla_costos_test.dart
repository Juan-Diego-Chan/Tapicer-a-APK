import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/inventario.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';
import 'package:tapiceria/funciones/pedidos/aviso_disponibilidad.dart';
import 'package:tapiceria/funciones/pedidos/providers.dart';
import 'package:tapiceria/funciones/pedidos/seccion_plantilla_costos.dart';
import 'package:tapiceria/funciones/usuarios/providers.dart';

Usuario _usuario(String uid, Rol rol) => Usuario(
      uid: uid,
      nombre: uid == 'dueno' ? 'Dueño' : 'Ana',
      email: '$uid@x.com',
      rol: rol,
      activo: true,
    );

Material _mat(String id, String nombre, Unidad u, double existencia) =>
    Material(
      id: id,
      nombre: nombre,
      categoria: Categoria.tela,
      unidad: u,
      stockMinimo: 0,
      existencia: existencia,
      usaRollos: false,
      marcadoAgotandose: false,
    );

const _plantilla = Plantilla(
  id: 'p1',
  tipoMueble: 'Sillón',
  lineas: [LineaPlantilla(materialId: 'tela', cantidad: 6)],
);

Mueble _mueble({String? plantillaId = 'p1', EstadoMueble? estado}) => Mueble(
      id: 'mu1',
      pedidoId: 'p',
      tipoTrabajo: TipoTrabajo.fabricacion,
      tipoMueble: 'Sillón',
      plantillaId: plantillaId,
      precio: 1000,
      comentarios: '',
      estado: estado ?? EstadoMueble.recibido,
    );

LineaMaterial _linea(String material, double cantidad, {String? rollo}) =>
    LineaMaterial(
      id: 'l-$material-$cantidad',
      materialId: material,
      rolloId: rollo,
      cantidad: cantidad,
      delCliente: false,
      usuarioId: 'dueno',
      fecha: DateTime(2026, 1, 1),
    );

DiaTrabajado _dia(String uid, double dias) => DiaTrabajado(
      id: 'd-$uid-$dias',
      usuarioId: uid,
      dias: dias,
      fecha: DateTime(2026, 1, 1),
    );

var _suscripciones = 0;

Future<void> _montar(
  WidgetTester t,
  Rol rol, {
  Mueble? mueble,
  List<LineaMaterial> lineas = const [],
  List<DiaTrabajado> dias = const [],
  double? costoEspuma = 10,
  double existenciaTela = 100,
}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _suscripciones = 0;
  await t.pumpWidget(ProviderScope(
    overrides: [
      estadoSesionProvider.overrideWith(
          (ref) => Stream.value(SesionActiva(_usuario('sesion', rol)))),
      plantillasProvider.overrideWith((ref) => Stream.value([_plantilla])),
      materialesProvider.overrideWith((ref) => Stream.value([
            _mat('tela', 'Tela lino', Unidad.m, existenciaTela),
            _mat('guata', 'Guata', Unidad.kg, 100),
            _mat('espuma', 'Espuma', Unidad.pza, 100),
            _mat('grapas', 'Grapas', Unidad.pza, 100),
          ])),
      usuariosProvider.overrideWith((ref) => Stream.value([
            _usuario('dueno', Rol.dueno),
            _usuario('emp', Rol.empleado),
          ])),
      costoPromedioProvider.overrideWith((ref, id) {
        _suscripciones++;
        return Stream.value(switch (id) {
          'guata' => 60.0,
          'espuma' => costoEspuma,
          'tela' => 100.0,
          _ => 1.0,
        });
      }),
      costoRolloProvider.overrideWith((ref, id) {
        _suscripciones++;
        return Stream.value(110.0);
      }),
      sueldoProvider.overrideWith((ref, uid) {
        _suscripciones++;
        return Stream.value(2100.0);
      }),
      diasLaboralesProvider.overrideWith((ref) => Stream.value(6)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SeccionPlantillaYCostos(
            mueble: mueble ?? _mueble(),
            lineas: lineas,
            dias: dias,
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('el usado excedido sale en rojo y lo de fuera de plantilla con —',
      (t) async {
    await _montar(t, Rol.empleado,
        lineas: [_linea('tela', 6.5), _linea('grapas', 3)]);
    final cs = Theme.of(t.element(find.byType(Scaffold))).colorScheme;
    expect(t.widget<Text>(find.byKey(const Key('usado-tela'))).style?.color,
        cs.error);
    expect(t.widget<Text>(find.byKey(const Key('estimado-grapas'))).data, '—');
    // Fuera de plantilla el estimado es 0, así que el domino lo cuenta excedido.
    expect(t.widget<Text>(find.byKey(const Key('usado-grapas'))).style?.color,
        cs.error);
  });

  testWidgets('el dueño ve materiales, mano de obra y costo real',
      (t) async {
    await _montar(t, Rol.dueno, lineas: [
      _linea('tela', 2.5, rollo: 'r1'),
      _linea('guata', 1),
    ], dias: [
      _dia('emp', 1.5),
      _dia('dueno', 2),
    ]);
    expect(find.text('Costos'), findsOneWidget);
    expect(find.text('Materiales: \$335.00'), findsOneWidget);
    expect(find.text('Mano de obra: \$525.00'), findsOneWidget);
    expect(find.text('Costo real: \$860.00'), findsOneWidget);
    expect(find.text('Estimado de plantilla: \$600.00'), findsOneWidget);
  });

  testWidgets('un costo desconocido marca incompleto', (t) async {
    await _montar(t, Rol.dueno,
        lineas: [_linea('espuma', 1)], costoEspuma: null);
    expect(find.textContaining('Materiales: \$'), findsOneWidget);
    expect(find.textContaining('Materiales: \$0.00 (incompleto)'),
        findsOneWidget);
    expect(find.textContaining('Costo real: \$0.00 (incompleto)'),
        findsOneWidget);
  });

  testWidgets('el empleado no ve costos ni se suscribe a ellos', (t) async {
    await _montar(t, Rol.empleado, lineas: [
      _linea('tela', 2.5, rollo: 'r1'),
      _linea('guata', 1),
    ], dias: [
      _dia('emp', 1.5),
    ]);
    expect(find.text('Costos'), findsNothing);
    expect(find.textContaining('Costo real'), findsNothing);
    expect(_suscripciones, 0);
  });

  testWidgets('el aviso aparece en recibido y no con terminado', (t) async {
    await _montar(t, Rol.empleado, existenciaTela: 2);
    expect(find.byType(AvisoDisponibilidad), findsOneWidget);
    expect(find.textContaining('No alcanza'), findsOneWidget);

    await _montar(t, Rol.empleado,
        existenciaTela: 2, mueble: _mueble(estado: EstadoMueble.terminado));
    expect(find.byType(AvisoDisponibilidad), findsNothing);
    expect(find.textContaining('No alcanza'), findsNothing);
  });

  testWidgets('sin plantilla muestra "Sin plantilla" y la tabla de usado',
      (t) async {
    await _montar(t, Rol.empleado,
        mueble: _mueble(plantillaId: null), lineas: [_linea('grapas', 3)]);
    expect(find.text('Sin plantilla'), findsOneWidget);
    expect(find.byKey(const Key('usado-grapas')), findsOneWidget);
  });
}
