# 10 — Licencias y fuentes

Este documento es la bitácora de verificación del kit: **qué se
comprobó, contra qué fuente y cuándo**. Para las licencias de cada
componente instalado, ver `../LICENCIAS.md`.

Estado del kit: `kit preparado`.

---

## 1. Versión verificada

| Dato | Valor | Fuente |
| --- | --- | --- |
| Etiqueta de la release | `2024.06.64` | API de releases de Mailu |
| Nombre de la release | `2024.06.64` | API de releases de Mailu |
| Publicada | 2026-10-15 | API de releases de Mailu |
| Rama de la serie | `2024.06` | Cuerpo de la release |

Consulta:
<https://api.github.com/repos/Mailu/Mailu/releases/latest>

Cita textual de la release, sobre la diferencia entre la versión de
rama y la versión fijada:

> The main versión X.Y (for example 2024.06) always reflects the latest
> changes. The pinned versión X.Y.Z (for example 2024.06.64) is always
> pinned to a specific commit and does not change.

Por eso este kit usa la forma con commit fijo.

---

## 2. Licencia verificada

**MIT.** Leida del archivo `LICENSE.md` del tag `2024.06.64`:

<https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/LICENSE.md>

Primera linea del archivo:

> MIT License
> Copyright (c) 2016 All Mailu contributors at the date

Refuerzo en el README del mismo tag:

<https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/README.md>

> All components are free software and compatible with the MIT license.

**No se copio el dato de ninguna guia de terceros.** La licencia se
verifico en el archivo del repositorio, en la versión exacta que este
kit despliega.

---

## 3. Registro de verificaciones

Todo lo siguiente se leyo directamente del código o de la documentacion
oficial en el tag `2024.06.64`.

### 3.1 Topologia de contenedores

Fuente: `setup/flavors/compose/docker-compose.yml` en el tag.

| Servicio | Imagen | Verificado |
| --- | --- | --- |
| `front` | `ghcr.io/mailu/nginx` | Si |
| `resolver` | `ghcr.io/mailu/unbound` | Si |
| `admin` | `ghcr.io/mailu/admin` | Si |
| `imap` | `ghcr.io/mailu/dovecot` | Si |
| `smtp` | `ghcr.io/mailu/postfix` | Si |
| `antispam` | `ghcr.io/mailu/rspamd` | Si |
| `webmail` | `ghcr.io/mailu/webmail` | Si |
| `redis` | `redis:alpine` en upstream | Si |

Servicios opcionales existentes en upstream y **no** incluidos:
`antivirus`, `webdav`, `fetchmail`, `fts_attachments`, `oletools`.

### 3.2 Base de datos del panel

Fuente: `core/admin/mailu/configuration.py` y `docs/configuration.rst`.

| Dato | Verificado |
| --- | --- |
| `SQLALCHEMY_DATABASE_URI` por defecto: `sqlite:////data/main.db` | Si |
| PostgreSQL y MariaDB admitidos pero **desaconsejados** | Si |
| **Supabase no aplica** | Consecuencia directa |

Cita de `configuration.rst`:

> Mailu is tested with SQLite and PostgreSQL/MariaDB. However the
> development team recommends against the use of PostgreSQL and
> MariaDB.

### 3.3 Volumenes y rutas

Fuente: la plantilla del compose y la documentacion de `compose`.

| Volumen | Ruta | Verificado |
| --- | --- | --- |
| Correo (Maildir) | `/mail` en `imap` | Si |
| Base del panel y de Roundcube | `/data` en `admin` | Si |
| Claves DKIM | `/dkim` en `admin` | Si |
| Certificados | `/certs` en `front` | Si |
| Cola de salida | `/queue` en `smtp` | Si |
| Aprendizaje del antispam | `/var/lib/rspamd` en `antispam` | Si |
| Overrides por servicio | `/overrides` | Si |

### 3.4 Puertos

Fuente: `docs/configuration.rst`.

| Dato | Verificado |
| --- | --- |
| `PORTS` por defecto: `25,80,443,465,993,995,4190` | Si |
| **587 no viene activo por defecto** | Si |
| 25, 465 y 993 no se pueden quitar | Si |
| 110 y 143 existen pero **este kit no los pública** | Si |

Decisión del kit: agregar el 587 y quitar el 995. Documentado en
`../VERSION.md`, seccion 5.

### 3.5 TLS

Fuente: `docs/compose/setup.rst` y `docs/configuration.rst`.

| Dato | Verificado |
| --- | --- |
| `TLS_FLAVOR`: `cert`, `letsencrypt`, `notls`, `mail`, `mail-letsencrypt` | Si |
| Los archivos deben llamarse `cert.pem` y `key.pem` | Si |
| Los enlaces simbolicos rompen la detección | Si |

