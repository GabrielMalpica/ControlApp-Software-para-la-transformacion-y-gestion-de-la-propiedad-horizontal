-- App Android sin conexión (ver docs/app-android-sin-conexion.md):
-- sesión larga de la app, cierres y asistencias hechos sin señal y enviados
-- después, con su hora original y marcas de auditoría.

-- AlterTable: canal del token de renovación ("web" cookie, "app" Android)
ALTER TABLE "SesionRefresh" ADD COLUMN "canal" TEXT NOT NULL DEFAULT 'web';

-- AlterTable: auditoría de cierres enviados desde la cola sin señal
ALTER TABLE "CierreTareaIdempotencia" ADD COLUMN "operarioId" TEXT,
ADD COLUMN "sinConexion" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "recibidoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN "desfaseRelojSeg" INTEGER,
ADD COLUMN "horaAjustada" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable: asistencia marcada sin señal
ALTER TABLE "RegistroAsistencia" ADD COLUMN "entradaSinConexion" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "salidaSinConexion" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "entradaRecibidaEn" TIMESTAMP(3),
ADD COLUMN "salidaRecibidaEn" TIMESTAMP(3),
ADD COLUMN "relojAjustado" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "VisitaSupervisor" ADD COLUMN "entradaSinConexion" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "salidaSinConexion" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "AsistenciaIdempotencia" (
    "clienteRegistroId" TEXT NOT NULL,
    "usuarioId" TEXT NOT NULL,
    "tipo" TEXT NOT NULL,
    "registroId" INTEGER,
    "visitaId" INTEGER,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AsistenciaIdempotencia_pkey" PRIMARY KEY ("clienteRegistroId")
);

-- CreateIndex
CREATE INDEX "AsistenciaIdempotencia_usuarioId_idx" ON "AsistenciaIdempotencia"("usuarioId");

-- AddForeignKey
ALTER TABLE "AsistenciaIdempotencia" ADD CONSTRAINT "AsistenciaIdempotencia_registroId_fkey" FOREIGN KEY ("registroId") REFERENCES "RegistroAsistencia"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AsistenciaIdempotencia" ADD CONSTRAINT "AsistenciaIdempotencia_visitaId_fkey" FOREIGN KEY ("visitaId") REFERENCES "VisitaSupervisor"("id") ON DELETE CASCADE ON UPDATE CASCADE;
