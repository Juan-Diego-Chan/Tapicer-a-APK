import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/inventario.dart';

class RepositorioInventario {
  final FirebaseFirestore _db;

  RepositorioInventario(this._db);

  CollectionReference<Map<String, dynamic>> get _materiales =>
      _db.collection('materiales');

  /// Omite los documentos mal formados en vez de fallar toda la lista.
  Stream<List<Material>> observarMateriales() =>
      _materiales.orderBy('nombre').snapshots().map((q) {
        final lista = <Material>[];
        for (final d in q.docs) {
          try {
            lista.add(Material.desdeMapa(d.id, d.data()));
          } on FormatException {
            // documento mal formado: se omite
          }
        }
        return lista;
      });

  Stream<Material?> observarMaterial(String id) =>
      _materiales.doc(id).snapshots().map((s) {
        final datos = s.data();
        return datos == null ? null : Material.desdeMapa(s.id, datos);
      });

  Stream<List<Rollo>> observarRollos(String materialId) => _db
          .collection('rollos')
          .where('materialId', isEqualTo: materialId)
          .orderBy('fechaCompra', descending: true)
          .snapshots()
          .map((q) {
        final lista = <Rollo>[];
        for (final d in q.docs) {
          try {
            final datos = d.data();
            final f = datos['fechaCompra'];
            if (f is! Timestamp) {
              throw const FormatException('fechaCompra no es Timestamp');
            }
            lista.add(Rollo.desdeMapa(d.id, datos, f.toDate()));
          } on FormatException {
            // documento mal formado: se omite
          }
        }
        return lista;
      });

  Stream<List<Movimiento>> observarMovimientos(String materialId,
          {int limite = 50}) =>
      _db
          .collection('movimientos')
          .where('materialId', isEqualTo: materialId)
          .orderBy('fecha', descending: true)
          .limit(limite)
          .snapshots()
          .map((q) {
        final lista = <Movimiento>[];
        for (final d in q.docs) {
          try {
            final datos = d.data();
            final f = datos['fecha'];
            if (f is! Timestamp) {
              throw const FormatException('fecha no es Timestamp');
            }
            lista.add(Movimiento.desdeMapa(d.id, datos, f.toDate()));
          } on FormatException {
            // documento mal formado: se omite
          }
        }
        return lista;
      });

  Future<String> crearMaterial(Material m) async {
    final ref = await _materiales.add(m.aMapaAlta());
    return ref.id;
  }

  /// Nunca toca `existencia`.
  Future<void> editarMaterial(
    String id, {
    required String nombre,
    required Categoria categoria,
    required Unidad unidad,
    required double stockMinimo,
  }) =>
      _materiales.doc(id).update({
        'nombre': nombre,
        'categoria': categoria.name,
        'unidad': unidad.clave,
        'stockMinimo': stockMinimo,
        'usaRollos': categoria == Categoria.tela,
      });

  Future<void> marcarAgotandose(String id) =>
      _materiales.doc(id).update({'marcadoAgotandose': true});
}
