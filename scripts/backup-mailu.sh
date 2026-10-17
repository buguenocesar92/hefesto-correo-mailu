#!/usr/bin/env bash
# =====================================================================
# backup-mailu.sh - Respaldo completo de Mailu
# Kit Hefesto Studio | Mailu 2024.06.64 | Estado: kit preparado
# =====================================================================
# QUE RESPALDA ESTE SCRIPT
#   mail       -> el Maildir: TODO el correo de todos los buzones.
#                 Irreemplazable. Si el cliente no tiene copia, no hay
#                 segunda oportunidad.
#   data       -> base del panel de administracion (SQLite main.db con
#                 usuarios, dominios, alias y cuotas) y base de Roundcube.
#   dkim       -> claves privadas DKIM. Si se pierden, hay que generar
#                 claves nuevas Y republicar el registro DNS.
#   certs      -> certificados TLS que presenta el servidor.
#   mailqueue  -> correo en cola, todavia no entregado.
#   filter     -> base de aprendizaje de Rspamd.
#   webmail    -> datos de Roundcube (preferencias, contactos).
#
# QUE NO RESPALDA, Y POR QUE
#   redis      -> cache de sesiones y limitador de autenticacion. Es
#                 efimera: se reconstruye sola al arrancar.
#   .env       -> NO se respalda porque contiene secretos en claro.
#                 Guardalo aparte, cifrado, junto al respaldo. Si pierdes
#                 SECRET_KEY hay que regenerarla y toda la sesion del
#                 panel se invalida. Ver docs/05-RESPALDOS-Y-RESTAURACION.md
#
# COMO LO USA ESTE SCRIPT
#   1. Verifica que docker y el archivo .env existan.
#   2. Detiene TODOS los servicios de Mailu, para que el correo no se
#      modifique mientras se copia. Sin esto, el respaldo puede quedar
#      inconsistente.
#   3. Verifica que cada volumen exista y NO este vacio.
#   4. Copia cada volumen en un tar dentro del destino.
#   5. Calcula SHA-256 de cada tar.
#   6. Escribe el manifiesto con el inventario.
#   7. Escribe el archivo .completo AL FINAL, como unico indicador de
#      que el respaldo termino bien. Si falta, el respaldo no sirve.
#   8. Vuelve a levantar los servicios.
#
# En caso de error, intenta volver a levantar los servicios y sale
# con codigo distinto de cero.
#
# USO
#   ./scripts/backup-mailu.sh [DESTINO]
#
#   DESTINO  Directorio donde se escribe el respaldo.
#            Por defecto: ./respaldos/mailu-<fecha>
#            Debe estar FUERA del directorio del proyecto.
#
# OPCIONES
#   --sin-parar   No detiene los servicios. Inseguro: el correo puede
#                 cambiar durante la copia. Solo para volúmenes de
#                 bajo tráfico de lectura.
# =====================================================================

set -Eeuo pipefail

# --- configuración ------------------------------------------------------
readonly MAILU_VERSION_ESPERADA="2024.06.64"
readonly NOMBRE_PROYECTO_POR_DEFECTO="mailu"

# Volúmenes respaldados: "nombre_logico:descripcion"
readonly VOLUMENES_A_RESPALDAR=(
    "mail:Maildir con todo el correo de los buzones"
    "data:base del panel de administracion (SQLite) y de Roundcube"
    "dkim:claves privadas DKIM de los dominios"
    "certs:certificados TLS del servidor"
    "mailqueue:cola de correo no entregado"
    "filter:base de aprendizaje del antispam Rspamd"
    "webmail:datos del webmail Roundcube"
)

# --- utilidades ---------------------------------------------------------

registrar() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fallar() {
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
    exit 1
}

# Devuelve un codigo de salida si el comando existe.
tiene() {
    command -v "$1" >/dev/null 2>&1
}

# Estado de los servicios, para poder restaurarlos.
SERVICIOS_DETENIDOS="false"

relanzar_servicios() {
    if [ "$SERVICIOS_DETENIDOS" = "true" ]; then
        registrar "Relanzando los servicios de Mailu"
        if ! docker compose -f "$ARCHIVO_COMPOSE" up -d; then
            printf '%s\n' \
                "[AVISO] No se pudieron relanzar los servicios automaticamente." \
                "         Revisa con: docker compose -f $ARCHIVO_COMPOSE ps" >&2
            return 1
        fi
    fi
    return 0
}

# Si algo falla, intenta dejar el servidor como estaba.
al_error() {
    local codigo=$?
    printf '\n' >&2
    fallar "El respaldo fallo (codigo $codigo). El marcador .completo NO fue escrito."
    relanzar_servicios || true
    exit "$codigo"
}

# --- argumentos ----------------------------------------------------------

