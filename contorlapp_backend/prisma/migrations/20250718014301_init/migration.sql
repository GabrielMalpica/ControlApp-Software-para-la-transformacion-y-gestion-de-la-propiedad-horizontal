-- CreateEnum
CREATE TYPE "EPS" AS ENUM ('SANITAS', 'NUEVA_EPS', 'SALUD_TOTAL', 'SURA', 'COMPENSAR', 'FAMISANAR', 'COOSALUD', 'MUTUAL_SER', 'SAVIA_SALUD', 'CAPITAL_SALUD', 'ASMET_SALUD', 'ECOOPSOS', 'EMSSANAR', 'CAJACOPI', 'COMFENALCO_ANTIOQUIA', 'COMFACHOCO', 'COMPARTA', 'DUSAKAWI', 'MALLAMAS', 'ANAS_WAIMAS');

-- CreateEnum
CREATE TYPE "EstadoCivil" AS ENUM ('SOLTERO', 'CASADO', 'UNION_LIBRE', 'VIUDOA');

-- CreateEnum
CREATE TYPE "EstadoMaquinaria" AS ENUM ('OPERATIVA', 'EN_REPARACION', 'FUERA_DE_SERVICIO');

-- CreateEnum
CREATE TYPE "EstadoSolicitud" AS ENUM ('PENDIENTE', 'APROBADA', 'RECHAZADA');

-- CreateEnum
CREATE TYPE "EstadoTarea" AS ENUM ('ASIGNADA', 'EN_PROCESO', 'COMPLETADA', 'APROBADA', 'PENDIENTE_APROBACION', 'RECHAZADA', 'NO_COMPLETADA');

-- CreateEnum
CREATE TYPE "FondoPension" AS ENUM ('COLPENSIONES', 'PORVENIR', 'PROTECCION', 'COLFONDOS', 'SKANDIA', 'OLD_MUTUAL');

-- CreateEnum
CREATE TYPE "JornadaLaboral" AS ENUM ('COMPLETA', 'MEDIO_TIEMPO', 'FINES_DE_SEMANA');

-- CreateEnum
CREATE TYPE "Rol" AS ENUM ('gerente', 'administrador', 'jefe_operaciones', 'supervisor', 'operario');

-- CreateEnum
CREATE TYPE "TallaCalzado" AS ENUM ('T_34', 'T_35', 'T_36', 'T_37', 'T_38', 'T_39', 'T_40', 'T_41', 'T_42', 'T_43', 'T_44');

-- CreateEnum
CREATE TYPE "TallaCamisa" AS ENUM ('XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL');

-- CreateEnum
CREATE TYPE "TallaPantalon" AS ENUM ('T_28', 'T_30', 'T_32', 'T_34', 'T_36', 'T_38', 'T_40', 'T_42', 'F_6', 'F_8', 'F_10', 'F_12', 'F_14', 'F_16');

-- CreateEnum
CREATE TYPE "TipoContrato" AS ENUM ('TERMINO_INDEFINIDO', 'TERMINO_FIJO', 'OBRA_LABOR');

-- CreateEnum
CREATE TYPE "TipoFuncion" AS ENUM ('TODERO', 'SALVAVIDAS', 'ASEO');

-- CreateEnum
CREATE TYPE "TipoMaquinaria" AS ENUM ('CORTASETOS_MANO', 'CORTASETOS_ALTURA', 'GUADANIA', 'PODADORA_CESPED', 'ESCALERA', 'SOPLADORA', 'FUMIGADORA_MOTOR', 'BOMBA_ESPALDA', 'MOTOSIERRA_MANO', 'MOTOSIERRA_ALTURA', 'HIDROLAVADORA_ELECTRICA', 'HIDROLAVADORA_GASOLINA', 'PULIDORA', 'TALADRO', 'ROTOMARTILLO', 'LAVABRILLADORA', 'COMPRESOR', 'PULVERIZADORA_PINTURA', 'EQUIPO_ALTURAS', 'MEDIA_LUNA', 'CAJA_HERRAMIENTAS', 'OTRO');

