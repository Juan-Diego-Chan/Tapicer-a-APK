import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pedidos/providers.dart';
import 'dialogo_plantilla.dart';

class PantallaPlantillas extends ConsumerWidget {
  const PantallaPlantillas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plantillas = ref.watch(plantillasProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Plantillas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => mostrarDialogoPlantilla(context),
        icon: const Icon(Icons.add),
        label: const Text('Nueva plantilla'),
      ),
      body: plantillas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('No se pudieron cargar las plantillas')),
        data: (lista) {
          if (lista.isEmpty) {
            return const Center(child: Text('Aún no hay plantillas'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final p in lista)
                ListTile(
                  title: Text(p.tipoMueble),
                  subtitle: Text('${p.lineas.length} materiales'),
                  onTap: () => mostrarDialogoPlantilla(context, existente: p),
                ),
            ],
          );
        },
      ),
    );
  }
}