DETENER="true"
ARGUMENTOS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --sin-parar)
            DETENER="false"
            ;;
        -h|--help)
            sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            ARGUMENTOS+=("$1")
            ;;
    esac
    shift
done

set -- ${ARGUMENTOS+"${ARGUMENTOS[@]}"}

# --- validaciones previas ------------------------------------------------

tiene docker || fallar "No se encontro 'docker' en el PATH."
docker compose version >/dev/null 2>&1 || \
    fallar "Se necesita el plugin 'docker compose' (Compose v2). No se encontro."

# El compose se busca primero junto al script (raiz del kit) y despues
# en el directorio actual.
RAIZ_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVO_COMPOSE="$RAIZ_KIT/compose.yaml"

[ -f "$ARCHIVO_COMPOSE" ] || ARCHIVO_COMPOSE="./compose.yaml"
[ -f "$ARCHIVO_COMPOSE" ] || \
    fallar "No se encontro compose.yaml. Ubicacion buscada: $RAIZ_KIT/compose.yaml"

[ -f "./.env" ] || \
    fallar "No se encontro ./.env. El respaldo lee los volumenes del proyecto activo."

# Nombre real del proyecto, leido del .env para no respaldar el equivocado.
NOMBRE_PROYECTO="$(grep -E '^COMPOSE_PROJECT_NAME=' ./.env 2>/dev/null \
    | head -n1 | cut -d= -f2- | tr -d '"'"'"' ' || true)"
NOMBRE_PROYECTO="${NOMBRE_PROYECTO:-$NOMBRE_PROYECTO_POR_DEFECTO}"

FECHA="$(date '+%Y%m%d-%H%M%S')"
DESTINO="${1:-./respaldos/mailu-$FECHA}"

# El destino no puede vivir dentro del proyecto: un respaldo dentro
# del directorio de trabajo se respalda a si mismo.
case "$(cd "$(dirname "$DESTINO")" 2>/dev/null && pwd || echo "$DESTINO")" in
    "$RAIZ_KIT"*)
        fallar "El destino no puede estar dentro del proyecto. Destino: $DESTINO"
        ;;
esac

[ -e "$DESTINO" ] && fallar "El destino ya existe: $DESTINO. Usa un directorio nuevo."

trap al_error ERR

registrar "Respaldo de Mailu"
registrar "  Proyecto:  $NOMBRE_PROYECTO"
registrar "  Compose:   $ARCHIVO_COMPOSE"
registrar "  Destino:   $DESTINO"
registrar "  Servidores: se detendran" || true
[ "$DETENER" = "false" ] && registrar "  AVISO: --sin-parar, el respaldo puede quedar inconsistente"

# --- preparacion ---------------------------------------------------------

mkdir -p "$DESTINO" || fallar "No se pudo crear el destino: $DESTINO"
DESTINO="$(cd "$DESTINO" && pwd)"
ARCHIVO_MANIFIESTO="$DESTINO/manifiesto.txt"
ARCHIVO_SUMAS="$DESTINO/SHA256SUMS"
MARCADOR="$DESTINO/.completo"

# --- deteccion del puerto 25 (informativa, no bloquea) --------------------

# El respaldo NO depende del puerto 25, pero conviene avisar si el
# servidor no tiene el 25 saliente, porque es la causa mas comun de
# "instalo Mailu y no me llega nada".
PUERTO_25_BLOQUEADO="desconocido"
if tiene timeout; then
    if timeout 10 bash -c 'exec 3<>/dev/tcp/mx.gmail.com/25' 2>/dev/null; then
        PUERTO_25_BLOQUEADO="libre desde este servidor"
    else
        PUERTO_25_BLOQUEADO="NO responde desde este servidor. Si el cliente no recibe correo, el bloqueo del puerto 25 saliente es la primera causa a revisar. Ver docs/08-SERVICIOS-COMERCIALES.md"
    fi
fi
registrar "  Puerto 25 saliente: $PUERTO_25_BLOQUEADO"

# --- detenido de servicios -----------------------------------------------

if [ "$DETENER" = "true" ]; then
    registrar "Deteniendo los servicios de Mailu para copiar sin escrituras"
    docker compose -f "$ARCHIVO_COMPOSE" stop
    SERVICIOS_DETENIDOS="true"
else
    registrar "No se detienen los servicios (--sin-parar)"
fi

# --- copia de volumenes --------------------------------------------------

ARCHIVOS_RESPALDOS=()

