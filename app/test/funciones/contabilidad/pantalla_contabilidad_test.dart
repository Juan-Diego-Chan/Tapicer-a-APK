import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tapiceria/dominio/contabilidad.dart';
import 'package:tapiceria/dominio/costos_pedido.dart';
import 'package:tapiceria/dominio/dinero.dart';
import 'package:tapiceria/dominio/inventario.dart' as inv;
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/contabilidad/armar_resumen.dart';
import 'package:tapiceria/funciones/contabilidad/pantalla_contabilidad.dart';
import 'package:tapiceria/funciones/contabilidad/providers.dart';
import 'package:tapiceria/funciones/dinero/providers.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';
import 'package:tapiceria/funciones/usuarios/providers.dart';

Usuario _usuario(String uid, String nombre, Rol rol) => Usuario(
    uid: uid, nombre: nombre, email: '$uid@x.com', rol: rol, activo: true);

final _dueno = _usuario('d1', 'Dueña', Rol.dueno);
final _empleado = _usuario('u1', 'Ana', Rol.empleado);

Pedido _pedido(String id, String folio, String cliente) => Pedido(
      id: id,
      folio: folio,
      cliente:
          Cliente(id: 'c-$id', nombre: cliente, telefono: '', direccion: ''),
      entrega: Entrega.recoge,
      envio: 0,
      comentarios: '',
      fechaIngreso: DateTime(2026, 11, 2),
      fechaEstimada: DateTime(2026, 11, 9),
      fechaTerminado: null,
      fechaEntregado: DateTime(2026, 11, 5),
      estado: EstadoMueble.entregado,
      creadoPor: 'd1',
    );

Mueble _mueble(String id, String pedidoId, String tipo, double precio,
        {TipoTrabajo trabajo = TipoTrabajo.fabricacion}) =>
    Mueble(
      id: id,
      pedidoId: pedidoId,
      tipoTrabajo: trabajo,
      tipoMueble: tipo,
      plantillaId: null,
      precio: precio,
      comentarios: '',
      estado: EstadoMueble.entregado,
    );

ResumenPeriodo _vacio(Periodo p) => ResumenPeriodo(
      periodo: p,
      cobros: const ResumenCobros(
          total: 0, porForma: {}, porUsuario: {}, porPedido: {}),
      pedidosDeCobros: const {},
      gastos: const ResumenGastos(compras: 0, sueldos: 0),
      ganancias: const [],
      muebles: {for (final t in TipoTrabajo.values) t: <GananciaMueble>[]},
      cambios: const [],
      pendientes: const [],
      diferencias: const [],
    );

ResumenPeriodo _lleno(Periodo p, {bool incompleto = false}) {
  final p1 = _pedido('p1abc', '261102-P1AB', 'Marta');
  final p2 = _pedido('p2xyz', '261103-P2XY', 'Jorge');
  final sillon = GananciaMueble(
    pedido: p1,
    mueble: _mueble('m1', 'p1abc', 'Sillón', 5000),
    materiales: Costo(400, incompleto: incompleto),
    manoObra: const Costo(260),
  );
  final silla = GananciaMueble(
    pedido: p1,
    mueble: _mueble('m2', 'p1abc', 'Silla', 1500,
        trabajo: TipoTrabajo.reparacion),
    materiales: const Costo(0),
    manoObra: const Costo(0),
  );
  return ResumenPeriodo(
    periodo: p,
    cobros: const ResumenCobros(
      total: 1800,
      porForma: {FormaPago.efectivo: 1500, FormaPago.transferencia: 300},
      porUsuario: {'u1': 1800},
      porPedido: {'p1abc': 1800},
    ),
    pedidosDeCobros: {'p1abc': p1},
    gastos: const ResumenGastos(compras: 1200, sueldos: 500),
    ganancias: [
      GananciaPedido(
        pedido: p1,
        total: 6500,
        muebles: [sillon, silla],
        costos: Costo(560, incompleto: incompleto),
      ),
    ],
    muebles: {
      TipoTrabajo.fabricacion: [sillon],
      TipoTrabajo.reparacion: [silla],
    },
    cambios: [
      (
        pedidoId: 'p1abc',
        cambio: CambioPrecio(
          id: 'c1',
          campo: CampoPrecio.precio,
          muebleId: 'm1',
          anterior: 5000,
          nuevo: 4500,
          motivo: null,
          usuarioId: 'd1',
          fecha: DateTime(2026, 11, 4),
        ),
      ),
    ],
    pendientes: [(pedido: p2, saldo: 750)],
    diferencias: [
      DiferenciaMaterial(
        pedido: p1,
        mueble: sillon.mueble,
        comparacion:
            const Comparacion(materialId: 'mat1', estimado: 3, usado: 4.5),
      ),
    ],
  );
}

class _PeriodoFijo extends PeriodoNotifier {
  @override
  Periodo build() => Periodo.semana(DateTime(2026, 11, 7));
}

