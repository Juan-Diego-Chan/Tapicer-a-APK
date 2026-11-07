import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import '../inventario/dialogo_movimiento.dart';
import '../inventario/providers.dart';

double _faltante(Material m) => m.stockMinimo - m.existencia;

/// Materiales por comprar: primero los marcados, luego mayor faltante, luego
/// nombre.
List<Material> ordenarParaCompra(Iterable<Material> materiales) {
  final lista = materiales.where((m) => m.necesitaCompra).toList();
  lista.sort((a, b) {
    if (a.marcadoAgotandose != b.marcadoAgotandose) {
      return a.marcadoAgotandose ? -1 : 1;
    }
    final c = _faltante(b).compareTo(_faltante(a));
    return c != 0 ? c : a.nombre.compareTo(b.nombre);
  });
  return lista;
}

class PantallaListaCompras extends ConsumerWidget {
  const PantallaListaCompras({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materiales = ref.watch(materialesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lista de compras')),
      body: materiales.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('No se pudo cargar la lista')),
        data: (todos) {
          final lista = ordenarParaCompra(todos);
          if (lista.isEmpty) {
            return const Center(child: Text('No hace falta comprar nada'));
          }
          return ListView(
            children: [for (final m in lista) _FilaCompra(material: m)],
          );
        },
      ),
    );
  }
}

class _FilaCompra extends StatelessWidget {
  final Material material;
  const _FilaCompra({required this.material});

  @override
  Widget build(BuildContext context) {
    final m = material;
    return ListTile(
      title: Text(m.nombre),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hay ${formatearCantidad(m.existencia, m.unidad)} · '
              'mínimo ${formatearCantidad(m.stockMinimo, m.unidad)}'),
          if (m.marcadoAgotandose) const Text('Marcado por un empleado'),
        ],
      ),
      trailing: TextButton(
        onPressed: () => mostrarDialogoMovimiento(context,
            material: m, tipo: TipoCaptura.compra),
        child: const Text('Registrar compra'),
      ),
    );
  }
}
