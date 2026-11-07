import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/pedidos.dart';
import '../../dominio/usuario.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';
import '../usuarios/providers.dart';
import 'dialogos_pedido.dart' show guardarSinEsperar;
import 'providers.dart';

Future<void> mostrarDialogoDias(
  BuildContext context, {
  required String pedidoId,
  required String muebleId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoDias(pedidoId: pedidoId, muebleId: muebleId),
  );
}

class _DialogoDias extends ConsumerStatefulWidget {
  const _DialogoDias({required this.pedidoId, required this.muebleId});

  final String pedidoId;
  final String muebleId;

  @override
  ConsumerState<_DialogoDias> createState() => _DialogoDiasState();
}

class _DialogoDiasState extends ConsumerState<_DialogoDias> {
  final _formKey = GlobalKey<FormState>();
  final _dias = TextEditingController();
  String? _trabajador;

  @override
  void dispose() {
    _dias.dispose();
    super.dispose();
  }

  Usuario get _yo =>
      (ref.read(estadoSesionProvider).value as SesionActiva).usuario;

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final yo = _yo;
    final messenger = ScaffoldMessenger.of(context);
    guardarSinEsperar(
      messenger,
      ref
          .read(servicioTrabajoProvider)
          .registrarDias(
            pedidoId: widget.pedidoId,
            muebleId: widget.muebleId,
            // El empleado solo registra sus propios días.
            usuarioId: yo.rol == Rol.dueno ? (_trabajador ?? yo.uid) : yo.uid,
            dias: leerDias(_dias.text)!,
          ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final yo = _yo;
    // Solo el dueño se suscribe a la lista de usuarios.
    final activos = yo.rol == Rol.dueno
        ? (ref.watch(usuariosProvider).value ?? const <Usuario>[])
              .where((u) => u.activo)
              .toList()
        : const <Usuario>[];
    return AlertDialog(
      title: const Text('Registrar días'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (yo.rol == Rol.dueno)
                DropdownButtonFormField<String>(
                  key: const Key('trabajador'),
                  initialValue: _trabajador ?? yo.uid,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Trabajador'),
                  items: [
                    for (final u in activos)
                      DropdownMenuItem(value: u.uid, child: Text(u.nombre)),
                  ],
                  onChanged: (v) => setState(() => _trabajador = v),
                ),
              TextFormField(
                controller: _dias,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Días (0.5 = medio día)',
                ),
                validator: (v) => leerDias(v ?? '') == null
                    ? 'Escribe días en múltiplos de 0.5, hasta 7'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
