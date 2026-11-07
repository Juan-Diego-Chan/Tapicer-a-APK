import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/pedidos.dart';
import '../../nucleo/formatos.dart';
import '../pedidos/providers.dart';

/// Muebles activos de un tipo de trabajo (Fabricación o Reparación),
/// ordenados por la fecha estimada de entrega de su pedido.
class PantallaTrabajo extends ConsumerWidget {
  const PantallaTrabajo({super.key, required this.tipo});

  final TipoTrabajo tipo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muebles = ref.watch(mueblesActivosProvider(tipo));
    final pedidos = ref.watch(pedidosActivosProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tipo.etiqueta)),
      body: muebles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('No se pudieron cargar los muebles')),
        data: (lista) {
          if (lista.isEmpty) {
            return Center(child: Text('No hay muebles en ${tipo.etiqueta}'));
          }
          final porId = {
            for (final p in pedidos.value ?? const <Pedido>[]) p.id: p
          };
          // Los muebles cuyo pedido no está cargado van al final.
          final filas = [...lista]..sort((a, b) {
              final pa = porId[a.pedidoId];
              final pb = porId[b.pedidoId];
              if (pa == null || pb == null) {
                if (pa == null && pb == null) return 0;
                return pa == null ? 1 : -1;
              }
              return pa.fechaEstimada.compareTo(pb.fechaEstimada);
            });
          return ListView.builder(
            itemCount: filas.length,
            itemBuilder: (context, i) {
              final m = filas[i];
              final p = porId[m.pedidoId];
              return ListTile(
                title: Text(m.tipoMueble),
                subtitle: p == null
                    ? const Text('Pedido sin cargar')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.cliente.nombre),
                          Text(p.folio),
                          Text('Entrega: ${formatearFecha(p.fechaEstimada)}'),
                        ],
                      ),
                trailing: Text(m.estado.etiqueta),
                onTap: () =>
                    context.push('/pedidos/${m.pedidoId}/muebles/${m.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
