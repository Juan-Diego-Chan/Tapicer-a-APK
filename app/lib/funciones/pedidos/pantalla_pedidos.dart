import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../nucleo/formatos.dart';
import 'providers.dart';

class PantallaPedidos extends StatelessWidget {
  const PantallaPedidos({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pedidos'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Activos'),
            Tab(text: 'Recientes'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/pedidos/nuevo'),
          icon: const Icon(Icons.add),
          label: const Text('Nuevo pedido'),
        ),
        body: const TabBarView(children: [
          _ListaPedidos(activos: true),
          _ListaPedidos(activos: false),
        ]),
      ),
    );
  }
}

class _ListaPedidos extends ConsumerWidget {
  const _ListaPedidos({required this.activos});

  final bool activos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(
        activos ? pedidosActivosProvider : pedidosRecientesProvider);
    return pedidos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          const Center(child: Text('No se pudieron cargar los pedidos')),
      data: (lista) {
        if (lista.isEmpty) {
          return Center(
              child:
                  Text(activos ? 'No hay pedidos activos' : 'No hay pedidos'));
        }
        final h = DateTime.now();
        final hoy = DateTime(h.year, h.month, h.day);
        return ListView.builder(
          // Deja espacio para que el botón flotante no tape la última fila.
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: lista.length,
          itemBuilder: (context, i) {
            final p = lista[i];
            final vencido = activos && p.fechaEstimada.isBefore(hoy);
            return ListTile(
              title: Text(p.folio),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.cliente.nombre),
                  Text(
                    'Entrega: ${formatearFecha(p.fechaEstimada)}',
                    style: vencido
                        ? TextStyle(
                            color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                ],
              ),
              trailing: Text(p.estado.etiqueta),
              onTap: () => context.push('/pedidos/${p.id}'),
            );
          },
        );
      },
    );
  }
}
