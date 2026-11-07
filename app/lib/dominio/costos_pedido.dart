import 'inventario.dart';
import 'pedidos.dart';

/// Monto con indicador de que faltó algún costo (nunca se calcula con 0
/// un costo desconocido: se marca [incompleto]).
class Costo {
  final double monto;
  final bool incompleto;

  const Costo(this.monto, {this.incompleto = false});

  static const cero = Costo(0);

  Costo operator +(Costo o) =>
      Costo(redondear2(monto + o.monto), incompleto: incompleto || o.incompleto);
}

Costo costoLineas(
  Iterable<LineaMaterial> lineas, {
  required double? Function(String materialId) costoMaterial,
  required double? Function(String rolloId) costoRollo,
}) {
  var total = Costo.cero;
  for (final l in lineas) {
    if (l.delCliente) continue;
    final rollo = l.rolloId;
    final unitario = rollo != null ? costoRollo(rollo) : costoMaterial(l.materialId);
    total = unitario == null
        ? total + const Costo(0, incompleto: true)
        : total + Costo(redondear2(l.cantidad * unitario));
  }
  return total;
}

double? costoPorDia({required double? sueldoSemanal, required int diasLaborales}) {
  if (sueldoSemanal == null || diasLaborales <= 0) return null;
  return sueldoSemanal / diasLaborales;
}

/// [costoDiaDe] devuelve 0 para el dueño y `null` si el sueldo es desconocido.
Costo costoManoObra(
  Iterable<DiaTrabajado> dias, {
  required double? Function(String usuarioId) costoDiaDe,
}) {
  var total = Costo.cero;
  for (final d in dias) {
    final porDia = costoDiaDe(d.usuarioId);
    total = porDia == null
        ? total + const Costo(0, incompleto: true)
        : total + Costo(redondear2(d.dias * porDia));
  }
  return total;
}

Costo costoEstimado(
  Plantilla p, {
  required double? Function(String materialId) costoMaterial,
}) {
  var total = Costo.cero;
  for (final l in p.lineas) {
    final unitario = costoMaterial(l.materialId);
    total = unitario == null
        ? total + const Costo(0, incompleto: true)
        : total + Costo(redondear2(l.cantidad * unitario));
  }
  return total;
}

/// Incluye las líneas del cliente: cuentan como material usado aunque no
/// tengan costo.
Map<String, double> usadoPorMaterial(Iterable<LineaMaterial> lineas) {
  final usado = <String, double>{};
  for (final l in lineas) {
    usado[l.materialId] = redondear2((usado[l.materialId] ?? 0) + l.cantidad);
  }
  return usado;
}

class Faltante {
  final String materialId;
  final double necesita;
  final double hay;

  const Faltante(
      {required this.materialId, required this.necesita, required this.hay});
}

List<Faltante> faltantes(
  Plantilla p, {
  required Map<String, double> existencias,
  required Map<String, double> usado,
}) {
  final resultado = <Faltante>[];
  for (final l in p.lineas) {
    final pendiente = redondear2(l.cantidad - (usado[l.materialId] ?? 0));
    final hay = redondear2(existencias[l.materialId] ?? 0);
    if (pendiente > 0 && hay < pendiente) {
      resultado.add(
          Faltante(materialId: l.materialId, necesita: pendiente, hay: hay));
    }
  }
  return resultado;
}

class Comparacion {
  final String materialId;
  final double estimado;
  final double usado;

  const Comparacion(
      {required this.materialId, required this.estimado, required this.usado});

  bool get excedido => redondear2(usado) > redondear2(estimado);
}

List<Comparacion> estimadoVsUsado(Plantilla? p, Map<String, double> usado) {
  final estimado = <String, double>{};
  for (final l in p?.lineas ?? const <LineaPlantilla>[]) {
    estimado[l.materialId] = (estimado[l.materialId] ?? 0) + l.cantidad;
  }
  return [
    for (final e in estimado.entries)
      Comparacion(
          materialId: e.key, estimado: e.value, usado: usado[e.key] ?? 0),
    for (final u in usado.entries)
      if (!estimado.containsKey(u.key))
        Comparacion(materialId: u.key, estimado: 0, usado: u.value),
  ];
}
