import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../inventario/providers.dart';
import '../pedidos/providers.dart';

Future<void> mostrarDialogoPlantilla(
  BuildContext context, {
  Plantilla? existente,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => DialogoPlantilla(existente: existente),
  );
}

class _LineaEditable {
  _LineaEditable(this.materialId, String cantidad)
    : cantidad = TextEditingController(text: cantidad);

  String? materialId;
  final TextEditingController cantidad;
}

class DialogoPlantilla extends ConsumerStatefulWidget {
  const DialogoPlantilla({super.key, this.existente});

  final Plantilla? existente;

  @override
  ConsumerState<DialogoPlantilla> createState() => _DialogoPlantillaState();
}

class _DialogoPlantillaState extends ConsumerState<DialogoPlantilla> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tipo;
  final List<_LineaEditable> _lineas = [];
  bool _intentoGuardar = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existente;
    _tipo = TextEditingController(text: p?.tipoMueble ?? '');
    for (final l in p?.lineas ?? const <LineaPlantilla>[]) {
      _lineas.add(
        _LineaEditable(
          l.materialId,
          formatearCantidad(l.cantidad, Unidad.pza).split(' ').first,
        ),
      );
    }
  }

  @override
  void dispose() {
    _tipo.dispose();
    for (final l in _lineas) {
      l.cantidad.dispose();
    }
    super.dispose();
  }

  void _guardar() {
    setState(() => _intentoGuardar = true);
    if (!_formKey.currentState!.validate() || _lineas.isEmpty) return;
    final repo = ref.read(repositorioPlantillasProvider);
    final messenger = ScaffoldMessenger.of(context);
    final existente = widget.existente;
    final plantilla = Plantilla(
      id: existente?.id ?? '',
      tipoMueble: _tipo.text.trim(),
      lineas: [
        for (final l in _lineas)
          LineaPlantilla(
            materialId: l.materialId!,
            cantidad: leerCantidad(l.cantidad.text)!,
          ),
      ],
    );
    final Future<void> futuro = existente == null
        ? repo.crear(plantilla)
        : repo.editar(plantilla);
    // Sin await: sin conexión el Future no termina y el diálogo debe cerrar.
    futuro.catchError((Object e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar')),
      );
    });
    Navigator.of(context).pop();
  }

  Future<void> _borrar() async {
    final existente = widget.existente!;
    final repo = ref.read(repositorioPlantillasProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Borrar la plantilla ${existente.tipoMueble}?'),
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
    if (confirmado != true) return;
    // Sin await: sin conexión el Future no termina.
    repo.borrar(existente.id).catchError((Object e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar')),
      );
    });
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final materiales =
        ref.watch(materialesProvider).value ?? const <Material>[];
    final porId = {for (final m in materiales) m.id: m};
    final editando = widget.existente != null;
    return AlertDialog(
      title: Text(editando ? 'Editar plantilla' : 'Nueva plantilla'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _tipo,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Tipo de mueble'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Escribe el tipo de mueble'
                    : null,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _lineas.length; i++)
                KeyedSubtree(
                  key: ObjectKey(_lineas[i]),
                  child: _filaLinea(i, materiales, porId),
                ),
              if (_intentoGuardar && _lineas.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Agrega al menos un material',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _lineas.add(_LineaEditable(null, ''))),
                icon: const Icon(Icons.add),
                label: const Text('Agregar material'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (editando)
          TextButton(
            onPressed: _borrar,
            child: Text(
              'Borrar',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }

  Widget _filaLinea(
    int i,
    List<Material> materiales,
    Map<String, Material> porId,
  ) {
    final linea = _lineas[i];
    final unidad = porId[linea.materialId]?.unidad;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            key: Key('material-$i'),
            initialValue: porId.containsKey(linea.materialId)
                ? linea.materialId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Material'),
            items: [
              for (final m in materiales)
                DropdownMenuItem(value: m.id, child: Text(m.nombre)),
            ],
            onChanged: (id) => setState(() => linea.materialId = id),
            validator: (v) {
              if (v == null) return 'Elige un material';
              final repetido = _lineas.take(i).any((o) => o.materialId == v);
              return repetido ? 'Ese material ya está en la plantilla' : null;
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            key: Key('cantidad-$i'),
            controller: linea.cantidad,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Cantidad',
              suffixText: unidad?.clave,
            ),
            validator: (v) {
              final n = leerCantidad(v ?? '');
              return (n == null || n <= 0)
                  ? 'Escribe una cantidad mayor a 0'
                  : null;
            },
          ),
        ),
        IconButton(
          tooltip: 'Quitar material',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() {
            _lineas.removeAt(i).cantidad.dispose();
          }),
        ),
      ],
    );
  }
}
