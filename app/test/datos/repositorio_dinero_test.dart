import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_dinero.dart';
import 'package:tapiceria/dominio/dinero.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioDinero repo;
  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioDinero(db);
  });

  Map<String, dynamic> pago(String pedido, String por, num monto, int dia) => {
        'pedidoId': pedido,
        'monto': monto,
        'forma': 'efectivo',
        'recibidoPor': por,
        'fecha': Timestamp.fromDate(DateTime(2026, 11, dia)),
      };

  Map<String, dynamic> entrega(Object monto, String estado, int dia) => {
        'empleadoId': 'emp1',
        'monto': monto,
        'forma': 'efectivo',
        'fecha': Timestamp.fromDate(DateTime(2026, 11, dia)),
        'estado': estado,
        'revisadoEn': null,
      };

  test('observarEnMano sin caja emite 0, con caja el valor', () async {
    expect(await repo.observarEnMano('emp1').first, 0);
    await db.collection('cajas').doc('emp1').set({'enMano': 250});
    expect(await repo.observarEnMano('emp1').first, 250);
  });

  test('observarCajas mapea uid a en mano', () async {
    await db.collection('cajas').doc('a').set({'enMano': 10});
    await db.collection('cajas').doc('b').set({'enMano': 20});
    expect(await repo.observarCajas().first, {'a': 10.0, 'b': 20.0});
  });

  test('pagos del pedido: dueño ve todos ordenados; empleado solo los suyos',
      () async {
    await db.collection('pagos').doc('p2').set(pago('pe1', 'emp2', 200, 9));
    await db.collection('pagos').doc('p1').set(pago('pe1', 'emp1', 100, 8));
    await db.collection('pagos').doc('px').set(pago('pe2', 'emp1', 5, 8));
    final todos = await repo.observarPagosPedido('pe1').first;
    expect(todos.map((p) => p.id), ['p1', 'p2']);
    final mios = await repo.observarMisPagosPedido('pe1', 'emp1').first;
    expect(mios.map((p) => p.id), ['p1']);
  });

  test('entregas pendientes omite documentos mal formados', () async {
    await db.collection('entregas').doc('ok').set(entrega(100, 'pendiente', 7));
    await db.collection('entregas').doc('mal').set(entrega('x', 'pendiente', 7));
    await db.collection('entregas').doc('conf').set(entrega(50, 'confirmada', 7));
    final l = await repo.observarEntregasPendientes().first;
    expect(l.map((x) => x.id), ['ok']);
    expect(l.single.estado, EstadoEntrega.pendiente);
  });

  test('entregas de un usuario, recientes primero', () async {
    await db.collection('entregas').doc('a').set(entrega(10, 'pendiente', 1));
    await db.collection('entregas').doc('b').set(entrega(10, 'pendiente', 3));
    await db.collection('entregas').doc('c').set(entrega(10, 'pendiente', 2));
    final l = await repo.observarEntregasDe('emp1').first;
    expect(l.map((x) => x.id), ['b', 'c', 'a']);
  });

  test('pagos de sueldo de un usuario, recientes primero', () async {
    for (final (id, dia) in [('a', 1), ('b', 2)]) {
      await db.collection('pagos_sueldo').doc(id).set({
        'usuarioId': 'emp1',
        'monto': 100,
        'fecha': Timestamp.fromDate(DateTime(2026, 11, dia)),
      });
    }
    final l = await repo.observarPagosSueldo('emp1').first;
    expect(l.map((x) => x.id), ['b', 'a']);
  });
}
