import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../inventario/pantalla_inventario.dart' show esDueno;
import 'aviso_disponibilidad.dart';
import 'providers.dart';
import 'servicio_pedidos.dart';

Future<NuevoMueble?> mostrarDialogoMueble(
  BuildContext context, {
  TipoTrabajo? tipoInicial,
}) {
  return showDialog<NuevoMueble>(
    context: context,
    builder: (_) => DialogoMueble(tipoInicial: tipoInicial),
  );
}

class DialogoMueble extends ConsumerStatefulWidget {
  const DialogoMueble({super.key, this.tipoInicial});

  final TipoTrabajo? tipoInicial;

  @override
  ConsumerState<DialogoMueble> createState() => _DialogoMuebleState();
}

class _DialogoMuebleState extends ConsumerState<DialogoMueble> {
  final _formKey = GlobalKey<FormState>();
  final _precio = TextEditingController();
  final _comentarios = TextEditingController();
  late TipoTrabajo _trabajo = widget.tipoInicial ?? TipoTrabajo.fabricacion;
  String _tipoMueble = '';
  String? _plantillaId;
  // Cambia al preseleccionar para que el desplegable tome el nuevo valor.
  int _version = 0;

  @override
  void dispose() {
    _precio.dispose();
    _comentarios.dispose();
    super.dispose();
  }

  void _alEscribirTipo(String texto, List<Plantilla> plantillas) {
    _tipoMueble = texto;
    final buscado = texto.trim().toLowerCase();
    for (final p in plantillas) {
      if (p.tipoMueble.trim().toLowerCase() == buscado &&
          p.id != _plantillaId) {
        setState(() {
          _plantillaId = p.id;
          _version++;
        });
        return;
      }
    }
    setState(() {});
  }

  void _agregar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(NuevoMueble(
      tipoTrabajo: _trabajo,
      tipoMueble: _tipoMueble.trim(),
      plantillaId: _plantillaId,
      precio: leerDinero(_precio.text)!,
      comentarios: _comentarios.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final plantillas = ref.watch(plantillasProvider).value ?? const [];
    final tipos = {for (final p in plantillas) p.tipoMueble}.toList();
    Plantilla? elegida;
    for (final p in plantillas) {
      if (p.id == _plantillaId) elegida = p;
    }
    const decimal = TextInputType.numberWithOptions(decimal: true);

    return AlertDialog(
      title: const Text('Agregar mueble'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<TipoTrabajo>(
                segments: [
                  for (final t in TipoTrabajo.values)
                    ButtonSegment(value: t, label: Text(t.etiqueta)),
                ],
                selected: {_trabajo},
                onSelectionChanged: (s) => setState(() => _trabajo = s.first),
              ),
              const SizedBox(height: 12),
              Autocomplete<String>(
                optionsBuilder: (v) {
                  final q = v.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable<String>.empty();
                  return tipos.where((t) => t.toLowerCase().contains(q));
                },
                onSelected: (t) => _alEscribirTipo(t, plantillas),
                fieldViewBuilder: (context, controller, foco, _) =>
                    TextFormField(
                  key: const Key('tipo-mueble'),
                  controller: controller,
                  focusNode: foco,
                  textCapitalization: TextCapitalization.sentences,
                  decoration:
                      const InputDecoration(labelText: 'Tipo de mueble'),
                  onChanged: (t) => _alEscribirTipo(t, plantillas),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Escribe el tipo de mueble'
                      : null,
                ),
              ),
              KeyedSubtree(
                key: ValueKey(_version),
                child: DropdownButtonFormField<String?>(
                  key: const Key('plantilla'),
                  initialValue: _plantillaId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Plantilla (opcional)'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Sin plantilla')),
                    for (final p in plantillas)
                      DropdownMenuItem<String?>(
                          value: p.id, child: Text(p.tipoMueble)),
                  ],
                  onChanged: (v) => setState(() => _plantillaId = v),
                ),
              ),
              if (elegida != null) ...[
                AvisoDisponibilidad(plantilla: elegida),
                if (esDueno(ref)) EstimadoPlantilla(plantilla: elegida),
              ],
              TextFormField(
                key: const Key('precio'),
                controller: _precio,
                keyboardType: decimal,
                decoration: const InputDecoration(labelText: 'Precio'),
                validator: (v) =>
                    leerDinero(v ?? '') == null ? 'Escribe el precio' : null,
              ),
              TextFormField(
                key: const Key('comentarios-mueble'),
                controller: _comentarios,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Comentarios'),
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
        FilledButton(onPressed: _agregar, child: const Text('Agregar')),
      ],
    );
  }
}
