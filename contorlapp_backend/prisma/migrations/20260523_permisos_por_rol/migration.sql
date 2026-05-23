CREATE TABLE "PermisoRol" (
    "id" SERIAL NOT NULL,
    "empresaId" TEXT NOT NULL,
    "rol" "Rol" NOT NULL,
    "permiso" TEXT NOT NULL,
    "permitido" BOOLEAN NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PermisoRol_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PermisoRol_empresaId_rol_permiso_key"
ON "PermisoRol"("empresaId", "rol", "permiso");

CREATE INDEX "PermisoRol_empresaId_rol_idx"
ON "PermisoRol"("empresaId", "rol");

ALTER TABLE "PermisoRol"
ADD CONSTRAINT "PermisoRol_empresaId_fkey"
FOREIGN KEY ("empresaId") REFERENCES "Empresa"("nit")
ON DELETE CASCADE ON UPDATE CASCADE;
