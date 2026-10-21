-- Sesiones seguras (auditoria de seguridad, hallazgos S2/S3/S9):
-- `versionSesion` permite cerrar todas las sesiones de un usuario y
-- `SesionRefresh` guarda (hasheados) los tokens de renovacion rotativos de la
-- sesion web, que viajan en una cookie HttpOnly.

-- AlterTable
ALTER TABLE "Usuario" ADD COLUMN     "versionSesion" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "SesionRefresh" (
    "id" TEXT NOT NULL,
    "familiaId" TEXT NOT NULL,
    "usuarioId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "versionSesion" INTEGER NOT NULL,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiraEn" TIMESTAMP(3) NOT NULL,
    "familiaExpiraEn" TIMESTAMP(3) NOT NULL,
    "usadoEn" TIMESTAMP(3),
    "revocadoEn" TIMESTAMP(3),
    "motivoRevocacion" TEXT,
    "userAgent" TEXT,

    CONSTRAINT "SesionRefresh_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SesionRefresh_tokenHash_key" ON "SesionRefresh"("tokenHash");

-- CreateIndex
CREATE INDEX "SesionRefresh_familiaId_idx" ON "SesionRefresh"("familiaId");

-- CreateIndex
CREATE INDEX "SesionRefresh_usuarioId_idx" ON "SesionRefresh"("usuarioId");

-- CreateIndex
CREATE INDEX "SesionRefresh_expiraEn_idx" ON "SesionRefresh"("expiraEn");

-- AddForeignKey
ALTER TABLE "SesionRefresh" ADD CONSTRAINT "SesionRefresh_usuarioId_fkey" FOREIGN KEY ("usuarioId") REFERENCES "Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;
