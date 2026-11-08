import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/contabilidad.dart';
import '../dominio/costos_pedido.dart';
import '../dominio/dinero.dart';
import '../dominio/inventario.dart';
import '../dominio/pedidos.dart';
import '../dominio/usuario.dart';

DateTime? _aFecha(Object? valor) => valor is Timestamp ? valor.toDate() : null;

/// Lecturas de una sola vez para la contabilidad (solo dueño, las reglas lo
/// imponen). Los documentos mal formados se omiten.
class RepositorioContabilidad {
  final FirebaseFirestore _db;

  RepositorioContabilidad(this._db);

  static const _diasLaboralesPorDefecto = 6;
  static const _ventanaEntregados = Duration(days: 180);

  static List<T> _convertir<T>(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    T Function(String, Map<String, dynamic>, DateTime? Function(Object?))
        desdeMapa,
  ) {
    final lista = <T>[];
    for (final d in docs) {
      try {
        lista.add(desdeMapa(d.id, d.data(), _aFecha));
      } on FormatException {
        // documento mal formado: se omite
      }
    }
    return lista;
  }

  Query<Map<String, dynamic>> _enPeriodo(
          Query<Map<String, dynamic>> q, String campo, Periodo p) =>
      q
          .where(campo, isGreaterThanOrEqualTo: Timestamp.fromDate(p.desde))
          .where(campo, isLessThan: Timestamp.fromDate(p.hasta));

  Future<List<Pago>> pagosEn(Periodo p) async => _convertir(
      (await _enPeriodo(_db.collection('pagos'), 'fecha', p).get()).docs,
      Pago.desdeMapa);

  Future<List<Compra>> comprasEn(Periodo p) async => _convertir(
      (await _enPeriodo(_db.collection('compras'), 'fecha', p).get()).docs,
      Compra.desdeMapa);

  Future<List<PagoSueldo>> sueldosEn(Periodo p) async => _convertir(
      (await _enPeriodo(_db.collection('pagos_sueldo'), 'fecha', p).get())
          .docs,
      PagoSueldo.desdeMapa);

  Future<List<Pedido>> entregadosEn(Periodo p) async {
    final q = _db
        .collection('pedidos')
        .where('estado', isEqualTo: EstadoMueble.entregado.clave);
    return _convertir(
        (await _enPeriodo(q, 'fechaEntregado', p).get()).docs,
        Pedido.desdeMapa);
  }

  Future<List<({String pedidoId, CambioPrecio cambio})>> cambiosEn(
      Periodo p) async {
    final q = await _enPeriodo(_db.collectionGroup('cambios_precio'), 'fecha', p)
        .get();
    final lista = <({String pedidoId, CambioPrecio cambio})>[];
    for (final d in q.docs) {
      try {
        final cambio = CambioPrecio.desdeMapa(d.id, d.data(), _aFecha);
        lista.add((pedidoId: d.reference.parent.parent!.id, cambio: cambio));
      } on FormatException {
        // documento mal formado: se omite
      }
    }
    return lista;
  }

  /// Todos los `terminado`, más los `entregado` de los últimos 180 días.
  Future<List<Pedido>> candidatosPendientes(DateTime ahora) async {
    final pedidos = _db.collection('pedidos');
    final terminados = await pedidos
        .where('estado', isEqualTo: EstadoMueble.terminado.clave)
        .get();
    final entregados = await pedidos
        .where('estado', isEqualTo: EstadoMueble.entregado.clave)
        .where('fechaEntregado',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(ahora.subtract(_ventanaEntregados)))
        .get();
    final porId = <String, Pedido>{};
    for (final p in [
      ..._convertir(terminados.docs, Pedido.desdeMapa),
      ..._convertir(entregados.docs, Pedido.desdeMapa),
    ]) {
      porId[p.id] = p;
    }
    return porId.values.toList();
  }

  Future<Map<String, Pedido>> pedidosPorId(Iterable<String> ids) async {
    final r = <String, Pedido>{};
    for (final id in ids.toSet()) {
      final d = await _db.collection('pedidos').doc(id).get();
      final datos = d.data();
      if (datos == null) continue;
      try {
        r[id] = Pedido.desdeMapa(id, datos, _aFecha);
      } on FormatException {
        // documento mal formado: se omite
      }
    }
    return r;
  }

  CollectionReference<Map<String, dynamic>> _mueble(
          String pedidoId, String muebleId, String sub) =>
      _db.collection('pedidos/$pedidoId/muebles/$muebleId/$sub');

  Future<List<Mueble>> mueblesDe(String pedidoId) async {
    final q = await _db.collection('pedidos/$pedidoId/muebles').get();
    final lista = <Mueble>[];
    for (final d in q.docs) {
      try {
        lista.add(Mueble.desdeMapa(d.id, pedidoId, d.data()));
      } on FormatException {
        // documento mal formado: se omite
      }
    }
    return lista;
  }

  Future<List<LineaMaterial>> lineasDe(String pedidoId, String muebleId) async =>
      _convertir((await _mueble(pedidoId, muebleId, 'materiales').get()).docs,
          LineaMaterial.desdeMapa);

  Future<List<DiaTrabajado>> diasDe(String pedidoId, String muebleId) async =>
      _convertir((await _mueble(pedidoId, muebleId, 'dias').get()).docs,
          DiaTrabajado.desdeMapa);

  /// Costos unitarios conocidos, leídos completos de una vez.
  Future<CostosConocidos> costos() async {
    final materiales = await _db.collection('materiales_costos').get();
    final rollos = await _db.collection('rollos_costos').get();
    final usuarios = await _db.collection('usuarios').get();
    final privados = await _db.collection('usuarios_privado').get();
    final config = await _db.collection('config').doc('general').get();

    final costoMaterial = <String, double>{};
    for (final d in materiales.docs) {
      final cantidad = d.data()['cantidadComprada'];
      final total = d.data()['costoTotalComprado'];
      if (cantidad is! num || total is! num) continue;
      final c = costoPromedio(
        cantidadComprada: cantidad.toDouble(),
        costoTotalComprado: total.toDouble(),
      );
      if (c != null) costoMaterial[d.id] = c;
    }

    final costoRollo = <String, double>{};
    for (final d in rollos.docs) {
      final v = d.data()['costoPorUnidad'];
      if (v is num) costoRollo[d.id] = v.toDouble();
    }

    final sueldos = <String, double>{};
    for (final d in privados.docs) {
      final v = d.data()['sueldoSemanal'];
      if (v is num) sueldos[d.id] = v.toDouble();
    }

    final diasConfig = config.data()?['diasLaborales'];
    final diasLaborales =
        diasConfig is num ? diasConfig.toInt() : _diasLaboralesPorDefecto;

    final costoDia = <String, double?>{};
    for (final d in usuarios.docs) {
      try {
        final u = Usuario.desdeMapa(d.id, d.data());
        costoDia[u.uid] = u.rol == Rol.dueno
            ? 0
            : costoPorDia(
                sueldoSemanal: sueldos[u.uid], diasLaborales: diasLaborales);
      } on FormatException {
        // usuario mal formado: su costo queda desconocido
      }
    }

    return CostosConocidos(
      costoMaterial: (id) => costoMaterial[id],
      costoRollo: (id) => costoRollo[id],
      costoDiaDe: (id) => costoDia[id],
    );
  }
}
