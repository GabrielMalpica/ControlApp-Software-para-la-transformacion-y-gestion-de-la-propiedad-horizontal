/*
  Warnings:

  - You are about to drop the column `responsableSugeridoId` on the `DefinicionTareaPreventiva` table. All the data in the column will be lost.
  - You are about to drop the column `minutosSetup` on the `Rendimiento` table. All the data in the column will be lost.

*/
-- DropForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" DROP CONSTRAINT "DefinicionTareaPreventiva_responsableSugeridoId_fkey";

-- AlterTable
ALTER TABLE "public"."DefinicionTareaPreventiva" DROP COLUMN "responsableSugeridoId",
ADD COLUMN     "supervisorId" TEXT;

-- AlterTable
ALTER TABLE "public"."Rendimiento" DROP COLUMN "minutosSetup";

-- CreateTable
CREATE TABLE "public"."_DefinicionOperarios" (
    "A" INTEGER NOT NULL,
    "B" TEXT NOT NULL,

    CONSTRAINT "_DefinicionOperarios_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE INDEX "_DefinicionOperarios_B_index" ON "public"."_DefinicionOperarios"("B");

-- AddForeignKey
ALTER TABLE "public"."DefinicionTareaPreventiva" ADD CONSTRAINT "DefinicionTareaPreventiva_supervisorId_fkey" FOREIGN KEY ("supervisorId") REFERENCES "public"."Supervisor"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."_DefinicionOperarios" ADD CONSTRAINT "_DefinicionOperarios_A_fkey" FOREIGN KEY ("A") REFERENCES "public"."DefinicionTareaPreventiva"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."_DefinicionOperarios" ADD CONSTRAINT "_DefinicionOperarios_B_fkey" FOREIGN KEY ("B") REFERENCES "public"."Operario"("id") ON DELETE CASCADE ON UPDATE CASCADE;
