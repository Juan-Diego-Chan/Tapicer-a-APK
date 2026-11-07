import 'lectura.dart';

enum Categoria {
  tela('Tela'),
  espuma('Espuma'),
  guata('Guata'),
  resortes('Resortes'),
  cinchas('Cinchas'),
  grapas('Grapas'),
  otros('Otros');

  const Categoria(this.etiqueta);
  final String etiqueta;

  static Categoria desdeTexto(String texto) {
    for (final c in values) {
      if (c.name == texto) return c;
    }
    throw FormatException('Categoría desconocida: $texto');
  }
}

enum Unidad {
  m('m'),
  kg('kg'),
  pza('pza'),
  l('l');

  const Unidad(this.clave);
  final String clave;

  static Unidad desdeTexto(String texto) {
    for (final u in values) {
      if (u.clave == texto) return u;
    }
    throw FormatException('Unidad desconocida: $texto');
  }
}

class Material {
  final String id;
  final String nombre;
  final Categoria categoria;
  final Unidad unidad;
  final double stockMinimo;
  final double existencia;
  final bool usaRollos;
  final bool marcadoAgotandose;

  const Material({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.unidad,
    required this.stockMinimo,
    required this.existencia,
    required this.usaRollos,
    required this.marcadoAgotandose,
  });

  factory Material.desdeMapa(String id, Map<String, dynamic> mapa) {
    return Material(
      id: id,
      nombre: leerTexto(mapa, 'nombre'),
      categoria: Categoria.desdeTexto(leerTexto(mapa, 'categoria')),
      unidad: Unidad.desdeTexto(leerTexto(mapa, 'unidad')),
      stockMinimo: leerNumero(mapa, 'stockMinimo'),
      existencia: leerNumero(mapa, 'existencia'),
      usaRollos: leerBooleano(mapa, 'usaRollos'),
      marcadoAgotandose: leerBooleano(mapa, 'marcadoAgotandose'),
    );
  }

  Map<String, dynamic> aMapaAlta() => {
        'nombre': nombre,
        'categoria': categoria.name,
        'unidad': unidad.clave,
        'stockMinimo': stockMinimo,
        'existencia': 0,
        'usaRollos': categoria == Categoria.tela,
        'marcadoAgotandose': false,
      };

  bool get necesitaCompra =>
      redondear2(existencia) < redondear2(stockMinimo) || marcadoAgotandose;

  bool get existenciaNegativa => redondear2(existencia) < 0;
}

class Rollo {
  final String id;
  final String materialId;
  final String codigo;
  final double cantidadInicial;
  final double existencia;
  final DateTime fechaCompra;

  const Rollo({
    required this.id,
    required this.materialId,
    required this.codigo,
    required this.cantidadInicial,
    required this.existencia,
    required this.fechaCompra,
  });

  /// [fechaCompra] llega ya convertida a [DateTime] (el repositorio convierte
  /// el Timestamp).
  factory Rollo.desdeMapa(
      String id, Map<String, dynamic> mapa, DateTime fechaCompra) {
    return Rollo(
      id: id,
      materialId: leerTexto(mapa, 'materialId'),
      codigo: leerTexto(mapa, 'codigo'),
      cantidadInicial: leerNumero(mapa, 'cantidadInicial'),
      existencia: leerNumero(mapa, 'existencia'),
      fechaCompra: fechaCompra,
    );
  }
}

enum TipoMovimiento { compra, inicial, consumo, ajuste }

class Movimiento {
  final String id;
  final TipoMovimiento tipo;
  final String materialId;
  final String? rolloId;
  final double cantidad;
  final String usuarioId;
  final DateTime fecha;

  const Movimiento({
    required this.id,
    required this.tipo,
    required this.materialId,
    required this.rolloId,
    required this.cantidad,
    required this.usuarioId,
    required this.fecha,
  });

  /// [fecha] llega ya convertida a [DateTime].
  factory Movimiento.desdeMapa(
      String id, Map<String, dynamic> mapa, DateTime fecha) {
    final nombreTipo = leerTexto(mapa, 'tipo');
    final tipo = TipoMovimiento.values.where((t) => t.name == nombreTipo);
    if (tipo.isEmpty) {
      throw FormatException('Tipo de movimiento desconocido: $nombreTipo');
    }
    final rolloId = mapa['rolloId'];
    if (rolloId != null && rolloId is! String) {
      throw FormatException('Campo "rolloId" no es texto: $rolloId');
    }
    return Movimiento(
      id: id,
      tipo: tipo.first,
      materialId: leerTexto(mapa, 'materialId'),
      rolloId: rolloId as String?,
      cantidad: leerNumero(mapa, 'cantidad'),
      usuarioId: leerTexto(mapa, 'usuarioId'),
      fecha: fecha,
    );
  }
}

double? costoPromedio({
  required double cantidadComprada,
  required double costoTotalComprado,
}) {
  if (cantidadComprada <= 0) return null;
  return costoTotalComprado / cantidadComprada;
}

String siguienteCodigoRollo(Iterable<String> codigos) {
  final patron = RegExp(r'^#(\d+)$');
  var mayor = 0;
  for (final codigo in codigos) {
    final n = int.tryParse(patron.firstMatch(codigo)?.group(1) ?? '');
    if (n != null && n > mayor) mayor = n;
  }
  return '#${mayor + 1}';
}

double? leerCantidad(String texto) {
  final limpio = texto.trim().replaceAll(',', '.');
  if (limpio.isEmpty) return null;
  final valor = double.tryParse(limpio);
  return valor != null && valor.isFinite ? valor : null;
}

/// Redondea a 2 decimales y normaliza -0 a 0 (evita deriva de punto flotante).
double redondear2(double v) {
  final r = (v * 100).roundToDouble() / 100;
  return r == 0 ? 0.0 : r;
}

/// Lee dinero en es-MX: la coma agrupa miles ("1,500" = 1500).
double? leerDinero(String texto) {
  var t = texto.trim();
  if (t.startsWith(r'$')) t = t.substring(1);
  t = t.replaceAll(' ', '');
  if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d{1,2})?$').hasMatch(t)) {
    t = t.replaceAll(',', '');
  } else if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) {
    return null;
  }
  final v = double.tryParse(t);
  return v != null && v.isFinite ? v : null;
}

String formatearCantidad(double c, Unidad u) {
  var s = c.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  if (s == '-0') s = '0';
  return '$s ${u.clave}';
}
