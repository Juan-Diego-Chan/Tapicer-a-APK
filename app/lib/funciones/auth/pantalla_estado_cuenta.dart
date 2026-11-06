import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'servicio_sesion.dart';

class PantallaEstadoCuenta extends ConsumerWidget {
  const PantallaEstadoCuenta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estadoSesionProvider).value;
    final mensaje = estado is CuentaDesactivada
        ? 'Tu cuenta está desactivada'
        : 'Tu cuenta no está configurada. Pide al dueño que la active.';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(mensaje, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => ref.read(servicioSesionProvider).cerrarSesion(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
