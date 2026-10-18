#!/usr/bin/env bash
# =====================================================================
# restore-mailu.sh - Restauracion de Mailu desde un respaldo
# Kit Hefesto Studio | Mailu 2024.06.64 | Estado: kit preparado
# =====================================================================
# QUE HACE ESTE SCRIPT, EN ORDEN
#   1. Valida los argumentos y las herramientas disponibles.
#   2. Verifica que el respaldo este COMPLETO: exige SHA256SUMS y el
#      marcador .completo. Sin el marcador, no toca nada.
#   3. Verifica la integridad de cada .tar con sha256sum -c, ANTES de
#      modificar cualquier volumen.
#   4. Inspecciona el contenido de cada tar y RECHAZA rutas absolutas o
#      rutas con "..", que permitirian escribir fuera del volumen.
#   5. Comprueba que cada volumen de destino este VACIO. Si tiene datos,
#      aborta. Nunca pisa correo existente por su cuenta.
#   6. Crea los volumenes que falten y extrae dentro de ellos.
#   7. NO borra nada en ningun momento. No ejecuta DROP de la base.
#   8. Deja los servicios DETENIDOS al terminar.
#
# POR QUE DEJA EL SERVIDOR APAGADO
#   Una restauracion de correo necesita una revision manual antes de
#   volver a recibir. Si el script levantara el servidor solo, un
#   error de restauracion se convierte en perdida de correo entrante.
#   Levanta tu con:  docker compose up -d
#
# USO
#   ./scripts/restore-mailu.sh /ruta/al/respaldo [opciones]
#
# OPCIONES
#   --force       Restaura aunque los volumenes de destino tengan datos.
#                 AUN ASI no borra lo que hay: extrae encima y el
#                 contenido previo queda pisado. Solo usalo cuando la
#                 instalacion actual se descarta a proposito.
#   -n, --simula  No escribe nada. Muestra que pasaria. Recomendado
#                 siempre antes de una restauracion real.
#   -h, --ayuda   Esta ayuda.
#
# QUE DEBES HACER ANTES DE USAR ESTE SCRIPT
#   - Tener el .env del servidor original (contiene SECRET_KEY).
#   - Confirmar que la version de Mailu del .env es la misma del
#     respaldo, o superior compatible.
#   - Tener el dominio con los registros DNS intactos.
# =====================================================================

set -Eeuo pipefail

readonly NOMBRE_PROYECTO_POR_DEFECTO="mailu"

# Volumenes que se restauran, en el mismo orden y con los mismos
# nombres de archivo que usa backup-mailu.sh.
readonly VOLUMENES_A_RESTAURAR=(
    "mail"
    "data"
    "dkim"
    "certs"
    "mailqueue"
    "filter"
    "webmail"
)

utilidades() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fallar() {
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
    exit 1
}

tiene() {
    command -v "$1" >/dev/null 2>&1
}

SIMULAR="false"
FUERZA="false"
ORIGEN=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --force)
            FUERZA="true"
            ;;
        -n|--simula|--dry-run)
            SIMULAR="true"
            ;;
        -h|--help|--ayuda)
            sed -n '2,58p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            fallar "Opcion desconocida: $1"
            ;;
        *)
            if [ -n "$ORIGEN" ]; then
                fallar "Se paso mas de un directorio de origen. Usa uno solo."
            fi
            ORIGEN="$1"
            ;;
    esac
    shift
done

[ -n "$ORIGEN" ] || {
    sed -n '2,58p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
}

# --- herramientas ---------------------------------------------------------

tiene docker || fallar "No se encontro 'docker' en el PATH."
tiene tar    || fallar "No se encontro 'tar'."
tiene sha256sum || fallar "No se encontro 'sha256sum'."
docker compose version >/dev/null 2>&1 || \
    fallar "Se necesita el plugin 'docker compose' (Compose v2). No se encontro."

# --- localizacion ---------------------------------------------------------

RAIZ_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVO_COMPOSE="$RAIZ_KIT/compose.yaml"
[ -f "$ARCHIVO_COMPOSE" ] || ARCHIVO_COMPOSE="./compose.yaml"
[ -f "$ARCHIVO_COMPOSE" ] || \
    fallar "No se encontro compose.yaml. Ubicacion buscada: $RAIZ_KIT/compose.yaml"

