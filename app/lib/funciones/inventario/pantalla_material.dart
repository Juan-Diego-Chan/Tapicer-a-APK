import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import '../../nucleo/formatos.dart';
import 'dialogo_material.dart';
import 'dialogo_movimiento.dart';
import 'pantalla_inventario.dart' show esDueno;
import 'providers.dart';

String _etiquetaTipo(TipoMovimiento t) => switch (t) {
      TipoMovimiento.compra => 'Compra',
      TipoMovimiento.inicial => 'Inventario inicial',
      TipoMovimiento.consumo => 'Consumo',
      TipoMovimiento.ajuste => 'Ajuste',
    };

class PantallaMaterial extends ConsumerWidget {
  final String materialId;
  const PantallaMaterial({super.key, required this.materialId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final material = ref.watch(materialProvider(materialId));
    final dueno = esDueno(ref);
    return Scaffold(
      appBar: AppBar(title: Text(material.value?.nombre ?? 'Material')),
      body: material.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('No se pudo cargar')),
        data: (m) {
          if (m == null) {
            return const Center(child: Text('Material no encontrado'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(m.nombre, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(label: Text(m.categoria.etiqueta)),
              ),
              Text(
                'Existencia: ${formatearCantidad(m.existencia, m.unidad)}',
                style: m.existenciaNegativa
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
              Text(
                'Stock mínimo: ${formatearCantidad(m.stockMinimo, m.unidad)}',
              ),
              if (dueno) _SeccionDueno(material: m) else _AccionEmpleado(m),
              if (m.usaRollos) _Rollos(material: m, dueno: dueno),
              const SizedBox(height: 16),
              Text('Últimos movimientos',
                  style: Theme.of(context).textTheme.titleMedium),
              _Movimientos(material: m),
            ],
          );
        },
      ),
    );
  }
}

class _AccionEmpleado extends ConsumerWidget {
  final Material material;
  const _AccionEmpleado(this.material);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (material.marcadoAgotandose) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: FilledButton(
          onPressed: null,
          child: Text('Marcado como por acabarse'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FilledButton(
        onPressed: () {
          final mensajero = ScaffoldMessenger.of(context);
          ref
              .read(repositorioInventarioProvider)
              .marcarAgotandose(material.id)
              .catchError((_) {
            mensajero.showSnackBar(
              const SnackBar(content: Text('No se pudo guardar')),
            );
          });
        },
        child: const Text('Se está acabando'),
      ),
    );
  }
}

/// Solo se construye para el dueño: aquí viven las suscripciones a costos.
class _SeccionDueno extends ConsumerWidget {
  final Material material;
  const _SeccionDueno({required this.material});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costo = ref.watch(costoPromedioProvider(material.id)).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(costo == null
            ? 'Sin costo'
            : 'Costo promedio: ${formatearDinero(costo)} / ${material.unidad.clave}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () =>
                  mostrarDialogoMaterial(context, existente: material),
              child: const Text('Editar'),
            ),
            for (final (tipo, texto) in [
              (TipoCaptura.compra, 'Registrar compra'),
              (TipoCaptura.inicial, 'Inventario inicial'),
              (TipoCaptura.ajuste, 'Ajuste'),
            ])
              OutlinedButton(
                onPressed: () => mostrarDialogoMovimiento(
                  context,
                  material: material,
                  tipo: tipo,
                ),
                child: Text(texto),
              ),
          ],
        ),
      ],
    );
  }
}

class _Rollos extends ConsumerWidget {
  final Material material;
  final bool dueno;
  const _Rollos({required this.material, required this.dueno});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rollos = ref.watch(rollosProvider(material.id)).value ?? const [];
    if (rollos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Rollos', style: Theme.of(context).textTheme.titleMedium),
        for (final r in rollos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r.codigo),
            subtitle: Text(
              '${formatearCantidad(r.existencia, material.unidad)} / '
              '${formatearCantidad(r.cantidadInicial, material.unidad)}',
            ),
            trailing: dueno
                ? _CostoRollo(rollo: r, unidad: material.unidad)
                : null,
          ),
      ],
    );
  }
}

class _CostoRollo extends ConsumerWidget {
  final Rollo rollo;
  final Unidad unidad;
  const _CostoRollo({required this.rollo, required this.unidad});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costo = ref.watch(costoRolloProvider(rollo.id)).value;
    return Text(costo == null
        ? 'Sin costo'
        : '${formatearDinero(costo)} / ${unidad.clave}');
  }
}

class _Movimientos extends ConsumerWidget {
  final Material material;
  const _Movimientos({required this.material});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movs = ref.watch(movimientosProvider(material.id)).value ?? const [];
    if (movs.isEmpty) return const Text('Sin movimientos');
    return Column(
      children: [
        for (final mv in movs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_etiquetaTipo(mv.tipo)),
            subtitle: Text(formatearFecha(mv.fecha)),
            trailing: Text(
              '${mv.cantidad > 0 ? '+' : ''}'
              '${formatearCantidad(mv.cantidad, material.unidad)}',
            ),
          ),
      ],
    );
  }
}
