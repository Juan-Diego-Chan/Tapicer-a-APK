import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_privado.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioPrivado repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioPrivado(db);
  });

  test('sin doc, los días laborales son 6', () async {
    expect(await repo.observarDiasLaborales().first, 6);
  });

  test('fijarDiasLaborales(5) emite 5', () async {
    await repo.fijarDiasLaborales(5);
    expect(await repo.observarDiasLaborales().first, 5);
  });

  test('fijarSueldo guarda y observarSueldo emite', () async {
    await repo.fijarSueldo('u1', 2100);
    expect(await repo.observarSueldo('u1').first, 2100);
  });

  test('sin doc, observarSueldo emite null', () async {
    expect(await repo.observarSueldo('nadie').first, isNull);
  });
}
