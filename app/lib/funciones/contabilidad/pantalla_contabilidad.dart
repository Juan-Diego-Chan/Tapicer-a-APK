import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/contabilidad.dart';
import '../../dominio/inventario.dart';
import '../../dominio/pedidos.dart';
import '../../nucleo/formatos.dart';
import '../dinero/providers.dart';
import '../inventario/pantalla_inventario.dart' show esDueno;
import '../inventario/providers.dart';
import '../usuarios/providers.dart';
import 'armar_resumen.dart';
import 'providers.dart';

/// Solo para el dueño: cobros, gastos, ganancias y pendientes de un periodo.
class PantallaContabilidad extends ConsumerWidget {
  const PantallaContabilidad({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Un no dueño que llegue aquí no ve nada ni lee nada.
    if (!esDueno(ref)) return const Scaffold();
    final periodo = ref.watch(periodoProvider);
    final resumen = ref.watch(resumenProvider(periodo));
    return Scaffold(
      appBar: AppBar(title: const Text('Contabilidad')),
      body: Column(
        children: [
          _SelectorPeriodo(periodo: periodo),
          Expanded(
            child: resumen.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudo cargar el resumen'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref.invalidate(resumenProvider(periodo)),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
              data: (r) => _Contenido(resumen: r),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectorPeriodo extends ConsumerWidget {
  const _SelectorPeriodo({required this.periodo});

  final Periodo periodo;

  DateTime get _ultimoDia =>
      DateTime(periodo.hasta.year, periodo.hasta.month, periodo.hasta.day - 1);

  Future<void> _elegirRango(BuildContext context, WidgetRef ref) async {
    final hoy = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(hoy.year, hoy.month, hoy.day + 1),
      initialDateRange: DateTimeRange(
        start: periodo.desde,
        end: _ultimoDia,
      ),
    );
    if (r == null) return;
    ref.read(periodoProvider.notifier).cambiar(Periodo.rango(r.start, r.end));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(periodoProvider.notifier);
    final navegable = periodo.tipo != TipoPeriodo.rango;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          SegmentedButton<TipoPeriodo>(
            segments: const [
              ButtonSegment(value: TipoPeriodo.semana, label: Text('Semana')),
              ButtonSegment(value: TipoPeriodo.mes, label: Text('Mes')),
              ButtonSegment(value: TipoPeriodo.rango, label: Text('Rango')),
            ],
            selected: {periodo.tipo},
            onSelectionChanged: (s) {
              switch (s.first) {
                case TipoPeriodo.semana:
                  notifier.cambiar(Periodo.semana(_ultimoDia));
                case TipoPeriodo.mes:
                  notifier.cambiar(Periodo.mes(_ultimoDia));
                case TipoPeriodo.rango:
                  _elegirRango(context, ref);
              }
            },
          ),
          Row(
            children: [
              if (!navegable)
                IconButton(
                  tooltip: 'Cambiar rango',
                  icon: const Icon(Icons.date_range),
                  onPressed: () => _elegirRango(context, ref),
                ),
              if (navegable)
                IconButton(
                  tooltip: 'Periodo anterior',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => notifier.cambiar(periodo.anterior()),
                ),
              Expanded(
                child: Text(
                  periodo.etiqueta,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (navegable)
                IconButton(
                  tooltip: 'Periodo siguiente',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => notifier.cambiar(periodo.siguiente()),
                ),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(resumenProvider(periodo)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.resumen});

  final ResumenPeriodo resumen;

  /// Folio conocido por los datos ya cargados; si no, el prefijo del id.
  String _folio(String pedidoId) {
    final r = resumen;
    final conocido = r.pedidosDeCobros[pedidoId] ??
        r.ganancias
            .where((g) => g.pedido.id == pedidoId)
            .map((g) => g.pedido)
            .firstOrNull ??
        r.pendientes
            .where((p) => p.pedido.id == pedidoId)
            .map((p) => p.pedido)
            .firstOrNull;
    if (conocido != null) return conocido.folio;
    final prefijo = pedidoId.length < 4 ? pedidoId : pedidoId.substring(0, 4);
    return prefijo.toUpperCase();
  }

  String _concepto(CambioPrecio c) {
    if (c.campo == CampoPrecio.envio) return 'Envío';
    final prefijo = switch (c.campo) {
      CampoPrecio.alta => 'Mueble agregado: ',
      CampoPrecio.cancelacion => 'Mueble cancelado: ',
      _ => 'Precio de ',
    };
    for (final g in resumen.ganancias.expand((g) => g.muebles)) {
      if (g.mueble.id == c.muebleId) return '$prefijo${g.mueble.tipoMueble}';
    }
    return switch (c.campo) {
      CampoPrecio.alta => 'Mueble agregado',
      CampoPrecio.cancelacion => 'Mueble cancelado',
      _ => 'Precio de mueble',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final r = resumen;
    final usuarios = ref.watch(usuariosProvider).value ?? const [];
    final materiales = ref.watch(materialesProvider).value ?? const [];
    final cajas = ref.watch(cajasProvider).value ?? const <String, double>{};
    final pendientesEntrega =
        ref.watch(entregasPendientesProvider).value ?? const [];

    String nombre(String uid) =>
        usuarios.where((u) => u.uid == uid).firstOrNull?.nombre ??
        'Usuario desconocido';

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 4),
          child: Text(t, style: tema.textTheme.titleMedium),
        );
    Widget subtitulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(t, style: tema.textTheme.labelLarge),
        );

    final cajasConDinero = cajas.entries.where((e) => e.value != 0).toList();
    final porConfirmar =
        pendientesEntrega.fold<double>(0, (s, e) => s + e.monto);
    final formas = r.cobros.porForma.entries.where((e) => e.value != 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        titulo('Lo cobrado'),
        if (r.cobros.porPedido.isEmpty && r.cobros.total == 0)
          const Text('Sin cobros en el periodo')
        else ...[
          Text('Total: ${formatearDinero(r.cobros.total)}'),
          for (final e in formas)
            Text('${e.key.etiqueta}: ${formatearDinero(e.value)}'),
          subtitulo('Por quién'),
          for (final e in r.cobros.porUsuario.entries)
            Text('${nombre(e.key)}: ${formatearDinero(e.value)}'),
          subtitulo('Por pedido'),
          for (final e in r.cobros.porPedido.entries)
            Text('${_folio(e.key)}: ${formatearDinero(e.value)}'),
        ],
        titulo('Por entregar'),
        if (cajasConDinero.isEmpty && pendientesEntrega.isEmpty)
          const Text('Nadie tiene dinero por entregar')
        else ...[
          for (final e in cajasConDinero)
            Text('${nombre(e.key)}: ${formatearDinero(e.value)}'),
          if (pendientesEntrega.isNotEmpty)
            Text('Entregas por confirmar: ${formatearDinero(porConfirmar)}'),
        ],
        titulo('Lo gastado'),
        Text('Compras de material: ${formatearDinero(r.gastos.compras)}'),
        Text('Sueldos: ${formatearDinero(r.gastos.sueldos)}'),
        Text('Total: ${formatearDinero(r.gastos.total)}'),
        titulo('Ganancia'),
        if (r.ganancias.isEmpty)
          const Text('Ningún pedido entregado en el periodo')
        else ...[
          Text('Ganancia total: ${formatearDinero(r.gananciaTotal)} '
              '(${r.ganancias.length} pedidos entregados)'),
          for (final tipo in TipoTrabajo.values)
            if ((r.muebles[tipo] ?? const []).isNotEmpty) ...[
              subtitulo(tipo.etiqueta),
              for (final g in r.muebles[tipo]!) _FilaMueble(g: g),
            ],
          subtitulo('Pedidos'),
          for (final g in r.ganancias)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${g.pedido.folio} · ${g.pedido.cliente.nombre}'),
              subtitle: g.incompleto ? const Text('Costo incompleto') : null,
              trailing: Text(
                formatearDinero(g.ganancia),
                style: g.ganancia < 0
                    ? TextStyle(color: tema.colorScheme.error)
                    : null,
              ),
            ),
        ],
        titulo('Cambios de precio'),
        if (r.cambios.isEmpty)
          const Text('Sin cambios de precio en el periodo')
        else
          for (final c in r.cambios)
            Text(
              '${_folio(c.pedidoId)} · ${_concepto(c.cambio)}: '
              '${formatearDinero(c.cambio.anterior)} → '
              '${formatearDinero(c.cambio.nuevo)}',
              style: c.cambio.nuevo < c.cambio.anterior
                  ? TextStyle(color: tema.colorScheme.error)
                  : null,
            ),
        titulo('Pendientes de cobro'),
        if (r.pendientes.isEmpty)
          const Text('Nada pendiente de cobro')
        else
          for (final p in r.pendientes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${p.pedido.folio} · ${p.pedido.cliente.nombre}'),
              subtitle: Text('Saldo: ${formatearDinero(p.saldo)}'),
              onTap: () => context.push('/pedidos/${p.pedido.id}'),
            ),
        titulo('Diferencias de material'),
        if (r.diferencias.isEmpty)
          const Text('Sin diferencias notables')
        else
          for (final d in r.diferencias)
            _FilaDiferencia(d: d, materiales: materiales),
      ],
    );
  }
}

class _FilaMueble extends StatelessWidget {
  const _FilaMueble({required this.g});

  final GananciaMueble g;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final margen = g.margen;
    final texto = margen == null
        ? formatearDinero(g.ganancia)
        : '${formatearDinero(g.ganancia)} '
            '(${(margen * 100).toStringAsFixed(1)}%)';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${g.mueble.tipoMueble} · ${g.pedido.folio}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Precio ${formatearDinero(g.mueble.precio)} · '
              'Materiales ${formatearDinero(g.materiales.monto)} · '
              'Mano de obra ${formatearDinero(g.manoObra.monto)}'),
          if (g.incompleto) const Text('Costo incompleto'),
        ],
      ),
      trailing: Text(
        texto,
        style: g.ganancia < 0 ? TextStyle(color: tema.colorScheme.error) : null,
      ),
    );
  }
}

class _FilaDiferencia extends StatelessWidget {
  const _FilaDiferencia({required this.d, required this.materiales});

  final DiferenciaMaterial d;
  final List<Material> materiales;

  @override
  Widget build(BuildContext context) {
    final m =
        materiales.where((x) => x.id == d.comparacion.materialId).firstOrNull;
    String cant(double c) => m == null ? '$c' : formatearCantidad(c, m.unidad);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${d.pedido.folio} · ${d.mueble.tipoMueble}'),
      subtitle: Text('${m?.nombre ?? 'Material desconocido'}: '
          'estimado ${cant(d.comparacion.estimado)}, '
          'usado ${cant(d.comparacion.usado)}'),
    );
  }
}
