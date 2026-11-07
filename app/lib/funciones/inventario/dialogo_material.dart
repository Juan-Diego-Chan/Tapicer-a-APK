import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import 'providers.dart';

Future<void> mostrarDialogoMaterial(BuildContext context,
    {Material? existente}) {
  return showDialog<void>(
    context: context,
    builder: (_) => DialogoMaterial(existente: existente),
  );
}

class DialogoMaterial extends ConsumerStatefulWidget {
  const DialogoMaterial({super.key, this.existente});

  final Material? existente;

  @override
  ConsumerState<DialogoMaterial> createState() => _DialogoMaterialState();
}

class _DialogoMaterialState extends ConsumerState<DialogoMaterial> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _stockMinimo;
  late Categoria _categoria;
  late Unidad _unidad;

  @override
  void initState() {
    super.initState();
    final m = widget.existente;
    _nombre = TextEditingController(text: m?.nombre ?? '');
    _stockMinimo = TextEditingController(
      text: m == null
          ? ''
          : formatearCantidad(m.stockMinimo, m.unidad).split(' ').first,
    );
    _categoria = m?.categoria ?? Categoria.otros;
    _unidad = m?.unidad ?? Unidad.pza;
    if (_categoria == Categoria.tela) _unidad = Unidad.m;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _stockMinimo.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(repositorioInventarioProvider);
    final messenger = ScaffoldMessenger.of(context);
    final nombre = _nombre.text.trim();
    final minimo = leerCantidad(_stockMinimo.text)!;
    final existente = widget.existente;

    final Future<void> futuro;
    if (existente == null) {
      futuro = repo.crearMaterial(Material(
        id: '',
        nombre: nombre,
        categoria: _categoria,
        unidad: _unidad,
        stockMinimo: minimo,
        existencia: 0,
        usaRollos: _categoria == Categoria.tela,
        marcadoAgotandose: false,
      ));
    } else {
      futuro = repo.editarMaterial(
        existente.id,
        nombre: nombre,
        categoria: _categoria,
        unidad: _unidad,
        stockMinimo: minimo,
      );
    }
    // Sin await: sin conexión el Future no termina y el diálogo debe cerrar.
    futuro.catchError((Object e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e is ArgumentError
            ? 'No se puede cambiar entre tela y otra categoría'
            : 'No se pudo guardar'),
      ));
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.existente != null;
    final eraTela = widget.existente?.usaRollos == true;
    return AlertDialog(
      title: Text(editando ? 'Editar material' : 'Nuevo material'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Escribe el nombre'
                    : null,
              ),
              DropdownButtonFormField<Categoria>(
                key: const Key('categoria'),
                initialValue: _categoria,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  for (final c in Categoria.values)
                    DropdownMenuItem(
                      value: c,
                      // Al editar no se puede pasar de tela a otra ni al revés.
                      enabled: !editando || ((c == Categoria.tela) == eraTela),
                      child: Text(c.etiqueta),
                    ),
                ],
                onChanged: (c) {
                  if (c == null) return;
                  setState(() {
                    _categoria = c;
                    if (c == Categoria.tela) _unidad = Unidad.m;
                  });
                },
              ),
              DropdownButtonFormField<Unidad>(
                key: ValueKey('unidad-$_unidad'),
                initialValue: _unidad,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Unidad'),
                items: const [
                  DropdownMenuItem(value: Unidad.m, child: Text('Metros (m)')),
                  DropdownMenuItem(value: Unidad.kg, child: Text('Kilos (kg)')),
                  DropdownMenuItem(
                      value: Unidad.pza, child: Text('Piezas (pza)')),
                  DropdownMenuItem(value: Unidad.l, child: Text('Litros (l)')),
                ],
                onChanged: _categoria == Categoria.tela
                    ? null
                    : (u) {
                        if (u != null) setState(() => _unidad = u);
                      },
              ),
              TextFormField(
                controller: _stockMinimo,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Stock mínimo'),
                validator: (v) {
                  final n = leerCantidad(v ?? '');
                  return (n == null || n < 0)
                      ? 'Escribe un número mayor o igual a 0'
                      : null;
                },
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
