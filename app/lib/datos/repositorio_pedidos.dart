import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/pedidos.dart';

DateTime? _aFecha(Object? valor) => valor is Timestamp ? valor.toDate() : null;

class RepositorioPedidos {
  final FirebaseFirestore _db;

  RepositorioPedidos(this._db);

  CollectionReference<Map<String, dynamic>> get _pedidos =>
      _db.collection('pedidos');

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

  Pedido _pedido(DocumentSnapshot<Map<String, dynamic>> d) =>
      Pedido.desdeMapa(d.id, d.data()!, _aFecha);

  /// Pedidos que aún no se entregan ni se cancelan, los más próximos primero.
  Stream<List<Pedido>> observarPedidosActivos() => _pedidos
      .where('estado', whereIn: [
        for (final e in EstadoMueble.values)
          if (e.activo) e.clave
      ])
      .snapshots()
      .map((q) => _convertir(q.docs, _pedido)
        ..sort((a, b) => a.fechaEstimada.compareTo(b.fechaEstimada)));

  Stream<List<Pedido>> observarPedidosRecientes({int limite = 50}) => _pedidos
      .orderBy('fechaIngreso', descending: true)
      .limit(limite)
      .snapshots()
      .map((q) => _convertir(q.docs, _pedido));

  Stream<Pedido?> observarPedido(String id) =>
      _pedidos.doc(id).snapshots().map((s) {
        if (s.data() == null) return null;
        try {
          return _pedido(s);
        } on FormatException {
          return null;
        }
      });

  Stream<List<Mueble>> observarMuebles(String pedidoId) => _pedidos
      .doc(pedidoId)
      .collection('muebles')
      .snapshots()
      .map((q) => _convertir(
          q.docs, (d) => Mueble.desdeMapa(d.id, pedidoId, d.data()))
        ..sort((a, b) => a.tipoMueble.compareTo(b.tipoMueble)));

  Stream<Mueble?> observarMueble(String pedidoId, String muebleId) => _pedidos
          .doc(pedidoId)
          .collection('muebles')
          .doc(muebleId)
          .snapshots()
          .map((s) {
        final datos = s.data();
        if (datos == null) return null;
        try {
          return Mueble.desdeMapa(s.id, pedidoId, datos);
        } on FormatException {
          return null;
        }
      });

  Stream<List<Mueble>> observarMueblesActivos(TipoTrabajo tipo) => _db
      .collectionGroup('muebles')
      .where('tipoTrabajo', isEqualTo: tipo.clave)
      .where('estado', whereIn: [
        for (final e in EstadoMueble.values)
          if (e.activo) e.clave
      ])
      .snapshots()
      .map((q) => _convertir(
          q.docs,
          (d) => Mueble.desdeMapa(
              d.id, d.reference.parent.parent!.id, d.data())));

  /// Solo para el dueño. `snapshots()` no admite `ServerTimestampBehavior`
  /// (solo `get()`), así que un registro recién escrito, con la fecha del
  /// servidor aún pendiente, llega con `fecha` nula: se muestra con la hora
  /// del dispositivo en vez de descartarlo como mal formado.
  Stream<List<CambioPrecio>> observarCambiosPrecio(String pedidoId) => _pedidos
      .doc(pedidoId)
      .collection('cambios_precio')
      .snapshots()
      .map((q) {
        final lista = <CambioPrecio>[];
        for (final d in q.docs) {
          try {
            final datos = Map<String, dynamic>.from(d.data());
            if (datos['fecha'] == null && d.metadata.hasPendingWrites) {
              datos['fecha'] = Timestamp.now();
            }
            lista.add(CambioPrecio.desdeMapa(d.id, datos, _aFecha));
          } on FormatException {
            // documento mal formado: se omite
          }
        }
        lista.sort((a, b) => b.fecha.compareTo(a.fecha));
        return lista;
      });
}
