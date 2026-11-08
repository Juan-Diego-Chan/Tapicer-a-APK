import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/dinero.dart';

EntregaDinero _entrega(double monto, EstadoEntrega estado) => EntregaDinero(
      id: 'e',
      empleadoId: 'u',
      monto: monto,
      forma: FormaPago.efectivo,
      fecha: DateTime(2026),
      estado: estado,
      revisadoEn: null,
    );

void main() {
  test('saldo con residuos de punto flotante', () {
    expect(saldoPedido(0.3, 0.1 + 0.2), 0);
    expect(saldoPedido(1500, 500), 1000);
    expect(saldoPedido(1000, 1200), -200);
  });
  test('por entregar descuenta solo pendientes', () {
    final e = [
      _entrega(300, EstadoEntrega.pendiente),
      _entrega(200, EstadoEntrega.confirmada),
      _entrega(50, EstadoEntrega.rechazada),
    ];
    expect(porEntregar(1000, e), 700);
  });
  test('caja ausente vale 0', () {
    expect(enManoDe(null), 0);
    expect(enManoDe({}), 0);
    expect(enManoDe({'enMano': 0.1 + 0.2}), 0.3);
  });
  test('pago: devolución, forma y monto 0', () {
    final p = Pago.desdeMapa('p1', {'pedidoId': 'x', 'monto': -200, 'forma': 'efectivo', 'recibidoPor': 'd', 'fecha': 1}, (_) => DateTime(2026));
    expect(p.esDevolucion, isTrue);
    expect(FormaPago.transferencia.etiqueta, 'Transferencia');
    expect(() => Pago.desdeMapa('p2', {'pedidoId': 'x', 'monto': 0, 'forma': 'efectivo', 'recibidoPor': 'd', 'fecha': 1}, (_) => DateTime(2026)), throwsFormatException);
    expect(() => FormaPago.desdeTexto('cheque'), throwsFormatException);
  });
  test('entrega de dinero y pago de sueldo', () {
    final e = EntregaDinero.desdeMapa('e1', {
      'empleadoId': 'u', 'monto': 100, 'forma': 'transferencia',
      'fecha': 1, 'estado': 'pendiente', 'revisadoEn': null,
    }, (v) => v == null ? null : DateTime(2026));
    expect(e.estado.etiqueta, 'Pendiente');
    expect(e.revisadoEn, isNull);
    expect(() => EstadoEntrega.desdeTexto('x'), throwsFormatException);
    expect(EstadoEntrega.rechazada.etiqueta, 'Rechazada');
    final s = PagoSueldo.desdeMapa(
        's1', {'usuarioId': 'u', 'monto': 500, 'fecha': 1}, (_) => DateTime(2026));
    expect(s.monto, 500);
  });
}
