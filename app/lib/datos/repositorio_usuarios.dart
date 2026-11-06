import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/usuario.dart';

class RepositorioUsuarios {
  final FirebaseFirestore _db;

  RepositorioUsuarios(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('usuarios');

  Stream<Usuario?> observar(String uid) => _col.doc(uid).snapshots().map((s) {
        final datos = s.data();
        return datos == null ? null : Usuario.desdeMapa(s.id, datos);
      });

  Stream<List<Usuario>> observarTodos() => _col.snapshots().map(
        (q) => q.docs.map((d) => Usuario.desdeMapa(d.id, d.data())).toList(),
      );

  /// Crea o actualiza el usuario. `creadoEn` solo se fija cuando el documento
  /// aún no existe; al actualizar no se toca.
  Future<void> guardar(Usuario u) async {
    final ref = _col.doc(u.uid);
    final existe = (await ref.get()).exists;
    await ref.set(
      {
        ...u.aMapa(),
        if (!existe) 'creadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> fijarActivo(String uid, bool activo) =>
      _col.doc(uid).update({'activo': activo});
}
