import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/contabilidad.dart';
import 'package:tapiceria/dominio/costos_pedido.dart';
import 'package:tapiceria/dominio/dinero.dart';
import 'package:tapiceria/dominio/pedidos.dart';

Pago _pago(
  String id,
  String pedidoId,
  double monto,
  FormaPago forma,
  String recibidoPor,
) => Pago(
  id: id,
  pedidoId: pedidoId,
  monto: monto,
  forma: forma,
  recibidoPor: recibidoPor,
  fecha: DateTime(2026, 11, 7),
);

Compra _compra(double? precioTotal, String tipo) => Compra(
  id: 'c',
  materialId: 'm',
  precioTotal: precioTotal,
  fecha: DateTime(2026, 11, 7),
  tipo: tipo,
);

PagoSueldo _sueldo(double monto) => PagoSueldo(
  id: 's',
  usuarioId: 'u',
  monto: monto,
  fecha: DateTime(2026, 11, 7),
);

void main() {
  _pruebasGanancias();
  test('semana que cruza el año', () {
    final s = Periodo.semana(DateTime(2027, 1, 3, 23, 59));
    expect(s.desde, DateTime(2026, 12, 28));
    expect(s.hasta, DateTime(2027, 1, 4));
    expect(s.contiene(DateTime(2027, 1, 3, 23, 59)), isTrue);
    expect(s.contiene(DateTime(2027, 1, 4)), isFalse);
    expect(s.etiqueta, 'Semana del 28/12/2026 al 03/01/2027');
    expect(s.siguiente().desde, DateTime(2027, 1, 4));
    expect(s.anterior().desde, DateTime(2026, 12, 21));
  });
  test('mes y rango', () {
    final m = Periodo.mes(DateTime(2026, 11, 7));
    expect(m.desde, DateTime(2026, 11, 1));
    expect(m.hasta, DateTime(2026, 12, 1));
    expect(m.etiqueta, 'Noviembre 2026');
    expect(m.anterior().etiqueta, 'Octubre 2026');
    expect(
      Periodo.mes(DateTime(2026, 12, 5)).siguiente().desde,
      DateTime(2027, 1, 1),
    );
    expect(
      Periodo.mes(DateTime(2026, 1, 5)).anterior().desde,
      DateTime(2025, 12, 1),
    );
    final r = Periodo.rango(DateTime(2026, 11, 10), DateTime(2026, 11, 3));
    expect(r.desde, DateTime(2026, 11, 3));
    expect(r.hasta, DateTime(2026, 11, 11));
    expect(r.etiqueta, 'Del 03/11/2026 al 10/11/2026');
    expect(() => r.anterior(), throwsStateError);
    expect(() => r.siguiente(), throwsStateError);
    expect(
      Periodo.semana(DateTime(2026, 11, 7)),
      Periodo.semana(DateTime(2026, 11, 5)),
    );
    expect(
      Periodo.semana(DateTime(2026, 11, 7)).hashCode,
      Periodo.semana(DateTime(2026, 11, 5)).hashCode,
    );
    expect(
      Periodo.mes(DateTime(2026, 11, 7)),
      isNot(Periodo.semana(DateTime(2026, 11, 7))),
    );
  });
  test('resumen de cobros con devolución', () {
    final r = resumirCobros([
      _pago('p1', 'pedA', 500, FormaPago.efectivo, 'emp1'),
      _pago('p2', 'pedA', 300, FormaPago.transferencia, 'due1'),
      _pago('p3', 'pedB', -200, FormaPago.efectivo, 'due1'),
    ]);
    expect(r.total, 600);
    expect(r.porForma[FormaPago.efectivo], 300);
    expect(r.porUsuario['due1'], 100);
    expect(r.porPedido['pedB'], -200);
  });
  test('gastos ignoran la carga inicial', () {
    final g = resumirGastos(
      compras: [
        _compra(1500, 'compra'),
        _compra(9000, 'inicial'),
        _compra(null, 'inicial'),
      ],
      sueldos: [_sueldo(1800)],
    );
    expect(g.compras, 1500);
    expect(g.total, 3300);
  });
  test('Compra.desdeMapa acepta precioTotal nulo', () {
    final c = Compra.desdeMapa('c1', {
      'materialId': 'm1',
      'tipo': 'compra',
      'fecha': 1,
    }, (_) => DateTime(2026, 11, 7));
    expect(c.precioTotal, isNull);
    expect(c.materialId, 'm1');
  });
}

