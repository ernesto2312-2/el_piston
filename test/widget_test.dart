import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:el_piston/main.dart';

void main() {
  // Inicializa SQLite FFI para que las pruebas funcionen en Windows/Linux/macOS.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await Db.instance.init();
  });

  testWidgets('La aplicación inicia y permite navegar entre secciones',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ElPistonApp());

    expect(find.text('EL PISTÓN'), findsOneWidget);
    expect(find.byType(Dashboard), findsOneWidget);

    await tester.tap(find.text('Órdenes'));
    await tester.pump();
    expect(find.byType(OrdersPage), findsOneWidget);

    await tester.tap(find.text('Clientes'));
    await tester.pump();
    expect(find.byType(ClientsPage), findsOneWidget);

    await tester.tap(find.text('Inventario'));
    await tester.pump();
    expect(find.byType(InventoryPage), findsOneWidget);
  });
}
