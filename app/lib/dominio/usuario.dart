enum Rol { dueno, empleado }

class Usuario {
  final String uid;
  final String nombre;
  final String email;
  final Rol rol;
  final bool activo;

  const Usuario({
    required this.uid,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.activo,
  });

  factory Usuario.desdeMapa(String uid, Map<String, dynamic> mapa) {
    String texto(String campo) {
      final v = mapa[campo];
      if (v is! String) {
        throw FormatException('Campo "$campo" ausente o no es texto: $v');
      }
      return v;
    }

    final activo = mapa['activo'];
    if (activo is! bool) {
      throw FormatException('Campo "activo" ausente o no es booleano: $activo');
    }
    final nombreRol = texto('rol');
    final rol = Rol.values.where((r) => r.name == nombreRol);
    if (rol.isEmpty) {
      throw FormatException('Rol desconocido: $nombreRol');
    }
    return Usuario(
      uid: uid,
      nombre: texto('nombre'),
      email: texto('email'),
      rol: rol.first,
      activo: activo,
    );
  }

  Map<String, dynamic> aMapa() => {
        'nombre': nombre,
        'email': email,
        'rol': rol.name,
        'activo': activo,
      };
}
