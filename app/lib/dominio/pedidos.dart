import 'inventario.dart';
import 'lectura.dart';

enum TipoTrabajo {
  fabricacion('fabricacion', 'Fabricación'),
  reparacion('reparacion', 'Reparación');

  const TipoTrabajo(this.clave, this.etiqueta);
  final String clave;
  final String etiqueta;

  static TipoTrabajo desdeTexto(String texto) {
    for (final t in values) {
      if (t.clave == texto) return t;
    }
    throw FormatException('Tipo de trabajo desconocido: $texto');
  }
}

enum Entrega {
  recoge('recoge', 'Lo recoge'),
  domicilio('domicilio', 'A domicilio');

  const Entrega(this.clave, this.etiqueta);
  final String clave;
  final String etiqueta;

  static Entrega desdeTexto(String texto) {
    for (final e in values) {
      if (e.clave == texto) return e;
    }
    throw FormatException('Entrega desconocida: $texto');
  }
}

/// El orden de los valores es el orden de avance (ver [estadoPedido]).
enum EstadoMueble {
  recibido('recibido', 'Recibido'),
  enProceso('en_proceso', 'En proceso'),
  terminado('terminado', 'Terminado'),
  entregado('entregado', 'Entregado'),
  cancelado('cancelado', 'Cancelado');

  const EstadoMueble(this.clave, this.etiqueta);
  final String clave;
  final String etiqueta;

  bool get activo =>
      this == recibido || this == enProceso || this == terminado;

  static EstadoMueble desdeTexto(String texto) {
    for (final e in values) {
      if (e.clave == texto) return e;
    }
    throw FormatException('Estado desconocido: $texto');
  }
}

class Cliente {
  final String id;
  final String nombre;
  final String telefono;
  final String direccion;

  const Cliente({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.direccion,
  });

  factory Cliente.desdeMapa(String id, Map<String, dynamic> mapa) {
    return Cliente(
      id: id,
      nombre: leerTexto(mapa, 'nombre'),
      telefono: leerTexto(mapa, 'telefono'),
      direccion: leerTexto(mapa, 'direccion'),
    );
  }

  Map<String, dynamic> aMapa() => {
        'nombre': nombre,
        'telefono': telefono,
        'direccion': direccion,
      };
}

DateTime _fechaObligatoria(Map<String, dynamic> mapa, String campo,
    DateTime? Function(Object?) aFecha) {
  final f = aFecha(mapa[campo]);
  if (f == null) {
    throw FormatException('Fecha "$campo" ausente o inválida: ${mapa[campo]}');
  }
  return f;
}

class Pedido {
  final String id;
  final String folio;
  final Cliente cliente;
  final Entrega entrega;
  final double envio;
  final String comentarios;
  final DateTime fechaIngreso;
  final DateTime fechaEstimada;
  final DateTime? fechaTerminado;
  final DateTime? fechaEntregado;
  final EstadoMueble estado;
  final String creadoPor;

  const Pedido({
    required this.id,
    required this.folio,
    required this.cliente,
    required this.entrega,
    required this.envio,
    required this.comentarios,
    required this.fechaIngreso,
    required this.fechaEstimada,
    required this.fechaTerminado,
    required this.fechaEntregado,
    required this.estado,
    required this.creadoPor,
  });

  /// [aFecha] convierte el valor crudo (Timestamp) a [DateTime]; devuelve
  /// `null` si no es una fecha.
  factory Pedido.desdeMapa(
      String id, Map<String, dynamic> m, DateTime? Function(Object?) aFecha) {
    final datosCliente = m['cliente'];
    if (datosCliente is! Map<String, dynamic>) {
      throw FormatException('Campo "cliente" ausente o inválido: $datosCliente');
    }
    return Pedido(
      id: id,
      folio: leerTexto(m, 'folio'),
      cliente: Cliente.desdeMapa(leerTexto(m, 'clienteId'), datosCliente),
      entrega: Entrega.desdeTexto(leerTexto(m, 'entrega')),
      envio: leerNumero(m, 'envio'),
      comentarios: leerTexto(m, 'comentarios'),
      fechaIngreso: _fechaObligatoria(m, 'fechaIngreso', aFecha),
      fechaEstimada: _fechaObligatoria(m, 'fechaEstimada', aFecha),
      fechaTerminado: aFecha(m['fechaTerminado']),
      fechaEntregado: aFecha(m['fechaEntregado']),
      estado: EstadoMueble.desdeTexto(leerTexto(m, 'estado')),
      creadoPor: leerTexto(m, 'creadoPor'),
    );
  }
}

