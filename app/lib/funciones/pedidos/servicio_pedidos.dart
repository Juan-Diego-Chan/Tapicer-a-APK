import 'package:cloud_firestore/cloud_firestore.dart';

import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';

class NuevoMueble {
  final TipoTrabajo tipoTrabajo;
  final String tipoMueble;
  final String? plantillaId;
  final double precio;
  final String comentarios;

  const NuevoMueble({
    required this.tipoTrabajo,
    required this.tipoMueble,
    this.plantillaId,
    required this.precio,
    this.comentarios = '',
  });
}

/// Cada operación valida antes de crear el lote y arma un solo `WriteBatch`
/// sin leer nada: los datos actuales llegan como parámetros.
class ServicioPedidos {
  final FirebaseFirestore _db;
  final String _usuarioId;

  ServicioPedidos(this._db, this._usuarioId);

  Map<String, dynamic> _datosMueble(NuevoMueble m) => {
        'tipoTrabajo': m.tipoTrabajo.clave,
        'tipoMueble': m.tipoMueble.trim(),
        'plantillaId': m.plantillaId,
        'precio': m.precio,
        'comentarios': m.comentarios.trim(),
        'estado': EstadoMueble.recibido.clave,
        'ultimoCambioId': null,
      };

  void _validarMueble(NuevoMueble m) {
    if (!m.precio.isFinite || m.precio < 0) {
      throw ArgumentError('El precio no puede ser negativo');
    }
    if (m.tipoMueble.trim().isEmpty) {
      throw ArgumentError('Falta el tipo de mueble');
    }
  }

  String? _limpiarMotivo(String? motivo) {
    final m = motivo?.trim();
    if (m == null || m.isEmpty) return null;
    if (m.length > 200) {
      throw ArgumentError('El motivo es demasiado largo (máximo 200)');
    }
    return m;
  }

  /// Devuelve el id de inmediato; [guardado] termina cuando el servidor
  /// confirma (sin conexión puede tardar).
  ({String pedidoId, Future<void> guardado}) crearPedido({
    String? clienteId,
    required String nombre,
    required String telefono,
    required String direccion,
    required Entrega entrega,
    required double envio,
    required String comentarios,
    required DateTime fechaEstimada,
    required List<NuevoMueble> muebles,
    DateTime? ahora,
  }) {
    final momento = ahora ?? DateTime.now();
    if (muebles.isEmpty) throw ArgumentError('Agrega al menos un mueble');
    if (nombre.trim().isEmpty) throw ArgumentError('Falta el nombre');
    if (!envio.isFinite || envio < 0) {
      throw ArgumentError('El envío no puede ser negativo');
    }
    if (entrega == Entrega.recoge && envio != 0) {
      throw ArgumentError('Si lo recoge, el envío debe ser 0');
    }
    if (entrega == Entrega.domicilio && direccion.trim().isEmpty) {
      throw ArgumentError('Falta la dirección');
    }
    muebles.forEach(_validarMueble);
    final hoy = DateTime(momento.year, momento.month, momento.day);
    final dia =
        DateTime(fechaEstimada.year, fechaEstimada.month, fechaEstimada.day);
    if (dia.isBefore(hoy)) {
      throw ArgumentError('La fecha estimada no puede ser anterior a hoy');
    }

    final batch = _db.batch();
    final datosCliente = {
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'direccion': direccion.trim(),
    };
    var idCliente = clienteId;
    if (idCliente == null) {
      final ref = _db.collection('clientes').doc();
      idCliente = ref.id;
      batch.set(ref, datosCliente);
    }
    final pedidoRef = _db.collection('pedidos').doc();
    batch.set(pedidoRef, {
      'folio': folioPara(momento, pedidoRef.id),
      'clienteId': idCliente,
      'cliente': datosCliente,
      'entrega': entrega.clave,
      'envio': envio,
      'comentarios': comentarios.trim(),
      'fechaIngreso': Timestamp.fromDate(momento),
      'fechaEstimada': Timestamp.fromDate(fechaEstimada),
      'fechaTerminado': null,
      'fechaEntregado': null,
      'estado': EstadoMueble.recibido.clave,
      'creadoPor': _usuarioId,
      'ultimoCambioId': null,
    });
    for (final m in muebles) {
      batch.set(pedidoRef.collection('muebles').doc(), _datosMueble(m));
    }
    return (pedidoId: pedidoRef.id, guardado: batch.commit());
  }

  Future<void> agregarMueble({
    required Pedido pedido,
    required List<Mueble> muebles,
    required NuevoMueble nuevo,
  }) async {
    _validarMueble(nuevo);
    final batch = _db.batch();
    final pedidoRef = _db.collection('pedidos').doc(pedido.id);
    batch.set(pedidoRef.collection('muebles').doc(), _datosMueble(nuevo));
    final estado = estadoPedido(
        [for (final m in muebles) m.estado, EstadoMueble.recibido]);
    if (estado != pedido.estado) {
      batch.update(pedidoRef, {'estado': estado.clave});
    }
    return batch.commit();
  }

