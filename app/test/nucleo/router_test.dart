import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/nucleo/router.dart';

SesionActiva _sesion(Rol rol) => SesionActiva(
  Usuario(uid: 'u1', nombre: 'Ana', email: 'a@b.c', rol: rol, activo: true),
);

void main() {
  test('sin sesión va a /entrar', () {
    expect(redirigir(const SinSesion(), '/'), '/entrar');
    expect(redirigir(const SinSesion(), '/entrar'), isNull);
  });
  test('cargando no redirige', () {
    expect(redirigir(const CargandoSesion(), '/'), isNull);
    expect(redirigir(const CargandoSesion(), '/usuarios'), isNull);
  });
  test('cuenta sin configurar o desactivada va a /cuenta', () {
    for (final e in [const CuentaSinConfigurar(), const CuentaDesactivada()]) {
      expect(redirigir(e, '/'), '/cuenta');
      expect(redirigir(e, '/usuarios'), '/cuenta');
      expect(redirigir(e, '/cuenta'), isNull);
    }
  });
  test('empleado no entra a rutas solo dueño', () {
    final emp = _sesion(Rol.empleado);
    for (final r in ['/usuarios', '/compras', '/contabilidad', '/plantillas']) {
      expect(redirigir(emp, r), '/');
    }
    expect(redirigir(emp, '/usuarios/x'), '/');
    expect(redirigir(emp, '/pedidos'), isNull);
    expect(redirigir(emp, '/pedidos/p1/muebles/m1'), isNull);
  });
  test('empleado entra a inventario y su detalle', () {
    final emp = _sesion(Rol.empleado);
    expect(redirigir(emp, '/inventario'), isNull);
    expect(redirigir(emp, '/inventario/abc'), isNull);
  });
  test('dueño entra a rutas solo dueño', () {
    final due = _sesion(Rol.dueno);
    for (final r in ['/usuarios', '/compras', '/contabilidad', '/plantillas']) {
      expect(redirigir(due, r), isNull);
    }
  });
  test('sesión activa en /entrar o /cuenta va a /', () {
    expect(redirigir(_sesion(Rol.dueno), '/entrar'), '/');
    expect(redirigir(_sesion(Rol.empleado), '/cuenta'), '/');
  });
}
