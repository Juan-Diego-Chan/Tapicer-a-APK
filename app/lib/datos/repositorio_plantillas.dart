import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/pedidos.dart';

class RepositorioPlantillas {
  final FirebaseFirestore _db;

  RepositorioPlantillas(this._db);

  CollectionReference<Map<String, dynamic>> get _plantillas =>
      _db.collection('plantillas');

  /// Omite los documentos mal formados en vez de fallar toda la lista.
  Stream<List<Plantilla>> observarPlantillas() =>
      _plantillas.orderBy('tipoMueble').snapshots().map((q) {
        final lista = <Plantilla>[];
        for (final d in q.docs) {
          try {
            lista.add(Plantilla.desdeMapa(d.id, d.data()));
          } on FormatException {
            // documento mal formado: se omite
          }
        }
        return lista;
      });

  Future<String> crear(Plantilla p) async {
    final ref = await _plantillas.add(p.aMapa());
    return ref.id;
  }

  Future<void> editar(Plantilla p) => _plantillas.doc(p.id).update(p.aMapa());

  Future<void> borrar(String id) => _plantillas.doc(id).delete();
}
