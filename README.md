# El Pistón — Flutter

Aplicación móvil local para la gestión de un taller mecánico.

## Requisitos
- Flutter SDK estable (Dart 3.3 o superior).
- Android Studio o VS Code con Flutter.
- Android SDK para ejecutar en teléfono Android.

## Ejecutar
```bash
flutter pub get
flutter run
```

## Persistencia y funcionamiento
La base de datos SQLite `el_piston.db` se crea en el almacenamiento privado de la aplicación. No necesita Internet y los registros permanecen al cerrar la app.

## Modelo de datos
- `clients`: clientes.
- `vehicles`: vehículos asociados a clientes.
- `mechanics`: mecánicos.
- `orders`: órdenes de servicio y estado.
- `jobs`: mano de obra.
- `parts`: inventario.
- `order_parts`: repuestos consumidos por orden, con precio histórico.
- `payments`: pagos parciales.

Las claves foráneas están habilitadas. El consumo de repuestos se realiza en una transacción y valida las existencias.

## Decisiones de diseño
- Material 3, navegación inferior y panel de resumen.
- Una persona puede tener varios vehículos.
- Cada visita genera una orden independiente.
- Los estados contemplados son: Recibida, En diagnóstico, En reparación, Lista para entregar, Entregada y Cancelada.
- La alerta de inventario se activa cuando `stock <= min_stock`.
- El total de la orden es mano de obra + repuestos; el saldo es total - pagos.

## Alcance de esta primera versión
Incluye panel, alta de clientes y vehículos, creación y seguimiento de órdenes, inventario y estructura SQLite para mano de obra, repuestos consumidos y pagos. Para completar el flujo comercial faltan las pantallas de detalle de orden para añadir trabajos, consumir repuestos y registrar pagos; también reportes por período, historial y edición/eliminación avanzada.

## Capturas
Crear la carpeta `capturas/` y añadir imágenes de la aplicación ejecutándose antes de entregar el repositorio.
