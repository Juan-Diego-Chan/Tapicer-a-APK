import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_contabilidad.dart';
import 'package:tapiceria/dominio/contabilidad.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioContabilidad repo;
  final semana = Periodo.semana(DateTime(2026, 11, 4));

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioContabilidad(db);
  });

  Timestamp ts(DateTime d) => Timestamp.fromDate(d);

  Map<String, dynamic> pago(DateTime f, {Object monto = 100}) => {
        'pedidoId': 'p1',
        'monto': monto,
        'forma': 'efectivo',
        'recibidoPor': 'u1',
        'fecha': ts(f),
      };

  Future<void> pedido(String id, String estado,
          {DateTime? entregado, DateTime? terminado}) =>
      db.collection('pedidos').doc(id).set({
        'folio': 'F-$id',
        'clienteId': 'c1',
        'cliente': {'nombre': 'Ana', 'telefono': '1', 'direccion': ''},
        'entrega': 'recoge',
        'envio': 0,
        'comentarios': '',
        'fechaIngreso': ts(DateTime(2026, 1, 1)),
        'fechaEstimada': ts(DateTime(2026, 1, 2)),
        'fechaTerminado': terminado == null ? null : ts(terminado),
        'fechaEntregado': entregado == null ? null : ts(entregado),
        'estado': estado,
        'creadoPor': 'u1',
      });

  test('pagosEn excluye 1 ms antes de desde y justo en hasta', () async {
    final c = db.collection('pagos');
    await c.doc('a').set(pago(semana.desde));
    await c
        .doc('b')
        .set(pago(semana.hasta.subtract(const Duration(milliseconds: 1))));
    await c
        .doc('antes')
        .set(pago(semana.desde.subtract(const Duration(milliseconds: 1))));
    await c.doc('en_hasta').set(pago(semana.hasta));
    final r = await repo.pagosEn(semana);
    expect(r.map((p) => p.id).toSet(), {'a', 'b'});
  });

  test('comprasEn incluye compras iniciales', () async {
    await db.collection('compras').doc('c1').set({
      'materialId': 'guata',
      'precioTotal': 0,
      'fecha': ts(DateTime(2026, 11, 4)),
      'tipo': 'inicial',
    });
    final r = await repo.comprasEn(semana);
    expect(r.single.tipo, 'inicial');
  });

  test('sueldosEn trae los sueldos del periodo', () async {
    await db.collection('pagos_sueldo').doc('s1').set(
        {'usuarioId': 'e1', 'monto': 500, 'fecha': ts(DateTime(2026, 11, 5))});
    await db.collection('pagos_sueldo').doc('s2').set(
        {'usuarioId': 'e1', 'monto': 500, 'fecha': ts(DateTime(2026, 10, 1))});
    expect((await repo.sueldosEn(semana)).map((s) => s.id), ['s1']);
  });

  test('entregadosEn excluye cancelados', () async {
    await pedido('ok', 'entregado', entregado: DateTime(2026, 11, 5));
    await pedido('can', 'cancelado', entregado: DateTime(2026, 11, 5));
    await pedido('fuera', 'entregado', entregado: DateTime(2026, 10, 5));
    expect((await repo.entregadosEn(semana)).map((p) => p.id), ['ok']);
  });

  test('cambiosEn regresa el pedidoId correcto', () async {
    Map<String, dynamic> cambio(DateTime f) => {
          'campo': 'precio',
          'muebleId': 'm1',
          'anterior': 100,
          'nuevo': 80,
          'motivo': null,
          'usuarioId': 'u1',
          'fecha': ts(f),
        };
    await db
        .doc('pedidos/pa/cambios_precio/x1')
        .set(cambio(DateTime(2026, 11, 4)));
    await db
        .doc('pedidos/pb/cambios_precio/x2')
        .set(cambio(DateTime(2026, 11, 5)));
    await db
        .doc('pedidos/pb/cambios_precio/x3')
        .set(cambio(DateTime(2026, 9, 5)));
    final r = await repo.cambiosEn(semana);
    expect(
        {for (final c in r) c.cambio.id: c.pedidoId}, {'x1': 'pa', 'x2': 'pb'});
  });

  test('candidatosPendientes: terminados y entregados recientes', () async {
    final ahora = DateTime(2026, 11, 7);
    await pedido('t', 'terminado', terminado: DateTime(2025, 11, 7));
    await pedido('e10', 'entregado',
        entregado: ahora.subtract(const Duration(days: 10)));
    await pedido('e200', 'entregado',
        entregado: ahora.subtract(const Duration(days: 200)));
    final r = await repo.candidatosPendientes(ahora);
    expect(r.map((p) => p.id).toSet(), {'t', 'e10'});
  });

  test('pedidosPorId ignora inexistentes', () async {
    await pedido('a', 'terminado');
    final r = await repo.pedidosPorId(['a', 'a', 'zz']);
    expect(r.keys, ['a']);
  });

  test('detalle: muebles, lineas y dias', () async {
    await pedido('a', 'terminado');
    final m = db.doc('pedidos/a/muebles/m1');
    await m.set({
      'tipoTrabajo': 'fabricacion',
      'tipoMueble': 'Sofá',
      'plantillaId': null,
      'precio': 1000,
      'comentarios': '',
      'estado': 'terminado',
    });
    await m.collection('materiales').doc('l1').set({
      'materialId': 'guata',
      'rolloId': null,
      'cantidad': 2,
      'delCliente': false,
      'usuarioId': 'u1',
      'fecha': ts(DateTime(2026, 11, 4)),
    });
    await m.collection('dias').doc('d1').set(
        {'usuarioId': 'u1', 'dias': 1, 'fecha': ts(DateTime(2026, 11, 4))});
    expect((await repo.mueblesDe('a')).single.id, 'm1');
    expect((await repo.lineasDe('a', 'm1')).single.id, 'l1');
    expect((await repo.diasDe('a', 'm1')).single.id, 'd1');
  });

  test('costos: material, dueño 0, empleado sin sueldo null', () async {
    await db
        .collection('materiales_costos')
        .doc('guata')
        .set({'cantidadComprada': 2, 'costoTotalComprado': 120});
    await db.collection('rollos_costos').doc('r1').set({'costoPorUnidad': 15});
    await db.collection('usuarios').doc('d').set(
        {'nombre': 'D', 'email': 'd@x', 'rol': 'dueno', 'activo': true});
    await db.collection('usuarios').doc('e1').set(
        {'nombre': 'E', 'email': 'e@x', 'rol': 'empleado', 'activo': true});
    await db.collection('usuarios').doc('e2').set(
        {'nombre': 'F', 'email': 'f@x', 'rol': 'empleado', 'activo': true});
    await db
        .collection('usuarios_privado')
        .doc('e1')
        .set({'sueldoSemanal': 600});
    final c = await repo.costos();
    expect(c.costoMaterial('guata'), 60);
    expect(c.costoMaterial('nada'), isNull);
    expect(c.costoRollo('r1'), 15);
    expect(c.costoDiaDe('d'), 0);
    expect(c.costoDiaDe('e1'), 100);
    expect(c.costoDiaDe('e2'), isNull);
    expect(c.costoDiaDe('desconocido'), isNull);
  });

  test('omite documentos mal formados', () async {
    await db.collection('pagos').doc('bueno').set(pago(DateTime(2026, 11, 4)));
    await db
        .collection('pagos')
        .doc('malo')
        .set(pago(DateTime(2026, 11, 4), monto: 'x'));
    expect((await repo.pagosEn(semana)).map((p) => p.id), ['bueno']);
  });
}
