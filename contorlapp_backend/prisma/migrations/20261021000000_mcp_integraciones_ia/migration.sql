-- Integraciones de IA por MCP, solo gerentes (docs/mcp/arquitectura.md):
-- conexiones autorizadas por OAuth, codigos y refresh tokens (solo hashes),
-- bitacora de herramientas, confirmaciones de operaciones y el interruptor
-- por gerente (Gerente.mcpHabilitado, desactivado por defecto).

-- AlterTable
ALTER TABLE "Gerente" ADD COLUMN     "mcpHabilitado" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "McpConexion" (
    "id" TEXT NOT NULL,
    "usuarioId" TEXT NOT NULL,
    "empresaId" TEXT NOT NULL,
    "clienteId" TEXT NOT NULL,
    "clienteNombre" TEXT NOT NULL,
    "redirectUri" TEXT NOT NULL,
    "scopes" TEXT[],
    "estado" TEXT NOT NULL DEFAULT 'ACTIVA',
    "creadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "autorizadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadaEn" TIMESTAMP(3) NOT NULL,
    "ultimoUsoEn" TIMESTAMP(3),
    "revocadaEn" TIMESTAMP(3),
    "revocadaPorId" TEXT,
    "motivoRevocacion" TEXT,

    CONSTRAINT "McpConexion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "McpSolicitudAutorizacion" (
    "id" TEXT NOT NULL,
    "clienteId" TEXT NOT NULL,
    "clienteNombre" TEXT NOT NULL,
    "redirectUri" TEXT NOT NULL,
    "state" TEXT,
    "codeChallenge" TEXT NOT NULL,
    "scopesSolicitados" TEXT[],
    "resource" TEXT NOT NULL,
    "csrf" TEXT NOT NULL,
    "usuarioId" TEXT,
    "creadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiraEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "McpSolicitudAutorizacion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "McpCodigoAutorizacion" (
    "codigoHash" TEXT NOT NULL,
    "conexionId" TEXT NOT NULL,
    "clienteId" TEXT NOT NULL,
    "redirectUri" TEXT NOT NULL,
    "codeChallenge" TEXT NOT NULL,
    "resource" TEXT NOT NULL,
    "scopes" TEXT[],
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiraEn" TIMESTAMP(3) NOT NULL,
    "usadoEn" TIMESTAMP(3),

    CONSTRAINT "McpCodigoAutorizacion_pkey" PRIMARY KEY ("codigoHash")
);

-- CreateTable
CREATE TABLE "McpRefreshToken" (
    "id" TEXT NOT NULL,
    "conexionId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "scopes" TEXT[],
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiraEn" TIMESTAMP(3) NOT NULL,
    "usadoEn" TIMESTAMP(3),
    "revocadoEn" TIMESTAMP(3),

    CONSTRAINT "McpRefreshToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "McpClienteRegistrado" (
    "clientId" TEXT NOT NULL,
    "nombre" TEXT NOT NULL,
    "redirectUris" TEXT[],
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "McpClienteRegistrado_pkey" PRIMARY KEY ("clientId")
);

-- CreateTable
CREATE TABLE "McpInvocacion" (
    "id" BIGSERIAL NOT NULL,
    "conexionId" TEXT NOT NULL,
    "usuarioId" TEXT NOT NULL,
    "empresaId" TEXT NOT NULL,
    "clienteId" TEXT NOT NULL,
    "herramienta" TEXT NOT NULL,
    "nivelRiesgo" TEXT NOT NULL,
    "resultado" TEXT NOT NULL,
    "codigo" TEXT,
    "mensaje" TEXT,
    "parametrosHash" TEXT NOT NULL,
    "parametrosRedactados" JSONB,
    "entidadesAfectadas" JSONB,
    "confirmacionId" TEXT,
    "latenciaMs" INTEGER NOT NULL,
    "ip" TEXT,
    "userAgent" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "McpInvocacion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "McpConfirmacion" (
    "id" TEXT NOT NULL,
    "conexionId" TEXT NOT NULL,
    "usuarioId" TEXT NOT NULL,
    "empresaId" TEXT NOT NULL,
    "operacion" TEXT NOT NULL,
    "parametros" JSONB NOT NULL,
    "parametrosHash" TEXT NOT NULL,
    "resumen" TEXT NOT NULL,
    "impacto" JSONB NOT NULL,
    "impactoHash" TEXT NOT NULL,
    "requiereAprobacionHumana" BOOLEAN NOT NULL DEFAULT false,
    "estado" TEXT NOT NULL DEFAULT 'PENDIENTE',
    "creadaEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiraEn" TIMESTAMP(3) NOT NULL,
    "decididaPorId" TEXT,
    "decididaEn" TIMESTAMP(3),
    "ejecutadaEn" TIMESTAMP(3),
    "resultado" JSONB,

    CONSTRAINT "McpConfirmacion_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "McpConexion_empresaId_estado_idx" ON "McpConexion"("empresaId", "estado");

-- CreateIndex
CREATE UNIQUE INDEX "McpConexion_usuarioId_clienteId_key" ON "McpConexion"("usuarioId", "clienteId");

-- CreateIndex
CREATE INDEX "McpSolicitudAutorizacion_expiraEn_idx" ON "McpSolicitudAutorizacion"("expiraEn");

-- CreateIndex
CREATE INDEX "McpCodigoAutorizacion_conexionId_idx" ON "McpCodigoAutorizacion"("conexionId");

-- CreateIndex
CREATE UNIQUE INDEX "McpRefreshToken_tokenHash_key" ON "McpRefreshToken"("tokenHash");

-- CreateIndex
CREATE INDEX "McpRefreshToken_conexionId_idx" ON "McpRefreshToken"("conexionId");

-- CreateIndex
CREATE INDEX "McpInvocacion_conexionId_creadoEn_idx" ON "McpInvocacion"("conexionId", "creadoEn");

-- CreateIndex
CREATE INDEX "McpInvocacion_usuarioId_creadoEn_idx" ON "McpInvocacion"("usuarioId", "creadoEn");

-- CreateIndex
CREATE INDEX "McpInvocacion_empresaId_creadoEn_idx" ON "McpInvocacion"("empresaId", "creadoEn");

-- CreateIndex
CREATE INDEX "McpConfirmacion_usuarioId_estado_idx" ON "McpConfirmacion"("usuarioId", "estado");

-- CreateIndex
CREATE INDEX "McpConfirmacion_conexionId_estado_idx" ON "McpConfirmacion"("conexionId", "estado");

-- AddForeignKey
ALTER TABLE "McpConexion" ADD CONSTRAINT "McpConexion_usuarioId_fkey" FOREIGN KEY ("usuarioId") REFERENCES "Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "McpCodigoAutorizacion" ADD CONSTRAINT "McpCodigoAutorizacion_conexionId_fkey" FOREIGN KEY ("conexionId") REFERENCES "McpConexion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "McpRefreshToken" ADD CONSTRAINT "McpRefreshToken_conexionId_fkey" FOREIGN KEY ("conexionId") REFERENCES "McpConexion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "McpConfirmacion" ADD CONSTRAINT "McpConfirmacion_conexionId_fkey" FOREIGN KEY ("conexionId") REFERENCES "McpConexion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

