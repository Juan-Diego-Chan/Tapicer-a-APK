import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/inventario.dart';
import '../../dominio/usuario.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';
import 'dialogo_material.dart';
import 'providers.dart';

bool esDueno(WidgetRef ref) =>
    switch (ref.watch(estadoSesionProvider).value) {
      SesionActiva(:final usuario) => usuario.rol == Rol.dueno,
      _ => false,
    };

class PantallaInventario extends ConsumerWidget {
  const PantallaInventario({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materiales = ref.watch(materialesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      floatingActionButton: esDueno(ref)
          ? FloatingActionButton.extended(
              onPressed: () => mostrarDialogoMaterial(context),
              icon: const Icon(Icons.add),
              label: const Text('Agregar material'),
            )
          : null,
      body: materiales.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('No se pudo cargar el inventario')),
        data: (lista) {
          if (lista.isEmpty) {
            return const Center(child: Text('Sin materiales'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final c in Categoria.values)
                ..._grupo(context, c, lista.where((m) => m.categoria == c)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _grupo(
      BuildContext context, Categoria c, Iterable<Material> items) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(c.etiqueta, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final m in items) _FilaMaterial(material: m),
    ];
  }
}

class _FilaMaterial extends StatelessWidget {
  final Material material;
  const _FilaMaterial({required this.material});

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      title: Text(material.nombre),
      leading: material.necesitaCompra
          ? Icon(Icons.warning_amber, color: error)
          : null,
      trailing: Text(
        formatearCantidad(material.existencia, material.unidad),
        style: material.existencia < 0 ? TextStyle(color: error) : null,
      ),
      onTap: () => context.push('/inventario/${material.id}'),
    );
  }
}
