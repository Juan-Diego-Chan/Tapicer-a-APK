import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import '../inventario/providers.dart';
import 'dialogos_pedido.dart' show guardarSinEsperar;
import 'providers.dart';

Future<void> mostrarDialogoLineaMaterial(
  BuildContext context, {
  required String pedidoId,
  required String muebleId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoLinea(pedidoId: pedidoId, muebleId: muebleId),
  );
}

class _DialogoLinea extends ConsumerStatefulWidget {
  const _DialogoLinea({required this.pedidoId, required this.muebleId});

  final String pedidoId;
  final String muebleId;

  @override
  ConsumerState<_DialogoLinea> createState() => _DialogoLineaState();
}

class _DialogoLineaState extends ConsumerState<_DialogoLinea> {
  final _formKey = GlobalKey<FormState>();
  final _cantidad = TextEditingController();
  String? _materialId;
  String? _rolloElegido;
  bool _delCliente = false;

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  /// El elegido por la persona si sigue existiendo; si no, el más reciente
  /// con existencia (los rollos llegan del más nuevo al más viejo).
  String? _rolloEfectivo(List<Rollo> rollos) {
    if (rollos.any((r) => r.id == _rolloElegido)) return _rolloElegido;
    for (final r in rollos) {
      if (r.existencia > 0) return r.id;
    }
    return null;
  }

  Material? _material(List<Material> todos) {
    for (final m in todos) {
      if (m.id == _materialId) return m;
    }
    return null;
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final material = _material(ref.read(materialesProvider).value ?? const [])!;
    final rolloId = material.usaRollos && !_delCliente
        ? _rolloEfectivo(
            ref.read(rollosProvider(material.id)).value ?? const [],
          )
        : null;
    final messenger = ScaffoldMessenger.of(context);
    guardarSinEsperar(
      messenger,
      ref
          .read(servicioTrabajoProvider)
          .agregarLinea(
            pedidoId: widget.pedidoId,
            muebleId: widget.muebleId,
            material: material,
            cantidad: leerCantidad(_cantidad.text)!,
            rolloId: rolloId,
            delCliente: _delCliente,
          ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(materialesProvider).value ?? const <Material>[];
    final lineas =
        ref
            .watch(
              lineasProvider((
                pedidoId: widget.pedidoId,
                muebleId: widget.muebleId,
              )),
            )
            .value ??
        const [];
    final usados = {for (final l in lineas) l.materialId};
    // Los ya usados en este mueble primero; dentro de cada grupo, por nombre.
    final ordenados = [...todos]
      ..sort((a, b) {
        final ua = usados.contains(a.id) ? 0 : 1;
        final ub = usados.contains(b.id) ? 0 : 1;
        if (ua != ub) return ua.compareTo(ub);
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    final material = _material(todos);
    final conRollo = material != null && material.usaRollos && !_delCliente;
    final rollos = conRollo
        ? ref.watch(rollosProvider(material.id)).value ?? const <Rollo>[]
        : const <Rollo>[];

    return AlertDialog(
      title: const Text('Agregar material'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('material'),
                initialValue: _materialId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Material'),
                items: [
                  for (final m in ordenados)
                    DropdownMenuItem(value: m.id, child: Text(m.nombre)),
                ],
                onChanged: (v) => setState(() {
                  _materialId = v;
                  _rolloElegido = null;
                }),
                validator: (v) => v == null ? 'Elige el material' : null,
              ),
              TextFormField(
                controller: _cantidad,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: material == null
                      ? 'Cantidad'
                      : 'Cantidad (${material.unidad.clave})',
                ),
                validator: (v) {
                  final n = leerCantidad(v ?? '');
                  return n == null || n <= 0
                      ? 'Escribe una cantidad mayor a 0'
                      : null;
                },
              ),
              if (material != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Lo trajo el cliente'),
                  value: _delCliente,
                  onChanged: (v) => setState(() => _delCliente = v ?? false),
                ),
              if (conRollo)
                DropdownButtonFormField<String>(
                  // La llave incluye la selección: si los rollos cargan
                  // después, el campo se reconstruye con el preseleccionado.
                  key: ValueKey('rollo-${_rolloEfectivo(rollos)}'),
                  initialValue: _rolloEfectivo(rollos),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Rollo'),
                  items: [
                    for (final r in rollos)
                      DropdownMenuItem(
                        value: r.id,
                        child: Text(
                          '${r.codigo} · quedan '
                          '${formatearCantidad(r.existencia, material.unidad)}',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _rolloElegido = v),
                  validator: (_) =>
                      _rolloEfectivo(rollos) == null ? 'Elige el rollo' : null,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