Pedido _pedido({double envio = 0, double pagado = 0}) => Pedido(
  id: 'p1',
  folio: '261107-P1',
  cliente: const Cliente(
    id: 'c1',
    nombre: 'Ana',
    telefono: '5551234567',
    direccion: '',
  ),
  entrega: Entrega.recoge,
  envio: envio,
  comentarios: '',
  fechaIngreso: DateTime(2026, 11, 7),
  fechaEstimada: DateTime(2026, 11, 20),
  fechaTerminado: null,
  fechaEntregado: null,
  estado: EstadoMueble.recibido,
  creadoPor: 'u1',
  pagado: pagado,
);

Mueble _mueble(
  String id,
  double precio, {
  EstadoMueble estado = EstadoMueble.recibido,
  TipoTrabajo tipo = TipoTrabajo.fabricacion,
  String? plantillaId,
}) => Mueble(
  id: id,
  pedidoId: 'p1',
  tipoTrabajo: tipo,
  tipoMueble: 'Sillón',
  plantillaId: plantillaId,
  precio: precio,
  comentarios: '',
  estado: estado,
);

LineaMaterial _linea(String materialId, double cantidad, {String? rolloId}) =>
    LineaMaterial(
      id: 'l-$materialId-$cantidad',
      materialId: materialId,
      rolloId: rolloId,
      cantidad: cantidad,
      delCliente: false,
      usuarioId: 'u1',
      fecha: DateTime(2026, 11, 7),
    );

DiaTrabajado _dias(double d) => DiaTrabajado(
  id: 'd',
  usuarioId: 'u1',
  dias: d,
  fecha: DateTime(2026, 11, 7),
);

CostosConocidos _costos({bool rolloConPrecio = true}) => CostosConocidos(
  costoMaterial: (id) => const {'guata': 60.0, 'espuma': 40.0}[id],
  costoRollo: (id) => rolloConPrecio && id == 'r1' ? 110.0 : null,
  costoDiaDe: (u) => u == 'u1' ? 2100 / 6 : null,
);

GananciaMueble _gm(
  String id,
  double precio,
  double costo, {
  TipoTrabajo tipo = TipoTrabajo.fabricacion,
}) => GananciaMueble(
  pedido: _pedido(),
  mueble: _mueble(id, precio, tipo: tipo),
  materiales: Costo(costo),
  manoObra: Costo.cero,
);

