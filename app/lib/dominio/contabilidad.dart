import 'dinero.dart';
import 'inventario.dart';
import 'lectura.dart';

enum TipoPeriodo { semana, mes, rango }

const _meses = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

String _dd(int n) => n.toString().padLeft(2, '0');
String _fechaTexto(DateTime f) => '${_dd(f.day)}/${_dd(f.month)}/${f.year}';

/// Intervalo semiabierto `[desde, hasta)` en hora local. Se usa como llave de
/// provider, por eso `==` y `hashCode` son por valor.
class Periodo {
  final TipoPeriodo tipo;
  final DateTime desde;
  final DateTime hasta;

  const Periodo._(this.tipo, this.desde, this.hasta);

  /// Semana de lunes a domingo que contiene [dia].
  factory Periodo.semana(DateTime dia) {
    final lunes = DateTime(dia.year, dia.month, dia.day - (dia.weekday - 1));
    return Periodo._(
      TipoPeriodo.semana,
      lunes,
      DateTime(lunes.year, lunes.month, lunes.day + 7),
    );
  }

  factory Periodo.mes(DateTime dia) => Periodo._(
    TipoPeriodo.mes,
    DateTime(dia.year, dia.month, 1),
    DateTime(dia.year, dia.month + 1, 1),
  );

  /// Del día [inicio] al día [fin] inclusive; si vienen al revés se
  /// intercambian.
  factory Periodo.rango(DateTime inicio, DateTime fin) {
    var a = DateTime(inicio.year, inicio.month, inicio.day);
    var b = DateTime(fin.year, fin.month, fin.day);
    if (b.isBefore(a)) {
      final t = a;
      a = b;
      b = t;
    }
    return Periodo._(
      TipoPeriodo.rango,
      a,
      DateTime(b.year, b.month, b.day + 1),
    );
  }

  Periodo anterior() => switch (tipo) {
    TipoPeriodo.semana => Periodo.semana(
      DateTime(desde.year, desde.month, desde.day - 7),
    ),
    TipoPeriodo.mes => Periodo.mes(DateTime(desde.year, desde.month - 1, 1)),
    TipoPeriodo.rango => throw StateError('Un rango no tiene periodo anterior'),
  };

  Periodo siguiente() => switch (tipo) {
    TipoPeriodo.semana => Periodo.semana(hasta),
    TipoPeriodo.mes => Periodo.mes(hasta),
    TipoPeriodo.rango => throw StateError(
      'Un rango no tiene periodo siguiente',
    ),
  };

  bool contiene(DateTime f) => !f.isBefore(desde) && f.isBefore(hasta);

  String get etiqueta {
    switch (tipo) {
      case TipoPeriodo.semana:
        final domingo = DateTime(hasta.year, hasta.month, hasta.day - 1);
        return 'Semana del ${_fechaTexto(desde)} al ${_fechaTexto(domingo)}';
      case TipoPeriodo.mes:
        return '${_meses[desde.month - 1]} ${desde.year}';
      case TipoPeriodo.rango:
        final fin = DateTime(hasta.year, hasta.month, hasta.day - 1);
        return 'Del ${_fechaTexto(desde)} al ${_fechaTexto(fin)}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Periodo &&
      other.tipo == tipo &&
      other.desde == desde &&
      other.hasta == hasta;

  @override
  int get hashCode => Object.hash(tipo, desde, hasta);
}

class Compra {
  final String id;
  final String materialId;
  final double? precioTotal;
  final DateTime fecha;
  final String tipo;

  const Compra({
    required this.id,
    required this.materialId,
    required this.precioTotal,
    required this.fecha,
    required this.tipo,
  });

  factory Compra.desdeMapa(
    String id,
    Map<String, dynamic> m,
    DateTime? Function(Object?) aFecha,
  ) {
    final fecha = aFecha(m['fecha']);
    if (fecha == null) {
      throw FormatException('Fecha "fecha" ausente o inválida: ${m['fecha']}');
    }
    final bruto = m['precioTotal'];
    return Compra(
      id: id,
      materialId: leerTexto(m, 'materialId'),
      precioTotal: bruto == null
          ? null
          : redondear2(leerNumero(m, 'precioTotal')),
      fecha: fecha,
      tipo: leerTexto(m, 'tipo'),
    );
  }
}

class ResumenCobros {
  final double total;
  final Map<FormaPago, double> porForma;
  final Map<String, double> porUsuario;
  final Map<String, double> porPedido;

  const ResumenCobros({
    required this.total,
    required this.porForma,
    required this.porUsuario,
    required this.porPedido,
  });
}

Map<K, double> _redondeado<K>(Map<K, double> m) =>
    m.map((k, v) => MapEntry(k, redondear2(v)));

ResumenCobros resumirCobros(Iterable<Pago> pagos) {
  var total = 0.0;
  final porForma = <FormaPago, double>{};
  final porUsuario = <String, double>{};
  final porPedido = <String, double>{};
  for (final p in pagos) {
    total += p.monto;
    porForma[p.forma] = (porForma[p.forma] ?? 0) + p.monto;
    porUsuario[p.recibidoPor] = (porUsuario[p.recibidoPor] ?? 0) + p.monto;
    porPedido[p.pedidoId] = (porPedido[p.pedidoId] ?? 0) + p.monto;
  }
  return ResumenCobros(
    total: redondear2(total),
    porForma: _redondeado(porForma),
    porUsuario: _redondeado(porUsuario),
    porPedido: _redondeado(porPedido),
  );
}

class ResumenGastos {
  final double compras;
  final double sueldos;

  const ResumenGastos({required this.compras, required this.sueldos});

  double get total => redondear2(compras + sueldos);
}

ResumenGastos resumirGastos({
  required Iterable<Compra> compras,
  required Iterable<PagoSueldo> sueldos,
}) {
  var c = 0.0;
  for (final x in compras) {
    if (x.tipo == 'compra' && x.precioTotal != null) c += x.precioTotal!;
  }
  var s = 0.0;
  for (final x in sueldos) {
    s += x.monto;
  }
  return ResumenGastos(compras: redondear2(c), sueldos: redondear2(s));
}
