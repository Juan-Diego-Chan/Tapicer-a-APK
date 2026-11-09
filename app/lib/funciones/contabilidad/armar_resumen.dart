import '../../datos/repositorio_contabilidad.dart';
import '../../dominio/contabilidad.dart';
import '../../dominio/dinero.dart';
import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';

class ResumenPeriodo {
  final Periodo periodo;
  final ResumenCobros cobros;
  final Map<String, Pedido> pedidosDeCobros;

  /// Pedidos y muebles (con los cancelados) a los que pertenecen los
  /// [cambios], para mostrar su folio y el nombre del mueble.
  final Map<String, Pedido> pedidosDeCambios;
  final Map<String, List<Mueble>> mueblesDeCambios;
  final ResumenGastos gastos;

  /// Ordenada por ganancia ascendente.
  final List<GananciaPedido> ganancias;
  final Map<TipoTrabajo, List<GananciaMueble>> muebles;

  /// Ordenados por fecha.
  final List<({String pedidoId, CambioPrecio cambio})> cambios;

  /// Ordenados por saldo descendente.
  final List<({Pedido pedido, double saldo})> pendientes;
  final List<DiferenciaMaterial> diferencias;

  const ResumenPeriodo({
    required this.periodo,
    required this.cobros,
    required this.pedidosDeCobros,
    this.pedidosDeCambios = const {},
    this.mueblesDeCambios = const {},
    required this.gastos,
    required this.ganancias,
    required this.muebles,
    required this.cambios,
    required this.pendientes,
    required this.diferencias,
  });

  double get gananciaTotal =>
      redondear2(ganancias.fold(0.0, (s, g) => s + g.ganancia));
}

Future<ResumenPeriodo> armarResumen(
  RepositorioContabilidad repo, {
  required Periodo periodo,
  required List<Plantilla> plantillas,
  DateTime? ahora,
}) async {
  final lecturas = await Future.wait<Object>([
    repo.pagosEn(periodo),
    repo.comprasEn(periodo),
    repo.sueldosEn(periodo),
    repo.entregadosEn(periodo),
    repo.cambiosEn(periodo),
    repo.candidatosPendientes(ahora ?? DateTime.now()),
    repo.costos(),
  ]);
  final pagos = lecturas[0] as List<Pago>;
  final compras = lecturas[1] as List<Compra>;
  final sueldos = lecturas[2] as List<PagoSueldo>;
  final entregados = lecturas[3] as List<Pedido>;
  final cambios = lecturas[4] as List<({String pedidoId, CambioPrecio cambio})>;
  final candidatos = lecturas[5] as List<Pedido>;
  final costos = lecturas[6] as CostosConocidos;

  final cobros = resumirCobros(pagos);
  final gastos = resumirGastos(compras: compras, sueldos: sueldos);

  // Muebles: una sola lectura por pedido, para ganancias y pendientes.
  // También los de los cambios de precio, para identificarlos.
  final idsCambios = cambios.map((c) => c.pedidoId).toSet();
  final ids = {...entregados.map((p) => p.id), ...candidatos.map((p) => p.id)};
  final listaIds = [...ids, ...idsCambios.where((id) => !ids.contains(id))];
  final yaCargados = {
    for (final p in [...entregados, ...candidatos]) p.id: p,
  };
  final faltantes = {
    ...cobros.porPedido.keys,
    ...idsCambios,
  }.where((id) => !yaCargados.containsKey(id));
  final resultados = await Future.wait([
    repo.pedidosPorId(faltantes),
    ...listaIds.map(repo.mueblesDe),
  ]);
  final leidos = resultados[0] as Map<String, Pedido>;
  Map<String, Pedido> pedidosDe(Iterable<String> claves) => {
    for (final id in claves)
      if ((yaCargados[id] ?? leidos[id]) != null)
        id: (yaCargados[id] ?? leidos[id])!,
  };
  final pedidosDeCobros = pedidosDe(cobros.porPedido.keys);
  final pedidosDeCambios = pedidosDe(idsCambios);
  final mueblesPorPedido = {
    for (var i = 0; i < listaIds.length; i++)
      listaIds[i]: resultados[i + 1] as List<Mueble>,
  };

  // Líneas y días solo de los entregados del periodo.
  final detalles =
      <String, ({List<LineaMaterial> lineas, List<DiaTrabajado> dias})>{};
  final lecturasDetalle = <Future<void>>[];
  for (final p in entregados) {
    for (final m in mueblesPorPedido[p.id]!) {
      lecturasDetalle.add(() async {
        final r = await Future.wait<Object>([
          repo.lineasDe(p.id, m.id),
          repo.diasDe(p.id, m.id),
        ]);
        detalles[m.id] = (
          lineas: r[0] as List<LineaMaterial>,
          dias: r[1] as List<DiaTrabajado>,
        );
      }());
    }
  }
  await Future.wait(lecturasDetalle);

  final ganancias = <GananciaPedido>[];
  final diferencias = <DiferenciaMaterial>[];
  final plantillasPorId = {for (final p in plantillas) p.id: p};
  for (final p in entregados) {
    final muebles = mueblesPorPedido[p.id]!;
    List<LineaMaterial> lineasDe(String id) => detalles[id]?.lineas ?? const [];
    ganancias.add(
      gananciaPedido(
        pedido: p,
        muebles: muebles,
        lineasDe: lineasDe,
        diasDe: (id) => detalles[id]?.dias ?? const [],
        costos: costos,
      ),
    );
    diferencias.addAll(
      diferenciasMaterial(
        pedido: p,
        muebles: muebles,
        lineasDe: lineasDe,
        plantillaDe: (id) => id == null ? null : plantillasPorId[id],
      ),
    );
  }
  ganancias.sort((a, b) => a.ganancia.compareTo(b.ganancia));

  final pendientes = <({Pedido pedido, double saldo})>[];
  for (final p in candidatos) {
    final saldo = saldoPendiente(p, mueblesPorPedido[p.id]!);
    if (saldo > 0) pendientes.add((pedido: p, saldo: saldo));
  }
  pendientes.sort((a, b) => b.saldo.compareTo(a.saldo));

  final cambiosOrdenados = [...cambios]
    ..sort((a, b) => a.cambio.fecha.compareTo(b.cambio.fecha));

  return ResumenPeriodo(
    periodo: periodo,
    cobros: cobros,
    pedidosDeCobros: pedidosDeCobros,
    pedidosDeCambios: pedidosDeCambios,
    mueblesDeCambios: {
      for (final id in idsCambios) id: mueblesPorPedido[id] ?? const [],
    },
    gastos: gastos,
    ganancias: ganancias,
    muebles: porMenorMargen(ganancias.expand((g) => g.muebles)),
    cambios: cambiosOrdenados,
    pendientes: pendientes,
    diferencias: diferencias,
  );
}
