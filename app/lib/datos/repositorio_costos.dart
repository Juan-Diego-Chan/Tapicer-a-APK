import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/inventario.dart';

/// Costos de inventario. Solo para el dueño (las reglas lo imponen).
class RepositorioCostos {
  final FirebaseFirestore _db;

  RepositorioCostos(this._db);

  Stream<double?> observarCostoPromedio(String materialId) =>
      _db.collection('materiales_costos').doc(materialId).snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        final cantidad = d['cantidadComprada'];
        final total = d['costoTotalComprado'];
        if (cantidad is! num || total is! num) return null;
        return costoPromedio(
          cantidadComprada: cantidad.toDouble(),
          costoTotalComprado: total.toDouble(),
        );
      });

  Stream<double?> observarCostoRollo(String rolloId) =>
      _db.collection('rollos_costos').doc(rolloId).snapshots().map((s) {
        final v = s.data()?['costoPorUnidad'];
        return v is num ? v.toDouble() : null;
      });
}
