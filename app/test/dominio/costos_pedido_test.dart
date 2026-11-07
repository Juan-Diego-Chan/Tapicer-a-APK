import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/costos_pedido.dart';
import 'package:tapiceria/dominio/pedidos.dart';

LineaMaterial linea({
  required String materialId,
  String? rolloId,
  required double cantidad,
  bool delCliente = false,
}) =>
    LineaMaterial(
      id: 'l',
      materialId: materialId,
      rolloId: rolloId,
      cantidad: cantidad,
      delCliente: delCliente,
      usuarioId: 'u',
      fecha: DateTime(2026, 1, 1),
    );

DiaTrabajado dia(String usuarioId, double dias) =>
    DiaTrabajado(id: 'd', usuarioId: usuarioId, dias: dias, fecha: DateTime(2026, 1, 1));

Plantilla plantilla(List<(String, double)> lineas) => Plantilla(
      id: 'p',
      tipoMueble: 'sofa',
      lineas: [
        for (final (m, c) in lineas) LineaPlantilla(materialId: m, cantidad: c),
      ],
    );

void main() {
  test('costo de líneas: rollo, promedio, cliente e incompleto', () {
    final lineas = [
      linea(materialId: 'tela', rolloId: 'r1', cantidad: 2.5),
      linea(materialId: 'guata', cantidad: 1),
      linea(materialId: 'tela', cantidad: 3, delCliente: true),
    ];
    final c = costoLineas(lineas,
        costoMaterial: (id) => {'guata': 60.0}[id],
        costoRollo: (id) => {'r1': 110.0}[id]);
    expect(c.monto, 335);
    expect(c.incompleto, isFalse);
    final sinCosto = costoLineas([linea(materialId: 'espuma', cantidad: 1)],
        costoMaterial: (_) => null, costoRollo: (_) => null);
    expect(sinCosto.monto, 0);
    expect(sinCosto.incompleto, isTrue);
  });
  test('línea del cliente sin costo conocido no marca incompleto', () {
    final c = costoLineas(
        [linea(materialId: 'tela', cantidad: 3, delCliente: true)],
        costoMaterial: (_) => null,
        costoRollo: (_) => null);
    expect(c.monto, 0);
    expect(c.incompleto, isFalse);
  });
  test('mano de obra', () {
    expect(costoPorDia(sueldoSemanal: 2100, diasLaborales: 6), 350);
    expect(costoPorDia(sueldoSemanal: null, diasLaborales: 6), isNull);
    expect(costoPorDia(sueldoSemanal: 2100, diasLaborales: 0), isNull);
    final c = costoManoObra([dia('emp', 1.5), dia('dueno', 2)],
        costoDiaDe: (u) => u == 'dueno' ? 0 : 350);
    expect(c.monto, 525);
    expect(costoManoObra([dia('x', 1)], costoDiaDe: (_) => null).incompleto,
        isTrue);
  });
  test('costo estimado y suma de costos', () {
    final p = plantilla([('tela', 2), ('guata', 1)]);
    final c = costoEstimado(p, costoMaterial: (id) => {'tela': 100.0}[id]);
    expect(c.monto, 200);
    expect(c.incompleto, isTrue);
    final s = Costo.cero + const Costo(0.1) + const Costo(0.2, incompleto: true);
    expect(s.monto, 0.3);
    expect(s.incompleto, isTrue);
  });
  test('usado por material incluye líneas del cliente', () {
    final u = usadoPorMaterial([
      linea(materialId: 'tela', cantidad: 1.5),
      linea(materialId: 'tela', cantidad: 2, delCliente: true),
      linea(materialId: 'guata', cantidad: 1),
    ]);
    expect(u, {'tela': 3.5, 'guata': 1});
  });
  test('faltantes descuenta lo ya usado', () {
    final p = plantilla([('tela', 6), ('guata', 1)]);
    final f = faltantes(p, existencias: {'tela': 4, 'guata': 5}, usado: {'tela': 1});
    expect(f.single.materialId, 'tela');
    expect(f.single.necesita, 5);
    expect(f.single.hay, 4);
    expect(
        faltantes(p, existencias: {'tela': 5, 'guata': 1}, usado: {'tela': 1}),
        isEmpty);
    expect(faltantes(p, existencias: {}, usado: {}).length, 2);
    expect(faltantes(p, existencias: {}, usado: {'tela': 6, 'guata': 1}),
        isEmpty);
  });
  test('estimado vs usado', () {
    final c = estimadoVsUsado(plantilla([('tela', 6)]), {'tela': 6.5, 'grapas': 1});
    expect(c.map((x) => x.materialId), ['tela', 'grapas']);
    expect(c.first.excedido, isTrue);
    expect(c.last.estimado, 0);
    expect(estimadoVsUsado(null, {}), isEmpty);
  });
}
