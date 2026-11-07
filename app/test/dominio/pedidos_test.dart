import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/pedidos.dart';

DateTime? _aFecha(Object? v) => v is DateTime ? v : null;

Map<String, dynamic> _mapaPedido() => {
      'folio': '261107-K3QZ',
      'clienteId': 'c1',
      'cliente': {'nombre': 'José', 'telefono': '999', 'direccion': 'Calle 1'},
      'entrega': 'domicilio',
      'envio': 200,
      'comentarios': '',
      'fechaIngreso': DateTime(2026, 11, 7),
      'fechaEstimada': DateTime(2026, 11, 20),
      'fechaTerminado': null,
      'fechaEntregado': null,
      'estado': 'recibido',
      'creadoPor': 'u1',
    };

Map<String, dynamic> _mapaMueble() => {
      'tipoTrabajo': 'fabricacion',
      'tipoMueble': 'Sillón',
      'plantillaId': null,
      'precio': 650,
      'comentarios': '',
      'estado': 'recibido',
    };

void main() {
  test('estado del pedido = mueble menos avanzado sin cancelados', () {
    final e = EstadoMueble.values;
    expect(estadoPedido([EstadoMueble.terminado, EstadoMueble.enProceso]),
        EstadoMueble.enProceso);
    expect(estadoPedido([EstadoMueble.terminado, EstadoMueble.cancelado]),
        EstadoMueble.terminado);
    expect(estadoPedido([EstadoMueble.cancelado, EstadoMueble.cancelado]),
        EstadoMueble.cancelado);
    expect(estadoPedido([]), EstadoMueble.recibido);
    expect(e.map((x) => x.clave),
        ['recibido', 'en_proceso', 'terminado', 'entregado', 'cancelado']);
  });

  test('claves, etiquetas y activo', () {
    expect(EstadoMueble.enProceso.etiqueta, 'En proceso');
    expect(EstadoMueble.desdeTexto('en_proceso'), EstadoMueble.enProceso);
    expect(EstadoMueble.recibido.activo, isTrue);
    expect(EstadoMueble.terminado.activo, isTrue);
    expect(EstadoMueble.entregado.activo, isFalse);
    expect(EstadoMueble.cancelado.activo, isFalse);
    expect(TipoTrabajo.reparacion.etiqueta, 'Reparación');
    expect(TipoTrabajo.desdeTexto('fabricacion'), TipoTrabajo.fabricacion);
    expect(Entrega.recoge.etiqueta, 'Lo recoge');
    expect(Entrega.domicilio.clave, 'domicilio');
    expect(() => Entrega.desdeTexto('x'), throwsFormatException);
    expect(() => TipoTrabajo.desdeTexto('x'), throwsFormatException);
  });

  test('total del pedido', () {
    expect(totalPedido([650, 650], 200), 1500);
    expect(totalPedido([0.1, 0.2], 0), 0.3);
  });

  test('folio', () {
    expect(folioPara(DateTime(2026, 11, 7), 'k3qzAbCd'), '261107-K3QZ');
  });

  test('búsqueda de cliente', () {
    const c = Cliente(
        id: 'c', nombre: 'José Pérez', telefono: '999 123 4567', direccion: '');
    expect(coincideCliente(c, 'jose'), isTrue);
    expect(coincideCliente(c, 'PÉREZ'), isTrue);
    expect(coincideCliente(c, '1234'), isTrue);
    expect(coincideCliente(c, '12'), isFalse);
    expect(coincideCliente(c, 'maría'), isFalse);
    expect(coincideCliente(c, ''), isTrue);
  });

  test('leerDias', () {
    expect(leerDias('1,5'), 1.5);
    expect(leerDias('0.5'), 0.5);
    expect(leerDias('7'), 7);
    expect(leerDias('0'), isNull);
    expect(leerDias('0.3'), isNull);
    expect(leerDias('8'), isNull);
    expect(leerDias('abc'), isNull);
  });

  test('desdeMapa valida', () {
    final m = _mapaMueble()..['estado'] = 'listo';
    expect(() => Mueble.desdeMapa('m', 'p', m), throwsFormatException);
    final ok = Mueble.desdeMapa('m', 'p', _mapaMueble());
    expect(ok.precio, 650);
    expect(ok.plantillaId, isNull);
    expect(ok.pedidoId, 'p');

    final sinEstimada = _mapaPedido()..remove('fechaEstimada');
    expect(() => Pedido.desdeMapa('p', sinEstimada, _aFecha),
        throwsFormatException);
    final p = Pedido.desdeMapa('p', _mapaPedido(), _aFecha);
    expect(p.fechaTerminado, isNull);
    expect(p.cliente.id, 'c1');
    expect(p.cliente.nombre, 'José');
    expect(p.entrega, Entrega.domicilio);

    final c = CambioPrecio.desdeMapa('x', {
      'campo': 'precio',
      'muebleId': 'm',
      'anterior': 500,
      'nuevo': 450,
      'motivo': null,
      'usuarioId': 'u',
      'fecha': DateTime(2026, 11, 7),
    }, _aFecha);
    expect(c.esBajada, isTrue);
    expect(c.campo, CampoPrecio.precio);

    final pl = Plantilla.desdeMapa('t', {
      'tipoMueble': 'Sillón',
      'lineas': [
        {'materialId': 'guata', 'cantidad': 1}
      ],
    });
    expect(pl.lineas, hasLength(1));
    expect(pl.lineas.first.cantidad, 1.0);
    expect(pl.aMapa()['lineas'], [
      {'materialId': 'guata', 'cantidad': 1.0}
    ]);
  });

  test('línea de material, día trabajado y cliente', () {
    final l = LineaMaterial.desdeMapa('l', {
      'materialId': 'tela',
      'rolloId': 'r',
      'cantidad': 2,
      'delCliente': false,
      'usuarioId': 'u',
      'fecha': DateTime(2026, 11, 7),
    }, _aFecha);
    expect(l.rolloId, 'r');
    expect(l.cantidad, 2.0);
    final d = DiaTrabajado.desdeMapa(
        'd', {'usuarioId': 'u', 'dias': 1.5, 'fecha': DateTime(2026, 11, 7)},
        _aFecha);
    expect(d.dias, 1.5);
    expect(
        () => DiaTrabajado.desdeMapa('d', {'usuarioId': 'u', 'dias': 1}, _aFecha),
        throwsFormatException);
    final c = Cliente.desdeMapa(
        'c', {'nombre': 'A', 'telefono': '1', 'direccion': ''});
    expect(c.aMapa(), {'nombre': 'A', 'telefono': '1', 'direccion': ''});
  });
}