void _pruebasGanancias() {
  group('gananciaPedido', () {
    test('sillón de 6500', () {
      final r = gananciaPedido(
        pedido: _pedido(),
        muebles: [_mueble('m1', 6500)],
        lineasDe: (_) => [
          _linea('tela', 2.5, rolloId: 'r1'),
          _linea('guata', 1),
        ],
        diasDe: (_) => [_dias(1.5)],
        costos: _costos(),
      );
      final m = r.muebles.single;
      expect(m.materiales.monto, 335.0);
      expect(m.manoObra.monto, 525.0);
      expect(m.ganancia, 5640.0);
      expect(m.margen, closeTo(0.8677, 0.0001));
      expect(m.incompleto, isFalse);
      expect(r.ganancia, 5640.0);
      expect(r.incompleto, isFalse);
    });

    test('rollo sin precio deja incompleto', () {
      final r = gananciaPedido(
        pedido: _pedido(),
        muebles: [_mueble('m1', 6500)],
        lineasDe: (_) => [
          _linea('tela', 2.5, rolloId: 'r1'),
          _linea('guata', 1),
        ],
        diasDe: (_) => const [],
        costos: _costos(rolloConPrecio: false),
      );
      expect(r.muebles.single.incompleto, isTrue);
      expect(r.muebles.single.ganancia, 6440.0);
      expect(r.incompleto, isTrue);
    });

    test('mueble cancelado: costos incluidos, lista excluida', () {
      final r = gananciaPedido(
        pedido: _pedido(envio: 200),
        muebles: [
          _mueble('m1', 1000),
          _mueble('m2', 600, estado: EstadoMueble.cancelado),
        ],
        lineasDe: (id) => id == 'm2' ? [_linea('guata', 1)] : const [],
        diasDe: (_) => const [],
        costos: CostosConocidos(
          costoMaterial: (_) => 100,
          costoRollo: (_) => null,
          costoDiaDe: (_) => 0,
        ),
      );
      expect(r.total, 1200.0);
      expect(r.costos.monto, 100.0);
      expect(r.ganancia, 1100.0);
      expect(r.muebles, hasLength(1));
    });
  });

  group('porMenorMargen', () {
    test('ordena con margen null primero', () {
      final r = porMenorMargen([
        _gm('a', 1000, 100), // 0.9
        _gm('b', 0, 50), // null
        _gm('c', 1000, 600), // 0.4
        _gm('d', 500, 100, tipo: TipoTrabajo.reparacion), // 0.8
      ]);
      expect(r.keys, containsAll(TipoTrabajo.values));
      expect(r[TipoTrabajo.fabricacion]!.map((g) => g.mueble.id), [
        'b',
        'c',
        'a',
      ]);
      expect(r[TipoTrabajo.reparacion]!.map((g) => g.mueble.id), ['d']);
    });

    test('empate de margen gana la menor ganancia; llaves vacías', () {
      final r = porMenorMargen([
        _gm('a', 2000, 1000), // 0.5, ganancia 1000
        _gm('b', 1000, 500), // 0.5, ganancia 500
      ]);
      expect(r[TipoTrabajo.fabricacion]!.map((g) => g.mueble.id), ['b', 'a']);
      expect(r[TipoTrabajo.reparacion], isEmpty);
    });
  });

  group('diferenciasMaterial', () {
    const plantilla = Plantilla(
      id: 'pl',
      tipoMueble: 'Sillón',
      lineas: [
        LineaPlantilla(materialId: 'tela', cantidad: 6),
        LineaPlantilla(materialId: 'guata', cantidad: 1),
      ],
    );

    List<DiferenciaMaterial> dif(
      List<LineaMaterial> lineas, {
      String? plantillaId = 'pl',
      EstadoMueble estado = EstadoMueble.recibido,
    }) => diferenciasMaterial(
      pedido: _pedido(),
      muebles: [_mueble('m1', 1000, plantillaId: plantillaId, estado: estado)],
      lineasDe: (_) => lineas,
      plantillaDe: (id) => id == 'pl' ? plantilla : null,
    );

    test('6.5 de tela no es diferencia', () {
      expect(dif([_linea('tela', 6.5), _linea('guata', 1)]), isEmpty);
    });
    test('6.7 de tela sí', () {
      final r = dif([_linea('tela', 6.7)]);
      expect(r.single.comparacion.materialId, 'tela');
    });
    test('material fuera de plantilla sí', () {
      final r = dif([_linea('espuma', 0.5)]);
      expect(r.single.comparacion.materialId, 'espuma');
      expect(r.single.comparacion.estimado, 0);
    });
    test('sin plantilla o cancelado: nada', () {
      expect(dif([_linea('tela', 9)], plantillaId: null), isEmpty);
      expect(dif([_linea('tela', 9)], estado: EstadoMueble.cancelado), isEmpty);
    });
  });

  test('saldoPendiente', () {
    final saldo = saldoPendiente(_pedido(envio: 300, pagado: 1500), [
      _mueble('m1', 6500),
      _mueble('m2', 900, estado: EstadoMueble.cancelado),
    ]);
    expect(saldo, 5300.0);
  });

  test('rangoAcotado recorta a 93 días desde el inicio', () {
    final ok = Periodo.rangoAcotado(DateTime(2026, 1, 1), DateTime(2026, 4, 3));
    expect(ok.recortado, isFalse); // 93 días exactos
    expect(ok.periodo.hasta, DateTime(2026, 4, 4));
    final largo = Periodo.rangoAcotado(
      DateTime(2026, 1, 1),
      DateTime(2026, 12, 31),
    );
    expect(largo.recortado, isTrue);
    expect(largo.periodo.tipo, TipoPeriodo.rango);
    expect(largo.periodo.desde, DateTime(2026, 1, 1));
    expect(largo.periodo.hasta, DateTime(2026, 4, 4));
    final corto = Periodo.rangoAcotado(
      DateTime(2026, 11, 3),
      DateTime(2026, 11, 3),
    );
    expect(corto.recortado, isFalse);
  });
}
