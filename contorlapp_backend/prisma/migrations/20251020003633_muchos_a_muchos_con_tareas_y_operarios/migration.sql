/*
  Warnings:

  - You are about to drop the column `operarioId` on the `Tarea` table. All the data in the column will be lost.

*/
-- DropForeignKey
ALTER TABLE "public"."Tarea" DROP CONSTRAINT "Tarea_operarioId_fkey";

-- AlterTable
ALTER TABLE "public"."Tarea" DROP COLUMN "operarioId";

-- CreateTable
CREATE TABLE "public"."_TareaOperarios" (
    "A" INTEGER NOT NULL,
    "B" INTEGER NOT NULL,

    CONSTRAINT "_TareaOperarios_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE INDEX "_TareaOperarios_B_index" ON "public"."_TareaOperarios"("B");

-- AddForeignKey
ALTER TABLE "public"."_TareaOperarios" ADD CONSTRAINT "_TareaOperarios_A_fkey" FOREIGN KEY ("A") REFERENCES "public"."Operario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."_TareaOperarios" ADD CONSTRAINT "_TareaOperarios_B_fkey" FOREIGN KEY ("B") REFERENCES "public"."Tarea"("id") ON DELETE CASCADE ON UPDATE CASCADE;
