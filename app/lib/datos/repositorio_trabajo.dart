import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/pedidos.dart';

DateTime? _aFecha(Object? valor) => valor is Timestamp ? valor.toDate() : null;

class RepositorioTrabajo {
  final FirebaseFirestore _db;

  RepositorioTrabajo(this._db);

  CollectionReference<Map<String, dynamic>> _mueble(
    String pedidoId,
    String muebleId,
    String coleccion,
  ) => _db
      .collection('pedidos')
      .doc(pedidoId)
      .collection('muebles')
      .doc(muebleId)
      .collection(coleccion);

  static List<T> _convertir<T>(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    T Function(QueryDocumentSnapshot<Map<String, dynamic>>) convertir,
  ) {
    final lista = <T>[];
    for (final d in docs) {
      try {
        lista.add(convertir(d));
      } on FormatException {
        // documento mal formado: se omite
      }
    }
    return lista;
  }

  /// Líneas de material del mueble, las más antiguas primero.
  Stream<List<LineaMaterial>> observarLineas(
    String pedidoId,
    String muebleId,
  ) => _mueble(pedidoId, muebleId, 'materiales').snapshots().map(
    (q) => _convertir(
      q.docs,
      (d) => LineaMaterial.desdeMapa(d.id, d.data(), _aFecha),
    )..sort((a, b) => a.fecha.compareTo(b.fecha)),
  );

  /// Días trabajados en el mueble, los más antiguos primero.
  Stream<List<DiaTrabajado>> observarDias(String pedidoId, String muebleId) =>
      _mueble(pedidoId, muebleId, 'dias').snapshots().map(
        (q) => _convertir(
          q.docs,
          (d) => DiaTrabajado.desdeMapa(d.id, d.data(), _aFecha),
        )..sort((a, b) => a.fecha.compareTo(b.fecha)),
      );
}
