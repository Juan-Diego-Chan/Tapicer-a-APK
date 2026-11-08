import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../../nucleo/formatos.dart';
import '../inventario/pantalla_inventario.dart' show esDueno;
import '../inventario/providers.dart';
import '../usuarios/providers.dart';
import 'dialogo_dias.dart';
import 'dialogo_linea_material.dart';
import 'dialogos_pedido.dart';
import 'providers.dart';
import 'seccion_plantilla_costos.dart';

class PantallaMueble extends ConsumerWidget {
  const PantallaMueble({
    super.key,
    required this.pedidoId,
    required this.muebleId,
  });

  final String pedidoId;
  final String muebleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedido = ref.watch(pedidoProvider(pedidoId));
    final muebles = ref.watch(mueblesProvider(pedidoId));
    final mueble = ref.watch(
      muebleProvider((pedidoId: pedidoId, muebleId: muebleId)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(mueble.value?.tipoMueble ?? 'Mueble')),
      body: switch ((pedido, muebles, mueble)) {
        (AsyncError(), _, _) || (_, AsyncError(), _) || (_, _, AsyncError()) =>
          const Center(child: Text('No se pudo cargar el mueble')),
        (_, _, AsyncData(value: null)) => const Center(
          child: Text('El mueble no existe'),
        ),
        (
          AsyncData(value: final p?),
          AsyncData(value: final todos),
          AsyncData(value: final m?),
        ) =>
          _Detalle(pedido: p, muebles: todos, mueble: m),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Detalle extends ConsumerWidget {
  const _Detalle({
    required this.pedido,
    required this.muebles,
    required this.mueble,
  });

  final Pedido pedido;
  final List<Mueble> muebles;
  final Mueble mueble;

  Future<void> _cambiarEstado(
    BuildContext context,
    WidgetRef ref,
    EstadoMueble nuevo,
  ) async {
    if (nuevo == mueble.estado) return;
    final messenger = ScaffoldMessenger.of(context);
    if (nuevo == EstadoMueble.cancelado) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text('¿Cancelar ${mueble.tipoMueble}?'),
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
      if (ok != true) return;
    }
    guardarSinEsperar(
      messenger,
      ref
          .read(servicioPedidosProvider)
          .cambiarEstadoMueble(
            pedido: pedido,
            muebles: muebles,
            muebleId: mueble.id,
            nuevo: nuevo,
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(mueble.tipoMueble, style: tema.textTheme.titleLarge),
        Text('${mueble.tipoTrabajo.etiqueta} · Pedido ${pedido.folio}'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Precio: ${formatearDinero(mueble.precio)}',
                style: tema.textTheme.titleMedium,
              ),
            ),
            if (mueble.estado != EstadoMueble.cancelado)
              OutlinedButton(
                onPressed: () => mostrarDialogoPrecio(
                  context,
                  pedidoId: pedido.id,
                  mueble: mueble,
                ),
                child: const Text('Cambiar precio'),
              ),
          ],
        ),
        if (mueble.comentarios.isNotEmpty)
          Text('Comentarios: ${mueble.comentarios}'),
        const Divider(height: 32),
        Text('Estado', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in EstadoMueble.values)
              ChoiceChip(
                label: Text(e.etiqueta),
                selected: mueble.estado == e,
                onSelected: mueble.estado == EstadoMueble.cancelado
                    ? null
                    : (_) => _cambiarEstado(context, ref, e),
              ),
          ],
        ),
        if (mueble.estado == EstadoMueble.cancelado) ...[
          const SizedBox(height: 8),
          const Text('Un mueble cancelado no se puede reactivar'),
        ],
        const Divider(height: 32),
        _SeccionMateriales(pedidoId: pedido.id, muebleId: mueble.id),
        const Divider(height: 32),
        _SeccionDias(pedidoId: pedido.id, muebleId: mueble.id),
        _PlantillaYCostos(pedidoId: pedido.id, mueble: mueble),
      ],
    );
  }
}

Future<bool> _confirmar(BuildContext context, String texto) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(texto),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  return ok == true;
}

class _PlantillaYCostos extends ConsumerWidget {
  const _PlantillaYCostos({required this.pedidoId, required this.mueble});

  final String pedidoId;
  final Mueble mueble;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clave = (pedidoId: pedidoId, muebleId: mueble.id);
    final lineas = ref.watch(lineasProvider(clave)).value ?? const [];
    final dias = ref.watch(diasProvider(clave)).value ?? const [];
    return SeccionPlantillaYCostos(mueble: mueble, lineas: lineas, dias: dias);
  }
}

