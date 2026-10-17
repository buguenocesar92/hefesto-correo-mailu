# VERSION.md — Mailu, kit de despliegue Hefesto Studio

Estado de este documento: todas las versiones y rutas de este archivo
fueron verificadas contra el repositorio oficial del proyecto. La
seccion "Digests" explica por que una parte queda como pendiente.

---

## 1. Version de Mailu usada por este kit

| Dato | Valor |
| --- | --- |
| Version de Mailu | `2024.06.64` |
| Etiqueta de Git | `2024.06.64` |
| Rama de la serie | `2024.06` |
| Publicada | 2026-10-15 |
| Registro de imagenes | `ghcr.io/mailu/*` |
| Licencia | MIT |

La version se fija en el `.env`:

```
MAILU_VERSION=2024.06.64
```

y se usa en `compose.yaml` para todas las imagenes del proyecto.

### Por que esa version y no la rama `master`

Upstream publica dos formas de version. El propio anuncio de la
release explica la diferencia:

> The main version X.Y (for example 2024.06) always reflects the
> latest changes. The pinned version X.Y.Z (for example 2024.06.64)
> is always pinned to a specific commit and does not change.

`master` se mueve con cada cambio. Para un servidor de correo de un
cliente, una actualizacion no auditada a las tres de la manana es un
riesgo innecesario. Por eso este kit queda en la version con
commit fijo.

Fuente: <https://api.github.com/repos/Mailu/Mailu/releases/latest>

### Como saber que hay una version nueva

```bash
curl -s https://api.github.com/repos/Mailu/Mailu/releases/latest \
  | grep '"tag_name"'
```

Actualizar no es automatico. Lee `docs/06-ACTUALIZACIONES-Y-REVERSION.md`
antes de cambiar `MAILU_VERSION`.

---

## 2. Digests de imagenes

### Lo que si esta fijado

| Imagen | Referencia |
| --- | --- |
| Redis | `redis:7.2.16-alpine@sha256:29e8589c3f9ba699b5f7aa4b3c7733c58852a3626439e619aa0ee78de08c6ca0` |

El digest de Redis **si** quedo resuelto y verificado: se consulto la
API publica de Docker Hub, que devuelve el digest del indice
multiplataforma de la etiqueta `7.2.16-alpine`.

### Lo que queda pendiente, y por que

Las imagenes de Mailu viven en `ghcr.io`, que es un registro privado
de facto: para consultar el digest de una etiqueta hay que pedir un
token de acceso anónimo y enviarlo en la cabecera `Authorization`.
Desde el entorno donde se escribio este kit no se pueden enviar
cabeceras, asi que **el digest de `ghcr.io/mailu/nginx:2024.06.64` y
de las demas imagenes de Mailu no quedo resuelto y no se invento**.

Lo que hace el kit es fijar la etiqueta exacta `2024.06.64`, que si es
inmutable en la practica por la politica de versionado de upstream.

### Como fijar los digests cuando lleves el kit al servidor

Ejecuta esto en la maquina destino y reemplaza las imagenes en
`compose.yaml` por su forma con digest:

```bash
for s in nginx unbound admin dovecot postfix rspamd webmail; do
  docker buildx imagetools inspect "ghcr.io/mailu/$s:2024.06.64" \
    --format '{{.Manifest.Digest}}'
done
```

Tambien sirve `crane digest ghcr.io/mailu/nginx:2024.06.64` si tienen
`crane` instalado.

Fijar por digest es lo recomendado para produccion: con digest, nadie
puede mover el contenido de una imagen que tu servidor ya descargo y
ejecuto.

---

## 3. Imagenes del kit

| Servicio | Imagen | Rol |
| --- | --- | --- |
| `front` | `ghcr.io/mailu/nginx` | Unico contenedor que publica puertos. Reverse proxy y TLS |
| `resolver` | `ghcr.io/mailu/unbound` | Resolutor DNS con validacion DNSSEC. Obligatorio en la practica |
| `admin` | `ghcr.io/mailu/admin` | Panel de administracion (Flask) y base SQLite interna |
| `imap` | `ghcr.io/mailu/dovecot` | IMAP. Monta el volumen con el correo |
| `smtp` | `ghcr.io/mailu/postfix` | SMTP, submission y cola de salida |
| `antispam` | `ghcr.io/mailu/rspamd` | Antispam y antiavirus de correo |
| `webmail` | `ghcr.io/mailu/webmail` | Roundcube (o SnappyMail) |
| `redis` | `redis:7.2.16-alpine` | Cache de sesiones. No es la base de Mailu |

Topologia verificada contra la plantilla oficial del proyecto en el
tag `2024.06.64`:
<https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml>

---

## 4. Imagenes que este kit NO incluye

El compose incluye solo los servicios indispensables. Los servicios
opcionales de Mailu existen, pero no se instalan aqui:

| Servicio opcional | Cuando se necesita | Estado en este kit |
| --- | --- | --- |
| `antivirus` | ClamAV para buscar virus en el correo entrante | No incluido |
| `webdav` | CalDAV/CARDDAV (Radicale) | No incluido |
| `fetchmail` | Traer correo desde un servidor antiguo | No incluido |
| `fts_attachments` | Indizacion de adjuntos (Apache Tika) | No incluido |
| `oletools` | Analisis de macros de Office | No incluido |

Cada uno anade consumo de memoria y superficie de ataque. Se agregan
solo cuando el cliente los pide y se anotan los costos. Ver
`docs/01-INSTALACION-DOCKER.md`.

---

## 5. Cambios respecto a guias de terceros

Estas son las diferencias que mas confunden cuando se copian guias
viejas. Todas fueron verificadas contra el codigo de la version
`2024.06.64`:

| En guias viejas | En Mailu 2024.06 |
| --- | --- |
| `LOGIN_RATELIMIT_IP` | Se llama `AUTH_RATELIMIT_IP` |
| Base de datos PostgreSQL obligatoria | SQLite por defecto (`sqlite:////data/main.db`). Upstream **desaconseja** PostgreSQL y MariaDB |
| El puerto 587 escucha por defecto | NO viene en `PORTS` por defecto. Hay que agregarlo |
| `mailu-config` con Lua separado | La configuracion se lee directo de variables de entorno |
| El contenedor `admin` es opcional | Sin `resolver` (unbound) el admin **no termina de arrancar** |
| Cambiar `.env` y reiniciar alcanza | Hay que bajar y volver a levantar el stack: `docker compose down && docker compose up -d` |

---

## 6. Fecha de compilacion de este kit

- Mailu verificado: 2024.06.64, release del 2026-10-15.
- Redis verificado: 7.2.16-alpine, digest multiplataforma confirmado
  contra Docker Hub.
- Estado de pruebas: **kit preparado**. Este kit nunca se ejecuto en un
  servidor. Ver `docs/07-PRUEBAS-DE-ACEPTACION.md`.
