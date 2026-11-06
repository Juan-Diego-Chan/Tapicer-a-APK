import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/funciones/auth/pantalla_estado_cuenta.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';

class _Falso implements ServicioSesion {
  bool cerro = false;
  @override
  Future<void> cerrarSesion() async => cerro = true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<_Falso> _montar(WidgetTester t, EstadoSesion e) async {
  final s = _Falso();
  await t.pumpWidget(ProviderScope(
    overrides: [
      servicioSesionProvider.overrideWithValue(s),
      estadoSesionProvider.overrideWith((ref) => Stream.value(e)),
    ],
    child: const MaterialApp(home: PantallaEstadoCuenta()),
  ));
  await t.pump();
  return s;
}

void main() {
  testWidgets('sin configurar', (t) async {
    final s = await _montar(t, const CuentaSinConfigurar());
    expect(
        find.text(
            'Tu cuenta no está configurada. Pide al dueño que la active.'),
        findsOneWidget);
    await t.tap(find.text('Cerrar sesión'));
    expect(s.cerro, isTrue);
  });
  testWidgets('desactivada', (t) async {
    await _montar(t, const CuentaDesactivada());
    expect(find.text('Tu cuenta está desactivada'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });
}
