import 'package:flutter/material.dart';

/// Pantalla provisional compartida por las secciones que aún no existen.
class PantallaProximamente extends StatelessWidget {
  const PantallaProximamente({super.key, this.titulo = ''});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: const Center(child: Text('Próximamente')),
    );
  }
}
