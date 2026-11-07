import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import 'providers.dart';

enum TipoCaptura { compra, inicial, ajuste }

Future<void> mostrarDialogoMovimiento(
  BuildContext context, {
  required Material material,
  required TipoCaptura tipo,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => DialogoMovimiento(material: material, tipo: tipo),
  );
}

class DialogoMovimiento extends ConsumerStatefulWidget {
  const DialogoMovimiento(
      {super.key, required this.material, required this.tipo});

  final Material material;
  final TipoCaptura tipo;

  @override
  ConsumerState<DialogoMovimiento> createState() => _DialogoMovimientoState();
}

class _DialogoMovimientoState extends ConsumerState<DialogoMovimiento> {
  final _formKey = GlobalKey<FormState>();
  final _cantidad = TextEditingController();
  final _precio = TextEditingController();
  final _codigo = TextEditingController();
  String? _rolloId;
  bool _codigoEditado = false;
  bool _codigoPrecargado = false;

  Material get _m => widget.material;
  String get _u => _m.unidad.clave;

  @override
  void initState() {
    super.initState();
    if (_m.usaRollos && widget.tipo != TipoCaptura.ajuste) {
      // listenManual mantiene vivo el provider autoDispose mientras el diálogo
      // existe; el código solo se precarga una vez, si el usuario no lo tocó.
      ref.listenManual(rollosProvider(_m.id), (_, estado) {
        final rollos = estado.value;
        if (rollos == null || _codigoPrecargado || _codigoEditado) return;
        _codigoPrecargado = true;
        _codigo.text = siguienteCodigoRollo(rollos.map((r) => r.codigo));
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _cantidad.dispose();
    _precio.dispose();
    _codigo.dispose();
    super.dispose();
  }

  String get _titulo => switch (widget.tipo) {
        TipoCaptura.compra => 'Registrar compra: ${_m.nombre}',
        TipoCaptura.inicial => 'Inventario inicial: ${_m.nombre}',
        TipoCaptura.ajuste => 'Ajuste de inventario: ${_m.nombre}',
      };

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final servicio = ref.read(servicioInventarioProvider);
    final messenger = ScaffoldMessenger.of(context);
    final cantidad = leerCantidad(_cantidad.text.replaceAll('−', '-'))!;
    final codigo = _m.usaRollos ? _codigo.text.trim() : null;

    final Future<void> futuro = switch (widget.tipo) {
      TipoCaptura.compra => servicio.registrarCompra(
          material: _m,
          cantidad: cantidad,
          precioTotal: leerCantidad(_precio.text)!,
          codigoRollo: codigo,
        ),
      TipoCaptura.inicial => servicio.registrarCargaInicial(
          material: _m,
          cantidad: cantidad,
          costoPorUnidad: leerCantidad(_precio.text),
          codigoRollo: codigo,
        ),
      TipoCaptura.ajuste => servicio.registrarAjuste(
          material: _m,
          cantidad: cantidad,
          rolloId: _m.usaRollos ? _rolloId : null,
        ),
    };
    // Sin await: sin conexión el Future no termina y el diálogo debe cerrar.
    futuro.catchError((Object _) {
      messenger
          .showSnackBar(const SnackBar(content: Text('No se pudo guardar')));
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tipo = widget.tipo;
    const decimal = TextInputType.numberWithOptions(decimal: true);
    final campos = <Widget>[];

    if (tipo == TipoCaptura.ajuste) {
      campos.add(TextFormField(
        controller: _cantidad,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration:
            const InputDecoration(labelText: 'Cantidad (+ entra, − sale)'),
        validator: (v) {
          final n = leerCantidad((v ?? '').replaceAll('−', '-'));
          return (n == null || n == 0) ? 'El ajuste no puede ser 0' : null;
        },
      ));
      if (_m.usaRollos) {
        final rollos = ref.watch(rollosProvider(_m.id)).value ?? const [];
        campos.add(DropdownButtonFormField<String>(
          key: const Key('rollo'),
          initialValue: _rolloId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Rollo'),
          items: [
            for (final r in rollos)
              DropdownMenuItem(
                value: r.id,
                child: Text(
                    '${r.codigo} (${formatearCantidad(r.existencia, _m.unidad)})'),
              ),
          ],
          onChanged: (v) => setState(() => _rolloId = v),
          validator: (v) => v == null ? 'Elige el rollo' : null,
        ));
      }
    } else {
      campos.add(TextFormField(
        controller: _cantidad,
        keyboardType: decimal,
        decoration: InputDecoration(labelText: 'Cantidad ($_u)'),
        validator: (v) {
          final n = leerCantidad(v ?? '');
          return (n == null || n <= 0) ? 'Escribe una cantidad mayor a 0' : null;
        },
      ));
      if (tipo == TipoCaptura.compra) {
        campos.add(TextFormField(
          controller: _precio,
          keyboardType: decimal,
          decoration: const InputDecoration(labelText: 'Precio total pagado'),
          validator: (v) {
            final n = leerCantidad(v ?? '');
            return (n == null || n < 0) ? 'Escribe el precio pagado' : null;
          },
        ));
      } else {
        campos.add(TextFormField(
          controller: _precio,
          keyboardType: decimal,
          decoration: InputDecoration(labelText: 'Costo por $_u (opcional)'),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final n = leerCantidad(v!);
            return (n == null || n < 0) ? 'Escribe el precio pagado' : null;
          },
        ));
      }
      if (_m.usaRollos) {
        campos.add(TextFormField(
          controller: _codigo,
          onChanged: (_) => _codigoEditado = true,
          decoration: const InputDecoration(labelText: 'Código del rollo'),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Escribe el código del rollo'
              : null,
        ));
      }
    }

    return AlertDialog(
      title: Text(_titulo),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: campos),
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
