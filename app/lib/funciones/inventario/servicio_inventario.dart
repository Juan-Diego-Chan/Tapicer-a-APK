import 'package:cloud_firestore/cloud_firestore.dart';

import '../../dominio/inventario.dart';

class ServicioInventario {
  final FirebaseFirestore _db;
  final String _usuarioId;

  ServicioInventario(this._db, this._usuarioId);

  Future<void> registrarCompra({
    required Material material,
    required double cantidad,
    required double precioTotal,
    String? codigoRollo,
    DateTime? fecha,
  }) async {
    if (cantidad <= 0) throw ArgumentError('La cantidad debe ser mayor a 0');
    if (precioTotal < 0) throw ArgumentError('El precio no puede ser negativo');
    return _entrada(
      tipo: 'compra',
      material: material,
      cantidad: cantidad,
      precioTotal: precioTotal,
      codigoRollo: codigoRollo,
      fecha: fecha,
    );
  }

  Future<void> registrarCargaInicial({
    required Material material,
    required double cantidad,
    double? costoPorUnidad,
    String? codigoRollo,
    DateTime? fecha,
  }) async {
    if (cantidad <= 0) throw ArgumentError('La cantidad debe ser mayor a 0');
    if (costoPorUnidad != null && costoPorUnidad < 0) {
      throw ArgumentError('El costo no puede ser negativo');
    }
    return _entrada(
      tipo: 'inicial',
      material: material,
      cantidad: cantidad,
      precioTotal: costoPorUnidad == null ? null : cantidad * costoPorUnidad,
      codigoRollo: codigoRollo,
      fecha: fecha,
    );
  }

  Future<void> registrarAjuste({
    required Material material,
    required double cantidad,
    String? rolloId,
  }) async {
    if (cantidad == 0) throw ArgumentError('El ajuste no puede ser 0');
    if (material.usaRollos && rolloId == null) {
      throw ArgumentError('Falta el rollo del ajuste');
    }
    final batch = _db.batch();
    batch.update(_db.collection('materiales').doc(material.id),
        {'existencia': FieldValue.increment(cantidad)});
    if (material.usaRollos) {
      batch.update(_db.collection('rollos').doc(rolloId),
          {'existencia': FieldValue.increment(cantidad)});
    }
    batch.set(_db.collection('movimientos').doc(), {
      'tipo': 'ajuste',
      'materialId': material.id,
      'rolloId': material.usaRollos ? rolloId : null,
      'cantidad': cantidad,
      'usuarioId': _usuarioId,
      'fecha': Timestamp.fromDate(DateTime.now()),
    });
    return batch.commit();
  }

  Future<void> _entrada({
    required String tipo,
    required Material material,
    required double cantidad,
    required double? precioTotal,
    required String? codigoRollo,
    required DateTime? fecha,
  }) {
    final esTela = material.usaRollos;
    if (esTela && (codigoRollo == null || codigoRollo.trim().isEmpty)) {
      throw ArgumentError('Falta el código del rollo');
    }
    final momento = Timestamp.fromDate(fecha ?? DateTime.now());
    final batch = _db.batch();

    String? rolloId;
    if (esTela) {
      final rolloRef = _db.collection('rollos').doc();
      rolloId = rolloRef.id;
      batch.set(rolloRef, {
        'materialId': material.id,
        'codigo': codigoRollo,
        'cantidadInicial': cantidad,
        'existencia': cantidad,
        'fechaCompra': momento,
      });
      batch.set(_db.collection('rollos_costos').doc(rolloId), {
        'costoPorUnidad': precioTotal == null ? null : precioTotal / cantidad,
      });
    }

    batch.update(_db.collection('materiales').doc(material.id), {
      'existencia': FieldValue.increment(cantidad),
      if (tipo == 'compra') 'marcadoAgotandose': false,
    });

    if (precioTotal != null) {
      batch.set(
        _db.collection('materiales_costos').doc(material.id),
        {
          'cantidadComprada': FieldValue.increment(cantidad),
          'costoTotalComprado': FieldValue.increment(precioTotal),
        },
        SetOptions(merge: true),
      );
    }

    batch.set(_db.collection('compras').doc(), {
      'materialId': material.id,
      'rolloId': rolloId,
      'cantidad': cantidad,
      'precioTotal': precioTotal,
      'fecha': momento,
      'tipo': tipo,
    });

    batch.set(_db.collection('movimientos').doc(), {
      'tipo': tipo,
      'materialId': material.id,
      'rolloId': rolloId,
      'cantidad': cantidad,
      'usuarioId': _usuarioId,
      'fecha': momento,
    });

    return batch.commit();
  }
}