for entrada in "${VOLUMENES_A_RESPALDAR[@]}"; do
    volumen_logico="${entrada%%:*}"
    descripcion="${entrada#*:}"
    volumen_real="${NOMBRE_PROYECTO}_${volumen_logico}"
    archivo_tar="${DESTINO}/${volumen_logico}.tar"

    if ! punto_montaje="$(docker volume inspect -f '{{ .Mountpoint }}' "$volumen_real" 2>/dev/null)"; then
        printf '%s\n' \
            "  [OMITIDO] $volumen_logico: el volumen $volumen_real no existe." \
            "             $descripcion" \
            "             Si es la primera vez que respaldas, puede ser normal." >&2
        continue
    fi

    if [ ! -d "$punto_montaje" ]; then
        printf '%s\n' "  [OMITIDO] $volumen_logico: $punto_montaje no es un directorio." >&2
        continue
    fi

    # Un volumen vacio en el volumen del correo significa algo muy
    # distinto a un volumen vacio en, por ejemplo, la cola.
    if [ -z "$(ls -A "$punto_montaje" 2>/dev/null)" ]; then
        if [ "$volumen_logico" = "mail" ]; then
            fallar "El volumen de correo ($volumen_real) esta VACIO. No hay nada que respaldar. Revisa que el servidor se haya inicializado bien."
        fi
        registrar "  $volumen_logico: vacio, se omite"
        continue
    fi

    registrar "  Respaldando $volumen_logico ($descripcion)"
    tar -C "$punto_montaje" -cf "$archivo_tar" . || \
        fallar "Fallo la copia del volumen $volumen_logico"

    ARCHIVOS_RESPALDOS+=("$(basename "$archivo_tar")")
done

# El correo es lo unico que no se puede recuperar de otro lado.
if ! printf '%s\n' "${ARCHIVOS_RESPALDOS[@]}" | grep -qx "mail.tar"; then
    fallar "El volumen de correo no aparece en el respaldo. Abortando: un respaldo sin correo no sirve."
fi

# --- sumas de verificacion ------------------------------------------------

registrar "Calculando sumas SHA-256"
(
    cd "$DESTINO"
    # Solo los .tar: el manifiesto todavia se esta escribiendo.
    sha256sum -- *.tar > "$ARCHIVO_SUMAS"
)

# --- manifiesto -----------------------------------------------------------

registrar "Escribiendo el manifiesto"
{
    echo "Manifiesto de respaldo de Mailu"
    echo "================================"
    echo "Generado:        $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Proyecto:        $NOMBRE_PROYECTO"
    echo "Version esperada: $MAILU_VERSION_ESPERADA"
    echo "Compose:         $ARCHIVO_COMPOSE"
    echo "Servicios detenidos durante el respaldo: $DETENER"
    echo "Puerto 25 saliente: $PUERTO_25_BLOQUEADO"
    echo ""
    echo "Volumenes respaldados"
    echo "---------------------"
    for entrada in "${VOLUMENES_A_RESPALDAR[@]}"; do
        volumen_logico="${entrada%%:*}"
        descripcion="${entrada#*:}"
        archivo="${DESTINO}/${volumen_logico}.tar"
        if [ -f "$archivo" ]; then
            printf '  %-12s %s\n' "$volumen_logico" "$descripcion"
        else
            printf '  %-12s %s [NO RESPALDADO]\n' "$volumen_logico" "$descripcion"
        fi
    done
    echo ""
    echo "Volumenes deliberadamente NO respaldados"
    echo "--------------------------------------"
    echo "  redis        cache de sesiones, se reconstruye sola"
    echo "  .env         contiene secretos en claro. Guardalo aparte y cifrado."
    echo ""
    echo "Verificacion de integridad"
    echo "-------------------------"
    echo "  cd \"$DESTINO\""
    echo "  sha256sum -c SHA256SUMS"
    echo ""
    echo "Este respaldo es VALIDO solo si el archivo .completo existe."
} > "$ARCHIVO_MANIFIESTO"

# --- marcador de finalizacion ---------------------------------------------

# Se escribe AL FINAL y por eso es la unica senal confiable. Si el
# respaldo se corto a la mitad, .completo no esta y hay que descartarlo.
registrar "Escribiendo el marcador de finalizacion"
printf 'Respaldo completo. Escrito el %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" > "$MARCADOR"

# --- cierre ---------------------------------------------------------------

relanzar_servicios || fallar "Respaldo terminado, pero no se pudieron relanzar los servicios."
trap - ERR

registrar "Respaldo terminado correctamente"
registrar "  Contenido:   $DESTINO"
registrar "  Manifiesto:  $ARCHIVO_MANIFIESTO"
registrar "  Sumas:       $ARCHIVO_SUMAS"
registrar ""
registrar "Antes de dar por buena la copia:"
registrar "  1. Copia .env a un lugar seguro y cifrado."
registrar "  2. Guarda una copia de este respaldo fuera del servidor."
registrar "  3. Prueba la restauracion en un equipo aparte. Un respaldo"
registrar "     que nunca se restaure no es un respaldo."