  Future<void> cambiarEstadoMueble({
    required Pedido pedido,
    required List<Mueble> muebles,
    required String muebleId,
    required EstadoMueble nuevo,
    DateTime? ahora,
  }) async {
    if (!muebles.any((m) => m.id == muebleId)) {
      throw ArgumentError('El mueble no pertenece al pedido');
    }
    final momento = ahora ?? DateTime.now();
    final batch = _db.batch();
    final pedidoRef = _db.collection('pedidos').doc(pedido.id);
    batch.update(pedidoRef.collection('muebles').doc(muebleId),
        {'estado': nuevo.clave});
    final estado = estadoPedido(
        [for (final m in muebles) m.id == muebleId ? nuevo : m.estado]);
    final cambios = <String, dynamic>{};
    if (estado != pedido.estado) {
      cambios['estado'] = estado.clave;
      if (estado == EstadoMueble.terminado && pedido.fechaTerminado == null) {
        cambios['fechaTerminado'] = Timestamp.fromDate(momento);
      }
      if (estado == EstadoMueble.entregado && pedido.fechaEntregado == null) {
        cambios['fechaEntregado'] = Timestamp.fromDate(momento);
      }
    }
    if (cambios.isNotEmpty) batch.update(pedidoRef, cambios);
    return batch.commit();
  }

  /// Los muebles ya entregados no cambian.
  Future<void> cancelarPedido({
    required Pedido pedido,
    required List<Mueble> muebles,
  }) async {
    final batch = _db.batch();
    final pedidoRef = _db.collection('pedidos').doc(pedido.id);
    final estados = <EstadoMueble>[];
    for (final m in muebles) {
      if (m.estado == EstadoMueble.entregado ||
          m.estado == EstadoMueble.cancelado) {
        estados.add(m.estado);
        continue;
      }
      estados.add(EstadoMueble.cancelado);
      batch.update(pedidoRef.collection('muebles').doc(m.id),
          {'estado': EstadoMueble.cancelado.clave});
    }
    final estado = estadoPedido(estados);
    if (estado != pedido.estado) {
      batch.update(pedidoRef, {'estado': estado.clave});
    }
    return batch.commit();
  }

  Future<void> cambiarPrecioMueble({
    required String pedidoId,
    required Mueble mueble,
    required double nuevo,
    String? motivo,
  }) async {
    if (!nuevo.isFinite || nuevo < 0) {
      throw ArgumentError('El precio no puede ser negativo');
    }
    if (redondear2(nuevo) == redondear2(mueble.precio)) {
      throw ArgumentError('El precio no cambió');
    }
    final motivoLimpio = _limpiarMotivo(motivo);
    final batch = _db.batch();
    final pedidoRef = _db.collection('pedidos').doc(pedidoId);
    final cambioRef = pedidoRef.collection('cambios_precio').doc();
    batch.set(cambioRef, {
      'campo': CampoPrecio.precio.name,
      'muebleId': mueble.id,
      'anterior': mueble.precio,
      'nuevo': redondear2(nuevo),
      'motivo': motivoLimpio,
      'usuarioId': _usuarioId,
      'fecha': FieldValue.serverTimestamp(),
    });
    batch.update(pedidoRef.collection('muebles').doc(mueble.id),
        {'precio': redondear2(nuevo), 'ultimoCambioId': cambioRef.id});
    return batch.commit();
  }

  Future<void> cambiarEnvio({
    required Pedido pedido,
    required Entrega entrega,
    required double envio,
    String? motivo,
  }) async {
    if (!envio.isFinite || envio < 0) {
      throw ArgumentError('El envío no puede ser negativo');
    }
    if (entrega == Entrega.recoge && envio != 0) {
      throw ArgumentError('Si lo recoge, el envío debe ser 0');
    }
    final cambiaEnvio = redondear2(envio) != redondear2(pedido.envio);
    if (!cambiaEnvio && entrega == pedido.entrega) {
      throw ArgumentError('No hay cambios');
    }
    final motivoLimpio = _limpiarMotivo(motivo);
    final batch = _db.batch();
    final pedidoRef = _db.collection('pedidos').doc(pedido.id);
    if (cambiaEnvio) {
      final cambioRef = pedidoRef.collection('cambios_precio').doc();
      batch.set(cambioRef, {
        'campo': CampoPrecio.envio.name,
        'muebleId': null,
        'anterior': pedido.envio,
        'nuevo': redondear2(envio),
        'motivo': motivoLimpio,
        'usuarioId': _usuarioId,
        'fecha': FieldValue.serverTimestamp(),
      });
      batch.update(pedidoRef, {
        'entrega': entrega.clave,
        'envio': redondear2(envio),
        'ultimoCambioId': cambioRef.id,
      });
    } else {
      batch.update(pedidoRef, {'entrega': entrega.clave});
    }
    return batch.commit();
  }

  Future<void> editarPedido({
    required String pedidoId,
    required String comentarios,
    required DateTime fechaEstimada,
  }) async {
    return _db.collection('pedidos').doc(pedidoId).update({
      'comentarios': comentarios.trim(),
      'fechaEstimada': Timestamp.fromDate(fechaEstimada),
    });
  }
}
