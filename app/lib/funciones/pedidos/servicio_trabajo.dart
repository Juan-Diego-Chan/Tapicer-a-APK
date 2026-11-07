import 'package:cloud_firestore/cloud_firestore.dart';

import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';

/// Material usado y días trabajados de un mueble. Cada operación es un solo
/// `WriteBatch` sin lecturas previas.
class ServicioTrabajo {
  final FirebaseFirestore _db;
  final String _usuarioId;

  ServicioTrabajo(this._db, this._usuarioId);

  DocumentReference<Map<String, dynamic>> _mueble(
    String pedidoId,
    String muebleId,
  ) => _db
      .collection('pedidos')
      .doc(pedidoId)
      .collection('muebles')
      .doc(muebleId);

  /// La línea y su movimiento comparten id; la existencia solo baja con
  /// `increment`.
  Future<void> agregarLinea({
    required String pedidoId,
    required String muebleId,
    required Material material,
    required double cantidad,
    String? rolloId,
    required bool delCliente,
    DateTime? fecha,
  }) async {
    if (!cantidad.isFinite || cantidad <= 0) {
      throw ArgumentError('La cantidad debe ser mayor que cero');
    }
    if (material.usaRollos && !delCliente && rolloId == null) {
      throw ArgumentError('Elige el rollo del que se cortó la tela');
    }
    final rollo = delCliente ? null : rolloId;
    final momento = Timestamp.fromDate(fecha ?? DateTime.now());
    final batch = _db.batch();
    final lineaRef = _mueble(pedidoId, muebleId).collection('materiales').doc();
    batch.set(lineaRef, {
      'materialId': material.id,
      'rolloId': rollo,
      'cantidad': cantidad,
      'delCliente': delCliente,
      'usuarioId': _usuarioId,
      'fecha': momento,
    });
    if (!delCliente) {
      batch.set(_db.collection('movimientos').doc(lineaRef.id), {
        'tipo': 'consumo',
        'materialId': material.id,
        'rolloId': rollo,
        'cantidad': -cantidad,
        'pedidoId': pedidoId,
        'muebleId': muebleId,
        'usuarioId': _usuarioId,
        'fecha': momento,
      });
      batch.update(_db.collection('materiales').doc(material.id), {
        'existencia': FieldValue.increment(-cantidad),
      });
      if (rollo != null) {
        batch.update(_db.collection('rollos').doc(rollo), {
          'existencia': FieldValue.increment(-cantidad),
        });
      }
    }
    return batch.commit();
  }

  /// Solo dueño. Si la línea salió del inventario, devuelve la existencia con
  /// un movimiento de ajuste.
  Future<void> borrarLinea({
    required String pedidoId,
    required String muebleId,
    required LineaMaterial linea,
    required Material material,
  }) async {
    final batch = _db.batch();
    batch.delete(
      _mueble(pedidoId, muebleId).collection('materiales').doc(linea.id),
    );
    if (!linea.delCliente) {
      batch.set(_db.collection('movimientos').doc(), {
        'tipo': 'ajuste',
        'materialId': linea.materialId,
        'rolloId': linea.rolloId,
        'cantidad': linea.cantidad,
        'pedidoId': pedidoId,
        'muebleId': muebleId,
        'usuarioId': _usuarioId,
        'fecha': Timestamp.now(),
      });
      batch.update(_db.collection('materiales').doc(linea.materialId), {
        'existencia': FieldValue.increment(linea.cantidad),
      });
      final rollo = linea.rolloId;
      if (rollo != null) {
        batch.update(_db.collection('rollos').doc(rollo), {
          'existencia': FieldValue.increment(linea.cantidad),
        });
      }
    }
    return batch.commit();
  }

  /// [usuarioId] es quien trabajó, que puede no ser quien registra.
  Future<void> registrarDias({
    required String pedidoId,
    required String muebleId,
    required String usuarioId,
    required double dias,
    DateTime? fecha,
  }) async {
    // Misma regla que `leerDias`: múltiplos de 0.5 en (0, 7].
    if (!dias.isFinite ||
        dias <= 0 ||
        dias > 7 ||
        dias * 2 != (dias * 2).roundToDouble()) {
      throw ArgumentError('Los días deben ser múltiplos de 0.5, de 0.5 a 7');
    }
    return _mueble(pedidoId, muebleId).collection('dias').doc().set({
      'usuarioId': usuarioId,
      'dias': dias,
      'fecha': Timestamp.fromDate(fecha ?? DateTime.now()),
    });
  }

  /// Solo dueño.
  Future<void> borrarDias({
    required String pedidoId,
    required String muebleId,
    required String diaId,
  }) async {
    return _mueble(pedidoId, muebleId).collection('dias').doc(diaId).delete();
  }
}
