# 06 — Actualizaciones y reversión

Estado del kit: `kit preparado`. **Ninguna actualización se ha probado
desde este kit.**

---

## 1. La regla que no se negocia

> **No actualices sin un respaldo verificado hecho en las ultimas
> horas.**

Actualizar un servidor de correo no es un `docker pull`. Es cambiar el
software que **todo el correo del cliente depende** y donde un error no
se ve de inmediato: el servidor acepta el correo, muestra que salio, y
los rebotes llegan dias despues.

Orden fijo:

1. Respaldo verificado
2. Leer las notas de la release
3. Actualizar
4. Verificar
5. Con larevision, **verificar tambien**

---

## 2. Como funciona una actualizacion en Mailu

Dos cosas pasan a la vez, y conviene saberlo.

### 2.1 Las imagenes se cambian

El `.env` fija `MAILU_VERSION`. Cambiarla y volver a levantar hace que
Docker descargue las imagenes de esa version.

### 2.2 La base de datos se migra automaticamente

Al arrancar, el contenedor `admin` ejecuta:

```bash
flask db upgrade
```

Eso aplica las migraciones de Alembic pendientes. **Pasa solo, sin
preguntar.**

Consecuencia importante: las migraciones de base de datos **no siempre
tienen camino de vuelta**. Por eso el respaldo del paso 1 no es
discrecional: es lo unico que permite volver atras.

### 2.3 Cambiar el `.env` exige bajar y subir

Las variables se leen al arrancar el contenedor:

```bash
docker compose down
docker compose up -d
```

Reiniciar un servicio suelto **no** aplica un `.env` nuevo.

---

## 3. Procedimiento de actualizacion

### 3.1 Antes

```bash
# 1. Respaldo, y verificar que termino bien
./scripts/backup-mailu.sh /var/backups/mailu-antes-de-actualizar
ls -la /var/backups/mailu-antes-de-actualizar/.completo
cd /var/backups/mailu-antes-de-actualizar && sha256sum -c SHA256SUMS

# 2. Anotar la version actual
grep MAILU_VERSION .env

# 3. Copia de seguridad del .env actual
cp .env .env.bak
```

### 3.2 Leer las notas de la version nueva

```bash
curl -s https://api.github.com/repos/Mailu/Mailu/releases/latest \
  | grep -E '"tag_name"|"published_at"'
```

Las notas de Mailu distinguen dos formas de version:

> The main version X.Y (for example 2024.06) always reflects the latest
> changes. The pinned version X.Y.Z (for example 2024.06.64) is always
> pinned to a specific commit.

**Este kit usa la forma con commit fijo.** Para actualizar hay que
buscar explicitamente la ultima `X.Y.Z` de la serie.

### 3.3 Actualizar

```bash
# Editar MAILU_VERSION en el .env
# MAILU_VERSION=2024.06.65

docker compose pull
docker compose down
docker compose up -d
```

### 3.4 Verificar

```bash
# Todos los servicios arriba
docker compose ps

# El panel responde
curl -sk https://mail.ejemplo.cl/admin/ping

# Los buzones siguen ahi
docker compose exec admin flask mailu domain ejemplo.cl -u

# El DKIM sigue validando
docker compose exec admin flask mailu dkim-test ejemplo.cl

# Un correo de entrada y uno de salida, ambos llegando
```

### 3.5 Deshacer, si algo falla

```bash
# 1. Volver a la version anterior
#    Editar MAILU_VERSION en el .env con el valor anotado en 3.1
docker compose pull
docker compose down
docker compose up -d

# 2. Si la base quedo en un estado intermedio, restaurar
cd /opt/mailu
./scripts/restore-mailu.sh /var/backups/mailu-antes-de-actualizar
```

El paso 2 es el que resuelve los casos en que la migracion de base de
datos dejo el schema a medio camino. Ver `05-RESPALDOS-Y-RESTAURACION.md`.

---

## 4. Decidir cuando actualizar

Actualizar tiene costos y tambien riesgos. La politica que este kit
recomienda:

| Situacion | Decision |
| --- | --- |
| Hay una version `X.Y.Z` nueva de la misma serie `X.Y` | Actualizar pronto. Es una correccion, no un salto mayor |
| Hay que cambiar de serie (`2024.06` a otra) | Con planificacion. Revisar notas, respaldar y ensayar en otro equipo |
| El cliente tiene un contrato con fechas de entrega | No actualizar la semana antes de una entrega |
| No hay nadie disponible para verificar | No actualizar. Un servidor caido el viernes a la noche no se arregla solo |

**Actualizar con una persona de Hefesto Studio disponible** para
verificar el resultado. No es opcional.

---

## 5. Actualizaciones del sistema anfitrion

Distinto de Mailu, y con su propio ritmo:

| Componente | Frecuencia sugerida | Nota |
| --- | --- | --- |
| Seguridad del sistema | Cada mes | `apt upgrade` |
| Docker Engine | Cada mes | Reinicia contenedores |
| Versiones de imagenes | Cada mes | Fijadas por `MAILU_VERSION` |

Reiniciar Docker **reinicia los contenedores de Mailu**. Con
`restart: unless-stopped`, vuelven solos, pero hay una interrupcion de
servicio de unos segundos. Para una Pyme es aceptable si no es en
horario de uso.

---

## 6. Compatibilidad de la base de datos al revertir

Este es el punto que mas problemas causa, y conviene entenderlo.

Al arrancar, `admin` aplica migraciones de Alembic automaticamente. Si
se actualiza de `A` a `B`, la base queda con el schema de `B`.

Al volver de `B` a `A`, Mailu **no baja el schema**. La migracion no
tiene reversa automatica, y no siempre existe.

| Situacion | Que hacer |
| --- | --- |
| Volver de `B` a `A` sin cambios en la base | Funciona. Las columnas de mas sobran |
| La base de `B` cambio de forma incompatible | Restaurar el respaldo de antes de actualizar |
| No hay respaldo | El problema es grande. Ver `05-RESPALDOS-Y-RESTAURACION.md`, seccion 8 |

**Moraleja:** el respaldo de antes de actualizar es la unica red de
seguridad real. Sin el, revertir no es garantizable.

---

## 7. Sobre actualizar sin querer

Coolify y los despliegues automaticos tienen una forma tipica de
actualizar Mailu sin quererlo: un `git pull` que cambia el `.env` o un
"reconstruir" que sube a `master`.

Para evitarlo:

- Fija `MAILU_VERSION` en el `.env` y no lo toques sin querer.
- Si el despliegue es automatico, desactivalo para este proyecto.
- Revisa que la imagen no quede en `:latest` ni en un rango abierto.

Este kit **no usa `:latest` en ninguna imagen**. La unica que lleva
digest fijo es Redis, y Mailu va por etiqueta exacta.

---

## 8. References

- Notas de la release: <https://api.github.com/repos/Mailu/Mailu/releases/latest>
- Arranque del contenedor admin y migraciones: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/start.py>
- Comandos del panel: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/manage.py>
- Preguntas frecuentes: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/faq.rst>
