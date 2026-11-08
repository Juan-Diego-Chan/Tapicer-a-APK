import 'inventario.dart';
import 'lectura.dart';

enum FormaPago {
  efectivo('efectivo', 'Efectivo'),
  transferencia('transferencia', 'Transferencia');

  const FormaPago(this.clave, this.etiqueta);
  final String clave;
  final String etiqueta;

  static FormaPago desdeTexto(String texto) {
    for (final f in values) {
      if (f.clave == texto) return f;
    }
    throw FormatException('Forma de pago desconocida: $texto');
  }
}

enum EstadoEntrega {
  pendiente('pendiente', 'Pendiente'),
  confirmada('confirmada', 'Confirmada'),
  rechazada('rechazada', 'Rechazada');

  const EstadoEntrega(this.clave, this.etiqueta);
  final String clave;
  final String etiqueta;

  static EstadoEntrega desdeTexto(String texto) {
    for (final e in values) {
      if (e.clave == texto) return e;
    }
    throw FormatException('Estado de entrega desconocido: $texto');
  }
}

DateTime _fecha(Map<String, dynamic> m, String campo,
    DateTime? Function(Object?) aFecha) {
  final f = aFecha(m[campo]);
  if (f == null) {
    throw FormatException('Fecha "$campo" ausente o inválida: ${m[campo]}');
  }
  return f;
}

class Pago {
  final String id;
  final String pedidoId;
  final double monto;
  final FormaPago forma;
  final String recibidoPor;
  final DateTime fecha;

  const Pago({
    required this.id,
    required this.pedidoId,
    required this.monto,
    required this.forma,
    required this.recibidoPor,
    required this.fecha,
  });

  bool get esDevolucion => monto < 0;

  factory Pago.desdeMapa(
      String id, Map<String, dynamic> m, DateTime? Function(Object?) aFecha) {
    final monto = redondear2(leerNumero(m, 'monto'));
    if (monto == 0) throw const FormatException('El monto del pago no puede ser 0');
    return Pago(
      id: id,
      pedidoId: leerTexto(m, 'pedidoId'),
      monto: monto,
      forma: FormaPago.desdeTexto(leerTexto(m, 'forma')),
      recibidoPor: leerTexto(m, 'recibidoPor'),
      fecha: _fecha(m, 'fecha', aFecha),
    );
  }
}

class EntregaDinero {
  final String id;
  final String empleadoId;
  final double monto;
  final FormaPago forma;
  final DateTime fecha;
  final EstadoEntrega estado;
  final DateTime? revisadoEn;

  const EntregaDinero({
    required this.id,
    required this.empleadoId,
    required this.monto,
    required this.forma,
    required this.fecha,
    required this.estado,
    required this.revisadoEn,
  });

  factory EntregaDinero.desdeMapa(
      String id, Map<String, dynamic> m, DateTime? Function(Object?) aFecha) {
    return EntregaDinero(
      id: id,
      empleadoId: leerTexto(m, 'empleadoId'),
      monto: redondear2(leerNumero(m, 'monto')),
      forma: FormaPago.desdeTexto(leerTexto(m, 'forma')),
      fecha: _fecha(m, 'fecha', aFecha),
      estado: EstadoEntrega.desdeTexto(leerTexto(m, 'estado')),
      revisadoEn: aFecha(m['revisadoEn']),
    );
  }
}

class PagoSueldo {
  final String id;
  final String usuarioId;
  final double monto;
  final DateTime fecha;

  const PagoSueldo({
    required this.id,
    required this.usuarioId,
    required this.monto,
    required this.fecha,
  });

  factory PagoSueldo.desdeMapa(
      String id, Map<String, dynamic> m, DateTime? Function(Object?) aFecha) {
    return PagoSueldo(
      id: id,
      usuarioId: leerTexto(m, 'usuarioId'),
      monto: redondear2(leerNumero(m, 'monto')),
      fecha: _fecha(m, 'fecha', aFecha),
    );
  }
}

/// Dinero en manos del empleado; 0 si aún no tiene caja.
double enManoDe(Map<String, dynamic>? datosCaja) {
  if (datosCaja == null || datosCaja['enMano'] == null) return 0;
  return redondear2(leerNumero(datosCaja, 'enMano'));
}

double saldoPedido(double total, double pagado) => redondear2(total - pagado);

/// Lo que el empleado aún puede entregar: en mano menos lo ya pendiente.
double porEntregar(double enMano, Iterable<EntregaDinero> entregas) {
  final pendiente = entregas
      .where((e) => e.estado == EstadoEntrega.pendiente)
      .fold<double>(0, (s, e) => s + e.monto);
  return redondear2(enMano - pendiente);
}
