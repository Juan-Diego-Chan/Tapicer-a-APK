import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/usuario.dart';
import '../../nucleo/formatos.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';
import 'dialogo_alta_empleado.dart';
import 'providers.dart';
import 'servicio_alta_usuario.dart';

class PantallaUsuarios extends ConsumerWidget {
  const PantallaUsuarios({super.key});

  Future<void> _cambiarActivo(
    BuildContext context,
    WidgetRef ref,
    Usuario u,
    bool activo,
  ) async {
    if (!activo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(
            '¿Desactivar a ${u.nombre}? Ya no podrá entrar a la app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Desactivar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(repositorioUsuariosProvider).fijarActivo(u.uid, activo);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yo = switch (ref.watch(estadoSesionProvider).value) {
      SesionActiva(:final usuario) => usuario.uid,
      _ => null,
    };
    final usuarios = ref.watch(usuariosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => const DialogoAltaEmpleado(),
        ),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo empleado'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: _CampoDiasLaborales(),
          ),
          const Divider(height: 1),
          usuarios.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No se pudieron cargar los usuarios'),
            ),
            data: (lista) => Column(
              children: [
                for (final u in lista)
                  _FilaUsuario(
                    usuario: u,
                    esYo: u.uid == yo,
                    alCambiar: (v) => _cambiarActivo(context, ref, u, v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaUsuario extends ConsumerWidget {
  final Usuario usuario;
  final bool esYo;
  final ValueChanged<bool> alCambiar;

  const _FilaUsuario({
    required this.usuario,
    required this.esYo,
    required this.alCambiar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esDueno = usuario.rol == Rol.dueno;
    String? sueldo;
    if (!esDueno) {
      final s = ref.watch(sueldoProvider(usuario.uid)).value;
      sueldo = s == null ? 'Sin sueldo' : formatearDinero(s);
    }
    return ListTile(
      title: Text(usuario.nombre),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(esDueno ? 'Dueño' : 'Empleado'),
          if (sueldo != null) Text(sueldo),
        ],
      ),
      trailing: esYo
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Activo'),
                Switch(value: usuario.activo, onChanged: alCambiar),
              ],
            ),
    );
  }
}

class _CampoDiasLaborales extends ConsumerStatefulWidget {
  const _CampoDiasLaborales();

  @override
  ConsumerState<_CampoDiasLaborales> createState() =>
      _CampoDiasLaboralesState();
}

class _CampoDiasLaboralesState extends ConsumerState<_CampoDiasLaborales> {
  final _formKey = GlobalKey<FormState>();
  final _controlador = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<int>>(diasLaboralesProvider, (_, nuevo) {
      final v = nuevo.value;
      if (v != null) _controlador.text = v.toString();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(repositorioPrivadoProvider)
          .fijarDiasLaborales(int.parse(_controlador.text.trim()));
      mensajero.showSnackBar(
        const SnackBar(content: Text('Días laborales guardados')),
      );
    } catch (_) {
      mensajero.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _controlador,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Días laborales por semana',
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n < 1 || n > 7)
                    ? 'Escribe un número del 1 al 7'
                    : null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: _guardar,
              child: const Text('Guardar días'),
            ),
          ),
        ],
      ),
    );
  }
}
