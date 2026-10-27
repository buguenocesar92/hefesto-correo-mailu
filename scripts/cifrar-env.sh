#!/usr/bin/env bash
# =====================================================================
# cifrar-env.sh - Cifra el .env de Mailu con la clave publica age.
#
# - NO borra el original.
# - NO escribe la clave privada en ningun sitio: es un insumo externo.
# - Sin AGE_RECIPIENTE falla con codigo 1: no hay modo degradado a texto
#   plano, porque el .env contiene el SECRET_KEY de Mailu.
# - El descifrado es con `age -d -i <clave_privada>`.
#
# Uso: ./scripts/cifrar-env.sh [RUTA_ENV]
# =====================================================================
set -euo pipefail

ORIGEN="${1:-$(cd "$(dirname "$0")/.." && pwd)/.env}"
PUBKEY="${AGE_RECIPIENTE:-${AGE_RECIPIENT:-}}"

if [ -z "${PUBKEY}" ]; then
  echo "falta AGE_RECIPIENTE: la clave publica age del receptor de los respaldos" >&2
  echo "Es un insumo externo: no se genera aqui. Definala en el entorno." >&2
  exit 1
fi

command -v age >/dev/null || { echo "age no esta instalado" >&2; exit 1; }
[ -f "${ORIGEN}" ] || { echo "no existe ${ORIGEN}" >&2; exit 1; }

DESTINO="${ORIGEN}.age"
age -r "${PUBKEY}" -o "${DESTINO}" "${ORIGEN}"
sha256sum "${DESTINO}" > "${DESTINO}.sha256"
chmod 600 "${DESTINO}" 2>/dev/null || true

echo "Cifrado: ${DESTINO} (el original NO se borra)"
echo "Descifrar: age -d -i CLAVE_PRIVADA ${DESTINO} > .env"
