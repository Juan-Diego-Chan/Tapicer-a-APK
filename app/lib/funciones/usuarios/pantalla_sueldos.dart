import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/dinero.dart';
import '../../dominio/inventario.dart';
import '../../nucleo/formatos.dart';
import '../dinero/providers.dart';
import '../inventario/pantalla_inventario.dart' show esDueno;
import '../pedidos/dialogos_pedido.dart' show guardarSinEsperar;
import 'providers.dart';

/// Solo para el dueño: sueldo y pagos de sueldo de un empleado.
class PantallaSueldos extends ConsumerWidget {
  const PantallaSueldos({super.key, required this.uid});

  final String uid;

  Future<void> _borrar(
      BuildContext context, WidgetRef ref, PagoSueldo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content:
            Text('¿Borrar el pago de sueldo de ${formatearDinero(p.monto)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      guardarSinEsperar(
          messenger, ref.read(servicioDineroProvider).borrarPagoSueldo(p.id));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Un no dueño que llegue aquí no ve nada ni lee nada.
    if (!esDueno(ref)) return const Scaffold();
    final usuarios = ref.watch(usuariosProvider).value ?? const [];
    final nombre = usuarios.where((u) => u.uid == uid).firstOrNull?.nombre ??
        'Usuario desconocido';
    final sueldo = ref.watch(sueldoProvider(uid)).value;
    final pagos = ref.watch(pagosSueldoProvider(uid)).value ?? const [];
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(nombre)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            sueldo == null
                ? 'Sin sueldo'
                : 'Sueldo semanal: ${formatearDinero(sueldo)}',
            style: tema.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _DialogoPagoSueldo(uid: uid, sueldo: sueldo),
              ),
              icon: const Icon(Icons.payments),
              label: const Text('Registrar pago de sueldo'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Pagos de sueldo', style: tema.textTheme.titleMedium),
          if (pagos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin pagos todavía'),
            ),
          for (final p in pagos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(formatearDinero(p.monto)),
              subtitle: Text(formatearFecha(p.fecha)),
              trailing: IconButton(
                tooltip: 'Borrar pago de sueldo',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _borrar(context, ref, p),
              ),
            ),
        ],
      ),
    );
  }
}

class _DialogoPagoSueldo extends ConsumerStatefulWidget {
  const _DialogoPagoSueldo({required this.uid, required this.sueldo});

  final String uid;
  final double? sueldo;

  @override
  ConsumerState<_DialogoPagoSueldo> createState() =>
      _DialogoPagoSueldoState();
}

class _DialogoPagoSueldoState extends ConsumerState<_DialogoPagoSueldo> {
  late final TextEditingController _monto;
  DateTime _fecha = DateTime.now();
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.sueldo;
    _monto = TextEditingController(
      text: s == null
          ? ''
          : (s == s.roundToDouble() ? s.toInt().toString() : s.toString()),
    );
  }

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (f != null) setState(() => _fecha = f);
  }

  void _guardar() {
    final n = leerDinero(_monto.text);
    if (n == null) {
      setState(() => _error = 'El monto debe ser mayor a 0');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      // El servicio valida de forma síncrona: si lanza, no hay Future.
      final futuro = ref.read(servicioDineroProvider).registrarPagoSueldo(
            usuarioId: widget.uid,
            monto: n,
            fecha: _fecha,
          );
      guardarSinEsperar(messenger, futuro);
      Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      setState(() => _error = e.message?.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar pago de sueldo'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _monto,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Monto', errorText: _error),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _elegirFecha,
            icon: const Icon(Icons.calendar_today),
            label: Text('Fecha: ${formatearFecha(_fecha)}'),
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
