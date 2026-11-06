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
    final rol = Rol.values.where((r) => r.name == mapa['rol']);
    if (rol.isEmpty) {
      throw FormatException('Rol desconocido: ${mapa['rol']}');
    }
    return Usuario(
      uid: uid,
      nombre: mapa['nombre'] as String,
      email: mapa['email'] as String,
      rol: rol.first,
      activo: mapa['activo'] as bool,
    );
  }

  Map<String, dynamic> aMapa() => {
        'nombre': nombre,
        'email': email,
        'rol': rol.name,
        'activo': activo,
      };
}