[ -d "$ORIGEN" ] || fallar "El origen no es un directorio: $ORIGEN"
ORIGEN="$(cd "$ORIGEN" && pwd)"

[ -f "$ORIGEN/SHA256SUMS" ] || \
    fallar "Falta SHA256SUMS en $ORIGEN. No parece un respaldo de este kit. NADA fue modificado."

[ -f "$ORIGEN/.completo" ] || \
    fallar "Falta el marcador .completo en $ORIGEN. El respaldo esta incompleto o se corto a la mitad. NADA fue modificado. Lee docs/05-RESPALDOS-Y-RESTAURACION.md"

MANIFIESTO="$ORIGEN/manifiesto.txt"
[ -f "$MANIFIESTO" ] || \
    fallar "Falta manifiesto.txt en $ORIGEN. NADA fue modificado."

NOMBRE_PROYECTO="$(grep -E '^COMPOSE_PROJECT_NAME=' ./.env 2>/dev/null \
    | head -n1 | cut -d= -f2- | tr -d '"'"'"' ' || true)"
NOMBRE_PROYECTO="${NOMBRE_PROYECTO:-$NOMBRE_PROYECTO_POR_DEFECTO}"

utilidades "Restauracion de Mailu"
utilidades "  Origen:    $ORIGEN"
utilidades "  Proyecto:  $NOMBRE_PROYECTO"
utilidades "  Compose:   $ARCHIVO_COMPOSE"
[ "$SIMULAR" = "true" ] && utilidades "  MODO: simulacion, no se escribira nada"
[ "$FUERZA" = "true" ]   && utilidades "  AVISO: --force, se puede pisar correo existente"

# --- paso 1: integridad de las sumas --------------------------------------

utilidades ""
utilidades "Paso 1/4: verificando la integridad del respaldo"
(
    cd "$ORIGEN"
    sha256sum -c SHA256SUMS
) || fallar "Las sumas SHA-256 no coinciden. El respaldo esta CORRUPTO. NADA fue modificado."
utilidades "  Sumas correctas."

# --- paso 2: validacion de rutas dentro de los tar -------------------------

utilidades ""
utilidades "Paso 2/4: validando las rutas contenidas en los archivos"

validar_rutas_de_tar() {
    local archivo="$1"
    local entradas

    entradas="$(tar -tf "$archivo" 2>/dev/null)" || \
        fallar "No se pudo leer el contenido de $archivo. Puede estar corrupto."

    # Lineas sospechosas: ruta absoluta, salto de directorio, o enlace
    # simbolico que apunte fuera del volumen.
    local sospechosas
    sospechosas="$(printf '%s\n' "$entradas" \
        | grep -E '(^/|(^|/)\.\.(/|$))' \
        || true)"

    if [ -n "$sospechosas" ]; then
        printf '%s\n' "$sospechosas" | head -n 20 >&2
        fallar "El archivo $(basename "$archivo") contiene rutas no permitidas (absolutas o con '..'). Se aborta por seguridad. NADA fue modificado."
    fi
}

ARCHIVOS_A_RESTAURAR=()

for volumen_logico in "${VOLUMENES_A_RESTAURAR[@]}"; do
    archivo="$ORIGEN/${volumen_logico}.tar"
    if [ -f "$archivo" ]; then
        validar_rutas_de_tar "$archivo"
        ARCHIVOS_A_RESTAURAR+=("$volumen_logico")
        utilidades "  $volumen_logico.tar: rutas correctas"
    else
        utilidades "  $volumen_logico.tar: ausente en el respaldo, se omite"
    fi
done

# --- paso 3: estado de los volumenes de destino ---------------------------

utilidades ""
utilidades "Paso 3/4: comprobando los volumenes de destino"

resolver_punto_de_montaje() {
    local volumen_real="$1"
    docker volume inspect -f '{{ .Mountpoint }}' "$volumen_real" 2>/dev/null || true
}

# Un volumen existente con contenido es la situacion peligrosa: se
# pisaria correo que el cliente todavia no tiene respaldado.
volumenes_con_contenido=()

