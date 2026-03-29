CREATE TABLE "public"."OperarioDisponibilidadPeriodo" (
    "id" SERIAL NOT NULL,
    "operarioId" TEXT NOT NULL,
    "fechaInicio" TIMESTAMP(3) NOT NULL,
    "fechaFin" TIMESTAMP(3),
    "trabajaDomingo" BOOLEAN NOT NULL DEFAULT false,
    "diaDescanso" "public"."DiaSemana",
    "observaciones" TEXT,
    "creadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "actualizadoEn" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OperarioDisponibilidadPeriodo_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "OperarioDisponibilidadPeriodo_operarioId_fechaInicio_fechaFin_idx"
ON "public"."OperarioDisponibilidadPeriodo"("operarioId", "fechaInicio", "fechaFin");

ALTER TABLE "public"."OperarioDisponibilidadPeriodo"
ADD CONSTRAINT "OperarioDisponibilidadPeriodo_operarioId_fkey"
FOREIGN KEY ("operarioId") REFERENCES "public"."Operario"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
