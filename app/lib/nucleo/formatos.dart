import 'package:intl/intl.dart';

/// Formatea un monto en pesos mexicanos, p. ej. `$1,500.00`.
String formatearDinero(num monto) =>
    NumberFormat.currency(locale: 'es_MX', symbol: r'$').format(monto);

/// Formatea una fecha como `dd/MM/yyyy`.
String formatearFecha(DateTime f) => DateFormat('dd/MM/yyyy').format(f);
