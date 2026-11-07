import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/pedidos.dart';
import '../../nucleo/formatos.dart';
import '../inventario/pantalla_inventario.dart' show esDueno;
import '../usuarios/providers.dart';
import 'dialogo_mueble.dart';
import 'dialogos_pedido.dart';
import 'providers.dart';

class PantallaPedido extends ConsumerWidget {
  const PantallaPedido({super.key, required this.pedidoId});

  final String pedidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedido = ref.watch(pedidoProvider(pedidoId));
    final muebles = ref.watch(mueblesProvider(pedidoId));
    return Scaffold(
      appBar: AppBar(title: Text(pedido.value?.folio ?? 'Pedido')),
      body: switch ((pedido, muebles)) {
        (AsyncError(), _) || (_, AsyncError()) => const Center(
          child: Text('No se pudo cargar el pedido'),
        ),
        (AsyncData(value: null), _) => const Center(
          child: Text('El pedido no existe'),
        ),
        (AsyncData(value: final p?), AsyncData(value: final m)) => _Detalle(
          pedido: p,
          muebles: m,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Detalle extends ConsumerWidget {
  const _Detalle({required this.pedido, required this.muebles});

  final Pedido pedido;
  final List<Mueble> muebles;

  Future<void> _agregarMueble(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final nuevo = await mostrarDialogoMueble(context);
    if (nuevo == null) return;
    guardarSinEsperar(
      messenger,
      ref
          .read(servicioPedidosProvider)
          .agregarMueble(pedido: pedido, muebles: muebles, nuevo: nuevo),
    );
  }

  Future<void> _cancelar(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          '¿Cancelar el pedido ${pedido.folio}? '
          'Los muebles no entregados quedarán cancelados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    guardarSinEsperar(
      messenger,
      ref
          .read(servicioPedidosProvider)
          .cancelarPedido(pedido: pedido, muebles: muebles),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final c = pedido.cliente;
    final total = totalPedido([
      for (final m in muebles)
        if (m.estado != EstadoMueble.cancelado) m.precio,
    ], pedido.envio);
    final puedeCancelar =
        pedido.estado != EstadoMueble.cancelado &&
        pedido.estado != EstadoMueble.entregado;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(pedido.folio, style: tema.textTheme.titleLarge),
            ),
            Chip(label: Text(pedido.estado.etiqueta)),
          ],
        ),
        const SizedBox(height: 8),
        Text(c.nombre, style: tema.textTheme.titleMedium),
        if (c.telefono.isNotEmpty) Text('Teléfono: ${c.telefono}'),
        if (c.direccion.isNotEmpty) Text('Dirección: ${c.direccion}'),
        const SizedBox(height: 8),
        Text(
          'Entrega: ${pedido.entrega.etiqueta}'
          '${pedido.entrega == Entrega.domicilio ? ' (envío ${formatearDinero(pedido.envio)})' : ''}',
        ),
        Text('Ingreso: ${formatearFecha(pedido.fechaIngreso)}'),
        Text('Fecha estimada: ${formatearFecha(pedido.fechaEstimada)}'),
        if (pedido.fechaTerminado != null)
          Text('Terminado: ${formatearFecha(pedido.fechaTerminado!)}'),
        if (pedido.fechaEntregado != null)
          Text('Entregado: ${formatearFecha(pedido.fechaEntregado!)}'),
        if (pedido.comentarios.isNotEmpty)
          Text('Comentarios: ${pedido.comentarios}'),
        const Divider(height: 32),
        Text('Muebles', style: tema.textTheme.titleMedium),
        if (muebles.isEmpty) const Text('Sin muebles'),
        for (final m in muebles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(m.tipoMueble),
            subtitle: Text(
              '${m.tipoTrabajo.etiqueta} · ${m.estado.etiqueta} · ${formatearDinero(m.precio)}',
            ),
            trailing: m.estado == EstadoMueble.cancelado
                ? null
                : IconButton(
                    tooltip: 'Cambiar precio',
                    icon: const Icon(Icons.attach_money),
                    onPressed: () => mostrarDialogoPrecio(
                      context,
                      pedidoId: pedido.id,
                      mueble: m,
                    ),
                  ),
            onTap: () => context.push('/pedidos/${pedido.id}/muebles/${m.id}'),
          ),
        const SizedBox(height: 8),
        Text(
          'Total: ${formatearDinero(total)}',
          style: tema.textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _agregarMueble(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Agregar mueble'),
            ),
            OutlinedButton.icon(
              onPressed: () => mostrarDialogoEnvio(context, pedido: pedido),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Cambiar envío'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  mostrarDialogoEditarPedido(context, pedido: pedido),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
            if (puedeCancelar)
              OutlinedButton.icon(
                onPressed: () => _cancelar(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tema.colorScheme.error,
                ),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar pedido'),
              ),
          ],
        ),
        // Solo se construye para el dueño: el empleado no puede leer el
        // historial y ni siquiera debe suscribirse a él.
        if (esDueno(ref))
          _HistorialPrecios(pedidoId: pedido.id, muebles: muebles),
      ],
    );
  }
}

class _HistorialPrecios extends ConsumerWidget {
  const _HistorialPrecios({required this.pedidoId, required this.muebles});

  final String pedidoId;
  final List<Mueble> muebles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final cambios = ref.watch(cambiosPrecioProvider(pedidoId));
    final usuarios = ref.watch(usuariosProvider).value ?? const [];

    String quien(String uid) {
      for (final u in usuarios) {
        if (u.uid == uid) return u.nombre;
      }
      return 'Usuario desconocido';
    }

    String concepto(CambioPrecio c) {
      if (c.campo == CampoPrecio.envio) return 'Envío';
      for (final m in muebles) {
        if (m.id == c.muebleId) return 'Precio de ${m.tipoMueble}';
      }
      return 'Precio de mueble';
    }

    final contenido = cambios.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Text('No se pudo cargar el historial'),
      data: (lista) {
        if (lista.isEmpty) return const Text('Sin cambios de precio');
        return Column(
          children: [
            for (final c in lista)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${concepto(c)}: ${formatearDinero(c.anterior)} → ${formatearDinero(c.nuevo)}',
                  style: c.esBajada
                      ? TextStyle(color: tema.colorScheme.error)
                      : null,
                ),
                subtitle: Text(
                  '${quien(c.usuarioId)} · ${formatearFecha(c.fecha)}'
                  '${c.motivo == null ? '' : '\n${c.motivo}'}',
                ),
              ),
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text('Historial de precios', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        contenido,
      ],
    );
  }
}
