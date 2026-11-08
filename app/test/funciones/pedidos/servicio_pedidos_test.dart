import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_pedidos.dart';
import 'package:tapiceria/dominio/pedidos.dart';
import 'package:tapiceria/funciones/pedidos/servicio_pedidos.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ServicioPedidos servicio;
  late RepositorioPedidos repo;
  final ahora = DateTime(2026, 11, 7, 10);
  final manana = DateTime(2026, 11, 8);

  setUp(() {
    db = FakeFirebaseFirestore();
    servicio = ServicioPedidos(db, 'u1');
    repo = RepositorioPedidos(db);
  });

  const sofa = NuevoMueble(
      tipoTrabajo: TipoTrabajo.fabricacion, tipoMueble: 'Sofá', precio: 650);
  const silla = NuevoMueble(
      tipoTrabajo: TipoTrabajo.reparacion, tipoMueble: 'Silla', precio: 100);

  ({String pedidoId, Future<void> guardado}) crear({
    String? clienteId,
    Entrega entrega = Entrega.domicilio,
    double envio = 200,
    String direccion = 'Calle 1',
    DateTime? fecha,
    List<NuevoMueble> muebles = const [sofa, silla],
    double anticipo = 0,
  }) =>
      servicio.crearPedido(
        clienteId: clienteId,
        nombre: ' Ana ',
        telefono: '5551234567',
        direccion: direccion,
        entrega: entrega,
        envio: envio,
        comentarios: '',
        fechaEstimada: fecha ?? manana,
        muebles: muebles,
        ahora: ahora,
        anticipo: anticipo,
      );

  Future<int> contar(String c) async => (await db.collection(c).get()).size;

  Future<(Pedido, List<Mueble>)> leer(String id) async {
    final p = (await repo.observarPedido(id).first)!;
    final m = await repo.observarMuebles(id).first;
    return (p, m);
  }

  CollectionReference<Map<String, dynamic>> cambiosDe(String id) =>
      db.collection('pedidos').doc(id).collection('cambios_precio');

  test('crearPedido con cliente nuevo', () async {
    final r = crear();
    await r.guardado;
    expect(await contar('clientes'), 1);
    expect(await contar('pedidos'), 1);
    final (p, m) = await leer(r.pedidoId);
    expect(m.length, 2);
    expect(p.estado, EstadoMueble.recibido);
    expect(p.cliente.nombre, 'Ana');
    expect(p.folio, matches(RegExp(r'^261107-[0-9A-Z]{4}$')));
    expect(p.creadoPor, 'u1');
    final doc = await db.collection('pedidos').doc(r.pedidoId).get();
    expect(doc.data()!['ultimoCambioId'], isNull);
  });

  test('crearPedido con cliente existente no crea cliente', () async {
    await crear(clienteId: 'c9').guardado;
    expect(await contar('clientes'), 0);
    expect(await contar('pedidos'), 1);
  });

  test('validaciones no escriben nada', () async {
    expect(() => crear(muebles: []), throwsArgumentError);
    expect(() => crear(entrega: Entrega.recoge, envio: 200),
        throwsArgumentError);
    expect(() => crear(direccion: '  '), throwsArgumentError);
    expect(() => crear(fecha: DateTime(2026, 11, 6)), throwsArgumentError);
    expect(
        () => crear(muebles: [
              const NuevoMueble(
                  tipoTrabajo: TipoTrabajo.fabricacion,
                  tipoMueble: ' ',
                  precio: 1)
            ]),
        throwsArgumentError);
    expect(await contar('clientes'), 0);
    expect(await contar('pedidos'), 0);
  });

  test('anticipo de 500 crea el pago, pagado y la caja', () async {
    final r = crear(anticipo: 500);
    await r.guardado;
    final pagos = (await db.collection('pagos').get()).docs;
    expect(pagos.length, 1);
    expect(pagos.single.data()['monto'], 500);
    expect(pagos.single.data()['pedidoId'], r.pedidoId);
    final doc = await db.collection('pedidos').doc(r.pedidoId).get();
    expect(doc.data()!['pagado'], 500);
    expect(doc.data()!['ultimoPagoId'], pagos.single.id);
    final caja = await db.collection('cajas').doc('u1').get();
    expect(caja.data()!['enMano'], 500);
  });

  test('sin anticipo no crea pago y pagado es 0', () async {
    final r = crear();
    await r.guardado;
    expect(await contar('pagos'), 0);
    final doc = await db.collection('pedidos').doc(r.pedidoId).get();
    expect(doc.data()!['pagado'], 0);
    expect(doc.data()!['ultimoPagoId'], isNull);
  });

  test('anticipo inválido lanza y no escribe', () async {
    // total = 650 + 100 + 200 = 950
    expect(() => crear(anticipo: 2000), throwsArgumentError);
    expect(() => crear(anticipo: -1), throwsArgumentError);
    expect(() => crear(anticipo: double.nan), throwsArgumentError);
    expect(await contar('pedidos'), 0);
    expect(await contar('pagos'), 0);
  });

  test('crearPedido devuelve el id antes de esperar guardado', () {
    final r = crear();
    expect(r.pedidoId, isNotEmpty);
    expect(r.guardado, isA<Future<void>>());
  });

  test('cambiarEstadoMueble fija fechaTerminado solo la primera vez', () async {
    final r = crear();
    await r.guardado;
    var (p, m) = await leer(r.pedidoId);
    final a = m.first.id;
    final b = m.last.id;
    await servicio.cambiarEstadoMueble(
        pedido: p, muebles: m, muebleId: b, nuevo: EstadoMueble.cancelado);
    (p, m) = await leer(r.pedidoId);
    await servicio.cambiarEstadoMueble(
        pedido: p,
        muebles: m,
        muebleId: a,
        nuevo: EstadoMueble.terminado,
        ahora: ahora);
    (p, m) = await leer(r.pedidoId);
    expect(p.estado, EstadoMueble.terminado);
    expect(p.fechaTerminado, ahora);

    await servicio.cambiarEstadoMueble(
        pedido: p, muebles: m, muebleId: a, nuevo: EstadoMueble.enProceso);
    (p, m) = await leer(r.pedidoId);
    expect(p.estado, EstadoMueble.enProceso);
    await servicio.cambiarEstadoMueble(
        pedido: p,
        muebles: m,
        muebleId: a,
        nuevo: EstadoMueble.terminado,
        ahora: ahora.add(const Duration(days: 3)));
    (p, _) = await leer(r.pedidoId);
    expect(p.estado, EstadoMueble.terminado);
    expect(p.fechaTerminado, ahora);
  });

  test('entregar todo fija fechaEntregado', () async {
    final r = crear(muebles: [sofa]);
    await r.guardado;
    final (p, m) = await leer(r.pedidoId);
    await servicio.cambiarEstadoMueble(
        pedido: p,
        muebles: m,
        muebleId: m.first.id,
        nuevo: EstadoMueble.entregado,
        ahora: ahora);
    final (p2, _) = await leer(r.pedidoId);
    expect(p2.estado, EstadoMueble.entregado);
    expect(p2.fechaEntregado, ahora);
  });

  test('cancelarPedido respeta los entregados', () async {
    final r = crear();
    await r.guardado;
    var (p, m) = await leer(r.pedidoId);
    await servicio.cambiarEstadoMueble(
        pedido: p,
        muebles: m,
        muebleId: m.first.id,
        nuevo: EstadoMueble.entregado);
    (p, m) = await leer(r.pedidoId);
    await servicio.cancelarPedido(pedido: p, muebles: m);
    final (p2, m2) = await leer(r.pedidoId);
    expect(m2.map((x) => x.estado).toSet(),
        {EstadoMueble.entregado, EstadoMueble.cancelado});
    expect(p2.estado, EstadoMueble.entregado);
  });

  test('reconciliarEstado corrige un pedido con estado viejo', () async {
    final r = crear();
    await r.guardado;
    final ped = db.collection('pedidos').doc(r.pedidoId);
    for (final d in (await ped.collection('muebles').get()).docs) {
      await d.reference.update({'estado': 'terminado'});
    }
    await ped.update({'estado': 'en_proceso'});
    final (p, m) = await leer(r.pedidoId);
    final f = servicio.reconciliarEstado(pedido: p, muebles: m, ahora: ahora);
    expect(f, isNotNull);
    await f;
    final (p2, _) = await leer(r.pedidoId);
    expect(p2.estado, EstadoMueble.terminado);
    expect(p2.fechaTerminado, ahora);
  });

  test('reconciliarEstado devuelve null si no hay nada que escribir',
      () async {
    final r = crear();
    await r.guardado;
    final (p, m) = await leer(r.pedidoId);
    expect(servicio.reconciliarEstado(pedido: p, muebles: m), isNull);
    expect(servicio.reconciliarEstado(pedido: p, muebles: const []), isNull);
  });

  test('cancelarPedido fija fechaEntregado si queda entregado', () async {
    final r = crear();
    await r.guardado;
    var (p, m) = await leer(r.pedidoId);
    await servicio.cambiarEstadoMueble(
        pedido: p,
        muebles: m,
        muebleId: m.first.id,
        nuevo: EstadoMueble.entregado);
    (p, m) = await leer(r.pedidoId);
    expect(p.fechaEntregado, isNull);
    await servicio.cancelarPedido(pedido: p, muebles: m, ahora: ahora);
    final (p2, _) = await leer(r.pedidoId);
    expect(p2.estado, EstadoMueble.entregado);
    expect(p2.fechaEntregado, ahora);
  });

  test('agregarMueble recalcula el estado', () async {
    final r = crear(muebles: [sofa]);
    await r.guardado;
    var (p, m) = await leer(r.pedidoId);
    await servicio.cambiarEstadoMueble(
        pedido: p,
        muebles: m,
        muebleId: m.first.id,
        nuevo: EstadoMueble.terminado,
        ahora: ahora);
    (p, m) = await leer(r.pedidoId);
    await servicio.agregarMueble(pedido: p, muebles: m, nuevo: silla);
    final (p2, m2) = await leer(r.pedidoId);
    expect(m2.length, 2);
    expect(p2.estado, EstadoMueble.recibido);
  });

  test('agregarMueble deja el registro de alta y lo enlaza', () async {
    final r = crear(muebles: [sofa]);
    await r.guardado;
    final (p, m) = await leer(r.pedidoId);
    const nuevo = NuevoMueble(
        tipoTrabajo: TipoTrabajo.reparacion, tipoMueble: 'Silla', precio: 600);
    await servicio.agregarMueble(pedido: p, muebles: m, nuevo: nuevo);
    final cambios = await cambiosDe(r.pedidoId).get();
    expect(cambios.size, 1);
    final c = cambios.docs.single.data();
    expect(c['campo'], 'alta');
    expect(c['anterior'], 0);
    expect(c['nuevo'], 600);
    expect(c['motivo'], isNull);
    expect(c['usuarioId'], 'u1');
    final (_, m2) = await leer(r.pedidoId);
    final creado = m2.firstWhere((x) => x.tipoMueble == 'Silla');
    expect(c['muebleId'], creado.id);
    final doc = await db
        .collection('pedidos')
        .doc(r.pedidoId)
        .collection('muebles')
        .doc(creado.id)
        .get();
    expect(doc['ultimoCambioId'], cambios.docs.single.id);
  });

  test('agregarMueble redondea el precio igual que su registro', () async {
    final r = crear(muebles: [sofa]);
    await r.guardado;
    final (p, m) = await leer(r.pedidoId);
    const nuevo = NuevoMueble(
        tipoTrabajo: TipoTrabajo.reparacion,
        tipoMueble: 'Silla',
        precio: 600.005);
    await servicio.agregarMueble(pedido: p, muebles: m, nuevo: nuevo);
    final c = (await cambiosDe(r.pedidoId).get()).docs.single.data();
    final (_, m2) = await leer(r.pedidoId);
    final creado = m2.firstWhere((x) => x.tipoMueble == 'Silla');
    expect(creado.precio, c['nuevo']);
  });

  test('cancelar un mueble deja el registro de cancelación', () async {
    final r = crear();
    await r.guardado;
    final (p, m) = await leer(r.pedidoId);
    final s = m.firstWhere((x) => x.tipoMueble == 'Sofá');
    await servicio.cambiarEstadoMueble(
        pedido: p, muebles: m, muebleId: s.id, nuevo: EstadoMueble.cancelado);
    final cambios = await cambiosDe(r.pedidoId).get();
    expect(cambios.size, 1);
    final c = cambios.docs.single.data();
    expect(c['campo'], 'cancelacion');
    expect(c['usuarioId'], 'u1');
    expect(c['muebleId'], s.id);
    expect(c['anterior'], 650);
    expect(c['nuevo'], 0);
    expect(c['motivo'], isNull);
    final doc = await db
        .collection('pedidos')
        .doc(r.pedidoId)
        .collection('muebles')
        .doc(s.id)
        .get();
    expect(doc['ultimoCambioId'], cambios.docs.single.id);
    expect(doc['estado'], 'cancelado');
  });

  test('cancelarPedido deja un registro por mueble que cancela', () async {
    final r = crear(muebles: [sofa, silla, sofa]);
    await r.guardado;
    var (p, m) = await leer(r.pedidoId);
    await servicio.cambiarEstadoMueble(
        pedido: p,
        muebles: m,
        muebleId: m.first.id,
        nuevo: EstadoMueble.entregado);
    (p, m) = await leer(r.pedidoId);
    await servicio.cancelarPedido(pedido: p, muebles: m);
    final cambios = await cambiosDe(r.pedidoId).get();
    expect(cambios.size, 2);
    expect(cambios.docs.map((d) => d.data()['campo']).toSet(), {'cancelacion'});
  });

  test('un mueble cancelado no se puede reactivar', () async {
    final r = crear();
    await r.guardado;
    var (p, m) = await leer(r.pedidoId);
    final id = m.first.id;
    await servicio.cambiarEstadoMueble(
        pedido: p, muebles: m, muebleId: id, nuevo: EstadoMueble.cancelado);
    (p, m) = await leer(r.pedidoId);
    expect(
        () => servicio.cambiarEstadoMueble(
            pedido: p, muebles: m, muebleId: id, nuevo: EstadoMueble.recibido),
        throwsArgumentError);
  });

  test('cambiarPrecioMueble registra el cambio', () async {
    final r = crear();
    await r.guardado;
    final (_, m) = await leer(r.pedidoId);
    final mueble = m.firstWhere((x) => x.tipoMueble == 'Sofá');
    await servicio.cambiarPrecioMueble(
        pedidoId: r.pedidoId,
        mueble: mueble,
        nuevo: 600,
        motivo: '  descuento ');
    final cambios = await cambiosDe(r.pedidoId).get();
    expect(cambios.size, 1);
    final c = cambios.docs.single.data();
    expect(c['motivo'], 'descuento');
    expect(c['anterior'], 650);
    expect(c['nuevo'], 600);
    expect(c['campo'], 'precio');
    expect(c['usuarioId'], 'u1');
    final doc = await db
        .collection('pedidos')
        .doc(r.pedidoId)
        .collection('muebles')
        .doc(mueble.id)
        .get();
    expect(doc.data()!['ultimoCambioId'], cambios.docs.single.id);
    expect(doc.data()!['precio'], 600);

    await expectLater(
        servicio.cambiarPrecioMueble(
            pedidoId: r.pedidoId, mueble: mueble, nuevo: 650),
        throwsArgumentError);
    await expectLater(
        servicio.cambiarPrecioMueble(
            pedidoId: r.pedidoId, mueble: mueble, nuevo: -1),
        throwsArgumentError);
    await expectLater(
        servicio.cambiarPrecioMueble(
            pedidoId: r.pedidoId,
            mueble: mueble,
            nuevo: 10,
            motivo: 'x' * 201),
        throwsArgumentError);
    expect((await cambiosDe(r.pedidoId).get()).size, 1);
  });

  test('cambiarEnvio registra el cambio', () async {
    final r = crear();
    await r.guardado;
    final (p, _) = await leer(r.pedidoId);
    await expectLater(
        servicio.cambiarEnvio(pedido: p, entrega: Entrega.recoge, envio: 50),
        throwsArgumentError);
    await expectLater(
        servicio.cambiarEnvio(
            pedido: p, entrega: Entrega.domicilio, envio: 200),
        throwsArgumentError);
    await servicio.cambiarEnvio(pedido: p, entrega: Entrega.recoge, envio: 0);
    final cambios = await cambiosDe(r.pedidoId).get();
    expect(cambios.size, 1);
    final c = cambios.docs.single.data();
    expect(c['campo'], 'envio');
    expect(c['anterior'], 200);
    expect(c['nuevo'], 0);
    expect(c['muebleId'], isNull);
    final (p2, _) = await leer(r.pedidoId);
    expect(p2.entrega, Entrega.recoge);
    expect(p2.envio, 0);
    final doc = await db.collection('pedidos').doc(r.pedidoId).get();
    expect(doc.data()!['ultimoCambioId'], cambios.docs.single.id);
  });

  test('cambiarEnvio solo de entrega no crea registro', () async {
    final r = crear(entrega: Entrega.domicilio, envio: 0);
    await r.guardado;
    final (p, _) = await leer(r.pedidoId);
    await servicio.cambiarEnvio(pedido: p, entrega: Entrega.recoge, envio: 0);
    expect((await cambiosDe(r.pedidoId).get()).size, 0);
    expect((await leer(r.pedidoId)).$1.entrega, Entrega.recoge);
  });

  test('editarPedido actualiza comentarios y fecha', () async {
    final r = crear();
    await r.guardado;
    await servicio.editarPedido(
        pedidoId: r.pedidoId,
        comentarios: ' nota ',
        fechaEstimada: DateTime(2026, 12, 1));
    final (p, _) = await leer(r.pedidoId);
    expect(p.comentarios, 'nota');
    expect(p.fechaEstimada, DateTime(2026, 12, 1));
  });

  test('las fechas se guardan como Timestamp', () async {
    final r = crear();
    await r.guardado;
    final d = await db.collection('pedidos').doc(r.pedidoId).get();
    expect(d.data()!['fechaIngreso'], isA<Timestamp>());
  });
}