Future<void> _montar(
  WidgetTester t, {
  Usuario? sesion,
  ResumenPeriodo Function(Periodo)? resumen,
  bool error = false,
  bool sinCajas = false,
  GoRouter? router,
}) async {
  t.view.physicalSize = const Size(800, 6000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final s = sesion ?? _dueno;
  final overrides = [
    estadoSesionProvider.overrideWith((ref) => Stream.value(SesionActiva(s))),
    periodoProvider.overrideWith(_PeriodoFijo.new),
    resumenProvider.overrideWith((ref, p) {
      if (s.rol != Rol.dueno) throw StateError('no debe leerse');
      if (error) throw StateError('falla');
      return (resumen ?? _vacio)(p);
    }),
    usuariosProvider.overrideWith((ref) => Stream.value([_dueno, _empleado])),
    cajasProvider.overrideWith((ref) => Stream.value(
        sinCajas ? <String, double>{} : {'u1': 300.0, 'u2': 0.0})),
    entregasPendientesProvider.overrideWith((ref) => Stream.value(sinCajas
        ? <EntregaDinero>[]
        : [
            EntregaDinero(
              id: 'e1',
              empleadoId: 'u1',
              monto: 200,
              forma: FormaPago.efectivo,
              fecha: DateTime(2026, 11, 5),
              estado: EstadoEntrega.pendiente,
              revisadoEn: null,
            ),
          ])),
    materialesProvider.overrideWith((ref) => Stream.value([
          const inv.Material(
            id: 'mat1',
            nombre: 'Tela gris',
            categoria: inv.Categoria.tela,
            unidad: inv.Unidad.m,
            stockMinimo: 0,
            existencia: 0,
            usaRollos: false,
            marcadoAgotandose: false,
          ),
        ])),
  ];
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: router != null
        ? MaterialApp.router(routerConfig: router)
        : const MaterialApp(home: PantallaContabilidad()),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('muestra los totales y el desglose', (t) async {
    await _montar(t, resumen: _lleno);
    expect(find.text('Contabilidad'), findsOneWidget);
    expect(find.text('Total: \$1,800.00'), findsOneWidget);
    expect(find.text('Efectivo: \$1,500.00'), findsOneWidget);
    expect(find.text('Ana: \$1,800.00'), findsOneWidget);
    expect(find.text('261102-P1AB: \$1,800.00'), findsOneWidget);
    expect(find.text('Compras de material: \$1,200.00'), findsOneWidget);
    expect(find.text('Sueldos: \$500.00'), findsOneWidget);
    expect(find.text('Total: \$1,700.00'), findsOneWidget);
    expect(find.text('Ganancia total: \$5,940.00 (1 pedidos entregados)'),
        findsOneWidget);
    expect(find.text('\$5,940.00'), findsOneWidget);
    expect(find.text('\$4,340.00 (86.8%)'), findsOneWidget);
    expect(find.text('Sillón · 261102-P1AB'), findsOneWidget);
    expect(
        find.text('Precio \$5,000.00 · Materiales \$400.00 · '
            'Mano de obra \$260.00'),
        findsOneWidget);
    expect(find.text('Costo incompleto'), findsNothing);
    expect(find.text('Ana: \$300.00'), findsOneWidget);
    expect(find.text('Entregas por confirmar: \$200.00'), findsOneWidget);
    expect(
        find.text('261102-P1AB · Precio de Sillón: \$5,000.00 → \$4,500.00'),
        findsOneWidget);
    expect(find.text('261103-P2XY · Jorge'), findsOneWidget);
    expect(find.text('Saldo: \$750.00'), findsOneWidget);
    expect(find.text('Tela gris: estimado 3 m, usado 4.5 m'), findsOneWidget);
  });

  testWidgets('periodo vacío muestra los textos vacíos', (t) async {
    await _montar(t, sinCajas: true);
    for (final s in [
      'Sin cobros en el periodo',
      'Nadie tiene dinero por entregar',
      'Ningún pedido entregado en el periodo',
      'Sin cambios de precio en el periodo',
      'Nada pendiente de cobro',
      'Sin diferencias notables',
    ]) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(find.text('Lo gastado'), findsOneWidget);
    expect(find.text('Compras de material: \$0.00'), findsOneWidget);
  });

  testWidgets('un mueble con costo incompleto lo indica', (t) async {
    await _montar(t, resumen: (p) => _lleno(p, incompleto: true));
    expect(find.text('Costo incompleto'), findsWidgets);
  });

  testWidgets('muestra el error y el botón Reintentar', (t) async {
    await _montar(t, error: true);
    expect(find.text('No se pudo cargar el resumen'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('periodo siguiente y anterior cambian la etiqueta', (t) async {
    await _montar(t);
    expect(find.text('Semana del 02/11/2026 al 08/11/2026'), findsOneWidget);
    await t.tap(find.byTooltip('Periodo siguiente'));
    await t.pumpAndSettle();
    expect(find.text('Semana del 09/11/2026 al 15/11/2026'), findsOneWidget);
    await t.tap(find.byTooltip('Periodo anterior'));
    await t.pumpAndSettle();
    expect(find.text('Semana del 02/11/2026 al 08/11/2026'), findsOneWidget);
  });

  testWidgets('elegir Mes muestra el mes', (t) async {
    await _montar(t);
    await t.tap(find.text('Mes'));
    await t.pumpAndSettle();
    expect(find.text('Noviembre 2026'), findsOneWidget);
  });

  testWidgets('tocar un pendiente abre el pedido', (t) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const PantallaContabilidad()),
      GoRoute(
        path: '/pedidos/:id',
        builder: (_, s) =>
            Scaffold(body: Text('pedido ${s.pathParameters['id']}')),
      ),
    ]);
    await _montar(t, resumen: _lleno, router: router);
    await t.tap(find.text('261103-P2XY · Jorge'));
    await t.pumpAndSettle();
    expect(find.text('pedido p2xyz'), findsOneWidget);
  });

  testWidgets('un empleado ve la pantalla vacía y no lee el resumen',
      (t) async {
    await _montar(t, sesion: _empleado);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Contabilidad'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
