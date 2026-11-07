import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/pedidos.dart';

class RepositorioClientes {
  final FirebaseFirestore _db;

  RepositorioClientes(this._db);

  /// Omite los documentos mal formados en vez de fallar toda la lista.
  Stream<List<Cliente>> observarClientes() =>
      _db.collection('clientes').orderBy('nombre').snapshots().map((q) {
        final lista = <Cliente>[];
        for (final d in q.docs) {
          try {
            lista.add(Cliente.desdeMapa(d.id, d.data()));
          } on FormatException {
            // documento mal formado: se omite
          }
        }
        return lista;
      });
}
