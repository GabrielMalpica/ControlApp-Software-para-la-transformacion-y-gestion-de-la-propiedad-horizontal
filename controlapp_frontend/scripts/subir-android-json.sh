#!/usr/bin/env bash
# Sube descargas/android.json a Hostinger por FTP (lo usa el workflow
# "App Android y web" después de subir el resto de la web; ver
# docs/app-android-sin-conexion.md, "Publicar una versión").
#
# Uso: bash scripts/subir-android-json.sh <ruta de android.json>
# Variables (las mismas del workflow):
#   HOSTINGER_FTP_SERVER, HOSTINGER_FTP_USER, HOSTINGER_FTP_PASSWORD,
#   HOSTINGER_FTP_DIR  carpeta de index.html desde la raíz de la cuenta FTP,
#                      terminada en / ("./" si la cuenta ya entra ahí).
#   FTP_PROTOCOLO      ftps (TLS explícito, por defecto), ftps-legacy (TLS
#                      implícito, puerto 990) o ftp (sin cifrar).
#   FTP_SEGURIDAD      strict (por defecto) o loose: no exige que el
#                      certificado tenga el nombre del servidor (el de
#                      Hostinger es *.hstgr.io); la conexión sigue cifrada.
#
# Es un solo archivo: no guarda estado en el servidor y curl reintenta con una
# conexión nueva si Hostinger la corta.

set -euo pipefail

archivo="${1:?Falta la ruta de android.json}"
[[ -f "$archivo" ]] || { echo "::error::No existe $archivo."; exit 1; }
for nombre in HOSTINGER_FTP_SERVER HOSTINGER_FTP_USER HOSTINGER_FTP_PASSWORD HOSTINGER_FTP_DIR; do
  [[ -n "${!nombre:-}" ]] || { echo "::error::Falta $nombre."; exit 1; }
done

opciones=()
case "${FTP_PROTOCOLO:-ftps}" in
  ftps) esquema=ftp; opciones+=(--ssl-reqd) ;;
  ftps-legacy) esquema=ftps ;;
  ftp) esquema=ftp ;;
  *) echo "::error::HOSTINGER_FTP_PROTOCOL debe ser ftps, ftps-legacy o ftp."; exit 1 ;;
esac
case "${FTP_SEGURIDAD:-strict}" in
  strict) ;;
  loose) opciones+=(--insecure) ;;
  *) echo "::error::HOSTINGER_FTP_SECURITY debe ser strict o loose."; exit 1 ;;
esac

# En una URL de curl la ruta es relativa a la carpeta con la que entra la
# cuenta; una ruta absoluta necesita %2F al comienzo.
dir="${HOSTINGER_FTP_DIR#./}"
if [[ "$dir" == /* ]]; then dir="%2F${dir#/}"; fi
servidor="${HOSTINGER_FTP_SERVER#*://}"
servidor="${servidor%/}"
url="${esquema}://${servidor}/${dir}descargas/android.json"

# Usuario y contraseña por la configuración de curl (stdin), no en la línea de
# comandos. Dentro de comillas, \ y " van escapados.
escapar() {
  local s="${1//\\/\\\\}"
  printf '%s' "${s//\"/\\\"}"
}
printf 'user = "%s:%s"\n' "$(escapar "$HOSTINGER_FTP_USER")" "$(escapar "$HOSTINGER_FTP_PASSWORD")" |
  curl --config - --fail --silent --show-error \
    "${opciones[@]}" --disable-epsv --ftp-create-dirs \
    --connect-timeout 30 --max-time 120 \
    --retry 5 --retry-delay 15 --retry-all-errors \
    --upload-file "$archivo" "$url"

echo "android.json subido."
