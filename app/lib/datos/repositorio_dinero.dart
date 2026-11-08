import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/dinero.dart';

DateTime? _aFecha(Object? valor) => valor is Timestamp ? valor.toDate() : null;

class RepositorioDinero {
  final FirebaseFirestore _db;

  RepositorioDinero(this._db);

  CollectionReference<Map<String, dynamic>> get _pagos =>
      _db.collection('pagos');

  /// Documentos recién escritos sin conexión llegan con la fecha del servidor
  /// aún pendiente (nula): se estima con la hora del dispositivo en vez de
  /// descartarlos. Los mal formados se omiten.
  static List<T> _convertir<T>(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    T Function(String, Map<String, dynamic>, DateTime? Function(Object?))
        desdeMapa,
  ) {
    final lista = <T>[];
    for (final d in docs) {
      try {
        final datos = Map<String, dynamic>.from(d.data());
        if (datos['fecha'] == null && d.metadata.hasPendingWrites) {
          datos['fecha'] = Timestamp.now();
        }
        lista.add(desdeMapa(d.id, datos, _aFecha));
      } on FormatException {
        // documento mal formado: se omite
      }
    }
    return lista;
  }

  static List<Pago> _pagosDe(QuerySnapshot<Map<String, dynamic>> q) {
    final lista = _convertir(q.docs, Pago.desdeMapa);
    lista.sort((a, b) => a.fecha.compareTo(b.fecha));
    return lista;
  }

  /// Solo para el dueño: todos los pagos del pedido, del más antiguo al más
  /// reciente.
  Stream<List<Pago>> observarPagosPedido(String pedidoId) => _pagos
      .where('pedidoId', isEqualTo: pedidoId)
      .snapshots()
      .map(_pagosDe);

  /// Para el empleado: solo los pagos que él recibió.
  Stream<List<Pago>> observarMisPagosPedido(String pedidoId, String uid) =>
      _pagos
          .where('pedidoId', isEqualTo: pedidoId)
          .where('recibidoPor', isEqualTo: uid)
          .snapshots()
          .map(_pagosDe);

  Stream<double> observarEnMano(String uid) =>
      _db.collection('cajas').doc(uid).snapshots().map((d) {
        try {
          return enManoDe(d.data());
        } on FormatException {
          return 0.0;
        }
      });

  /// uid del empleado -> dinero en mano.
  Stream<Map<String, double>> observarCajas() =>
      _db.collection('cajas').snapshots().map((q) {
        final mapa = <String, double>{};
        for (final d in q.docs) {
          try {
            mapa[d.id] = enManoDe(d.data());
          } on FormatException {
            // documento mal formado: se omite
          }
        }
        return mapa;
      });

  Stream<List<EntregaDinero>> observarEntregasPendientes() => _db
      .collection('entregas')
      .where('estado', isEqualTo: EstadoEntrega.pendiente.clave)
      .snapshots()
      .map((q) => _convertir(q.docs, EntregaDinero.desdeMapa));

  Stream<List<EntregaDinero>> observarEntregasDe(String uid,
          {int limite = 30}) =>
      _db
          .collection('entregas')
          .where('empleadoId', isEqualTo: uid)
          .orderBy('fecha', descending: true)
          .limit(limite)
          .snapshots()
          .map((q) => _convertir(q.docs, EntregaDinero.desdeMapa));

  Stream<List<PagoSueldo>> observarPagosSueldo(String uid, {int limite = 20}) =>
      _db
          .collection('pagos_sueldo')
          .where('usuarioId', isEqualTo: uid)
          .orderBy('fecha', descending: true)
          .limit(limite)
          .snapshots()
          .map((q) => _convertir(q.docs, PagoSueldo.desdeMapa));
}
