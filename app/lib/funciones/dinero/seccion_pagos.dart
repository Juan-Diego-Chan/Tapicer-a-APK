import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/dinero.dart';
import '../../dominio/pedidos.dart';
import '../../nucleo/formatos.dart';
import '../inventario/pantalla_inventario.dart' show esDueno;
import '../pedidos/dialogos_pedido.dart' show guardarSinEsperar;
import '../usuarios/providers.dart';
import 'dialogo_pago.dart';
import 'providers.dart';

String _montoConSigno(double monto) =>
    monto < 0 ? '-${formatearDinero(-monto)}' : formatearDinero(monto);

class SeccionPagos extends ConsumerWidget {
  const SeccionPagos({super.key, required this.pedido, required this.total});

  final Pedido pedido;
  final double total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final dueno = esDueno(ref);
    final pagado = pedido.pagado;
    final saldo = saldoPedido(total, pagado);
    final cancelado = pedido.estado == EstadoMueble.cancelado;
    final resumen = cancelado && pagado > 0
        ? 'Anticipo retenido: ${formatearDinero(pagado)}'
        : saldo > 0
            ? 'Saldo: ${formatearDinero(saldo)}'
            : saldo == 0
                ? 'Pagado por completo'
                : 'Pagado de más: ${formatearDinero(-saldo)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text('Pagos', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Total: ${formatearDinero(total)}',
            style: tema.textTheme.titleLarge),
        Text('Pagado: ${formatearDinero(pagado)}'),
        Text(resumen),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!cancelado && saldo > 0)
            FilledButton.icon(
              onPressed: () => mostrarDialogoPago(context,
                  pedido: pedido, saldo: saldo, devolucion: false),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Registrar pago'),
            ),
          if (dueno && pagado > 0)
            OutlinedButton.icon(
              onPressed: () => mostrarDialogoPago(context,
                  pedido: pedido, saldo: saldo, devolucion: true),
              icon: const Icon(Icons.undo),
              label: const Text('Devolución'),
            ),
        ]),
        // Solo el dueño puede leer todos los pagos y las cajas.
        if (dueno)
          _PagosDueno(pedidoId: pedido.id)
        else
          _MisPagos(pedidoId: pedido.id),
      ],
    );
  }
}

class _FilaPago extends StatelessWidget {
  const _FilaPago({required this.pago, required this.subtitulo, this.alBorrar});

  final Pago pago;
  final String subtitulo;
  final VoidCallback? alBorrar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${_montoConSigno(pago.monto)} · ${pago.forma.etiqueta}',
        style: pago.esDevolucion ? TextStyle(color: cs.error) : null,
      ),
      subtitle: Text(subtitulo),
      trailing: alBorrar == null
          ? null
          : IconButton(
              tooltip: 'Borrar pago',
              icon: const Icon(Icons.delete_outline),
              onPressed: alBorrar,
            ),
    );
  }
}

class _MisPagos extends ConsumerWidget {
  const _MisPagos({required this.pedidoId});

  final String pedidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagos = ref.watch(misPagosPedidoProvider(pedidoId)).value ?? const [];
    return Column(children: [
      for (final p in pagos)
        _FilaPago(
            pago: p, subtitulo: 'Tus cobros · ${formatearFecha(p.fecha)}'),
    ]);
  }
}

class _PagosDueno extends ConsumerWidget {
  const _PagosDueno({required this.pedidoId});

  final String pedidoId;

  Future<void> _borrar(BuildContext context, WidgetRef ref, Pago pago,
      bool cobroDeEmpleado) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          '¿Borrar el pago de ${formatearDinero(pago.monto)}? '
          'Esto cambia el saldo del pedido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, borrar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      guardarSinEsperar(
        messenger,
        ref
            .read(servicioDineroProvider)
            .borrarPago(pago: pago, cobroDeEmpleado: cobroDeEmpleado),
      );
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagos = ref.watch(pagosPedidoProvider(pedidoId)).value ?? const [];
    final cajas = ref.watch(cajasProvider).value ?? const <String, double>{};
    final usuarios = ref.watch(usuariosProvider).value ?? const [];

    String quien(String uid) {
      for (final u in usuarios) {
        if (u.uid == uid) return u.nombre;
      }
      return 'Usuario desconocido';
    }

    return Column(children: [
      for (final p in pagos)
        _FilaPago(
          pago: p,
          subtitulo: '${quien(p.recibidoPor)} · ${formatearFecha(p.fecha)}',
          // Las reglas dependen de si esa caja existe, no del rol.
          alBorrar: () =>
              _borrar(context, ref, p, cajas.containsKey(p.recibidoPor)),
        ),
    ]);
  }
}
