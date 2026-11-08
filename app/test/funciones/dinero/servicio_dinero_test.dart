import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/dinero.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/dinero/servicio_dinero.dart';

void main() {
  late FakeFirebaseFirestore db;

  Pedido pedido({double pagado = 0}) => Pedido(
        id: 'pe1',
        folio: 'P-1',
        cliente: const Cliente(
            id: 'c1', nombre: 'Ana', telefono: '555', direccion: 'x'),
        entrega: Entrega.recoge,
        envio: 0,
        comentarios: '',
        fechaIngreso: DateTime(2026, 11, 7),
        fechaEstimada: DateTime(2026, 11, 8),
        fechaTerminado: null,
        fechaEntregado: null,
        estado: EstadoMueble.recibido,
        creadoPor: 'u',
        pagado: pagado,
      );

  DateTime? aFecha(Object? v) => v is Timestamp ? v.toDate() : null;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('pedidos').doc('pe1').set({'pagado': 0});
  });

  Matcher lanza(String msg) =>
      throwsA(isA<ArgumentError>().having((e) => e.message, 'message', msg));

  Future<Map<String, dynamic>> leer(String col, String id) async =>
      (await db.collection(col).doc(id).get()).data()!;

  test('empleado cobra: pago, pedido y caja con el mismo ultimoPagoId',
      () async {
    final s = ServicioDinero(db, 'emp1', Rol.empleado);
    await s.registrarPago(
        pedido: pedido(), saldo: 1000, monto: 500, forma: FormaPago.efectivo);
    final pagos = await db.collection('pagos').get();
    expect(pagos.docs, hasLength(1));
    final id = pagos.docs.single.id;
    final p = pagos.docs.single.data();
    expect(p['monto'], 500);
    expect(p['recibidoPor'], 'emp1');
    expect(p['forma'], 'efectivo');
    final ped = await leer('pedidos', 'pe1');
    expect(ped['pagado'], 500);
    expect(ped['ultimoPagoId'], id);
    final caja = await leer('cajas', 'emp1');
    expect(caja['enMano'], 500);
    expect(caja['ultimoPagoId'], id);
    expect(caja.containsKey('ultimaEntregaId'), isFalse);
  });

  test('dueño cobra: no se crea caja', () async {
    final s = ServicioDinero(db, 'dueno1', Rol.dueno);
    await s.registrarPago(
        pedido: pedido(),
        saldo: 1000,
        monto: 300,
        forma: FormaPago.transferencia);
    expect((await db.collection('cajas').get()).docs, isEmpty);
    expect((await leer('pedidos', 'pe1'))['pagado'], 300);
  });

  test('pago mayor que el saldo y montos inválidos lanzan', () async {
    final s = ServicioDinero(db, 'emp1', Rol.empleado);
    expect(
        () => s.registrarPago(
            pedido: pedido(),
            saldo: 1000,
            monto: 1200,
            forma: FormaPago.efectivo),
        lanza(r'El pago es mayor que el saldo ($1,000.00)'));
    expect(
        () => s.registrarPago(
            pedido: pedido(),
            saldo: 1000,
            monto: 0,
            forma: FormaPago.efectivo),
        lanza('El monto debe ser mayor a 0'));
    expect(
        () => s.registrarPago(
            pedido: pedido(),
            saldo: 1000,
            monto: double.nan,
            forma: FormaPago.efectivo),
        lanza('El monto debe ser mayor a 0'));
    expect((await db.collection('pagos').get()).docs, isEmpty);
  });

  test('devolución: empleado no puede; dueño crea pago negativo', () async {
    final emp = ServicioDinero(db, 'emp1', Rol.empleado);
    expect(
        () => emp.registrarDevolucion(
            pedido: pedido(pagado: 500), monto: 200, forma: FormaPago.efectivo),
        lanza('Solo el dueño puede hacer esto'));
    await db.collection('pedidos').doc('pe1').update({'pagado': 500});
    final d = ServicioDinero(db, 'dueno1', Rol.dueno);
    expect(
        () => d.registrarDevolucion(
            pedido: pedido(pagado: 500), monto: 600, forma: FormaPago.efectivo),
        lanza(r'La devolución es mayor que lo pagado ($500.00)'));
    await d.registrarDevolucion(
        pedido: pedido(pagado: 500), monto: 200, forma: FormaPago.efectivo);
    final pagos = await db.collection('pagos').get();
    expect(pagos.docs.single.data()['monto'], -200);
    expect((await leer('pedidos', 'pe1'))['pagado'], 300);
    expect((await db.collection('cajas').get()).docs, isEmpty);
  });

  test('borrarPago descuenta pedido y, si fue de empleado, la caja', () async {
    final emp = ServicioDinero(db, 'emp1', Rol.empleado);
    await emp.registrarPago(
        pedido: pedido(), saldo: 1000, monto: 500, forma: FormaPago.efectivo);
    final doc = (await db.collection('pagos').get()).docs.single;
    final pago = Pago.desdeMapa(doc.id, doc.data(), aFecha);
    final dueno = ServicioDinero(db, 'dueno1', Rol.dueno);
    expect(() => emp.borrarPago(pago: pago, cobroDeEmpleado: true),
        lanza('Solo el dueño puede hacer esto'));
    await dueno.borrarPago(pago: pago, cobroDeEmpleado: true);
    expect((await db.collection('pagos').get()).docs, isEmpty);
    expect((await leer('pedidos', 'pe1'))['pagado'], 0);
    expect((await leer('cajas', 'emp1'))['enMano'], 0);
  });

  test('borrarPago sin cobroDeEmpleado solo toca el pedido', () async {
    final dueno = ServicioDinero(db, 'dueno1', Rol.dueno);
    await dueno.registrarPago(
        pedido: pedido(), saldo: 1000, monto: 400, forma: FormaPago.efectivo);
    final doc = (await db.collection('pagos').get()).docs.single;
    final pago = Pago.desdeMapa(doc.id, doc.data(), aFecha);
    await dueno.borrarPago(pago: pago, cobroDeEmpleado: false);
    expect((await leer('pedidos', 'pe1'))['pagado'], 0);
    expect((await db.collection('cajas').get()).docs, isEmpty);
  });

  test('entrega, confirmar y rechazar', () async {
    final emp = ServicioDinero(db, 'emp1', Rol.empleado);
    final dueno = ServicioDinero(db, 'dueno1', Rol.dueno);
    await db.collection('cajas').doc('emp1').set({'enMano': 700});
    expect(
        () => emp.registrarEntrega(
            porEntregar: 700, monto: 800, forma: FormaPago.efectivo),
        lanza(r'La entrega es mayor que lo que tienes por entregar ($700.00)'));
    expect(
        () => dueno.registrarEntrega(
            porEntregar: 700, monto: 100, forma: FormaPago.efectivo),
        throwsA(isA<ArgumentError>()));
    await emp.registrarEntrega(
        porEntregar: 700, monto: 300, forma: FormaPago.efectivo);
    await emp.registrarEntrega(
        porEntregar: 400, monto: 200, forma: FormaPago.efectivo);
    final docs = (await db.collection('entregas').get()).docs;
    expect(docs, hasLength(2));
    final crudo = docs.firstWhere((d) => d.data()['monto'] == 300).data();
    expect(crudo['estado'], 'pendiente');
    expect(crudo['revisadoEn'], isNull);
    expect(crudo['empleadoId'], 'emp1');
    EntregaDinero ent(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
        EntregaDinero.desdeMapa(d.id, d.data(), aFecha);
    final e1 = ent(docs.firstWhere((d) => d.data()['monto'] == 300));
    final e2 = ent(docs.firstWhere((d) => d.data()['monto'] == 200));

    expect(() => emp.confirmarEntrega(e1),
        lanza('Solo el dueño puede hacer esto'));
    await dueno.confirmarEntrega(e1);
    final d1 = await leer('entregas', e1.id);
    expect(d1['estado'], 'confirmada');
    expect(d1['revisadoEn'], isNotNull);
    final caja = await leer('cajas', 'emp1');
    expect(caja['enMano'], 400);
    expect(caja['ultimaEntregaId'], e1.id);
    expect(caja.containsKey('ultimoPagoId'), isFalse);

    await dueno.rechazarEntrega(e2);
    expect((await leer('entregas', e2.id))['estado'], 'rechazada');
    expect((await leer('cajas', 'emp1'))['enMano'], 400);
  });

  test('pagos de sueldo', () async {
    final dueno = ServicioDinero(db, 'dueno1', Rol.dueno);
    await dueno.registrarPagoSueldo(
        usuarioId: 'emp1', monto: 1500, fecha: DateTime(2026, 11, 7));
    final docs = (await db.collection('pagos_sueldo').get()).docs;
    expect(docs.single.data()['usuarioId'], 'emp1');
    expect(docs.single.data()['monto'], 1500);
    await dueno.borrarPagoSueldo(docs.single.id);
    expect((await db.collection('pagos_sueldo').get()).docs, isEmpty);
    final emp = ServicioDinero(db, 'emp1', Rol.empleado);
    expect(
        () => emp.registrarPagoSueldo(
            usuarioId: 'emp1', monto: 10, fecha: DateTime(2026)),
        lanza('Solo el dueño puede hacer esto'));
  });
}
