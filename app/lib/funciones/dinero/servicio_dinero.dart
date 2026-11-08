import 'package:cloud_firestore/cloud_firestore.dart';

import '../../dominio/dinero.dart';
import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../../dominio/usuario.dart';
import '../../nucleo/formatos.dart';

/// Cada operación valida antes de armar un solo `WriteBatch` sin leer nada.
/// Los lotes coinciden con las reglas de Firestore; si no, las escrituras sin
/// conexión se descartan al sincronizar.
class ServicioDinero {
  final FirebaseFirestore _db;
  final String _usuarioId;
  final Rol _rol;

  ServicioDinero(this._db, this._usuarioId, this._rol);

  void _soloDueno() {
    if (_rol != Rol.dueno) {
      throw ArgumentError('Solo el dueño puede hacer esto');
    }
  }

  void _validarMonto(double monto) {
    if (!monto.isFinite || redondear2(monto) <= 0) {
      throw ArgumentError('El monto debe ser mayor a 0');
    }
  }

  /// Escribe solo el pago y, si el rol es empleado, su caja. El lado del
  /// pedido lo escribe quien llama. Devuelve el id del pago.
  String agregarPagoAlLote(
    WriteBatch b, {
    required String pedidoId,
    required double monto,
    required FormaPago forma,
  }) {
    final m = redondear2(monto);
    final ref = _db.collection('pagos').doc();
    b.set(ref, {
      'pedidoId': pedidoId,
      'monto': m,
      'forma': forma.clave,
      'recibidoPor': _usuarioId,
      'fecha': FieldValue.serverTimestamp(),
    });
    if (_rol == Rol.empleado) {
      b.set(
        _db.collection('cajas').doc(_usuarioId),
        {'enMano': FieldValue.increment(m), 'ultimoPagoId': ref.id},
        SetOptions(merge: true),
      );
    }
    return ref.id;
  }

  Future<void> registrarPago({
    required Pedido pedido,
    required double saldo,
    required double monto,
    required FormaPago forma,
  }) {
    _validarMonto(monto);
    final m = redondear2(monto);
    if (m > redondear2(saldo)) {
      throw ArgumentError(
          'El pago es mayor que el saldo (${formatearDinero(saldo)})');
    }
    final b = _db.batch();
    final id =
        agregarPagoAlLote(b, pedidoId: pedido.id, monto: m, forma: forma);
    b.update(_db.collection('pedidos').doc(pedido.id),
        {'pagado': FieldValue.increment(m), 'ultimoPagoId': id});
    return b.commit();
  }

  Future<void> registrarDevolucion({
    required Pedido pedido,
    required double monto,
    required FormaPago forma,
  }) {
    _soloDueno();
    _validarMonto(monto);
    final m = redondear2(monto);
    if (m > redondear2(pedido.pagado)) {
      throw ArgumentError(
          'La devolución es mayor que lo pagado (${formatearDinero(pedido.pagado)})');
    }
    final b = _db.batch();
    final id =
        agregarPagoAlLote(b, pedidoId: pedido.id, monto: -m, forma: forma);
    b.update(_db.collection('pedidos').doc(pedido.id),
        {'pagado': FieldValue.increment(-m), 'ultimoPagoId': id});
    return b.commit();
  }

  Future<void> borrarPago({
    required Pago pago,
    required bool cobroDeEmpleado,
  }) {
    _soloDueno();
    final b = _db.batch();
    b.delete(_db.collection('pagos').doc(pago.id));
    b.update(_db.collection('pedidos').doc(pago.pedidoId), {
      'pagado': FieldValue.increment(-pago.monto),
      'ultimoPagoId': pago.id,
    });
    if (cobroDeEmpleado) {
      b.set(
        _db.collection('cajas').doc(pago.recibidoPor),
        {'enMano': FieldValue.increment(-pago.monto), 'ultimoPagoId': pago.id},
        SetOptions(merge: true),
      );
    }
    return b.commit();
  }

  Future<void> registrarEntrega({
    required double porEntregar,
    required double monto,
    required FormaPago forma,
  }) {
    if (_rol != Rol.empleado) {
      throw ArgumentError('Solo el empleado puede entregar dinero');
    }
    _validarMonto(monto);
    final m = redondear2(monto);
    if (m > redondear2(porEntregar)) {
      throw ArgumentError(
          'La entrega es mayor que lo que tienes por entregar (${formatearDinero(porEntregar)})');
    }
    final b = _db.batch();
    b.set(_db.collection('entregas').doc(), {
      'empleadoId': _usuarioId,
      'monto': m,
      'forma': forma.clave,
      'fecha': FieldValue.serverTimestamp(),
      'estado': EstadoEntrega.pendiente.clave,
      'revisadoEn': null,
    });
    return b.commit();
  }

  Future<void> confirmarEntrega(EntregaDinero e) {
    _soloDueno();
    final b = _db.batch();
    b.update(_db.collection('entregas').doc(e.id), {
      'estado': EstadoEntrega.confirmada.clave,
      'revisadoEn': FieldValue.serverTimestamp(),
    });
    b.set(
      _db.collection('cajas').doc(e.empleadoId),
      {'enMano': FieldValue.increment(-e.monto), 'ultimaEntregaId': e.id},
      SetOptions(merge: true),
    );
    return b.commit();
  }

  Future<void> rechazarEntrega(EntregaDinero e) {
    _soloDueno();
    final b = _db.batch();
    b.update(_db.collection('entregas').doc(e.id), {
      'estado': EstadoEntrega.rechazada.clave,
      'revisadoEn': FieldValue.serverTimestamp(),
    });
    return b.commit();
  }

  Future<void> registrarPagoSueldo({
    required String usuarioId,
    required double monto,
    required DateTime fecha,
  }) {
    _soloDueno();
    _validarMonto(monto);
    final b = _db.batch();
    b.set(_db.collection('pagos_sueldo').doc(), {
      'usuarioId': usuarioId,
      'monto': redondear2(monto),
      'fecha': Timestamp.fromDate(fecha),
    });
    return b.commit();
  }

  Future<void> borrarPagoSueldo(String id) {
    _soloDueno();
    final b = _db.batch();
    b.delete(_db.collection('pagos_sueldo').doc(id));
    return b.commit();
  }
}
