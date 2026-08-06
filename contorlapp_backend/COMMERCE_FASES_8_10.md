# Comercio ControlApp: Fases 8, 9 y 10

## Estados internos

El flujo es `BORRADOR → PENDIENTE_PAGO → PAGADO → PENDIENTE_ENVIO → ENVIADO → RECIBIDO → ENTREGADO`. `CANCELADO` solo se admite antes de `ENVIADO`; cancelado y entregado son terminales. No hay saltos, retrocesos ni reactivaciones. Repetir el estado actual es idempotente.

`estadoWoo` queda como referencia externa: nunca produce una entrada de inventario ni omite una confirmación interna.

| Actor | Alcance y acciones |
| --- | --- |
| Residente | Solo su pedido `RESIDENTE`: reportar pago, cancelar antes del pago y confirmar recepción/entrega cuando corresponde. |
| Administrador | Pedidos de sus conjuntos; cualquier transición válida y recepción operativa. |
| Gerente / jefe de operaciones | Pedidos de conjuntos de su empresa; cualquier transición válida y recepción operativa. |
| Otros roles | Sin acceso a transiciones. |

Cada transición se audita en `PedidoAppEstadoHistorico` con estado anterior/nuevo, usuario, rol, motivo y fecha.

## Recepción e inventario

Solo el paso manual `ENVIADO → RECIBIDO` de un pedido `CONJUNTO` toca inventario. Los pedidos `RESIDENTE` nunca lo hacen.

El mapeo de cada ítem se resuelve, en orden, por `PedidoAppItem.insumoId`, `Insumo.wooProductId` o `Insumo.wooSku`, siempre dentro de la empresa del conjunto. Si falta un mapeo, se rechaza la transición completa. La vista previa lista el resultado y permite realizar el mapeo manual.

Una sola transacción reclama `entradaInventarioAplicada`, crea el inventario si hace falta, incrementa `InventarioInsumo`, registra `ConsumoInsumo` tipo `ENTRADA` referenciado al pedido y cambia el estado. El indicador y la llave única `(pedidoAppId, insumoId, tipo)` evitan duplicados.

## Puntos

`ConfigPuntosConjunto` contiene activación, monto COP por punto independiente para `RESIDENTE` y `CONJUNTO`, mínimo de redención y beneficios. La configuración se crea inactiva y requiere activación explícita.

La acumulación ocurre solo al pasar a `ENTREGADO`: `floor(total / montoPorPunto)`. Los puntos pertenecen al usuario creador del pedido y `puntosAplicados` garantiza una única ejecución. Una configuración inactiva genera cero puntos y no acredita retroactivamente ese pedido.

El saldo es la suma de `MovimientoPuntos` por usuario y conjunto. Un canje crea una `REDENCION` negativa; una corrección administrativa crea un `AJUSTE`. Ambas operaciones validan autorización y saldo dentro de transacciones serializables, sin permitir saldo negativo. Solo gerente/jefe de operaciones pueden ajustar usuarios de su conjunto autorizado.

## Endpoints

- `GET /commerce/pedidos/:pedidoId`
- `POST /commerce/pedidos/:pedidoId/estado`
- `GET /commerce/pedidos/:pedidoId/recepcion-preview`
- `POST /commerce/pedidos/:pedidoId/items/:itemId/mapeo`
- `GET /commerce/puntos/resumen`
- `GET|PUT /commerce/puntos/configuracion`
- `POST /commerce/puntos/redenciones`
- `POST /commerce/puntos/ajustes`

Todos requieren autenticación y validan rol y alcance en el servicio.

## Migración segura

La migración aditiva está en `prisma/migrations/20260804_commerce_estados_inventario_puntos/migration.sql`. No elimina ni renombra columnas. Crea las tablas de auditoría/configuración/beneficios, referencias, indicadores e índices; además registra un evento inicial para pedidos existentes.

Antes de producción se debe respaldar la base, aplicar la migración en la etapa aprobada de despliegue y luego desplegar el backend. `postinstall` continúa generando el cliente Prisma; no aplica cambios de base.

## WooCommerce

El contrato principal usa `WOOCOMMERCE_API_KEY` y `WOOCOMMERCE_SECRET_KEY`. `WOOCOMMERCE_CONSUMER_KEY` y `WOOCOMMERCE_CONSUMER_SECRET` se conservan como alias legados. Ningún error expone nombres o valores de credenciales.
