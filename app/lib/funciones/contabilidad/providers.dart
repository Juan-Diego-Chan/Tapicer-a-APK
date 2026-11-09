import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/repositorio_contabilidad.dart';
import '../../dominio/contabilidad.dart';
import '../auth/providers.dart';
import '../pedidos/providers.dart';
import 'armar_resumen.dart';

final repositorioContabilidadProvider = Provider<RepositorioContabilidad>(
  (ref) => RepositorioContabilidad(ref.watch(firestoreProvider)),
);

final resumenProvider = FutureProvider.autoDispose
    .family<ResumenPeriodo, Periodo>((ref, periodo) async {
      final plantillas = await ref.watch(plantillasProvider.future);
      return armarResumen(
        ref.watch(repositorioContabilidadProvider),
        periodo: periodo,
        plantillas: plantillas,
      );
    });

class PeriodoNotifier extends Notifier<Periodo> {
  @override
  Periodo build() => Periodo.semana(DateTime.now());

  void cambiar(Periodo p) => state = p;
}

final periodoProvider = NotifierProvider<PeriodoNotifier, Periodo>(
  PeriodoNotifier.new,
);