class Mueble {
  final String id;
  final String pedidoId;
  final TipoTrabajo tipoTrabajo;
  final String tipoMueble;
  final String? plantillaId;
  final double precio;
  final String comentarios;
  final EstadoMueble estado;

  const Mueble({
    required this.id,
    required this.pedidoId,
    required this.tipoTrabajo,
    required this.tipoMueble,
    required this.plantillaId,
    required this.precio,
    required this.comentarios,
    required this.estado,
  });

  factory Mueble.desdeMapa(
      String id, String pedidoId, Map<String, dynamic> mapa) {
    return Mueble(
      id: id,
      pedidoId: pedidoId,
      tipoTrabajo: TipoTrabajo.desdeTexto(leerTexto(mapa, 'tipoTrabajo')),
      tipoMueble: leerTexto(mapa, 'tipoMueble'),
      plantillaId: leerTextoOpcional(mapa, 'plantillaId'),
      precio: leerNumero(mapa, 'precio'),
      comentarios: leerTexto(mapa, 'comentarios'),
      estado: EstadoMueble.desdeTexto(leerTexto(mapa, 'estado')),
    );
  }
}

class LineaMaterial {
  final String id;
  final String materialId;
  final String? rolloId;
  final double cantidad;
  final bool delCliente;
  final String usuarioId;
  final DateTime fecha;

  const LineaMaterial({
    required this.id,
    required this.materialId,
    required this.rolloId,
    required this.cantidad,
    required this.delCliente,
    required this.usuarioId,
    required this.fecha,
  });

  factory LineaMaterial.desdeMapa(
      String id, Map<String, dynamic> m, DateTime? Function(Object?) aFecha) {
    return LineaMaterial(
      id: id,
      materialId: leerTexto(m, 'materialId'),
      rolloId: leerTextoOpcional(m, 'rolloId'),
      cantidad: leerNumero(m, 'cantidad'),
      delCliente: leerBooleano(m, 'delCliente'),
      usuarioId: leerTexto(m, 'usuarioId'),
      fecha: _fechaObligatoria(m, 'fecha', aFecha),
    );
  }
}

class DiaTrabajado {
  final String id;
  final String usuarioId;
  final double dias;
  final DateTime fecha;

  const DiaTrabajado({
    required this.id,
    required this.usuarioId,
    required this.dias,
    required this.fecha,
  });

  factory DiaTrabajado.desdeMapa(
      String id, Map<String, dynamic> m, DateTime? Function(Object?) aFecha) {
    return DiaTrabajado(
      id: id,
      usuarioId: leerTexto(m, 'usuarioId'),
      dias: leerNumero(m, 'dias'),
      fecha: _fechaObligatoria(m, 'fecha', aFecha),
    );
  }
}

enum CampoPrecio {
  precio,
  envio;

  static CampoPrecio desdeTexto(String texto) {
    for (final c in values) {
      if (c.name == texto) return c;
    }
    throw FormatException('Campo de precio desconocido: $texto');
  }
}

class CambioPrecio {
  final String id;
  final CampoPrecio campo;
  final String? muebleId;
  final double anterior;
  final double nuevo;
  final String? motivo;
  final String usuarioId;
  final DateTime fecha;

  const CambioPrecio({
    required this.id,
    required this.campo,
    required this.muebleId,
    required this.anterior,
    required this.nuevo,
    required this.motivo,
    required this.usuarioId,
    required this.fecha,
  });

  bool get esBajada => nuevo < anterior;

