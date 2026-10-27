#!/usr/bin/env bats
# Regresion del compose de Mailu.
#
# Defectos que este fichero fija:
#
# 1. `services.webmail.networks.0 must be a string`: el elemento de lista
#    `- webmail:` se parsea como MAPA (clave "webmail" con valor nulo), no
#    como cadena, y `docker compose config` rechaza el compose entero.
#
# 2. Ciclo de dependencias: `front` dependia de imap/smtp/antispam/webmail y
#    esos cuatro dependian a su vez de `front`. Compose detecta un ciclo cada
#    vez y el conjunto no se puede ni arrancar ni validar.
#
# El compose declara `env_file: - .env`. Para que la comprobacion no dependa
# de un `.env` real (que NUNCA se lee ni se genera aqui), los tests renderizan
# el compose en un directorio temporal con una copia de `.env.example`.
#
# Estos tests no levantan contenedores: solo validan el modelo del compose.

setup() {
  RAIZ="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TMP_PROYECTO="$(mktemp -d "${TMPDIR:-/tmp}/mailu-compose.XXXXXX")"
  cp "${RAIZ}/compose.yaml" "${TMP_PROYECTO}/compose.yaml"
  cp "${RAIZ}/.env.example" "${TMP_PROYECTO}/.env"
  COMPOSE=(docker compose --project-directory "${TMP_PROYECTO}"
           -f "${TMP_PROYECTO}/compose.yaml" --env-file "${TMP_PROYECTO}/.env")
}

teardown() {
  rm -rf "${TMP_PROYECTO}"
}

@test "el compose es valido para la Compose Specification" {
  run "${COMPOSE[@]}" config -q
  [ "$status" -eq 0 ] || {
    echo "docker compose config fallo:" >&2
    echo "${output}" >&2
    return 1
  }
}

@test "ningun elemento de lista del compose termina en dos puntos" {
  run grep -nE "^[[:space:]]+-[[:space:]]+[A-Za-z0-9_.-]+:[[:space:]]*$" compose.yaml
  [ "$status" -ne 0 ] || {
    echo "elemento de lista malformado (se parsea como mapa, no como cadena):" >&2
    echo "${output}" >&2
    return 1
  }
}

@test "el grafo de dependencias no tiene ciclos" {
  run python3 - "${TMP_PROYECTO}" <<'PY'
import json
import subprocess
import sys

proyecto = sys.argv[1]
proc = subprocess.run(
    ["docker", "compose", "--project-directory", proyecto,
     "-f", f"{proyecto}/compose.yaml", "--env-file", f"{proyecto}/.env",
     "config", "--format", "json"],
    capture_output=True,
    text=True,
)
if proc.returncode != 0:
    print(proc.stderr.strip(), file=sys.stderr)
    sys.exit(1)

servicios = json.loads(proc.stdout).get("services", {})
grafo = {
    nombre: sorted((spec.get("depends_on") or {}).keys())
    for nombre, spec in servicios.items()
}

# Deteccion de ciclos por DFS con pila de camino.
estado = {}   # 0 = en curso, 1 = terminado
ciclo = []

def visitar(nodo, camino):
    if estado.get(nodo) == 1:
        return
    if estado.get(nodo) == 0:
        ciclo.append(" -> ".join(camino + [nodo]))
        return
    estado[nodo] = 0
    for siguiente in grafo.get(nodo, []):
        visitar(siguiente, camino + [nodo])
    estado[nodo] = 1

for nombre in sorted(grafo):
    visitar(nombre, [])

if ciclo:
    print("ciclo de dependencias: " + ciclo[0], file=sys.stderr)
    sys.exit(1)
print("ok")
PY
  [ "$status" -eq 0 ] || {
    echo "${output}" >&2
    return 1
  }
}

@test "front es el servicio de entrada y el resto arranca despues" {
  run python3 - "${TMP_PROYECTO}" <<'PY'
import json
import subprocess
import sys

proyecto = sys.argv[1]
proc = subprocess.run(
    ["docker", "compose", "--project-directory", proyecto,
     "-f", f"{proyecto}/compose.yaml", "--env-file", f"{proyecto}/.env",
     "config", "--format", "json"],
    capture_output=True,
    text=True,
)
if proc.returncode != 0:
    print(proc.stderr.strip(), file=sys.stderr)
    sys.exit(1)

servicios = json.loads(proc.stdout).get("services", {})
front = (servicios.get("front") or {}).get("depends_on") or {}
problemas = []
for nombre, condicion in front.items():
    if condicion.get("condition") not in (None, "service_started"):
        problemas.append(f"front depende de {nombre} con condition={condicion.get('condition')!r}")
for nombre, spec in servicios.items():
    if nombre == "front":
        continue
    dep = (spec.get("depends_on") or {}).get("front")
    if dep and dep.get("condition") not in (None, "service_started"):
        problemas.append(f"{nombre} depende de front con condition={dep.get('condition')!r}")
if problemas:
    print("; ".join(problemas), file=sys.stderr)
    sys.exit(1)
print("ok")
PY
  [ "$status" -eq 0 ] || {
    echo "${output}" >&2
    return 1
  }
}

@test "el compose declara los 8 servicios esperados" {
  run "${COMPOSE[@]}" config --services
  [ "$status" -eq 0 ]
  for servicio in front resolver admin imap smtp antispam webmail redis; do
    echo "${output}" | grep -qx "${servicio}" || {
      echo "falta el servicio ${servicio} en el compose renderizado" >&2
      return 1
    }
  done
}