### 3.6 Administración

Fuente: `core/admin/mailu/manage.py`.

Comandos verificados: `domain`, `user`, `admin`, `password`,
`user-delete`, `alias`, `setmanager`, `user-import`, `config-import`,
`config-export`.

Opciones de `config-export` verificadas: `-j`, `-y`, `-f`, `-s`,
`--dns`, `--without-users`, `--without-aliases`, `--without-datas`,
`--without-fetchmails`.

Opciones de `user-import` verificadas: `--dry-run`, `--sep`, `--quote`,
`--skip-header`, `--skip-existing`, `--skip-invalid`, `--yes`.

### 3.7 Primer arranque

Fuente: `core/admin/start.py`.

| Dato | Verificado |
| --- | --- |
| `INITIAL_ADMIN_ACCOUNT`, `_DOMAIN`, `_PW`, `_MODE` | Si |
| Modos `create`, `ifmissing`, `update` | Si |
| El panel corre `flask db upgrade` al arrancar | Si |
| **Exige un resolutor con DNSSEC valida** | Si |

Cita del código:

> Mailu 1.9 introduces a requirement that the host machine is running a
> DNSSEC validating resolver

### 3.8 Resolutor DNSSEC obligatorio

Fuente: `docs/compose/setup.rst`.

> Mailu 1.9 introduces a requirement that the host machine is running a
> DNSSEC validating resolver, since some DNS entries are DNSS signed and
> required for the mail server to work correctly. The current status of
> this can be checked on https://dnssec.works.

Por eso `resolver` no es opcional en el `compose.yaml` de este kit.

### 3.9 Cambios en el `.env`

Fuente: `docs/faq.rst`.

> If you change the configuration of Mailu (in the .env), you need to
> restart the containers. The environment variables are read at
> container startup.

### 3.10 SPF y NAT

Fuente: `docs/faq.rst`.

> If you are behind a NAT ... the SPF check will fail because the
> reverse DNS does not match.

De ahi la recomendacion de fijar `BIND4` a la IP pública cuando el
servidor la tiene.

### 3.11 Redis

Fuente: API pública de Docker Hub.

| Dato | Valor |
| --- | --- |
| Etiqueta | `7.2.16-alpine` |
| Digest del indice multiplataforma | `sha256:29e8589c3f9ba699b5f7aa4b3c7733c58852a3626439e619aa0ee78de08c6ca0` |

Consulta: <https://hub.docker.com/v2/repositories/library/redis/tags/7.2.16-alpine>

---

## 4. Lo que NO se pudo verificar

| Dato | Motivo |
| --- | --- |
| **Digest de las imagenes de Mailu** | `ghcr.io` exige un token anónimo y una cabecera `Authorization`. El entorno de elaboracion no puede enviar cabeceras. Procedimiento para resolverlo en `../VERSION.md` |
| **Cualquier prueba de ejecución** | No se levanto ningun contenedor. Ver `07-PRUEBAS-DE-ACEPTACION.md` |
| **shellcheck sobre los scripts** | No estaba instalado. Solo se valido la sintaxis con `bash -n` |

---

## 5. Reglas de estilo que se siguieron

- Todo el material en español de Chile.
- Sin caracteres fuera del español. Verificado con un barrido de los
  rangos CJK, cirílico, griego y hebreo sobre todos los archivos del
  kit.
- Los nombres de comandos, variables, rutas y claves de configuración
  se dejan en su forma original en ingles, porque es la que espera el
  software. Traducirlos rompería el despliegue.
- Las citas textuales del proyecto se conservan en ingles, marcadas
  como cita.
- Ninguna afirmacion sobre el comportamiento de Mailu que no venga de
  una de las fuentes listadas arriba.

---

## 6. Índice de fuentes

| Fuente | URL |
| --- | --- |
| Release actual | <https://api.github.com/repos/Mailu/Mailu/releases/latest> |
| Licencia | <https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/LICENSE.md> |
| README | <https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/README.md> |
| Plantilla del compose | <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml> |
| Plantilla del `.env` | <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/mailu.env> |
| Valores por defecto | <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/configuration.py> |
| Arranque del panel | <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/start.py> |
| CLI de administración | <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/manage.py> |
| Referencia de configuración | <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/configuration.rst> |
| Preguntas frecuentes | <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/faq.rst> |
| Requisitos | <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/compose/requirements.rst> |
| Instalación | <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/compose/setup.rst> |
| Registros DNS | <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/dns.rst> |
| Redis, etiqueta y digest | <https://hub.docker.com/v2/repositories/library/redis/tags/7.2.16-alpine> |

Todas consultadas sobre el tag `2024.06.64` salvo la release, que es
por definicion la mas reciente, y la de Redis.
