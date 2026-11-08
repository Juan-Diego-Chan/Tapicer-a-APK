import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dinero.dart';
import '../../dominio/inventario.dart';
import '../../dominio/usuario.dart';
import '../../nucleo/formatos.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';
import '../inventario/pantalla_inventario.dart' show esDueno;
import '../pedidos/dialogos_pedido.dart' show guardarSinEsperar;
import '../usuarios/providers.dart';
import 'providers.dart';

String _nombreDe(List<Usuario> usuarios, String uid) {
  for (final u in usuarios) {
    if (u.uid == uid) return u.nombre;
  }
  return 'Usuario desconocido';
}

String _nombreEnLista(List<Usuario> usuarios, String uid) {
  for (final u in usuarios) {
    if (u.uid == uid) return u.activo ? u.nombre : '${u.nombre} (inactivo)';
  }
  return 'Usuario desconocido';
}

/// Lo ve cada quien según su rol. El árbol del empleado nunca lee las cajas
/// ni las entregas de todos: esas lecturas son solo del dueño.
class PantallaDinero extends ConsumerWidget {
  const PantallaDinero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dinero')),
      body: esDueno(ref) ? const _VistaDueno() : const _VistaEmpleado(),
    );
  }
}

/// Solo para el dueño: las entregas de un empleado.
class PantallaEntregasEmpleado extends ConsumerWidget {
  const PantallaEntregasEmpleado({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Un empleado que llegue aquí no ve nada.
    if (!esDueno(ref)) return const Scaffold();
    final usuarios = ref.watch(usuariosProvider).value ?? const [];
    final enMano = ref.watch(enManoProvider(uid)).value ?? 0;
    final entregas = ref.watch(entregasDeProvider(uid)).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(_nombreDe(usuarios, uid))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('En sus manos: ${formatearDinero(enMano)}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _ListaEntregas(titulo: 'Entregas', entregas: entregas),
        ],
      ),
    );
  }
}

class _ListaEntregas extends StatelessWidget {
  const _ListaEntregas({required this.titulo, required this.entregas});

  final String titulo;
  final List<EntregaDinero> entregas;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: tema.textTheme.titleMedium),
        if (entregas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Sin entregas todavía'),
          ),
        for (final e in entregas)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${formatearDinero(e.monto)} · ${e.forma.etiqueta}'),
            subtitle:
                Text('${formatearFecha(e.fecha)} · ${e.estado.etiqueta}'),
          ),
      ],
    );
  }
}

class _VistaEmpleado extends ConsumerWidget {
  const _VistaEmpleado();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = switch (ref.watch(estadoSesionProvider).value) {
      SesionActiva(:final usuario) => usuario.uid,
      _ => null,
    };
    if (uid == null) return const SizedBox.shrink();
    final enMano = ref.watch(enManoProvider(uid)).value ?? 0;
    final entregas = ref.watch(entregasDeProvider(uid)).value ?? const [];
    final pendiente = entregas
        .where((e) => e.estado == EstadoEntrega.pendiente)
        .fold<double>(0, (s, e) => s + e.monto);
    final libre = porEntregar(enMano, entregas);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('En tus manos: ${formatearDinero(enMano)}',
            style: Theme.of(context).textTheme.titleLarge),
        if (pendiente > 0) Text('Por confirmar: ${formatearDinero(pendiente)}'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _DialogoEntrega(porEntregar: libre),
            ),
            icon: const Icon(Icons.outbox),
            label: const Text('Registrar entrega'),
          ),
        ),
        const SizedBox(height: 16),
        _ListaEntregas(titulo: 'Tus entregas', entregas: entregas),
      ],
    );
  }
}

class _DialogoEntrega extends ConsumerStatefulWidget {
  const _DialogoEntrega({required this.porEntregar});

  final double porEntregar;

  @override
  ConsumerState<_DialogoEntrega> createState() => _DialogoEntregaState();
}

