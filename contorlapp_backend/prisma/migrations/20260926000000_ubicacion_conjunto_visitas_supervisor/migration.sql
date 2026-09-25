-- AlterTable
ALTER TABLE "Conjunto"
  ADD COLUMN "ubicacionMapsUrl" TEXT,
  ADD COLUMN "latitud" DECIMAL(10,7),
  ADD COLUMN "longitud" DECIMAL(10,7),
  ADD COLUMN "radioAsistenciaMetros" INTEGER NOT NULL DEFAULT 150;

-- CreateTable
CREATE TABLE "VisitaSupervisor" (
    "id" SERIAL NOT NULL,
    "supervisorId" TEXT NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "fecha" DATE NOT NULL,
    "horaEntrada" TIMESTAMP(3) NOT NULL,
    "horaSalida" TIMESTAMP(3),
    "latitudEntrada" DECIMAL(10,7),
    "longitudEntrada" DECIMAL(10,7),
    "latitudSalida" DECIMAL(10,7),
    "longitudSalida" DECIMAL(10,7),
    "distanciaEntradaMetros" INTEGER,
    "distanciaSalidaMetros" INTEGER,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "VisitaSupervisor_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "VisitaSupervisor_supervisorId_fecha_idx" ON "VisitaSupervisor"("supervisorId", "fecha");

-- CreateIndex
CREATE INDEX "VisitaSupervisor_conjuntoId_fecha_idx" ON "VisitaSupervisor"("conjuntoId", "fecha");

-- AddForeignKey
ALTER TABLE "VisitaSupervisor" ADD CONSTRAINT "VisitaSupervisor_supervisorId_fkey" FOREIGN KEY ("supervisorId") REFERENCES "Supervisor"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "VisitaSupervisor" ADD CONSTRAINT "VisitaSupervisor_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;
