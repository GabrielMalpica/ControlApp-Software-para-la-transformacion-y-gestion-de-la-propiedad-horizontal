-- CreateTable
CREATE TABLE "CierreTareaIdempotencia" (
    "clienteCierreId" TEXT NOT NULL,
    "tareaId" INTEGER NOT NULL,
    "estadoResultante" "EstadoTarea" NOT NULL,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CierreTareaIdempotencia_pkey" PRIMARY KEY ("clienteCierreId")
);

-- CreateIndex
CREATE INDEX "CierreTareaIdempotencia_tareaId_idx" ON "CierreTareaIdempotencia"("tareaId");

-- AddForeignKey
ALTER TABLE "CierreTareaIdempotencia" ADD CONSTRAINT "CierreTareaIdempotencia_tareaId_fkey" FOREIGN KEY ("tareaId") REFERENCES "Tarea"("id") ON DELETE CASCADE ON UPDATE CASCADE;
