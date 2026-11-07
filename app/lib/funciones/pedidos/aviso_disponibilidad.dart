import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/costos_pedido.dart';
import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../../nucleo/formatos.dart';
import '../inventario/providers.dart';

/// Lista lo que la plantilla pide y no alcanza en existencia. Avisa, no
/// bloquea: la compra puede llegar antes de que se use el material.
class AvisoDisponibilidad extends ConsumerWidget {
  const AvisoDisponibilidad({
    super.key,
    required this.plantilla,
    this.usado = const {},
  });

  final Plantilla plantilla;
  final Map<String, double> usado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materiales = ref.watch(materialesProvider).value ?? const [];
    final porId = {for (final m in materiales) m.id: m};
    final faltan = faltantes(
      plantilla,
      existencias: {for (final m in materiales) m.id: m.existencia},
      usado: usado,
    );
    if (faltan.isEmpty) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in faltan)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No alcanza: ${porId[f.materialId]?.nombre ?? 'Material desconocido'}'
              ' (necesita ${_cantidad(f.necesita, porId[f.materialId])},'
              ' hay ${_cantidad(f.hay, porId[f.materialId])})',
              style: TextStyle(color: color),
            ),
          ),
      ],
    );
  }
}

String _cantidad(double c, Material? m) =>
    formatearCantidad(c, m?.unidad ?? Unidad.pza);

/// Solo se construye para el dueño: consulta el costo promedio, que el
/// empleado no puede leer.
class EstimadoPlantilla extends ConsumerWidget {
  const EstimadoPlantilla({super.key, required this.plantilla});

  final Plantilla plantilla;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costos = <String, double?>{
      for (final l in plantilla.lineas)
        l.materialId: ref.watch(costoPromedioProvider(l.materialId)).value,
    };
    final costo = costoEstimado(plantilla, costoMaterial: (id) => costos[id]);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('Costo estimado: ${formatearDinero(costo.monto)}'
          '${costo.incompleto ? ' (incompleto)' : ''}'),
    );
  }
}