  factory CambioPrecio.desdeMapa(
      String id, Map<String, dynamic> m, DateTime? Function(Object?) aFecha) {
    return CambioPrecio(
      id: id,
      campo: CampoPrecio.desdeTexto(leerTexto(m, 'campo')),
      muebleId: leerTextoOpcional(m, 'muebleId'),
      anterior: leerNumero(m, 'anterior'),
      nuevo: leerNumero(m, 'nuevo'),
      motivo: leerTextoOpcional(m, 'motivo'),
      usuarioId: leerTexto(m, 'usuarioId'),
      fecha: _fechaObligatoria(m, 'fecha', aFecha),
    );
  }
}

class LineaPlantilla {
  final String materialId;
  final double cantidad;

  const LineaPlantilla({required this.materialId, required this.cantidad});

  factory LineaPlantilla.desdeMapa(Map<String, dynamic> m) => LineaPlantilla(
        materialId: leerTexto(m, 'materialId'),
        cantidad: leerNumero(m, 'cantidad'),
      );

  Map<String, dynamic> aMapa() =>
      {'materialId': materialId, 'cantidad': cantidad};
}

class Plantilla {
  final String id;
  final String tipoMueble;
  final List<LineaPlantilla> lineas;

  const Plantilla({
    required this.id,
    required this.tipoMueble,
    required this.lineas,
  });

  factory Plantilla.desdeMapa(String id, Map<String, dynamic> mapa) {
    final crudas = mapa['lineas'];
    if (crudas is! List) {
      throw FormatException('Campo "lineas" ausente o no es lista: $crudas');
    }
    return Plantilla(
      id: id,
      tipoMueble: leerTexto(mapa, 'tipoMueble'),
      lineas: [
        for (final l in crudas)
          if (l is Map<String, dynamic>)
            LineaPlantilla.desdeMapa(l)
          else
            throw FormatException('Línea de plantilla inválida: $l'),
      ],
    );
  }

  Map<String, dynamic> aMapa() => {
        'tipoMueble': tipoMueble,
        'lineas': [for (final l in lineas) l.aMapa()],
      };
}

/// Menor avance entre los muebles no cancelados. Todos cancelados →
/// cancelado; sin muebles → recibido.
EstadoMueble estadoPedido(Iterable<EstadoMueble> estados) {
  final lista = estados.toList();
  if (lista.isEmpty) return EstadoMueble.recibido;
  final vivos = lista.where((e) => e != EstadoMueble.cancelado);
  if (vivos.isEmpty) return EstadoMueble.cancelado;
  return vivos.reduce((a, b) => a.index <= b.index ? a : b);
}

/// [precios] son los de los muebles no cancelados.
double totalPedido(Iterable<double> precios, double envio) =>
    redondear2(precios.fold<double>(0, (s, p) => s + p) + envio);

String folioPara(DateTime fechaIngreso, String pedidoId) {
  String dos(int n) => n.toString().padLeft(2, '0');
  final prefijo = pedidoId.length < 4 ? pedidoId : pedidoId.substring(0, 4);
  return '${dos(fechaIngreso.year % 100)}${dos(fechaIngreso.month)}'
      '${dos(fechaIngreso.day)}-${prefijo.toUpperCase()}';
}

String _normalizar(String texto) {
  const origen = 'áéíóúü';
  const destino = 'aeiouu';
  final sb = StringBuffer();
  for (final c in texto.toLowerCase().split('')) {
    final i = origen.indexOf(c);
    sb.write(i >= 0 ? destino[i] : c);
  }
  return sb.toString();
}

bool coincideCliente(Cliente c, String consulta) {
  final q = _normalizar(consulta.trim());
  if (q.isEmpty) return true;
  if (_normalizar(c.nombre).contains(q)) return true;
  final digitosQ = q.replaceAll(RegExp(r'\D'), '');
  if (digitosQ.length >= 3) {
    return c.telefono.replaceAll(RegExp(r'\D'), '').contains(digitosQ);
  }
  return false;
}

/// Días trabajados: múltiplos de 0.5 en (0, 7]. `null` si no es válido.
double? leerDias(String texto) {
  final v = leerCantidad(texto);
  if (v == null || v <= 0 || v > 7) return null;
  if (v * 2 != (v * 2).roundToDouble()) return null;
  return v;
}
