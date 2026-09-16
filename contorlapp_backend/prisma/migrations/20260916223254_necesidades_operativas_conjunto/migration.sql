-- AlterEnum
ALTER TYPE "TipoFuncion" ADD VALUE 'PISCINERO';

-- CreateTable
CREATE TABLE "ConjuntoNecesidadOperario" (
    "id" SERIAL NOT NULL,
    "conjuntoId" TEXT NOT NULL,
    "rol" "TipoFuncion" NOT NULL,
    "etiqueta" TEXT NOT NULL,
    "orden" INTEGER NOT NULL DEFAULT 0,
    "horarioEspecial" BOOLEAN NOT NULL DEFAULT false,
    "operarioId" TEXT,
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "observaciones" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ConjuntoNecesidadOperario_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConjuntoNecesidadHorario" (
    "id" SERIAL NOT NULL,
    "necesidadId" INTEGER NOT NULL,
    "dia" "DiaSemana" NOT NULL,
    "horaApertura" TEXT NOT NULL,
    "horaCierre" TEXT NOT NULL,
    "descansoInicio" TEXT,
    "descansoFin" TEXT,

    CONSTRAINT "ConjuntoNecesidadHorario_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "_DefinicionNecesidades" (
    "A" INTEGER NOT NULL,
    "B" INTEGER NOT NULL,

    CONSTRAINT "_DefinicionNecesidades_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "_TareaNecesidades" (
    "A" INTEGER NOT NULL,
    "B" INTEGER NOT NULL,

    CONSTRAINT "_TareaNecesidades_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE INDEX "ConjuntoNecesidadOperario_conjuntoId_activo_idx" ON "ConjuntoNecesidadOperario"("conjuntoId", "activo");

-- CreateIndex
CREATE INDEX "ConjuntoNecesidadOperario_operarioId_idx" ON "ConjuntoNecesidadOperario"("operarioId");

-- CreateIndex
CREATE UNIQUE INDEX "ConjuntoNecesidadOperario_conjuntoId_etiqueta_key" ON "ConjuntoNecesidadOperario"("conjuntoId", "etiqueta");

-- CreateIndex
CREATE UNIQUE INDEX "ConjuntoNecesidadOperario_conjuntoId_operarioId_key" ON "ConjuntoNecesidadOperario"("conjuntoId", "operarioId");

-- CreateIndex
CREATE UNIQUE INDEX "ConjuntoNecesidadHorario_necesidadId_dia_key" ON "ConjuntoNecesidadHorario"("necesidadId", "dia");

-- CreateIndex
CREATE INDEX "_DefinicionNecesidades_B_index" ON "_DefinicionNecesidades"("B");

-- CreateIndex
CREATE INDEX "_TareaNecesidades_B_index" ON "_TareaNecesidades"("B");

-- AddForeignKey
ALTER TABLE "ConjuntoNecesidadOperario" ADD CONSTRAINT "ConjuntoNecesidadOperario_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConjuntoNecesidadOperario" ADD CONSTRAINT "ConjuntoNecesidadOperario_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConjuntoNecesidadHorario" ADD CONSTRAINT "ConjuntoNecesidadHorario_necesidadId_fkey" FOREIGN KEY ("necesidadId") REFERENCES "ConjuntoNecesidadOperario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_DefinicionNecesidades" ADD CONSTRAINT "_DefinicionNecesidades_A_fkey" FOREIGN KEY ("A") REFERENCES "ConjuntoNecesidadOperario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_DefinicionNecesidades" ADD CONSTRAINT "_DefinicionNecesidades_B_fkey" FOREIGN KEY ("B") REFERENCES "DefinicionTareaPreventiva"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_TareaNecesidades" ADD CONSTRAINT "_TareaNecesidades_A_fkey" FOREIGN KEY ("A") REFERENCES "ConjuntoNecesidadOperario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_TareaNecesidades" ADD CONSTRAINT "_TareaNecesidades_B_fkey" FOREIGN KEY ("B") REFERENCES "Tarea"("id") ON DELETE CASCADE ON UPDATE CASCADE;