for volumen_logico in "${ARCHIVOS_A_RESTAURAR[@]}"; do
    volumen_real="${NOMBRE_PROYECTO}_${volumen_logico}"

    if docker volume inspect "$volumen_real" >/dev/null 2>&1; then
        punto_montaje="$(resolver_punto_de_montaje "$volumen_real")"
        if [ -n "$punto_montaje" ] && [ -d "$punto_montaje" ] && [ -n "$(ls -A "$punto_montaje" 2>/dev/null)" ]; then
            volumenes_con_contenido+=("$volumen_logico")
        fi
    fi
done

if [ "${#volumenes_con_contenido[@]}" -gt 0 ]; then
    utilidades "  Los siguientes volumenes YA TIENEN datos:"
    for v in "${volumenes_con_contenido[@]}"; do
        utilidades "    - $v"
    done
    if [ "$FUERZA" != "true" ]; then
        printf '\n' >&2
        printf '%s\n' \
            "ABORTADO: restaurar sobre estos volumenes pisaria correo que el cliente" \
            "todavia no tiene respaldado. Este script nunca sobrescribe por su cuenta." >&2
        printf '%s\n' \
            "Opciones legitimas:" \
            "  a) Apuntar la restauracion a un proyecto nuevo con otra variable" \
            "     COMPOSE_PROJECT_NAME, para comparar antes de cambiar nada." \
            "  b) Renombrar los volumenes actuales para conservarlos:" \
            "       docker volume rename <proyecto>_<volumen> <proyecto>_<volumen>-antes-de-restaurar" \
            "  c) Si de verdad queres pisar, usa --force, sabiendo que se pierde" \
            "     lo que hubiera ahora." >&2
        printf '%s\n' "NADA fue modificado." >&2
        exit 1
    fi
    printf '%s\n' "  --force activo: se restaurara encima." >&2
fi

# --- paso 4: restauracion -------------------------------------------------

utilidades ""
utilidades "Paso 4/4: restaurando"

if [ "$SIMULAR" = "true" ]; then
    for volumen_logico in "${ARCHIVOS_A_RESTAURAR[@]}"; do
        utilidades "  [simulado] $volumen_logico"
    done
    utilidades ""
    utilidades "Simulacion terminada. No se escribio nada."
    exit 0
fi

# Detiene los servicios antes de tocar los volumenes. Si algo estaba
# corriendo, se detiene; si no, no es un error.
if docker compose -f "$ARCHIVO_COMPOSE" ps --status running --quiet 2>/dev/null \
    | grep -q .; then
    utilidades "Deteniendo los servicios de Mailu"
    docker compose -f "$ARCHIVO_COMPOSE" stop
else
    utilidades "Los servicios ya estaban detenidos"
fi

for volumen_logico in "${ARCHIVOS_A_RESTAURAR[@]}"; do
    volumen_real="${NOMBRE_PROYECTO}_${volumen_logico}"
    archivo="$ORIGEN/${volumen_logico}.tar"

    if ! docker volume inspect "$volumen_real" >/dev/null 2>&1; then
        utilidades "  Creando el volumen $volumen_real"
        docker volume create "$volumen_real" >/dev/null
    fi

    punto_montaje="$(resolver_punto_de_montaje "$volumen_real")"
    [ -n "$punto_montaje" ] || fallar "No se pudo resolver el punto de montaje de $volumen_real."

    utilidades "  Extrayendo $volumen_logico en $punto_montaje"
    # -p conserva los permisos originales, que en el Maildir importan.
    tar -C "$punto_montaje" -xpf "$archivo" || \
        fallar "Fallo la extraccion de $volumen_logico. Revisa el espacio en disco."
done

utilidades ""
utilidades "Restauracion terminada."
utilidades ""
utilidades "  Los servicios quedan DETENIDOS a proposito."
utilidades ""
utilidades "  Antes de levantar el servidor, revisa:"
utilidades "    1. Que el .env sea el del servidor original (misma SECRET_KEY)."
utilidades "    2. Que los registros DNS del dominio sigan vigentes."
utilidades "    3. Que el dominio tenga los mismos buzones que antes, si es que"
utilidades "       cambiaste algo en el panel durante el intento fallido."
utilidades ""
utilidades "  Para levantar:"
utilidades "    docker compose -f $ARCHIVO_COMPOSE up -d"
utilidades ""
utilidades "  Si algo quedo mal, los respaldos anteriores siguen en disco."