class _SeccionMateriales extends ConsumerWidget {
  const _SeccionMateriales({required this.pedidoId, required this.muebleId});

  final String pedidoId;
  final String muebleId;

  Future<void> _borrar(
    BuildContext context,
    WidgetRef ref,
    LineaMaterial linea,
    Material material,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirmar(
      context,
      '¿Borrar esta línea? La cantidad regresa al inventario.',
    );
    if (!ok) return;
    guardarSinEsperar(
      messenger,
      ref
          .read(servicioTrabajoProvider)
          .borrarLinea(
            pedidoId: pedidoId,
            muebleId: muebleId,
            linea: linea,
            material: material,
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final lineas = ref.watch(
      lineasProvider((pedidoId: pedidoId, muebleId: muebleId)),
    );
    final materiales = ref.watch(materialesProvider).value ?? const [];
    final dueno = esDueno(ref);

    Material? buscar(String id) {
      for (final m in materiales) {
        if (m.id == id) return m;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Materiales', style: tema.textTheme.titleMedium),
        lineas.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('No se pudieron cargar los materiales'),
          data: (lista) => Column(
            children: [
              if (lista.isEmpty) const Text('Sin materiales'),
              for (final l in lista)
                _FilaLinea(
                  linea: l,
                  material: buscar(l.materialId),
                  alBorrar: dueno && buscar(l.materialId) != null
                      ? () => _borrar(context, ref, l, buscar(l.materialId)!)
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => mostrarDialogoLineaMaterial(
            context,
            pedidoId: pedidoId,
            muebleId: muebleId,
          ),
          icon: const Icon(Icons.add),
          label: const Text('Agregar material'),
        ),
      ],
    );
  }
}

class _FilaLinea extends ConsumerWidget {
  const _FilaLinea({
    required this.linea,
    required this.material,
    required this.alBorrar,
  });

  final LineaMaterial linea;
  final Material? material;
  final VoidCallback? alBorrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = material;
    String? codigoRollo;
    if (linea.rolloId != null) {
      // Solo hay rollo en telas; la suscripción es la misma que usa el diálogo.
      final rollos = ref.watch(rollosProvider(linea.materialId)).value;
      for (final r in rollos ?? const <Rollo>[]) {
        if (r.id == linea.rolloId) codigoRollo = r.codigo;
      }
    }
    final cantidad = m == null
        ? linea.cantidad.toString()
        : formatearCantidad(linea.cantidad, m.unidad);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(m?.nombre ?? 'Material desconocido'),
      subtitle: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(cantidad),
          if (codigoRollo != null) Text('Rollo $codigoRollo'),
          if (linea.delCliente) const Chip(label: Text('Del cliente')),
        ],
      ),
      trailing: alBorrar == null
          ? null
          : IconButton(
              tooltip: 'Borrar línea',
              icon: const Icon(Icons.delete_outline),
              onPressed: alBorrar,
            ),
    );
  }
}

class _SeccionDias extends ConsumerWidget {
  const _SeccionDias({required this.pedidoId, required this.muebleId});

  final String pedidoId;
  final String muebleId;

  Future<void> _borrar(
    BuildContext context,
    WidgetRef ref,
    DiaTrabajado dia,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirmar(context, '¿Borrar este registro de días?');
    if (!ok) return;
    guardarSinEsperar(
      messenger,
      ref
          .read(servicioTrabajoProvider)
          .borrarDias(pedidoId: pedidoId, muebleId: muebleId, diaId: dia.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final dias = ref.watch(
      diasProvider((pedidoId: pedidoId, muebleId: muebleId)),
    );
    final usuarios = ref.watch(usuariosProvider).value ?? const [];
    final dueno = esDueno(ref);

    String quien(String uid) {
      for (final u in usuarios) {
        if (u.uid == uid) return u.nombre;
      }
      return 'Usuario desconocido';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Días trabajados', style: tema.textTheme.titleMedium),
        dias.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('No se pudieron cargar los días'),
          data: (lista) => Column(
            children: [
              if (lista.isEmpty) const Text('Sin días registrados'),
              for (final d in lista)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(quien(d.usuarioId)),
                  subtitle: Text(
                    '${formatearCantidad(d.dias, Unidad.pza).replaceAll(' pza', '')} días · '
                    '${formatearFecha(d.fecha)}',
                  ),
                  trailing: dueno
                      ? IconButton(
                          tooltip: 'Borrar días',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _borrar(context, ref, d),
                        )
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => mostrarDialogoDias(
            context,
            pedidoId: pedidoId,
            muebleId: muebleId,
          ),
          icon: const Icon(Icons.add),
          label: const Text('Registrar días'),
        ),
      ],
    );
  }
}
