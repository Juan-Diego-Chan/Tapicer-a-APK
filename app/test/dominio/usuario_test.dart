import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/usuario.dart';

void main() {
  test('desdeMapa lee el rol', () {
    final u = Usuario.desdeMapa('u1', {
      'nombre': 'Ana',
      'email': 'a@x.mx',
      'rol': 'empleado',
      'activo': true,
    });
    expect(u.rol, Rol.empleado);
    expect(u.uid, 'u1');
  });

  test('rol desconocido lanza FormatException', () {
    expect(
      () => Usuario.desdeMapa('u1', {
        'nombre': 'Ana',
        'email': 'a@x.mx',
        'rol': 'jefe',
        'activo': true,
      }),
      throwsFormatException,
    );
  });

  test('aMapa ida y vuelta conserva los campos', () {
    final u = Usuario(
      uid: 'u2',
      nombre: 'Luis',
      email: 'l@x.mx',
      rol: Rol.dueno,
      activo: false,
    );
    final v = Usuario.desdeMapa('u2', u.aMapa());
    expect(v.nombre, 'Luis');
    expect(v.email, 'l@x.mx');
    expect(v.rol, Rol.dueno);
    expect(v.activo, false);
  });

  test('activo ausente lanza FormatException', () {
    expect(
      () => Usuario.desdeMapa(
          'u1', {'nombre': 'Ana', 'email': 'a@x.mx', 'rol': 'empleado'}),
      throwsFormatException,
    );
  });

  test('nombre que no es texto lanza FormatException', () {
    expect(
      () => Usuario.desdeMapa('u1', {
        'nombre': 5,
        'email': 'a@x.mx',
        'rol': 'empleado',
        'activo': true,
      }),
      throwsFormatException,
    );
  });
}