class _DialogoEntregaState extends ConsumerState<_DialogoEntrega> {
  final _monto = TextEditingController();
  FormaPago _forma = FormaPago.efectivo;
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  void _guardar() {
    final n = leerDinero(_monto.text);
    if (n == null) {
      setState(() => _error = 'Escribe un monto válido');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      // El servicio valida de forma síncrona: si lanza, no hay Future.
      final futuro = ref.read(servicioDineroProvider).registrarEntrega(
            porEntregar: widget.porEntregar,
            monto: n,
            forma: _forma,
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
      title: const Text('Registrar entrega'),
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
          const SizedBox(height: 16),
          SegmentedButton<FormaPago>(
            segments: [
              for (final f in FormaPago.values)
                ButtonSegment(value: f, label: Text(f.etiqueta)),
            ],
            selected: {_forma},
            onSelectionChanged: (s) => setState(() => _forma = s.first),
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

class _VistaDueno extends ConsumerStatefulWidget {
  const _VistaDueno();

  @override
  ConsumerState<_VistaDueno> createState() => _VistaDuenoState();
}

class _VistaDuenoState extends ConsumerState<_VistaDueno> {
  /// Entregas ya tocadas: evita mandar el lote dos veces con un doble toque.
  final _tocadas = <String>{};

  void _ejecutar(BuildContext context, Future<void> Function() accion) {
    final messenger = ScaffoldMessenger.of(context);
    try {
      guardarSinEsperar(messenger, accion());
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  void _confirmar(EntregaDinero e) {
    if (!_tocadas.add(e.id)) return;
    setState(() {});
    _ejecutar(context, () => ref.read(servicioDineroProvider).confirmarEntrega(e));
  }

  Future<void> _rechazar(EntregaDinero e, String nombre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          '¿Rechazar la entrega de ${formatearDinero(e.monto)} de $nombre? '
          'Su dinero en manos no cambia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, rechazar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || !_tocadas.add(e.id)) return;
    setState(() {});
    _ejecutar(context, () => ref.read(servicioDineroProvider).rechazarEntrega(e));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final usuarios = ref.watch(usuariosProvider).value ?? const [];
    final pendientes = ref.watch(entregasPendientesProvider).value ?? const [];
    final cajas = ref.watch(cajasProvider).value ?? const {};
    // Todo empleado activo, más cualquiera con dinero en su caja aunque ya
    // esté inactivo o haya cambiado de rol.
    final uids = <String>[
      for (final u in usuarios)
        if ((u.rol == Rol.empleado && u.activo) ||
            redondear2(cajas[u.uid] ?? 0) != 0)
          u.uid,
      for (final c in cajas.entries)
        if (redondear2(c.value) != 0 && !usuarios.any((u) => u.uid == c.key))
          c.key,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Por confirmar', style: tema.textTheme.titleMedium),
        if (pendientes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nada por confirmar'),
          ),
        for (final e in pendientes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
                '${_nombreDe(usuarios, e.empleadoId)}: ${formatearDinero(e.monto)} · ${e.forma.etiqueta}'),
            subtitle: Text(formatearFecha(e.fecha)),
            trailing: Wrap(spacing: 4, children: [
              TextButton(
                onPressed: _tocadas.contains(e.id)
                    ? null
                    : () => _rechazar(e, _nombreDe(usuarios, e.empleadoId)),
                child: const Text('Rechazar'),
              ),
              FilledButton(
                onPressed:
                    _tocadas.contains(e.id) ? null : () => _confirmar(e),
                child: const Text('Confirmar'),
              ),
            ]),
          ),
        const Divider(height: 32),
        Text('En manos de empleados', style: tema.textTheme.titleMedium),
        for (final uid in uids)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_nombreEnLista(usuarios, uid)),
            trailing: Text(formatearDinero(cajas[uid] ?? 0)),
            onTap: () => context.push('/dinero/$uid'),
          ),
      ],
    );
  }
}
