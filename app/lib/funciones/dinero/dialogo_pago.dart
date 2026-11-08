import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/dinero.dart';
import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../pedidos/dialogos_pedido.dart' show guardarSinEsperar;
import 'providers.dart';

Future<void> mostrarDialogoPago(
  BuildContext context, {
  required Pedido pedido,
  required double saldo,
  required bool devolucion,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoPago(
      pedido: pedido,
      saldo: saldo,
      devolucion: devolucion,
    ),
  );
}

class _DialogoPago extends ConsumerStatefulWidget {
  const _DialogoPago({
    required this.pedido,
    required this.saldo,
    required this.devolucion,
  });

  final Pedido pedido;
  final double saldo;
  final bool devolucion;

  @override
  ConsumerState<_DialogoPago> createState() => _DialogoPagoState();
}

class _DialogoPagoState extends ConsumerState<_DialogoPago> {
  final _monto = TextEditingController();
  FormaPago _forma = FormaPago.efectivo;
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  void _guardar() {
    final n = leerDinero(_monto.text);
    if (n == null) {
      setState(() => _error = 'Escribe un monto válido');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final servicio = ref.read(servicioDineroProvider);
    try {
      // El servicio valida de forma síncrona: si lanza, no hay Future.
      final futuro = widget.devolucion
          ? servicio.registrarDevolucion(
              pedido: widget.pedido, monto: n, forma: _forma)
          : servicio.registrarPago(
              pedido: widget.pedido,
              saldo: widget.saldo,
              monto: n,
              forma: _forma);
      guardarSinEsperar(messenger, futuro);
      Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      setState(() => _error = e.message?.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.devolucion ? 'Devolución' : 'Registrar pago'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _monto,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                InputDecoration(labelText: 'Monto', errorText: _error),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 16),
          SegmentedButton<FormaPago>(
            segments: [
              for (final f in FormaPago.values)
                ButtonSegment(value: f, label: Text(f.etiqueta)),
            ],
            selected: {_forma},
            onSelectionChanged: (s) => setState(() => _forma = s.first),
          ),
        ]),
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
