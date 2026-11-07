import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../../nucleo/formatos.dart';
import 'dialogo_mueble.dart';
import 'providers.dart';
import 'servicio_pedidos.dart';

class PantallaNuevoPedido extends ConsumerStatefulWidget {
  const PantallaNuevoPedido({super.key});

  @override
  ConsumerState<PantallaNuevoPedido> createState() =>
      _PantallaNuevoPedidoState();
}

class _PantallaNuevoPedidoState extends ConsumerState<PantallaNuevoPedido> {
  final _formKey = GlobalKey<FormState>();
  final _busqueda = TextEditingController();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _envio = TextEditingController();
  final _comentarios = TextEditingController();
  final _muebles = <NuevoMueble>[];
  Cliente? _cliente;
  Entrega _entrega = Entrega.recoge;
  late DateTime _fechaEstimada = _hoyMas7();
  bool _faltanMuebles = false;

  static DateTime _hoyMas7() {
    final h = DateTime.now();
    return DateTime(h.year, h.month, h.day).add(const Duration(days: 7));
  }

  @override
  void dispose() {
    for (final c in [
      _busqueda,
      _nombre,
      _telefono,
      _direccion,
      _envio,
      _comentarios,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _elegirCliente(Cliente c) {
    setState(() {
      _cliente = c;
      _nombre.text = c.nombre;
      _telefono.text = c.telefono;
      _direccion.text = c.direccion;
      _busqueda.clear();
    });
  }

  void _cambiarCliente() {
    setState(() {
      _cliente = null;
      _nombre.clear();
      _telefono.clear();
      _direccion.clear();
    });
  }

  double get _envioNumero =>
      _entrega == Entrega.domicilio ? (leerDinero(_envio.text) ?? 0) : 0;

  Future<void> _elegirFecha() async {
    final h = DateTime.now();
    final hoy = DateTime(h.year, h.month, h.day);
    final f = await showDatePicker(
      context: context,
      initialDate: _fechaEstimada.isBefore(hoy) ? hoy : _fechaEstimada,
      firstDate: hoy,
      lastDate: hoy.add(const Duration(days: 365 * 2)),
    );
    if (f != null) setState(() => _fechaEstimada = f);
  }

  Future<void> _agregarMueble() async {
    final m = await mostrarDialogoMueble(context);
    if (m != null && mounted) {
      setState(() {
        _muebles.add(m);
        _faltanMuebles = false;
      });
    }
  }

  void _guardar() {
    final valido = _formKey.currentState!.validate();
    setState(() => _faltanMuebles = _muebles.isEmpty);
    if (!valido || _muebles.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final servicio = ref.read(servicioPedidosProvider);
    final ({String pedidoId, Future<void> guardado}) resultado;
    try {
      resultado = servicio.crearPedido(
        clienteId: _cliente?.id,
        nombre: _nombre.text,
        telefono: _telefono.text,
        direccion: _direccion.text,
        entrega: _entrega,
        envio: _envioNumero,
        comentarios: _comentarios.text,
        fechaEstimada: _fechaEstimada,
        muebles: List.of(_muebles),
      );
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
      return;
    }
    // Sin await: sin conexión el Future no termina y hay que seguir.
    resultado.guardado.catchError((Object _) {
      messenger
          .showSnackBar(const SnackBar(content: Text('No se pudo guardar')));
    });
    // Reemplaza solo esta pantalla: `go` rehace la pila y pierde el menú.
    router.pushReplacement('/pedidos/${resultado.pedidoId}');
  }

  @override
  Widget build(BuildContext context) {
    final clientes = ref.watch(clientesProvider).value ?? const <Cliente>[];
    final consulta = _busqueda.text;
    final sugeridos = consulta.trim().isEmpty
        ? const <Cliente>[]
        : clientes.where((c) => coincideCliente(c, consulta)).take(5).toList();
    final total =
        totalPedido([for (final m in _muebles) m.precio], _envioNumero);
    const decimal = TextInputType.numberWithOptions(decimal: true);
    final soloLectura = _cliente != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo pedido')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Cliente', style: Theme.of(context).textTheme.titleMedium),
            if (!soloLectura) ...[
              TextField(
                key: const Key('buscar-cliente'),
                controller: _busqueda,
                decoration: const InputDecoration(
                  labelText: 'Buscar cliente',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              for (final c in sugeridos)
                ListTile(
                  title: Text(c.nombre),
                  subtitle: Text(c.telefono),
                  onTap: () => _elegirCliente(c),
                ),
            ],
            TextFormField(
              controller: _nombre,
              maxLength: 100,
              readOnly: soloLectura,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Escribe el nombre del cliente'
                  : null,
            ),
            TextFormField(
              controller: _telefono,
              maxLength: 30,
              readOnly: soloLectura,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
            TextFormField(
              controller: _direccion,
              maxLength: 200,
              // Un cliente sin dirección permite escribirla para este pedido;
              // el catálogo de clientes no se actualiza.
              readOnly: soloLectura && _cliente!.direccion.trim().isNotEmpty,
              decoration: const InputDecoration(labelText: 'Dirección'),
              validator: (v) =>
                  _entrega == Entrega.domicilio && (v ?? '').trim().isEmpty
                      ? 'Escribe la dirección de entrega'
                      : null,
            ),
            if (soloLectura)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _cambiarCliente,
                  child: const Text('Cambiar'),
                ),
              ),
            const SizedBox(height: 16),
            Text('Entrega', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<Entrega>(
              segments: [
                for (final e in Entrega.values)
                  ButtonSegment(value: e, label: Text(e.etiqueta)),
              ],
              selected: {_entrega},
              onSelectionChanged: (s) => setState(() => _entrega = s.first),
            ),
            if (_entrega == Entrega.domicilio)
              TextFormField(
                controller: _envio,
                keyboardType: decimal,
                decoration: const InputDecoration(labelText: 'Envío'),
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    leerDinero(v ?? '') == null ? 'Escribe el precio' : null,
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha estimada de terminado'),
              subtitle: Text(formatearFecha(_fechaEstimada)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _elegirFecha,
            ),
            TextFormField(
              controller: _comentarios,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Comentarios'),
            ),
            const SizedBox(height: 16),
            Text('Muebles', style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _muebles.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_muebles[i].tipoMueble),
                subtitle: Text(_muebles[i].tipoTrabajo.etiqueta),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatearDinero(_muebles[i].precio)),
                    IconButton(
                      tooltip: 'Quitar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _muebles.removeAt(i)),
                    ),
                  ],
                ),
              ),
            if (_faltanMuebles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Agrega al menos un mueble',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _agregarMueble,
                icon: const Icon(Icons.add),
                label: const Text('Agregar mueble'),
              ),
            ),
            const Divider(),
            Text('Total: ${formatearDinero(total)}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _guardar,
              child: const Text('Guardar pedido'),
            ),
          ],
        ),
      ),
    );
  }
}
