import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/costos_pedido.dart';
import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../../dominio/usuario.dart';
import '../../nucleo/formatos.dart';
import '../inventario/pantalla_inventario.dart' show esDueno;
import '../inventario/providers.dart';
import '../usuarios/providers.dart';
import 'aviso_disponibilidad.dart';
import 'providers.dart';

/// Estimado vs. usado para todos; costo real solo para el dueño.
class SeccionPlantillaYCostos extends ConsumerWidget {
  const SeccionPlantillaYCostos({
    super.key,
    required this.mueble,
    required this.lineas,
    required this.dias,
  });

  final Mueble mueble;
  final List<LineaMaterial> lineas;
  final List<DiaTrabajado> dias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final plantillas = ref.watch(plantillasProvider).value ?? const [];
    Plantilla? plantilla;
    for (final p in plantillas) {
      if (p.id == mueble.plantillaId) plantilla = p;
    }
    final usado = usadoPorMaterial(lineas);
    final activo = mueble.estado == EstadoMueble.recibido ||
        mueble.estado == EstadoMueble.enProceso;
    final dueno = esDueno(ref);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text('Estimado vs. usado', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (plantilla == null) const Text('Sin plantilla'),
        if (plantilla != null || lineas.isNotEmpty)
          _TablaEstimadoUsado(
            comparaciones: estimadoVsUsado(plantilla, usado),
            conEstimado: plantilla != null,
          ),
        if (plantilla != null && activo)
          AvisoDisponibilidad(plantilla: plantilla, usado: usado),
        if (dueno) ...[
          const SizedBox(height: 16),
          _CostosDueno(lineas: lineas, dias: dias, plantilla: plantilla),
        ],
      ],
    );
  }
}

class _TablaEstimadoUsado extends ConsumerWidget {
  const _TablaEstimadoUsado({
    required this.comparaciones,
    required this.conEstimado,
  });

  final List<Comparacion> comparaciones;
  final bool conEstimado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final materiales = ref.watch(materialesProvider).value ?? const [];
    final porId = {for (final m in materiales) m.id: m};
    final estiloEncabezado = tema.textTheme.labelLarge;

    String cantidad(double c, String id) =>
        formatearCantidad(c, porId[id]?.unidad ?? Unidad.pza);

    Widget celda(String texto, {Key? key, TextStyle? estilo}) => Expanded(
          child: Text(texto, key: key, style: estilo, textAlign: TextAlign.end),
        );

    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 2, child: Text('Material', style: estiloEncabezado)),
            if (conEstimado)
              celda('Estimado', estilo: estiloEncabezado),
            celda('Usado', estilo: estiloEncabezado),
          ],
        ),
        for (final c in comparaciones)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(porId[c.materialId]?.nombre ??
                      'Material desconocido'),
                ),
                if (conEstimado)
                  celda(
                    c.estimado == 0 ? '—' : cantidad(c.estimado, c.materialId),
                    key: Key('estimado-${c.materialId}'),
                  ),
                celda(
                  cantidad(c.usado, c.materialId),
                  key: Key('usado-${c.materialId}'),
                  estilo: (conEstimado && c.excedido)
                      ? TextStyle(color: tema.colorScheme.error)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Solo se construye para el dueño: consulta costos y sueldos, que el
/// empleado no puede leer.
class _CostosDueno extends ConsumerWidget {
  const _CostosDueno({
    required this.lineas,
    required this.dias,
    required this.plantilla,
  });

  final List<LineaMaterial> lineas;
  final List<DiaTrabajado> dias;
  final Plantilla? plantilla;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final usuarios = ref.watch(usuariosProvider).value ?? const <Usuario>[];
    final diasLaborales = ref.watch(diasLaboralesProvider).value ?? 6;

    final costosMaterial = <String, double?>{};
    final costosRollo = <String, double?>{};
    for (final l in lineas) {
      if (l.delCliente) continue;
      final rollo = l.rolloId;
      if (rollo != null) {
        costosRollo[rollo] = ref.watch(costoRolloProvider(rollo)).value;
      } else {
        costosMaterial[l.materialId] =
            ref.watch(costoPromedioProvider(l.materialId)).value;
      }
    }
    final materiales = costoLineas(
      lineas,
      costoMaterial: (id) => costosMaterial[id],
      costoRollo: (id) => costosRollo[id],
    );

    final costosDia = <String, double?>{};
    for (final d in dias) {
      if (costosDia.containsKey(d.usuarioId)) continue;
      Usuario? u;
      for (final x in usuarios) {
        if (x.uid == d.usuarioId) u = x;
      }
      if (u == null) {
        costosDia[d.usuarioId] = null;
      } else if (u.rol == Rol.dueno) {
        costosDia[d.usuarioId] = 0;
      } else {
        costosDia[d.usuarioId] = costoPorDia(
          sueldoSemanal: ref.watch(sueldoProvider(u.uid)).value,
          diasLaborales: diasLaborales,
        );
      }
    }
    final manoObra = costoManoObra(dias, costoDiaDe: (id) => costosDia[id]);
    final real = materiales + manoObra;

    Costo? estimado;
    final p = plantilla;
    if (p != null) {
      final costosPlantilla = <String, double?>{
        for (final l in p.lineas)
          l.materialId: ref.watch(costoPromedioProvider(l.materialId)).value,
      };
      estimado = costoEstimado(p, costoMaterial: (id) => costosPlantilla[id]);
    }

    String texto(String etiqueta, Costo c) => '$etiqueta: '
        '${formatearDinero(c.monto)}${c.incompleto ? ' (incompleto)' : ''}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Costos', style: tema.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(texto('Materiales', materiales)),
            Text(texto('Mano de obra', manoObra)),
            Text(texto('Costo real', real),
                style: tema.textTheme.titleSmall),
            if (estimado != null) Text(texto('Estimado de plantilla', estimado)),
          ],
        ),
      ),
    );
  }
}
