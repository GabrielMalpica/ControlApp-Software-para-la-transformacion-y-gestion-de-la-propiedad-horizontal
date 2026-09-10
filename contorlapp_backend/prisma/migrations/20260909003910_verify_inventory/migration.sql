-- DropForeignKey
ALTER TABLE "Maquinaria" DROP CONSTRAINT "Maquinaria_empresaId_fkey";

-- RenameForeignKey
ALTER TABLE "MovimientoPuntos" RENAME CONSTRAINT "MovimientoPuntos_pedido_fkey" TO "MovimientoPuntos_pedidoId_fkey";

-- RenameForeignKey
ALTER TABLE "MovimientoPuntos" RENAME CONSTRAINT "MovimientoPuntos_usuario_fkey" TO "MovimientoPuntos_usuarioId_fkey";

-- RenameForeignKey
ALTER TABLE "PedidoApp" RENAME CONSTRAINT "PedidoApp_conjunto_fkey" TO "PedidoApp_conjuntoId_fkey";

-- RenameForeignKey
ALTER TABLE "PedidoApp" RENAME CONSTRAINT "PedidoApp_residente_fkey" TO "PedidoApp_residenteId_fkey";

-- RenameForeignKey
ALTER TABLE "PedidoApp" RENAME CONSTRAINT "PedidoApp_usuario_fkey" TO "PedidoApp_usuarioId_fkey";

-- RenameForeignKey
ALTER TABLE "PedidoAppItem" RENAME CONSTRAINT "PedidoAppItem_pedido_fkey" TO "PedidoAppItem_pedidoId_fkey";

-- RenameForeignKey
ALTER TABLE "Residente" RENAME CONSTRAINT "Residente_conjunto_fkey" TO "Residente_conjuntoId_fkey";

-- RenameForeignKey
ALTER TABLE "Residente" RENAME CONSTRAINT "Residente_usuario_fkey" TO "Residente_id_fkey";

-- AddForeignKey
ALTER TABLE "Maquinaria" ADD CONSTRAINT "Maquinaria_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- RenameIndex
ALTER INDEX "Herramienta_empresa_activo_aprobacion_idx" RENAME TO "Herramienta_empresaId_activo_estadoAprobacion_idx";

-- RenameIndex
ALTER INDEX "Herramienta_empresa_nombre_normalizado_idx" RENAME TO "Herramienta_empresaId_nombreNormalizado_idx";

-- RenameIndex
ALTER INDEX "HerramientaItem_conjunto_aprobacion_estado_idx" RENAME TO "HerramientaItem_conjuntoPropietarioId_estadoAprobacion_esta_idx";

-- RenameIndex
ALTER INDEX "HerramientaItem_empresa_catalogo_aprobacion_estado_idx" RENAME TO "HerramientaItem_empresaId_herramientaId_estadoAprobacion_es_idx";

-- RenameIndex
ALTER INDEX "HerramientaItem_empresa_codigo_key" RENAME TO "HerramientaItem_empresaId_codigoInterno_key";

-- RenameIndex
ALTER INDEX "HerramientaItem_lote_idx" RENAME TO "HerramientaItem_registroLoteId_idx";

-- RenameIndex
ALTER INDEX "HerramientaItemConjunto_conjunto_estado_idx" RENAME TO "HerramientaItemConjunto_conjuntoId_estado_idx";

-- RenameIndex
ALTER INDEX "HerramientaItemConjunto_item_estado_idx" RENAME TO "HerramientaItemConjunto_herramientaItemId_estado_idx";

-- RenameIndex
ALTER INDEX "HerramientaItemConjunto_tarea_idx" RENAME TO "HerramientaItemConjunto_tareaId_idx";

-- RenameIndex
ALTER INDEX "Maquinaria_conjunto_aprobacion_estado_idx" RENAME TO "Maquinaria_conjuntoPropietarioId_estadoAprobacion_estado_idx";

-- RenameIndex
ALTER INDEX "Maquinaria_empresa_codigo_key" RENAME TO "Maquinaria_empresaId_codigoInterno_key";

-- RenameIndex
ALTER INDEX "Maquinaria_empresa_tipo_aprobacion_estado_idx" RENAME TO "Maquinaria_empresaId_tipoCatalogoId_estadoAprobacion_estado_idx";

-- RenameIndex
ALTER INDEX "Maquinaria_registro_lote_idx" RENAME TO "Maquinaria_registroLoteId_idx";

-- RenameIndex
ALTER INDEX "TipoMaquinariaCatalogo_empresa_activo_aprobacion_idx" RENAME TO "TipoMaquinariaCatalogo_empresaId_activo_estadoAprobacion_idx";
