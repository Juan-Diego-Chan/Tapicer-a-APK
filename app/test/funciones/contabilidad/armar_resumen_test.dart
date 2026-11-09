import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_contabilidad.dart';
import 'package:tapiceria/dominio/contabilidad.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/funciones/contabilidad/armar_resumen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioContabilidad repo;
  final semana = Periodo.semana(DateTime(2026, 11, 4));
  final ahora = DateTime(2026, 11, 7);

  Timestamp ts(DateTime d) => Timestamp.fromDate(d);

  Future<void> pedido(
    String id,
    String estado, {
    DateTime? entregado,
    double pagado = 0,
    double envio = 0,
  }) => db.collection('pedidos').doc(id).set({
    'folio': 'F-$id',
    'clienteId': 'c1',
    'cliente': {'nombre': 'Ana', 'telefono': '1', 'direccion': ''},
    'entrega': 'recoge',
    'envio': envio,
    'comentarios': '',
    'fechaIngreso': ts(DateTime(2026, 1, 1)),
    'fechaEstimada': ts(DateTime(2026, 1, 2)),
    'fechaTerminado': null,
    'fechaEntregado': entregado == null ? null : ts(entregado),
    'estado': estado,
    'creadoPor': 'u1',
    'pagado': pagado,
  });

  Future<void> pago(String id, String pedidoId, num monto, DateTime f) =>
      db.collection('pagos').doc(id).set({
        'pedidoId': pedidoId,
        'monto': monto,
        'forma': 'efectivo',
        'recibidoPor': 'u1',
        'fecha': ts(f),
      });

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = RepositorioContabilidad(db);

    await pedido(
      'e',
      'entregado',
      entregado: DateTime(2026, 11, 5),
      pagado: 1500,
      envio: 300,
    );
    await db.doc('pedidos/e/muebles/m1').set({
      'tipoTrabajo': 'fabricacion',
      'tipoMueble': 'Sillón',
      'plantillaId': null,
      'precio': 6500,
      'comentarios': '',
      'estado': 'entregado',
    });
    final m = db.doc('pedidos/e/muebles/m1');
    await m.collection('materiales').doc('l1').set({
      'materialId': 'tela',
      'rolloId': 'r1',
      'cantidad': 2.5,
      'delCliente': false,
      'usuarioId': 'u1',
      'fecha': ts(DateTime(2026, 11, 3)),
    });
    await m.collection('materiales').doc('l2').set({
      'materialId': 'guata',
      'rolloId': null,
      'cantidad': 1,
      'delCliente': false,
      'usuarioId': 'u1',
      'fecha': ts(DateTime(2026, 11, 3)),
    });
    await m.collection('dias').doc('d1').set({
      'usuarioId': 'u1',
      'dias': 1.5,
      'fecha': ts(DateTime(2026, 11, 3)),
    });

    await pedido('c', 'cancelado');
    await pago('p1', 'c', 500, DateTime(2026, 11, 4));
    await pago('p2', 'e', 1500, DateTime(2026, 11, 5));
    await pago('p3', 'e', -200, DateTime(2026, 11, 6));

    await db.collection('compras').doc('k1').set({
      'materialId': 'guata',
      'precioTotal': 1200,
      'fecha': ts(DateTime(2026, 11, 4)),
      'tipo': 'compra',
    });
    await db.collection('pagos_sueldo').doc('s1').set({
      'usuarioId': 'u1',
      'monto': 1800,
      'fecha': ts(DateTime(2026, 11, 5)),
    });
    await db.doc('pedidos/e/cambios_precio/x1').set({
      'campo': 'precio',
      'muebleId': 'm1',
      'anterior': 7000,
      'nuevo': 6500,
      'motivo': null,
      'usuarioId': 'u1',
      'fecha': ts(DateTime(2026, 11, 4)),
    });

    await db.collection('materiales_costos').doc('guata').set({
      'cantidadComprada': 2,
      'costoTotalComprado': 120,
    });
    await db.collection('rollos_costos').doc('r1').set({'costoPorUnidad': 110});
    await db.collection('usuarios').doc('u1').set({
      'nombre': 'E',
      'email': 'e@x',
      'rol': 'empleado',
      'activo': true,
    });
    await db.collection('usuarios_privado').doc('u1').set({
      'sueldoSemanal': 2100,
    });
  });

  test('arma el resumen de la semana', () async {
    final r = await armarResumen(
      repo,
      periodo: semana,
      plantillas: const [],
      ahora: ahora,
    );

    expect(r.periodo, semana);
    expect(r.cobros.total, 1800);
    expect(r.gastos.total, 3000);
    expect(r.pedidosDeCobros.keys.toSet(), {'c', 'e'});
    expect(r.pedidosDeCobros['e']!.folio, 'F-e');

    expect(r.ganancias.map((g) => g.pedido.id), ['e']);
    expect(r.ganancias.single.ganancia, 5940.0);
    expect(r.gananciaTotal, 5940.0);

    expect(r.muebles[TipoTrabajo.fabricacion]!.single.mueble.id, 'm1');
    expect(r.muebles[TipoTrabajo.reparacion], isEmpty);

    expect(r.cambios.length, 1);
    expect(r.cambios.single.pedidoId, 'e');

    expect(r.pendientes.length, 1);
    expect(r.pendientes.single.pedido.id, 'e');
    expect(r.pendientes.single.saldo, 5300.0);
    expect(r.diferencias, isEmpty);
  });

  test('pendientes ordenados por saldo descendente', () async {
    await pedido('t', 'terminado', pagado: 0);
    await db.doc('pedidos/t/muebles/m1').set({
      'tipoTrabajo': 'reparacion',
      'tipoMueble': 'Silla',
      'plantillaId': null,
      'precio': 100,
      'comentarios': '',
      'estado': 'terminado',
    });
    final r = await armarResumen(
      repo,
      periodo: semana,
      plantillas: const [],
      ahora: ahora,
    );
    expect(r.pendientes.map((x) => x.pedido.id), ['e', 't']);
    expect(r.pendientes.last.saldo, 100.0);
  });

  test(
    'los cambios de un pedido sin pagos ni entrega traen folio y mueble',
    () async {
      await pedido('w', 'en_proceso');
      await db.doc('pedidos/w/muebles/mc').set({
        'tipoTrabajo': 'reparacion',
        'tipoMueble': 'Silla',
        'plantillaId': null,
        'precio': 800,
        'comentarios': '',
        'estado': 'cancelado',
      });
      await db.doc('pedidos/w/cambios_precio/x2').set({
        'campo': 'cancelacion',
        'muebleId': 'mc',
        'anterior': 800,
        'nuevo': 0,
        'motivo': null,
        'usuarioId': 'u1',
        'fecha': ts(DateTime(2026, 11, 6)),
      });
      final r = await armarResumen(
        repo,
        periodo: semana,
        plantillas: const [],
        ahora: ahora,
      );
      expect(r.pedidosDeCambios['w']!.folio, 'F-w');
      expect(r.pedidosDeCambios['e']!.folio, 'F-e');
      expect(r.mueblesDeCambios['w']!.single.tipoMueble, 'Silla');
      expect(r.pedidosDeCobros.containsKey('w'), isFalse);
    },
  );
}
