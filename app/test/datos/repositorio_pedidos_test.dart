import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_clientes.dart';
import 'package:tapiceria/datos/repositorio_pedidos.dart';
import 'package:tapiceria/datos/repositorio_plantillas.dart';
import 'package:tapiceria/dominio/pedidos.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioPedidos repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioPedidos(db);
  });

  Future<void> pedido(String id, String estado, DateTime estimada) =>
      db.collection('pedidos').doc(id).set({
        'folio': '261107-${id.toUpperCase()}',
        'clienteId': 'c1',
        'cliente': {'nombre': 'Ana', 'telefono': '1', 'direccion': ''},
        'entrega': 'recoge',
        'envio': 0,
        'comentarios': '',
        'fechaIngreso': Timestamp.fromDate(DateTime(2026, 11, 7)),
        'fechaEstimada': Timestamp.fromDate(estimada),
        'fechaTerminado': null,
        'fechaEntregado': null,
        'estado': estado,
        'creadoPor': 'u1',
        'ultimoCambioId': null,
      });

  Future<void> mueble(String pedidoId, String id, String tipo, String estado,
          [String nombre = 'Sofá']) =>
      db
          .collection('pedidos')
          .doc(pedidoId)
          .collection('muebles')
          .doc(id)
          .set({
        'tipoTrabajo': tipo,
        'tipoMueble': nombre,
        'plantillaId': null,
        'precio': 100,
        'comentarios': '',
        'estado': estado,
        'ultimoCambioId': null,
      });

  test('observarMueblesActivos filtra por tipo y estado y trae el pedidoId',
      () async {
    await pedido('p1', 'recibido', DateTime(2026, 12, 1));
    await pedido('p2', 'entregado', DateTime(2026, 12, 1));
    await mueble('p1', 'm1', 'fabricacion', 'en_proceso');
    await mueble('p1', 'm2', 'reparacion', 'recibido');
    await mueble('p2', 'm3', 'fabricacion', 'entregado');
    final lista =
        await repo.observarMueblesActivos(TipoTrabajo.fabricacion).first;
    expect(lista.map((m) => m.id), ['m1']);
    expect(lista.single.pedidoId, 'p1');
  });

  test('observarMuebles ordena por tipoMueble', () async {
    await pedido('p1', 'recibido', DateTime(2026, 12, 1));
    await mueble('p1', 'a', 'fabricacion', 'recibido', 'Silla');
    await mueble('p1', 'b', 'fabricacion', 'recibido', 'Mesa');
    final l = await repo.observarMuebles('p1').first;
    expect(l.map((m) => m.tipoMueble), ['Mesa', 'Silla']);
  });

  test('observarPedidosActivos omite cerrados y mal formados', () async {
    await pedido('p1', 'recibido', DateTime(2026, 12, 5));
    await pedido('p2', 'terminado', DateTime(2026, 12, 1));
    await pedido('p3', 'entregado', DateTime(2026, 12, 1));
    await db.collection('pedidos').doc('p4').set({'estado': 'recibido'});
    final l = await repo.observarPedidosActivos().first;
    expect(l.map((p) => p.id), ['p2', 'p1']);
  });

  test('observarPedidosRecientes y observarPedido', () async {
    await pedido('p1', 'recibido', DateTime(2026, 12, 5));
    expect((await repo.observarPedidosRecientes().first).length, 1);
    expect((await repo.observarPedido('p1').first)!.cliente.nombre, 'Ana');
    expect(await repo.observarPedido('nada').first, isNull);
    expect(await repo.observarMueble('p1', 'nada').first, isNull);
  });

  test('observarCambiosPrecio ordena por fecha descendente', () async {
    final c = db.collection('pedidos').doc('p1').collection('cambios_precio');
    Map<String, dynamic> datos(DateTime f) => {
          'campo': 'precio',
          'muebleId': 'm1',
          'anterior': 10,
          'nuevo': 5,
          'motivo': null,
          'usuarioId': 'u1',
          'fecha': Timestamp.fromDate(f),
        };
    await c.doc('a').set(datos(DateTime(2026, 1, 1)));
    await c.doc('b').set(datos(DateTime(2026, 2, 1)));
    await c.doc('malo').set({'campo': 'precio'});
    final l = await repo.observarCambiosPrecio('p1').first;
    expect(l.map((x) => x.id), ['b', 'a']);
  });

  test('clientes y plantillas', () async {
    await db
        .collection('clientes')
        .doc('2')
        .set({'nombre': 'Zoe', 'telefono': '', 'direccion': ''});
    await db
        .collection('clientes')
        .doc('1')
        .set({'nombre': 'Ana', 'telefono': '', 'direccion': ''});
    final cl = await RepositorioClientes(db).observarClientes().first;
    expect(cl.map((c) => c.nombre), ['Ana', 'Zoe']);

    final rp = RepositorioPlantillas(db);
    final id = await rp.crear(const Plantilla(
        id: '',
        tipoMueble: 'Sofá',
        lineas: [LineaPlantilla(materialId: 'm', cantidad: 2)]));
    var l = await rp.observarPlantillas().first;
    expect(l.single.lineas.single.cantidad, 2);
    await rp.editar(Plantilla(id: id, tipoMueble: 'Sillón', lineas: const []));
    l = await rp.observarPlantillas().first;
    expect(l.single.tipoMueble, 'Sillón');
    await rp.borrar(id);
    expect(await rp.observarPlantillas().first, isEmpty);
  });
}
