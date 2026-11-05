import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.instance.init();
  runApp(const ElPistonApp());
}

// -----------------------------------------------------------------------------
// BASE DE DATOS
// -----------------------------------------------------------------------------

class Db {
  Db._();

  static final Db instance = Db._();
  Database? _database;

  Database get db {
    final database = _database;
    if (database == null || !database.isOpen) {
      throw StateError('La base de datos todavía no está inicializada.');
    }
    return database;
  }

  Future<void> init() async {
    if (_database != null && _database!.isOpen) return;

    final databasesPath = await getDatabasesPath();
    final databasePath = p.join(databasesPath, 'el_piston.db');

    _database = await openDatabase(
      databasePath,
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            address TEXT
          )
        ''');

        await database.execute('''
          CREATE TABLE vehicles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id INTEGER NOT NULL,
            plate TEXT NOT NULL UNIQUE,
            brand TEXT NOT NULL,
            model TEXT NOT NULL,
            year INTEGER NOT NULL,
            mileage INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE
          )
        ''');

        await database.execute('''
          CREATE TABLE mechanics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
          )
        ''');

        await database.execute('''
          CREATE TABLE parts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sku TEXT,
            unit_price REAL NOT NULL DEFAULT 0,
            stock INTEGER NOT NULL DEFAULT 0,
            min_stock INTEGER NOT NULL DEFAULT 1
          )
        ''');

        await database.execute('''
          CREATE TABLE orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            vehicle_id INTEGER NOT NULL,
            mechanic_id INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            problem TEXT NOT NULL,
            status TEXT NOT NULL,
            FOREIGN KEY (vehicle_id) REFERENCES vehicles(id),
            FOREIGN KEY (mechanic_id) REFERENCES mechanics(id)
          )
        ''');

        await database.execute('''
          CREATE TABLE jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL,
            description TEXT NOT NULL,
            hours REAL NOT NULL,
            unit_price REAL NOT NULL,
            FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
          )
        ''');

        await database.execute('''
          CREATE TABLE order_parts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL,
            part_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            unit_price REAL NOT NULL,
            FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
            FOREIGN KEY (part_id) REFERENCES parts(id)
          )
        ''');

        await database.execute('''
          CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            paid_at TEXT NOT NULL,
            method TEXT NOT NULL,
            FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
          )
        ''');
      },
    );

    final mechanics = await db.query('mechanics');
    if (mechanics.isEmpty) {
      await db.insert('mechanics', {'name': 'Mecánico 1'});
      await db.insert('mechanics', {'name': 'Mecánico 2'});
    }
  }

  Future<List<Map<String, Object?>>> rows(
      String sql, [
        List<Object?> arguments = const [],
      ]) {
    return db.rawQuery(sql, arguments);
  }

  Future<int> add(String table, Map<String, Object?> values) {
    return db.insert(table, values);
  }

  Future<int> update(
      String table,
      Map<String, Object?> values,
      String where,
      List<Object?> whereArgs,
      ) {
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
      String table,
      String where,
      List<Object?> whereArgs,
      ) {
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> createClientWithVehicle({
    required String name,
    required String phone,
    String? address,
    required String plate,
    required String brand,
    required String model,
    required int year,
    required int mileage,
  }) async {
    await db.transaction((txn) async {
      final clientId = await txn.insert('clients', {
        'name': name.trim(),
        'phone': phone.trim(),
        'address': address?.trim().isEmpty == true ? null : address?.trim(),
      });

      await txn.insert('vehicles', {
        'client_id': clientId,
        'plate': plate.trim().toUpperCase(),
        'brand': brand.trim(),
        'model': model.trim(),
        'year': year,
        'mileage': mileage,
      });
    });
  }

  Future<void> addVehicleToClient({
    required int clientId,
    required String plate,
    required String brand,
    required String model,
    required int year,
    required int mileage,
  }) async {
    await add('vehicles', {
      'client_id': clientId,
      'plate': plate.trim().toUpperCase(),
      'brand': brand.trim(),
      'model': model.trim(),
      'year': year,
      'mileage': mileage,
    });
  }

  Future<List<Map<String, Object?>>> listClients() {
    return rows('''
      SELECT c.id, c.name, c.phone, c.address,
        COUNT(v.id) AS vehicle_count,
        GROUP_CONCAT(v.plate || ' - ' || v.brand || ' ' || v.model, '\n') AS vehicles
      FROM clients c
      LEFT JOIN vehicles v ON v.client_id = c.id
      GROUP BY c.id
      ORDER BY c.name COLLATE NOCASE
    ''');
  }

  Future<List<Map<String, Object?>>> listVehicles() {
    return rows('''
      SELECT v.*, c.name AS client_name
      FROM vehicles v
      INNER JOIN clients c ON c.id = v.client_id
      ORDER BY v.plate
    ''');
  }

  Future<List<Map<String, Object?>>> listMechanics() {
    return db.query('mechanics', orderBy: 'name');
  }

  Future<List<Map<String, Object?>>> listParts() {
    return db.query('parts', orderBy: 'name');
  }

  Future<List<Map<String, Object?>>> listOrders() {
    return rows('''
      SELECT
        o.id, o.vehicle_id, o.mechanic_id, o.created_at, o.problem, o.status,
        v.plate, v.brand, v.model, c.name AS client_name,
        m.name AS mechanic_name,
        COALESCE((SELECT SUM(j.hours * j.unit_price)
          FROM jobs j WHERE j.order_id = o.id), 0)
        + COALESCE((SELECT SUM(op.quantity * op.unit_price)
          FROM order_parts op WHERE op.order_id = o.id), 0) AS total,
        COALESCE((SELECT SUM(pay.amount)
          FROM payments pay WHERE pay.order_id = o.id), 0) AS paid
      FROM orders o
      INNER JOIN vehicles v ON v.id = o.vehicle_id
      INNER JOIN clients c ON c.id = v.client_id
      INNER JOIN mechanics m ON m.id = o.mechanic_id
      ORDER BY o.id DESC
    ''');
  }

  Future<int> createOrder({
    required int vehicleId,
    required int mechanicId,
    required String problem,
  }) {
    return add('orders', {
      'vehicle_id': vehicleId,
      'mechanic_id': mechanicId,
      'created_at': DateTime.now().toIso8601String(),
      'problem': problem.trim(),
      'status': 'Recibida',
    });
  }

  Future<void> changeOrderStatus(int orderId, String status) async {
    await update('orders', {'status': status}, 'id = ?', [orderId]);
  }

  Future<void> addJob({
    required int orderId,
    required String description,
    required double hours,
    required double unitPrice,
  }) async {
    await add('jobs', {
      'order_id': orderId,
      'description': description.trim(),
      'hours': hours,
      'unit_price': unitPrice,
    });
  }

  Future<void> usePart({
    required int orderId,
    required int partId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('La cantidad debe ser mayor que cero.');
    }

    await db.transaction((txn) async {
      final result = await txn.query(
        'parts',
        where: 'id = ?',
        whereArgs: [partId],
        limit: 1,
      );

      if (result.isEmpty) {
        throw StateError('El repuesto no existe.');
      }

      final part = result.first;
      final stock = (part['stock'] as num).toInt();

      if (stock < quantity) {
        throw StateError('Stock insuficiente. Disponible: $stock.');
      }

      await txn.insert('order_parts', {
        'order_id': orderId,
        'part_id': partId,
        'quantity': quantity,
        'unit_price': (part['unit_price'] as num).toDouble(),
      });

      await txn.update(
        'parts',
        {'stock': stock - quantity},
        where: 'id = ?',
        whereArgs: [partId],
      );
    });
  }

  Future<void> addPayment({
    required int orderId,
    required double amount,
    required String method,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('El pago debe ser mayor que cero.');
    }

    final orderRows = await rows('''
      SELECT
        COALESCE((SELECT SUM(j.hours * j.unit_price) FROM jobs j WHERE j.order_id = ?), 0)
        + COALESCE((SELECT SUM(op.quantity * op.unit_price) FROM order_parts op WHERE op.order_id = ?), 0)
        AS total,
        COALESCE((SELECT SUM(pay.amount) FROM payments pay WHERE pay.order_id = ?), 0)
        AS paid
    ''', [orderId, orderId, orderId]);

    if (orderRows.isEmpty) {
      throw StateError('La orden no existe.');
    }

    final total = (orderRows.first['total'] as num).toDouble();
    final paid = (orderRows.first['paid'] as num).toDouble();

    if (amount > total - paid + 0.0001) {
      throw StateError('El pago supera el saldo pendiente.');
    }

    await add('payments', {
      'order_id': orderId,
      'amount': amount,
      'paid_at': DateTime.now().toIso8601String(),
      'method': method,
    });
  }

  Future<Map<String, int>> dashboardCounts() async {
    final clients = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM clients'),
    ) ??
        0;

    final openOrders = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM orders WHERE status NOT IN ('Entregada', 'Cancelada')",
      ),
    ) ??
        0;

    final lowStock = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM parts WHERE stock <= min_stock'),
    ) ??
        0;

    final vehicles = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM vehicles'),
    ) ??
        0;

    return {
      'clients': clients,
      'openOrders': openOrders,
      'lowStock': lowStock,
      'vehicles': vehicles,
    };
  }
}

// -----------------------------------------------------------------------------
// APLICACIÓN Y NAVEGACIÓN
// -----------------------------------------------------------------------------

class ElPistonApp extends StatelessWidget {
  const ElPistonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'El Pistón',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB3261E),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int selectedIndex = 0;

  static const pages = <Widget>[
    Dashboard(),
    OrdersPage(),
    ClientsPage(),
    InventoryPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'EL PISTÓN',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: pages[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          setState(() => selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Órdenes',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// INICIO / RESUMEN
// -----------------------------------------------------------------------------

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late Future<Map<String, int>> future;

  @override
  void initState() {
    super.initState();
    future = Db.instance.dashboardCounts();
  }

  Future<void> refresh() async {
    setState(() => future = Db.instance.dashboardCounts());
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Resumen del taller',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, int>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorMessage(
                  message: 'No se pudo cargar el resumen: ${snapshot.error}',
                );
              }

              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final data = snapshot.data!;

              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _StatCard(
                    title: 'Órdenes abiertas',
                    value: '${data['openOrders']}',
                    icon: Icons.build,
                  ),
                  _StatCard(
                    title: 'Clientes',
                    value: '${data['clients']}',
                    icon: Icons.people,
                  ),
                  _StatCard(
                    title: 'Vehículos',
                    value: '${data['vehicles']}',
                    icon: Icons.directions_car,
                  ),
                  _StatCard(
                    title: 'Repuestos con stock bajo',
                    value: '${data['lowStock']}',
                    icon: Icons.warning_amber,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'El Pistón permite registrar clientes, vehículos, órdenes de trabajo, mano de obra, repuestos y pagos. Los datos se guardan localmente en SQLite.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 25),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ÓRDENES DE TRABAJO
// -----------------------------------------------------------------------------

const orderStatuses = <String>[
  'Recibida',
  'En diagnóstico',
  'En reparación',
  'Lista para entregar',
  'Entregada',
  'Cancelada',
];

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late Future<List<Map<String, Object?>>> future;

  @override
  void initState() {
    super.initState();
    future = Db.instance.listOrders();
  }

  void reload() {
    setState(() => future = Db.instance.listOrders());
  }

  Future<void> create() async {
    final vehicles = await Db.instance.listVehicles();
    final mechanics = await Db.instance.listMechanics();

    if (!mounted) return;

    if (vehicles.isEmpty || mechanics.isEmpty) {
      _showMessage(context, 'Primero registra un cliente y su vehículo.');
      return;
    }

    int selectedVehicle = (vehicles.first['id'] as num).toInt();
    int selectedMechanic = (mechanics.first['id'] as num).toInt();
    final problemController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nueva orden'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedVehicle,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Vehículo',
                      ),
                      items: vehicles.map((vehicle) {
                        final id = (vehicle['id'] as num).toInt();

                        return DropdownMenuItem(
                          value: id,
                          child: Text(
                            '${vehicle['plate']} - ${vehicle['brand']} ${vehicle['model']}',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedVehicle = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedMechanic,
                      decoration: const InputDecoration(
                        labelText: 'Mecánico',
                      ),
                      items: mechanics.map((mechanic) {
                        final id = (mechanic['id'] as num).toInt();

                        return DropdownMenuItem(
                          value: id,
                          child: Text('${mechanic['name']}'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedMechanic = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: problemController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Problema informado',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (problemController.text.trim().isEmpty) {
                      _showMessage(
                        context,
                        'Describe el problema del vehículo.',
                      );
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      try {
        await Db.instance.createOrder(
          vehicleId: selectedVehicle,
          mechanicId: selectedMechanic,
          problem: problemController.text,
        );
        reload();
      } catch (error) {
        if (mounted) {
          _showMessage(context, 'No se pudo crear la orden: $error');
        }
      }
    }

    problemController.dispose();
  }

  Future<void> changeStatus(int orderId, String status) async {
    try {
      await Db.instance.changeOrderStatus(orderId, status);
      reload();
    } catch (error) {
      if (mounted) {
        _showMessage(context, 'No se pudo cambiar el estado: $error');
      }
    }
  }

  Future<void> addLabor(int orderId) async {
    final description = TextEditingController();
    final hours = TextEditingController(text: '1');
    final price = TextEditingController();

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Añadir mano de obra'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hours,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Horas',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio por hora',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (save == true) {
      final parsedHours = double.tryParse(
        hours.text.replaceAll(',', '.'),
      );
      final parsedPrice = double.tryParse(
        price.text.replaceAll(',', '.'),
      );

      if (description.text.trim().isEmpty ||
          parsedHours == null ||
          parsedHours <= 0 ||
          parsedPrice == null ||
          parsedPrice < 0) {
        if (mounted) {
          _showMessage(
            context,
            'Comprueba la descripción, las horas y el precio.',
          );
        }
      } else {
        try {
          await Db.instance.addJob(
            orderId: orderId,
            description: description.text,
            hours: parsedHours,
            unitPrice: parsedPrice,
          );
          reload();
        } catch (error) {
          if (mounted) {
            _showMessage(
              context,
              'No se pudo guardar la mano de obra: $error',
            );
          }
        }
      }
    }

    description.dispose();
    hours.dispose();
    price.dispose();
  }

  Future<void> addPartToOrder(int orderId) async {
    final parts = await Db.instance.listParts();

    if (!mounted) return;

    if (parts.isEmpty) {
      _showMessage(
        context,
        'No hay repuestos registrados en el inventario.',
      );
      return;
    }

    int selectedPart = (parts.first['id'] as num).toInt();
    final quantity = TextEditingController(text: '1');

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Consumir repuesto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: selectedPart,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Repuesto',
                ),
                items: parts.map((part) {
                  final id = (part['id'] as num).toInt();

                  return DropdownMenuItem(
                    value: id,
                    child: Text(
                      '${part['name']} (stock: ${part['stock']})',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedPart = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Consumir'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      final amount = int.tryParse(quantity.text);

      if (amount == null || amount <= 0) {
        if (mounted) {
          _showMessage(context, 'Introduce una cantidad válida.');
        }
      } else {
        try {
          await Db.instance.usePart(
            orderId: orderId,
            partId: selectedPart,
            quantity: amount,
          );
          reload();
        } catch (error) {
          if (mounted) {
            _showMessage(context, '$error');
          }
        }
      }
    }

    quantity.dispose();
  }

  Future<void> addPaymentToOrder(int orderId, double balance) async {
    final amount = TextEditingController(
      text: balance > 0 ? balance.toStringAsFixed(2) : '',
    );

    String method = 'Efectivo';

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar pago'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Importe',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: method,
                decoration: const InputDecoration(
                  labelText: 'Método de pago',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Efectivo',
                    child: Text('Efectivo'),
                  ),
                  DropdownMenuItem(
                    value: 'Transferencia',
                    child: Text('Transferencia'),
                  ),
                  DropdownMenuItem(
                    value: 'Otro',
                    child: Text('Otro'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => method = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      final parsedAmount = double.tryParse(
        amount.text.replaceAll(',', '.'),
      );

      if (parsedAmount == null || parsedAmount <= 0) {
        if (mounted) {
          _showMessage(context, 'Introduce un importe válido.');
        }
      } else {
        try {
          await Db.instance.addPayment(
            orderId: orderId,
            amount: parsedAmount,
            method: method,
          );
          reload();
        } catch (error) {
          if (mounted) {
            _showMessage(context, '$error');
          }
        }
      }
    }

    amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.add),
        label: const Text('Nueva orden'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorMessage(
              message: 'Error al cargar las órdenes: ${snapshot.error}',
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final orders = snapshot.data!;

          if (orders.isEmpty) {
            return const _EmptyMessage(
              icon: Icons.receipt_long,
              message: 'Todavía no hay órdenes de trabajo.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final id = (order['id'] as num).toInt();
              final total = (order['total'] as num).toDouble();
              final paid = (order['paid'] as num).toDouble();
              final balance = (total - paid)
                  .clamp(0.0, double.infinity)
                  .toDouble();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  key: ValueKey('order-$id'),
                  title: Text('Orden #$id · ${order['plate']}'),
                  subtitle: Text(
                    '${order['brand']} ${order['model']} · ${order['client_name']}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    16,
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Problema: ${order['problem']}'),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Mecánico: ${order['mechanic_name']}',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: orderStatuses.contains(order['status'])
                          ? order['status'] as String
                          : orderStatuses.first,
                      decoration: const InputDecoration(
                        labelText: 'Estado de la orden',
                      ),
                      items: orderStatuses.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        );
                      }).toList(),
                      onChanged: (status) {
                        if (status != null) {
                          changeStatus(id, status);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total: ${total.toStringAsFixed(2)}'),
                        Text('Pagado: ${paid.toStringAsFixed(2)}'),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Saldo: ${balance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => addLabor(id),
                          icon: const Icon(Icons.handyman_outlined),
                          label: const Text('Mano de obra'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => addPartToOrder(id),
                          icon: const Icon(Icons.build_circle_outlined),
                          label: const Text('Repuesto'),
                        ),
                        OutlinedButton.icon(
                          onPressed: balance > 0
                              ? () => addPaymentToOrder(id, balance)
                              : null,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Pago'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CLIENTES Y VEHÍCULOS
// -----------------------------------------------------------------------------

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  late Future<List<Map<String, Object?>>> future;

  @override
  void initState() {
    super.initState();
    future = Db.instance.listClients();
  }

  void reload() {
    setState(() => future = Db.instance.listClients());
  }

  Future<void> createClient() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final plate = TextEditingController();
    final brand = TextEditingController();
    final model = TextEditingController();
    final year = TextEditingController(
      text: '${DateTime.now().year}',
    );
    final mileage = TextEditingController(text: '0');

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo cliente y vehículo'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del cliente',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(
                    labelText: 'Dirección (opcional)',
                  ),
                ),
                const Divider(height: 24),
                TextField(
                  controller: plate,
                  decoration: const InputDecoration(
                    labelText: 'Matrícula',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: brand,
                  decoration: const InputDecoration(
                    labelText: 'Marca',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(
                    labelText: 'Modelo',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Año',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: mileage,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Kilometraje',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (save == true) {
      final parsedYear = int.tryParse(year.text);
      final parsedMileage = int.tryParse(mileage.text);

      if (name.text.trim().isEmpty ||
          phone.text.trim().isEmpty ||
          plate.text.trim().isEmpty ||
          brand.text.trim().isEmpty ||
          model.text.trim().isEmpty ||
          parsedYear == null ||
          parsedMileage == null ||
          parsedMileage < 0) {
        if (mounted) {
          _showMessage(
            context,
            'Completa los campos obligatorios con valores válidos.',
          );
        }
      } else {
        try {
          await Db.instance.createClientWithVehicle(
            name: name.text,
            phone: phone.text,
            address: address.text,
            plate: plate.text,
            brand: brand.text,
            model: model.text,
            year: parsedYear,
            mileage: parsedMileage,
          );
          reload();
        } catch (error) {
          if (mounted) {
            _showMessage(
              context,
              'No se pudo guardar el cliente: $error',
            );
          }
        }
      }
    }

    name.dispose();
    phone.dispose();
    address.dispose();
    plate.dispose();
    brand.dispose();
    model.dispose();
    year.dispose();
    mileage.dispose();
  }

  Future<void> addVehicle(int clientId, String clientName) async {
    final plate = TextEditingController();
    final brand = TextEditingController();
    final model = TextEditingController();
    final year = TextEditingController(
      text: '${DateTime.now().year}',
    );
    final mileage = TextEditingController(text: '0');

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Añadir vehículo · $clientName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: plate,
                decoration: const InputDecoration(
                  labelText: 'Matrícula',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: brand,
                decoration: const InputDecoration(
                  labelText: 'Marca',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: model,
                decoration: const InputDecoration(
                  labelText: 'Modelo',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Año',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: mileage,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kilometraje',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (save == true) {
      final parsedYear = int.tryParse(year.text);
      final parsedMileage = int.tryParse(mileage.text);

      if (plate.text.trim().isEmpty ||
          brand.text.trim().isEmpty ||
          model.text.trim().isEmpty ||
          parsedYear == null ||
          parsedMileage == null ||
          parsedMileage < 0) {
        if (mounted) {
          _showMessage(
            context,
            'Completa los campos del vehículo correctamente.',
          );
        }
      } else {
        try {
          await Db.instance.addVehicleToClient(
            clientId: clientId,
            plate: plate.text,
            brand: brand.text,
            model: model.text,
            year: parsedYear,
            mileage: parsedMileage,
          );
          reload();
        } catch (error) {
          if (mounted) {
            _showMessage(
              context,
              'No se pudo añadir el vehículo: $error',
            );
          }
        }
      }
    }

    plate.dispose();
    brand.dispose();
    model.dispose();
    year.dispose();
    mileage.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: createClient,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo cliente'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorMessage(
              message: 'Error al cargar clientes: ${snapshot.error}',
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final clients = snapshot.data!;

          if (clients.isEmpty) {
            return const _EmptyMessage(
              icon: Icons.people,
              message: 'Todavía no hay clientes registrados.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: clients.length,
            itemBuilder: (context, index) {
              final client = clients[index];
              final vehicles = client['vehicles']?.toString();
              final clientId = (client['id'] as num).toInt();

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text('${client['name']}'),
                        subtitle: Text(
                          'Teléfono: ${client['phone']}\n'
                              'Vehículos: ${client['vehicle_count']}'
                              '${vehicles == null ? '' : '\n$vehicles'}',
                        ),
                        isThreeLine: true,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: 12,
                            bottom: 4,
                          ),
                          child: TextButton.icon(
                            onPressed: () => addVehicle(
                              clientId,
                              '${client['name']}',
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Añadir vehículo'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// INVENTARIO
// -----------------------------------------------------------------------------

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late Future<List<Map<String, Object?>>> future;

  @override
  void initState() {
    super.initState();
    future = Db.instance.listParts();
  }

  void reload() {
    setState(() => future = Db.instance.listParts());
  }

  Future<void> addPart() async {
    final name = TextEditingController();
    final sku = TextEditingController();
    final price = TextEditingController(text: '0');
    final stock = TextEditingController(text: '0');
    final minStock = TextEditingController(text: '1');

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo repuesto'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: sku,
                decoration: const InputDecoration(
                  labelText: 'Código (opcional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio unitario',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: stock,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Existencias',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: minStock,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Mínimo de alerta',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (save == true) {
      final parsedPrice = double.tryParse(
        price.text.replaceAll(',', '.'),
      );
      final parsedStock = int.tryParse(stock.text);
      final parsedMinStock = int.tryParse(minStock.text);

      if (name.text.trim().isEmpty ||
          parsedPrice == null ||
          parsedPrice < 0 ||
          parsedStock == null ||
          parsedStock < 0 ||
          parsedMinStock == null ||
          parsedMinStock < 0) {
        if (mounted) {
          _showMessage(
            context,
            'Completa el nombre y revisa precio y existencias.',
          );
        }
      } else {
        try {
          await Db.instance.add('parts', {
            'name': name.text.trim(),
            'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
            'unit_price': parsedPrice,
            'stock': parsedStock,
            'min_stock': parsedMinStock,
          });
          reload();
        } catch (error) {
          if (mounted) {
            _showMessage(
              context,
              'No se pudo guardar el repuesto: $error',
            );
          }
        }
      }
    }

    name.dispose();
    sku.dispose();
    price.dispose();
    stock.dispose();
    minStock.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addPart,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo repuesto'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorMessage(
              message: 'Error al cargar inventario: ${snapshot.error}',
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final parts = snapshot.data!;

          if (parts.isEmpty) {
            return const _EmptyMessage(
              icon: Icons.inventory_2,
              message: 'El inventario está vacío.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: parts.length,
            itemBuilder: (context, index) {
              final part = parts[index];
              final stock = (part['stock'] as num).toInt();
              final minStock = (part['min_stock'] as num).toInt();
              final isLow = stock <= minStock;
              final price = (part['unit_price'] as num).toDouble();

              return Card(
                child: ListTile(
                  leading: Icon(
                    isLow ? Icons.warning_amber : Icons.inventory_2,
                    color: isLow ? Colors.deepOrange : null,
                  ),
                  title: Text('${part['name']}'),
                  subtitle: Text(
                    'Código: ${part['sku'] ?? '—'}\n'
                        'Precio: ${price.toStringAsFixed(2)} · Mínimo: $minStock',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    'Stock\n$stock',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isLow ? Colors.deepOrange : null,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// COMPONENTES AUXILIARES
// -----------------------------------------------------------------------------

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
    ),
  );
}