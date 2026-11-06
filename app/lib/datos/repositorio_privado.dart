import 'package:cloud_firestore/cloud_firestore.dart';

/// Datos que solo ve el dueño: sueldos (`usuarios_privado`) y configuración
/// general (`config/general`).
class RepositorioPrivado {
  final FirebaseFirestore _db;

  RepositorioPrivado(this._db);

  static const diasLaboralesPorDefecto = 6;

  DocumentReference<Map<String, dynamic>> get _config =>
      _db.collection('config').doc('general');

  Stream<double?> observarSueldo(String uid) =>
      _db.collection('usuarios_privado').doc(uid).snapshots().map((s) {
        final v = s.data()?['sueldoSemanal'];
        return v is num ? v.toDouble() : null;
      });

  Future<void> fijarSueldo(String uid, double sueldoSemanal) => _db
      .collection('usuarios_privado')
      .doc(uid)
      .set({'sueldoSemanal': sueldoSemanal}, SetOptions(merge: true));

  Stream<int> observarDiasLaborales() => _config.snapshots().map((s) {
    final v = s.data()?['diasLaborales'];
    return v is num ? v.toInt() : diasLaboralesPorDefecto;
  });

  Future<void> fijarDiasLaborales(int dias) =>
      _config.set({'diasLaborales': dias}, SetOptions(merge: true));
}
