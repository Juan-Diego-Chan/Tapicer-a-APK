import 'costos_pedido.dart';
import 'dinero.dart';
import 'inventario.dart';
import 'lectura.dart';
import 'pedidos.dart';

enum TipoPeriodo { semana, mes, rango }

/// Máximo de días de un rango (3 meses): acota las lecturas del plan Spark.
const maxDiasRango = 93;

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

  /// Como [Periodo.rango], pero un rango de más de [maxDiasRango] días se
  /// recorta a los primeros [maxDiasRango] a partir de la fecha inicial.
  static ({Periodo periodo, bool recortado}) rangoAcotado(
    DateTime inicio,
    DateTime fin,
  ) {
    final r = Periodo.rango(inicio, fin);
    final tope = DateTime(
      r.desde.year,
      r.desde.month,
      r.desde.day + maxDiasRango,
    );
    if (!r.hasta.isAfter(tope)) return (periodo: r, recortado: false);
    return (
      periodo: Periodo._(TipoPeriodo.rango, r.desde, tope),
      recortado: true,
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

/// Costos unitarios conocidos; cada función devuelve `null` si el costo se
/// desconoce (el dueño cuesta 0 por día).
class CostosConocidos {
  final double? Function(String materialId) costoMaterial;
  final double? Function(String rolloId) costoRollo;
  final double? Function(String usuarioId) costoDiaDe;

  const CostosConocidos({
    required this.costoMaterial,
    required this.costoRollo,
    required this.costoDiaDe,
  });
}

class GananciaMueble {
  final Pedido pedido;
  final Mueble mueble;
  final Costo materiales;
  final Costo manoObra;

  const GananciaMueble({
    required this.pedido,
    required this.mueble,
    required this.materiales,
    required this.manoObra,
  });

  double get ganancia =>
      redondear2(mueble.precio - materiales.monto - manoObra.monto);

  /// `null` si el precio es 0.
  double? get margen => mueble.precio == 0 ? null : ganancia / mueble.precio;

  bool get incompleto => materiales.incompleto || manoObra.incompleto;
}

class GananciaPedido {
  final Pedido pedido;
  final double total;

  /// Solo los muebles no cancelados.
  final List<GananciaMueble> muebles;

  /// Suma de los costos de todos los muebles, cancelados incluidos.
  final Costo costos;

  const GananciaPedido({
    required this.pedido,
    required this.total,
    required this.muebles,
    required this.costos,
  });

  double get ganancia => redondear2(total - costos.monto);

  bool get incompleto => costos.incompleto;
}

GananciaPedido gananciaPedido({
  required Pedido pedido,
  required List<Mueble> muebles,
  required List<LineaMaterial> Function(String muebleId) lineasDe,
  required List<DiaTrabajado> Function(String muebleId) diasDe,
  required CostosConocidos costos,
}) {
  var suma = Costo.cero;
  final vivos = <GananciaMueble>[];
  for (final m in muebles) {
    final materiales = costoLineas(
      lineasDe(m.id),
      costoMaterial: costos.costoMaterial,
      costoRollo: costos.costoRollo,
    );
    final manoObra = costoManoObra(diasDe(m.id), costoDiaDe: costos.costoDiaDe);
    suma = suma + materiales + manoObra;
    if (m.estado != EstadoMueble.cancelado) {
      vivos.add(
        GananciaMueble(
          pedido: pedido,
          mueble: m,
          materiales: materiales,
          manoObra: manoObra,
        ),
      );
    }
  }
  return GananciaPedido(
    pedido: pedido,
    total: totalPedido(vivos.map((g) => g.mueble.precio), pedido.envio),
    muebles: vivos,
    costos: suma,
  );
}

/// Menor margen primero; margen nulo antes que todos; empate, menor ganancia.
Map<TipoTrabajo, List<GananciaMueble>> porMenorMargen(
  Iterable<GananciaMueble> muebles,
) {
  final r = {for (final t in TipoTrabajo.values) t: <GananciaMueble>[]};
  for (final g in muebles) {
    r[g.mueble.tipoTrabajo]!.add(g);
  }
  for (final lista in r.values) {
    lista.sort((a, b) {
      final ma = a.margen, mb = b.margen;
      if (ma == null && mb != null) return -1;
      if (ma != null && mb == null) return 1;
      if (ma != null && mb != null) {
        final c = ma.compareTo(mb);
        if (c != 0) return c;
      }
      return a.ganancia.compareTo(b.ganancia);
    });
  }
  return r;
}

class DiferenciaMaterial {
  final Pedido pedido;
  final Mueble mueble;
  final Comparacion comparacion;

  const DiferenciaMaterial({
    required this.pedido,
    required this.mueble,
    required this.comparacion,
  });
}

/// Comparaciones con más de 10 % sobre lo estimado (incluye materiales
/// usados que no están en la plantilla).
List<DiferenciaMaterial> diferenciasMaterial({
  required Pedido pedido,
  required List<Mueble> muebles,
  required List<LineaMaterial> Function(String muebleId) lineasDe,
  required Plantilla? Function(String? plantillaId) plantillaDe,
}) {
  final r = <DiferenciaMaterial>[];
  for (final m in muebles) {
    if (m.estado == EstadoMueble.cancelado || m.plantillaId == null) continue;
    final plantilla = plantillaDe(m.plantillaId);
    if (plantilla == null) continue;
    final comparaciones = estimadoVsUsado(
      plantilla,
      usadoPorMaterial(lineasDe(m.id)),
    );
    for (final c in comparaciones) {
      if (c.usado > c.estimado * 1.10 + 1e-9) {
        r.add(DiferenciaMaterial(pedido: pedido, mueble: m, comparacion: c));
      }
    }
  }
  return r;
}

double saldoPendiente(Pedido pedido, List<Mueble> muebles) => saldoPedido(
  totalPedido(
    muebles
        .where((m) => m.estado != EstadoMueble.cancelado)
        .map((m) => m.precio),
    pedido.envio,
  ),
  pedido.pagado,
);
