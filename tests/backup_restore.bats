#!/usr/bin/env bats
# Ciclo de respaldo de hefesto-correo-mailu con datos sinteticos.
#
# No se levanta ningun contenedor: se comprueban las precondiciones del ciclo
# (que fallan ANTES de tocar Docker), la exclusicion del .env, el cifrado del
# .env con age y los healthchecks del compose.

load 'ayudante.bash'

setup() {
  preparar_kit
  unset AGE_RECIPIENT || true
  unset AGE_RECIPIENTE || true
}

@test "backup-mailu.sh exige el .env" {
  rm -f "$KIT/.env"
  run bash -c "cd '$KIT' && bash scripts/backup-mailu.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *".env"* ]]
}

@test "backup-mailu.sh se niega a escribir el destino dentro del proyecto" {
  run bash -c "cd '$KIT' && bash scripts/backup-mailu.sh ./destino-interno"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no puede estar dentro del proyecto"* ]]
}

@test "backup-mailu.sh NO respalda el .env" {
  # El script lo declara en su cabecera y en el manifiesto que escribe.
  run bash -c "grep -c 'NO se respalda porque contiene secretos en claro' '$RAIZ/scripts/backup-mailu.sh'"
  [ "$output" -ge 1 ]
  run bash -c "grep -cE 'cp .*\\.env |cp -a .*\\.env ' '$RAIZ/scripts/backup-mailu.sh'"
  [ "$output" -eq 0 ]
}

@test "restore-mailu.sh exige un origen valido" {
  run bash -c "cd '$KIT' && bash scripts/restore-mailu.sh /no/existe"
  [ "$status" -ne 0 ]
}

@test "cifrar-env.sh sin receptor falla y nombra la variable" {
  run bash "$RAIZ/scripts/cifrar-env.sh" "$KIT/.env"
  [ "$status" -ne 0 ]
  [[ "$output" == *"AGE_RECIPIENTE"* ]]
}

@test "cifrar-env.sh con receptor cifra el .env y no lo borra" {
  if ! generar_receptor_age; then skip "age-keygen no disponible en este entorno"; fi
  run bash -c "AGE_RECIPIENTE='$AGE_RECIPIENT' bash '$RAIZ/scripts/cifrar-env.sh' '$KIT/.env'"
  [ "$status" -eq 0 ]
  [ -f "$KIT/.env.age" ]
  [ -f "$KIT/.env" ]
  run bash -c "grep -c 'SECRET_KEY' '$KIT/.env.age' || true"
  [ "$output" -eq 0 ]
}

@test "cifrar-env.sh con receptor recupera el .env byte a byte" {
  if ! generar_receptor_age; then skip "age-keygen no disponible en este entorno"; fi
  run bash -c "AGE_RECIPIENTE='$AGE_RECIPIENT' bash '$RAIZ/scripts/cifrar-env.sh' '$KIT/.env'"
  [ "$status" -eq 0 ]
  age -d -i "$BATS_TEST_TMPDIR/age/clave.txt" "$KIT/.env.age" > "$BATS_TEST_TMPDIR/env.plano"
  cmp "$BATS_TEST_TMPDIR/env.plano" "$KIT/.env"
}

@test "los 8 servicios de Mailu declaran healthcheck" {
  run python3 - "$KIT/compose.yaml" <<'PY'
import re, sys
texto = open(sys.argv[1], encoding="utf-8").read()
servicios = ["front", "resolver", "admin", "imap", "smtp", "antispam", "webmail", "redis"]
for nombre in servicios:
    patron = r"(?m)^  %s:\n(?:(?!^  [a-zA-Z0-9_-]+:\n).)*" % re.escape(nombre)
    bloque = re.search(patron, texto, re.S)
    if not bloque:
        raise SystemExit("no se encontro el servicio " + nombre)
    if "healthcheck:" not in bloque.group(0):
        raise SystemExit("el servicio " + nombre + " no declara healthcheck")
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "el compose sigue sin ciclos y con front como entrada (regresion de la ola 1)" {
  run bats "$RAIZ/tests/compose.bats"
  [ "$status" -eq 0 ]
}

@test "shellcheck no reporta hallazgos de nivel warning" {
  run bash -c "cd '$RAIZ' && shellcheck -S warning -x scripts/*.sh"
  [ "$status" -eq 0 ]
}

@test "existe .env.example y no trae secretos reales" {
  [ -f "$RAIZ/.env.example" ]
  run bash -c "grep -E '(SECRET_KEY|PASSWORD)=' '$RAIZ/.env.example' | grep -vE '=(GENERAR|REEMPLAZAR|CAMBIAR|CHANGE_ME)*$' | wc -l"
  [ "$output" -eq 0 ]
}

@test "existe la politica de datos personales y la guia del SECRET_KEY" {
  [ -f "$RAIZ/docs/POLITICA-DATOS-PERSONALES.md" ]
  [ -f "$RAIZ/docs/RECUPERACION-SECRET-KEY.md" ]
}
