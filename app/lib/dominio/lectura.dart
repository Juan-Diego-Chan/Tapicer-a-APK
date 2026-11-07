/// Lectores de campos de mapas de Firestore. Lanzan [FormatException] si el
/// campo falta o tiene un tipo incorrecto.
String leerTexto(Map<String, dynamic> mapa, String campo) {
  final v = mapa[campo];
  if (v is! String) {
    throw FormatException('Campo "$campo" ausente o no es texto: $v');
  }
  return v;
}

/// `null` si el campo falta o es null.
String? leerTextoOpcional(Map<String, dynamic> mapa, String campo) {
  final v = mapa[campo];
  if (v == null) return null;
  if (v is! String) {
    throw FormatException('Campo "$campo" no es texto: $v');
  }
  return v;
}

double leerNumero(Map<String, dynamic> mapa, String campo) {
  final v = mapa[campo];
  if (v is! num || !v.isFinite) {
    throw FormatException('Campo "$campo" ausente o no es número finito: $v');
  }
  return v.toDouble();
}

bool leerBooleano(Map<String, dynamic> mapa, String campo) {
  final v = mapa[campo];
  if (v is! bool) {
    throw FormatException('Campo "$campo" ausente o no es booleano: $v');
  }
  return v;
}
