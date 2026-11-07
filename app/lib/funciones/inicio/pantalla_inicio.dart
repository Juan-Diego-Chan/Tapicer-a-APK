import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/usuario.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';

class EntradaMenu {
  final String titulo;
  final IconData icono;
  final String ruta;
  final bool soloDueno;

  const EntradaMenu({
    required this.titulo,
    required this.icono,
    required this.ruta,
    this.soloDueno = false,
  });
}

const List<EntradaMenu> entradasMenu = [
  EntradaMenu(titulo: 'Pedidos', icono: Icons.assignment, ruta: '/pedidos'),
  EntradaMenu(
      titulo: 'Fabricación', icono: Icons.chair, ruta: '/fabricacion'),
  EntradaMenu(titulo: 'Reparación', icono: Icons.build, ruta: '/reparacion'),
  EntradaMenu(
      titulo: 'Inventario', icono: Icons.inventory_2, ruta: '/inventario'),
  EntradaMenu(
      titulo: 'Lista de compras',
      icono: Icons.shopping_cart,
      ruta: '/compras',
      soloDueno: true),
  EntradaMenu(
      titulo: 'Plantillas',
      icono: Icons.list_alt,
      ruta: '/plantillas',
      soloDueno: true),
  EntradaMenu(titulo: 'Dinero', icono: Icons.payments, ruta: '/dinero'),
  EntradaMenu(
      titulo: 'Contabilidad',
      icono: Icons.account_balance,
      ruta: '/contabilidad',
      soloDueno: true),
  EntradaMenu(
      titulo: 'Usuarios',
      icono: Icons.people,
      ruta: '/usuarios',
      soloDueno: true),
];

class PantallaInicio extends ConsumerWidget {
  const PantallaInicio({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estadoSesionProvider).value;
    if (estado is! SesionActiva) {
      // Cargando sesión: el router redirige si hace falta.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final usuario = estado.usuario;
    final entradas = entradasMenu
        .where((e) => !e.soloDueno || usuario.rol == Rol.dueno)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(usuario.nombre),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(servicioSesionProvider).cerrarSesion(),
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          for (final e in entradas)
            Card(
              child: InkWell(
                onTap: () => context.push(e.ruta),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(e.icono, size: 40),
                    const SizedBox(height: 8),
                    Text(e.titulo),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