-- CreateEnum
CREATE TYPE "TipoSangre" AS ENUM ('O_POSITIVO', 'O_NEGATIVO', 'A_POSITIVO', 'A_NEGATIVO', 'B_POSITIVO', 'B_NEGATIVO', 'AB_POSITIVO', 'AB_NEGATIVO');

-- CreateTable
CREATE TABLE "Usuario" (
    "id" INTEGER NOT NULL,
    "nombre" TEXT NOT NULL,
    "correo" TEXT NOT NULL,
    "contrasena" TEXT NOT NULL,
    "rol" TEXT NOT NULL,
    "telefono" BIGINT NOT NULL,
    "fechaNacimiento" TIMESTAMP(3) NOT NULL,
    "direccion" TEXT,
    "estadoCivil" "EstadoCivil",
    "numeroHijos" INTEGER,
    "padresVivos" BOOLEAN,
    "tipoSangre" "TipoSangre",
    "eps" "EPS",
    "fondoPensiones" "FondoPension",
    "tallaCamisa" "TallaCamisa",
    "tallaPantalon" "TallaPantalon",
    "tallaCalzado" "TallaCalzado",
    "tipoContrato" "TipoContrato",
    "jornadaLaboral" "JornadaLaboral",

    CONSTRAINT "Usuario_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Gerente" (
    "id" INTEGER NOT NULL,
    "empresaId" INTEGER,

    CONSTRAINT "Gerente_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Administrador" (
    "id" INTEGER NOT NULL,

    CONSTRAINT "Administrador_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "JefeOperaciones" (
    "id" INTEGER NOT NULL,
    "empresaId" INTEGER,

    CONSTRAINT "JefeOperaciones_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Supervisor" (
    "id" INTEGER NOT NULL,

    CONSTRAINT "Supervisor_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Operario" (
    "id" INTEGER NOT NULL,
    "funciones" "TipoFuncion"[],
    "cursoSalvamentoAcuatico" BOOLEAN NOT NULL,
    "urlEvidenciaSalvamento" TEXT,
    "cursoAlturas" BOOLEAN NOT NULL,
    "urlEvidenciaAlturas" TEXT,
    "examenIngreso" BOOLEAN NOT NULL,
    "urlEvidenciaExamenIngreso" TEXT,
    "fechaIngreso" TIMESTAMP(3) NOT NULL,
    "fechaSalida" TIMESTAMP(3),
    "fechaUltimasVacaciones" TIMESTAMP(3),
    "observaciones" TEXT,

    CONSTRAINT "Operario_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Tarea" (
    "id" SERIAL NOT NULL,
    "descripcion" TEXT NOT NULL,
    "fechaInicio" TIMESTAMP(3) NOT NULL,
    "fechaFin" TIMESTAMP(3) NOT NULL,
    "fechaIniciarTarea" TIMESTAMP(3),
    "fechaFinalizarTarea" TIMESTAMP(3),
    "duracionHoras" INTEGER NOT NULL,
    "estado" "EstadoTarea" NOT NULL DEFAULT 'ASIGNADA',
    "evidencias" TEXT[],
    "insumosUsados" JSONB NOT NULL,
    "observacionesRechazo" TEXT,
    "operarioId" INTEGER NOT NULL,
    "supervisorId" INTEGER,
    "ubicacionId" INTEGER NOT NULL,
    "elementoId" INTEGER NOT NULL,
    "conjuntoId" INTEGER,
    "empresaAprobadaId" INTEGER,
    "empresaRechazadaId" INTEGER,

    CONSTRAINT "Tarea_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Conjunto" (
    "nit" INTEGER NOT NULL,
    "nombre" TEXT NOT NULL,
    "direccion" TEXT NOT NULL,
    "correo" TEXT NOT NULL,
    "administradorId" INTEGER,
    "empresaId" INTEGER,

    CONSTRAINT "Conjunto_pkey" PRIMARY KEY ("nit")
);

-- CreateTable
CREATE TABLE "Ubicacion" (
    "id" SERIAL NOT NULL,
    "nombre" TEXT NOT NULL,
    "conjuntoId" INTEGER NOT NULL,

    CONSTRAINT "Ubicacion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Elemento" (
    "id" SERIAL NOT NULL,
    "nombre" TEXT NOT NULL,
    "ubicacionId" INTEGER NOT NULL,

    CONSTRAINT "Elemento_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Insumo" (
    "id" SERIAL NOT NULL,
    "nombre" TEXT NOT NULL,
    "unidad" TEXT NOT NULL,
    "empresaId" INTEGER,

    CONSTRAINT "Insumo_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Inventario" (
    "id" SERIAL NOT NULL,
    "conjuntoId" INTEGER NOT NULL,

    CONSTRAINT "Inventario_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InventarioInsumo" (
    "id" SERIAL NOT NULL,
    "inventarioId" INTEGER NOT NULL,
    "insumoId" INTEGER NOT NULL,
    "cantidad" INTEGER NOT NULL,

    CONSTRAINT "InventarioInsumo_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ConsumoInsumo" (
    "id" SERIAL NOT NULL,
    "inventarioId" INTEGER NOT NULL,
    "insumoId" INTEGER NOT NULL,
    "operarioId" INTEGER,
    "tareaId" INTEGER,
    "cantidad" INTEGER NOT NULL,
    "fecha" TIMESTAMP(3) NOT NULL,
    "observacion" TEXT,

    CONSTRAINT "ConsumoInsumo_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Maquinaria" (
    "id" SERIAL NOT NULL,
    "nombre" TEXT NOT NULL,
    "marca" TEXT NOT NULL,
    "tipo" "TipoMaquinaria" NOT NULL,
    "estado" "EstadoMaquinaria" NOT NULL DEFAULT 'OPERATIVA',
    "disponible" BOOLEAN NOT NULL DEFAULT true,
    "conjuntoId" INTEGER,
    "operarioId" INTEGER,
    "empresaId" INTEGER,
    "fechaPrestamo" TIMESTAMP(3),
    "fechaDevolucionEstimada" TIMESTAMP(3),

    CONSTRAINT "Maquinaria_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Empresa" (
    "id" SERIAL NOT NULL,
    "nombre" TEXT NOT NULL,
    "nit" TEXT NOT NULL,
    "gerenteId" INTEGER NOT NULL,

    CONSTRAINT "Empresa_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InsumoConsumoEmpresa" (
    "id" SERIAL NOT NULL,
    "insumoId" INTEGER NOT NULL,
    "empresaId" INTEGER NOT NULL,
    "cantidad" INTEGER NOT NULL,
    "fecha" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InsumoConsumoEmpresa_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SolicitudTarea" (
    "id" SERIAL NOT NULL,
    "descripcion" TEXT NOT NULL,
    "duracionHoras" INTEGER NOT NULL,
    "estado" "EstadoSolicitud" NOT NULL DEFAULT 'PENDIENTE',
    "observaciones" TEXT,
    "conjuntoId" INTEGER NOT NULL,
    "ubicacionId" INTEGER NOT NULL,
    "elementoId" INTEGER NOT NULL,
    "empresaId" INTEGER,

    CONSTRAINT "SolicitudTarea_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SolicitudInsumo" (
    "id" SERIAL NOT NULL,
    "fechaSolicitud" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fechaAprobacion" TIMESTAMP(3),
    "aprobado" BOOLEAN NOT NULL DEFAULT false,
    "conjuntoId" INTEGER NOT NULL,
    "empresaId" INTEGER,

    CONSTRAINT "SolicitudInsumo_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SolicitudInsumoItem" (
    "id" SERIAL NOT NULL,
    "solicitudId" INTEGER NOT NULL,
    "insumoId" INTEGER NOT NULL,
    "cantidad" INTEGER NOT NULL,

    CONSTRAINT "SolicitudInsumoItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SolicitudMaquinaria" (
    "id" SERIAL NOT NULL,
    "fechaSolicitud" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fechaUso" TIMESTAMP(3) NOT NULL,
    "fechaDevolucionEstimada" TIMESTAMP(3) NOT NULL,
    "fechaAprobacion" TIMESTAMP(3),
    "aprobado" BOOLEAN NOT NULL DEFAULT false,
    "conjuntoId" INTEGER NOT NULL,
    "maquinariaId" INTEGER NOT NULL,
    "operarioId" INTEGER NOT NULL,
    "empresaId" INTEGER,

    CONSTRAINT "SolicitudMaquinaria_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "_OperarioConjuntos" (
    "A" INTEGER NOT NULL,
    "B" INTEGER NOT NULL,

    CONSTRAINT "_OperarioConjuntos_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE UNIQUE INDEX "Usuario_correo_key" ON "Usuario"("correo");

-- CreateIndex
CREATE UNIQUE INDEX "Inventario_conjuntoId_key" ON "Inventario"("conjuntoId");

-- CreateIndex
CREATE UNIQUE INDEX "InventarioInsumo_inventarioId_insumoId_key" ON "InventarioInsumo"("inventarioId", "insumoId");

-- CreateIndex
CREATE UNIQUE INDEX "Empresa_nit_key" ON "Empresa"("nit");

-- CreateIndex
CREATE UNIQUE INDEX "SolicitudInsumoItem_solicitudId_insumoId_key" ON "SolicitudInsumoItem"("solicitudId", "insumoId");

-- CreateIndex
CREATE INDEX "_OperarioConjuntos_B_index" ON "_OperarioConjuntos"("B");

-- AddForeignKey
ALTER TABLE "Gerente" ADD CONSTRAINT "Gerente_id_fkey" FOREIGN KEY ("id") REFERENCES "Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Gerente" ADD CONSTRAINT "Gerente_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Administrador" ADD CONSTRAINT "Administrador_id_fkey" FOREIGN KEY ("id") REFERENCES "Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "JefeOperaciones" ADD CONSTRAINT "JefeOperaciones_id_fkey" FOREIGN KEY ("id") REFERENCES "Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "JefeOperaciones" ADD CONSTRAINT "JefeOperaciones_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Supervisor" ADD CONSTRAINT "Supervisor_id_fkey" FOREIGN KEY ("id") REFERENCES "Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Operario" ADD CONSTRAINT "Operario_id_fkey" FOREIGN KEY ("id") REFERENCES "Usuario"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Tarea" ADD CONSTRAINT "Tarea_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "Operario"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Tarea" ADD CONSTRAINT "Tarea_supervisorId_fkey" FOREIGN KEY ("supervisorId") REFERENCES "Supervisor"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Tarea" ADD CONSTRAINT "Tarea_ubicacionId_fkey" FOREIGN KEY ("ubicacionId") REFERENCES "Ubicacion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Tarea" ADD CONSTRAINT "Tarea_elementoId_fkey" FOREIGN KEY ("elementoId") REFERENCES "Elemento"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Tarea" ADD CONSTRAINT "Tarea_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Tarea" ADD CONSTRAINT "Tarea_empresaAprobadaId_fkey" FOREIGN KEY ("empresaAprobadaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Tarea" ADD CONSTRAINT "Tarea_empresaRechazadaId_fkey" FOREIGN KEY ("empresaRechazadaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Conjunto" ADD CONSTRAINT "Conjunto_administradorId_fkey" FOREIGN KEY ("administradorId") REFERENCES "Administrador"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Conjunto" ADD CONSTRAINT "Conjunto_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Ubicacion" ADD CONSTRAINT "Ubicacion_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Elemento" ADD CONSTRAINT "Elemento_ubicacionId_fkey" FOREIGN KEY ("ubicacionId") REFERENCES "Ubicacion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Insumo" ADD CONSTRAINT "Insumo_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Inventario" ADD CONSTRAINT "Inventario_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventarioInsumo" ADD CONSTRAINT "InventarioInsumo_inventarioId_fkey" FOREIGN KEY ("inventarioId") REFERENCES "Inventario"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventarioInsumo" ADD CONSTRAINT "InventarioInsumo_insumoId_fkey" FOREIGN KEY ("insumoId") REFERENCES "Insumo"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConsumoInsumo" ADD CONSTRAINT "ConsumoInsumo_inventarioId_fkey" FOREIGN KEY ("inventarioId") REFERENCES "Inventario"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConsumoInsumo" ADD CONSTRAINT "ConsumoInsumo_insumoId_fkey" FOREIGN KEY ("insumoId") REFERENCES "Insumo"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConsumoInsumo" ADD CONSTRAINT "ConsumoInsumo_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConsumoInsumo" ADD CONSTRAINT "ConsumoInsumo_tareaId_fkey" FOREIGN KEY ("tareaId") REFERENCES "Tarea"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Maquinaria" ADD CONSTRAINT "Maquinaria_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Maquinaria" ADD CONSTRAINT "Maquinaria_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "Operario"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Maquinaria" ADD CONSTRAINT "Maquinaria_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InsumoConsumoEmpresa" ADD CONSTRAINT "InsumoConsumoEmpresa_insumoId_fkey" FOREIGN KEY ("insumoId") REFERENCES "Insumo"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InsumoConsumoEmpresa" ADD CONSTRAINT "InsumoConsumoEmpresa_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudTarea" ADD CONSTRAINT "SolicitudTarea_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudTarea" ADD CONSTRAINT "SolicitudTarea_ubicacionId_fkey" FOREIGN KEY ("ubicacionId") REFERENCES "Ubicacion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudTarea" ADD CONSTRAINT "SolicitudTarea_elementoId_fkey" FOREIGN KEY ("elementoId") REFERENCES "Elemento"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudTarea" ADD CONSTRAINT "SolicitudTarea_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudInsumo" ADD CONSTRAINT "SolicitudInsumo_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudInsumo" ADD CONSTRAINT "SolicitudInsumo_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudInsumoItem" ADD CONSTRAINT "SolicitudInsumoItem_solicitudId_fkey" FOREIGN KEY ("solicitudId") REFERENCES "SolicitudInsumo"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudInsumoItem" ADD CONSTRAINT "SolicitudInsumoItem_insumoId_fkey" FOREIGN KEY ("insumoId") REFERENCES "Insumo"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudMaquinaria" ADD CONSTRAINT "SolicitudMaquinaria_conjuntoId_fkey" FOREIGN KEY ("conjuntoId") REFERENCES "Conjunto"("nit") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudMaquinaria" ADD CONSTRAINT "SolicitudMaquinaria_maquinariaId_fkey" FOREIGN KEY ("maquinariaId") REFERENCES "Maquinaria"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudMaquinaria" ADD CONSTRAINT "SolicitudMaquinaria_operarioId_fkey" FOREIGN KEY ("operarioId") REFERENCES "Operario"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudMaquinaria" ADD CONSTRAINT "SolicitudMaquinaria_empresaId_fkey" FOREIGN KEY ("empresaId") REFERENCES "Empresa"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_OperarioConjuntos" ADD CONSTRAINT "_OperarioConjuntos_A_fkey" FOREIGN KEY ("A") REFERENCES "Conjunto"("nit") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_OperarioConjuntos" ADD CONSTRAINT "_OperarioConjuntos_B_fkey" FOREIGN KEY ("B") REFERENCES "Operario"("id") ON DELETE CASCADE ON UPDATE CASCADE;
