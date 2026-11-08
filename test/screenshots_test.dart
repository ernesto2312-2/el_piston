// Genera capturas de todas las pantallas de El Pistón, incluidas las de detalle
// (orden desplegada y diálogos), sin emulador.
//
// Ejecutar desde la raíz del proyecto:
//   flutter test test/screenshots_test.dart
//
// Los PNG se guardan en la carpeta `screenshots/`.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:el_piston/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final GlobalKey _appKey = GlobalKey();

/// Carga Roboto desde el SDK de Flutter para que el texto se vea real
/// (si no, los tests dibujan cada letra como un bloque cuadrado).
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;

  final loader = FontLoader('Roboto');
  var found = false;
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final file = File('$root/bin/cache/artifacts/material_fonts/$name');
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      found = true;
    }
  }
  if (found) await loader.load();

  // Íconos de Material: sin esto se dibujan como cuadrados.
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await iconLoader.load();
  }
}

/// Datos de ejemplo para que las pantallas no salgan vacías.
Future<void> _seed() async {
  final db = Db.instance;

  await db.createClientWithVehicle(
    name: 'Carlos Pérez',
    phone: '5555 1234',
    address: 'Calle 12 #45, Pinar del Río',
    plate: 'P123456',
    brand: 'Chevrolet',
    model: 'Aveo',
    year: 2012,
    mileage: 148000,
  );
  await db.addVehicleToClient(
    clientId: 1,
    plate: 'P654321',
    brand: 'Lada',
    model: '2107',
    year: 1998,
    mileage: 210000,
  );
  await db.createClientWithVehicle(
    name: 'María González',
    phone: '5234 9876',
    address: 'Avenida Principal #8',
    plate: 'B445566',
    brand: 'Hyundai',
    model: 'Accent',
    year: 2016,
    mileage: 92000,
  );
  await db.createClientWithVehicle(
    name: 'Luis Rodríguez',
    phone: '5311 4455',
    plate: 'M778899',
    brand: 'Toyota',
    model: 'Corolla',
    year: 2008,
    mileage: 175000,
  );

  await db.add('parts', {
    'name': 'Pastillas de freno delanteras',
    'sku': 'FRN-001',
    'unit_price': 25.0,
    'stock': 8,
    'min_stock': 3,
  });
  await db.add('parts', {
    'name': 'Aceite 10W-40 (litro)',
    'sku': 'ACE-010',
    'unit_price': 6.5,
    'stock': 2,
    'min_stock': 5,
  });
  await db.add('parts', {
    'name': 'Filtro de aceite',
    'sku': 'FIL-204',
    'unit_price': 9.0,
    'stock': 12,
    'min_stock': 4,
  });
  await db.add('parts', {
    'name': 'Termostato',
    'sku': 'REF-033',
    'unit_price': 18.0,
    'stock': 1,
    'min_stock': 2,
  });

  final vehicles = await db.rows('SELECT id FROM vehicles ORDER BY id');
  final parts = await db.rows('SELECT id FROM parts ORDER BY id');
  int vid(int i) => (vehicles[i]['id'] as num).toInt();
  int pid(int i) => (parts[i]['id'] as num).toInt();

  final o1 = await db.createOrder(
    vehicleId: vid(0),
    mechanicId: 1,
    problem: 'Ruido en el tren delantero al frenar',
  );
  await db.changeOrderStatus(o1, 'En reparación');
  await db.addJob(
    orderId: o1,
    description: 'Cambio de pastillas de freno',
    hours: 1.5,
    unitPrice: 20.0,
  );
  await db.usePart(orderId: o1, partId: pid(0), quantity: 1);
  await db.addPayment(orderId: o1, amount: 20.0, method: 'Efectivo');

  final o2 = await db.createOrder(
    vehicleId: vid(2),
    mechanicId: 2,
    problem: 'El motor se calienta en el tráfico',
  );
  await db.changeOrderStatus(o2, 'En diagnóstico');
  await db.addJob(
    orderId: o2,
    description: 'Diagnóstico del sistema de enfriamiento',
    hours: 1.0,
    unitPrice: 15.0,
  );

  final o3 = await db.createOrder(
    vehicleId: vid(3),
    mechanicId: 1,
    problem: 'Cambio de aceite y filtro',
  );
  await db.changeOrderStatus(o3, 'Lista para entregar');
  await db.addJob(
    orderId: o3,
    description: 'Cambio de aceite',
    hours: 1.0,
    unitPrice: 10.0,
  );
  await db.usePart(orderId: o3, partId: pid(2), quantity: 1);
  await db.addPayment(orderId: o3, amount: 10.0, method: 'Efectivo');
}

/// Las pantallas cargan datos reales de SQLite (async real), así que se
/// alternan esperas reales con avances del reloj del test.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _openApp(WidgetTester tester) async {
  // 360 x 780 lógicos, como un teléfono Android, a 3x de densidad.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // Los tests dibujan las sombras como bloques negros sólidos; esto las
  // devuelve a la normalidad (y se restaura al final para no fallar).
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);

  await tester.pumpWidget(
    RepaintBoundary(key: _appKey, child: const ElPistonApp()),
  );
  await _settle(tester);
}

Future<void> _goTo(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    ),
  );
  await _settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _closeDialog(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(AlertDialog).first)).pop();
  await _settle(tester);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _appKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('screenshots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();

    // Base de datos aparte, para no mezclarse con la de widget_test.dart.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('el_piston_shots_');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);

    await Db.instance.init();
    await _seed();
  });

  testWidgets('01 Inicio', (tester) async {
    await _openApp(tester);
    await _shot(tester, '01_inicio');
  });

  testWidgets('02 Órdenes: lista, detalle y diálogos', (tester) async {
    await _openApp(tester);
    await _goTo(tester, 'Órdenes');
    await _shot(tester, '02_ordenes_lista');

    // Detalle: se despliega la primera orden.
    await tester.tap(find.textContaining('Orden #').first);
    await _settle(tester);
    await _shot(tester, '03_orden_detalle');

    await _tapText(tester, 'Mano de obra');
    await _shot(tester, '04_orden_dialogo_mano_de_obra');
    await _closeDialog(tester);

    await _tapText(tester, 'Repuesto');
    await _shot(tester, '05_orden_dialogo_repuesto');
    await _closeDialog(tester);

    await _tapText(tester, 'Pago');
    await _shot(tester, '06_orden_dialogo_pago');
    await _closeDialog(tester);

    await _tapText(tester, 'Nueva orden');
    await _shot(tester, '07_orden_dialogo_nueva');
    await _closeDialog(tester);
  });

  testWidgets('03 Clientes: lista y diálogos', (tester) async {
    await _openApp(tester);
    await _goTo(tester, 'Clientes');
    await _shot(tester, '08_clientes_lista');

    await _tapText(tester, 'Añadir vehículo');
    await _shot(tester, '09_clientes_dialogo_vehiculo');
    await _closeDialog(tester);

    await _tapText(tester, 'Nuevo cliente');
    await _shot(tester, '10_clientes_dialogo_nuevo');
    await _closeDialog(tester);
  });

  testWidgets('04 Inventario: lista y diálogo', (tester) async {
    await _openApp(tester);
    await _goTo(tester, 'Inventario');
    await _shot(tester, '11_inventario_lista');

    await _tapText(tester, 'Nuevo repuesto');
    await _shot(tester, '12_inventario_dialogo_nuevo');
    await _closeDialog(tester);
  });
}
