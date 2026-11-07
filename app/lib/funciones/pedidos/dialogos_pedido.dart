import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../../nucleo/formatos.dart';
import 'providers.dart';

/// Sin await: sin conexión el Future no termina y la UI debe seguir.
void guardarSinEsperar(ScaffoldMessengerState messenger, Future<void> futuro) {
  futuro.catchError((Object _) {
    messenger.showSnackBar(const SnackBar(content: Text('No se pudo guardar')));
  });
}

const _decimal = TextInputType.numberWithOptions(decimal: true);

Future<void> mostrarDialogoPrecio(
  BuildContext context, {
  required String pedidoId,
  required Mueble mueble,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoPrecio(pedidoId: pedidoId, mueble: mueble),
  );
}

class _DialogoPrecio extends ConsumerStatefulWidget {
  const _DialogoPrecio({required this.pedidoId, required this.mueble});

  final String pedidoId;
  final Mueble mueble;

  @override
  ConsumerState<_DialogoPrecio> createState() => _DialogoPrecioState();
}

class _DialogoPrecioState extends ConsumerState<_DialogoPrecio> {
  final _formKey = GlobalKey<FormState>();
  late final _precio =
      TextEditingController(text: widget.mueble.precio.toStringAsFixed(2));
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _precio.dispose();
    _motivo.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    guardarSinEsperar(
      messenger,
      ref.read(servicioPedidosProvider).cambiarPrecioMueble(
            pedidoId: widget.pedidoId,
            mueble: widget.mueble,
            nuevo: leerDinero(_precio.text)!,
            motivo: _motivo.text,
          ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Precio de ${widget.mueble.tipoMueble}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _precio,
              keyboardType: _decimal,
              decoration: const InputDecoration(labelText: 'Nuevo precio'),
              validator: (v) {
                final n = leerDinero(v ?? '');
                if (n == null) return 'Escribe el precio';
                if (redondear2(n) == redondear2(widget.mueble.precio)) {
                  return 'El precio no cambió';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _motivo,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
          ]),
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

Future<void> mostrarDialogoEnvio(
  BuildContext context, {
  required Pedido pedido,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoEnvio(pedido: pedido),
  );
}

class _DialogoEnvio extends ConsumerStatefulWidget {
  const _DialogoEnvio({required this.pedido});

  final Pedido pedido;

  @override
  ConsumerState<_DialogoEnvio> createState() => _DialogoEnvioState();
}

class _DialogoEnvioState extends ConsumerState<_DialogoEnvio> {
  final _formKey = GlobalKey<FormState>();
  late Entrega _entrega = widget.pedido.entrega;
  late final _envio = TextEditingController(
      text: widget.pedido.envio == 0
          ? ''
          : widget.pedido.envio.toStringAsFixed(2));
  final _motivo = TextEditingController();
  bool _sinCambios = false;

  @override
  void dispose() {
    _envio.dispose();
    _motivo.dispose();
    super.dispose();
  }

  double get _monto =>
      _entrega == Entrega.domicilio ? (leerDinero(_envio.text) ?? 0) : 0;

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final p = widget.pedido;
    if (_entrega == p.entrega && redondear2(_monto) == redondear2(p.envio)) {
      setState(() => _sinCambios = true);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    guardarSinEsperar(
      messenger,
      ref.read(servicioPedidosProvider).cambiarEnvio(
            pedido: widget.pedido,
            entrega: _entrega,
            envio: _monto,
            motivo: _motivo.text,
          ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar envío'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<Entrega>(
              segments: [
                for (final e in Entrega.values)
                  ButtonSegment(value: e, label: Text(e.etiqueta)),
              ],
              selected: {_entrega},
              onSelectionChanged: (s) => setState(() {
                _entrega = s.first;
                _sinCambios = false;
              }),
            ),
            if (_entrega == Entrega.domicilio)
              TextFormField(
                controller: _envio,
                keyboardType: _decimal,
                decoration: const InputDecoration(labelText: 'Envío'),
                validator: (v) {
                  return leerDinero(v ?? '') == null ? 'Escribe el precio' : null;
                },
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Envío: ${formatearDinero(0)}'),
              ),
            TextFormField(
              controller: _motivo,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
            if (_sinCambios)
              Text('No hay cambios',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
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

Future<void> mostrarDialogoEditarPedido(
  BuildContext context, {
  required Pedido pedido,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoEditarPedido(pedido: pedido),
  );
}

class _DialogoEditarPedido extends ConsumerStatefulWidget {
  const _DialogoEditarPedido({required this.pedido});

  final Pedido pedido;

  @override
  ConsumerState<_DialogoEditarPedido> createState() =>
      _DialogoEditarPedidoState();
}

class _DialogoEditarPedidoState extends ConsumerState<_DialogoEditarPedido> {
  late final _comentarios =
      TextEditingController(text: widget.pedido.comentarios);
  late DateTime _fecha = widget.pedido.fechaEstimada;

  @override
  void dispose() {
    _comentarios.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final h = DateTime.now();
    final hoy = DateTime(h.year, h.month, h.day);
    final primera = _fecha.isBefore(hoy) ? _fecha : hoy;
    final f = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: primera,
      lastDate: hoy.add(const Duration(days: 365 * 2)),
    );
    if (f != null) setState(() => _fecha = f);
  }

  void _guardar() {
    final messenger = ScaffoldMessenger.of(context);
    guardarSinEsperar(
      messenger,
      ref.read(servicioPedidosProvider).editarPedido(
            pedidoId: widget.pedido.id,
            comentarios: _comentarios.text,
            fechaEstimada: _fecha,
          ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar pedido'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _comentarios,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Comentarios'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fecha estimada de terminado'),
            subtitle: Text(formatearFecha(_fecha)),
            trailing: const Icon(Icons.calendar_today),
            onTap: _elegirFecha,
          ),
        ]),
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
