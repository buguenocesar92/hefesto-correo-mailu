# 07 — Pruebas de aceptación

> ## ESTADO DEL KIT: `kit preparado`
>
> **Este kit nunca se ejecutó en un servidor. En particular, NUNCA SE
> HA PROBADO EL ENVÍO REAL DE CORREO DESDE ESTE KIT.**
>
> No hay ninguna prueba de este documento marcada como aprobada que
> implique levantar contenedores, abrir puertos o enviar correo.

---

## 1. Que significa cada estado

| Estado | Significado |
| --- | --- |
| **Verificado** | Comprobado contra una fuente primaria durante la elaboracion de este kit |
| **Pendiente** | Hay que ejecutarlo en un servidor. Este kit no lo hizo |
| **Aprobada** | Se ejecuto y paso. **Ninguna prueba de envio real esta en esta categoria** |

Las pruebas marcadas como **Verificado** son de lectura de codigo y
documentacion. Se hizo con las fuentes listadas en
`10-LICENCIAS-Y-FUENTES.md`.

**No hay simulaciones presentadas como pruebas reales en este kit.**

---

## 2. Verificado contra fuente primaria

### 2.1 Version y licencia

| Dato | Verificado | Fuente |
| --- | --- | --- |
| Version `2024.06.64` | Si | API de releases de GitHub, etiqueta `2024.06.64`, publicada 2026-10-15 |
| Licencia **MIT** | Si | `LICENSE.md` del tag `2024.06.64` |
| Registro de imagenes `ghcr.io/mailu` | Si | Plantilla del compose en el tag |
| Redis `7.2.16-alpine` con digest | Si | API de Docker Hub, indice multiplataforma |

### 2.2 Topologia de contenedores

| Servicio | Imagen | Rol | Verificado |
| --- | --- | --- | --- |
| `front` | `ghcr.io/mailu/nginx` | TLS y proxy de todos los puertos | Si |
| `resolver` | `ghcr.io/mailu/unbound` | Resolutor DNSSEC | Si |
| `admin` | `ghcr.io/mailu/admin` | Panel Flask | Si |
| `imap` | `ghcr.io/mailu/dovecot` | IMAP, monta el volumen de correo | Si |
| `smtp` | `ghcr.io/mailu/postfix` | SMTP y cola | Si |
| `antispam` | `ghcr.io/mailu/rspamd` | Antispam | Si |
| `webmail` | `ghcr.io/mailu/webmail` | Roundcube | Si |
| `redis` | `redis:7.2.16-alpine` | Cache, no es la base de Mailu | Si |

Servicios opcionales que este kit **no** incluye: `antivirus`,
`webdav`, `fetchmail`, `fts_attachments`, `oletools`.

### 2.3 Base de datos del panel

| Dato | Verificado |
| --- | --- |
| `SQLALCHEMY_DATABASE_URI` por defecto es `sqlite:////data/main.db` | Si, leido de `configuration.py` |
| Upstream admite PostgreSQL y MariaDB pero **desaconseja** ambos | Si, leido de `configuration.rst` |
| **Supabase no aplica** | Consecuencia directa de lo anterior |

### 2.4 Volumenes

| Volumen | Ruta en el contenedor | Verificado |
| --- | --- | --- |
| `mail` | `/mail` en `imap` | Si |
| `data` | `/data` en `admin` | Si |
| `dkim` | `/dkim` en `admin` | Si |
| `certs` | `/certs` en `front` | Si |
| `mailqueue` | `/queue` en `smtp` | Si |
| `filter` | `/var/lib/rspamd` en `antispam` | Si |
| `redis` | `/data` en `redis` | Si |
| Overrides | `/overrides` en varios | Si |

### 2.5 Puertos y variables

| Dato | Verificado |
| --- | --- |
| `PORTS` por defecto upstream: `25,80,443,465,993,995,4190` | Si |
| El **587 no viene activo** por defecto | Si |
| 25, 465 y 993 no se pueden quitar de `PORTS` | Si |
| `RESOLVER_IP` y `SUBNET` | Si |
| `TLS_FLAVOR`: `cert`, `letsencrypt`, `notls` | Si |
| `INITIAL_ADMIN_*` y sus modos | Si, leido de `core/admin/start.py` |
| `DKIM_SELECTOR` y la ruta `/dkim/<dominio><selector>.key` | Si |
| El reslutor DNSSEC es obligatorio desde 1.9 | Si, leido de `core/admin/start.py` |

### 2.6 CLI de administracion

Comandos verificados leyendo `core/admin/mailu/manage.py`:
`domain`, `user`, `admin`, `password`, `user-delete`, `alias`,
`setmanager`, `config-import`, `config-export`.

### 2.7 Sintaxis de los scripts

| Prueba | Resultado |
| --- | --- |
| `bash -n scripts/backup-mailu.sh` | Sin errores de sintaxis |
| `bash -n scripts/restore-mailu.sh` | Sin errores de sintaxis |

`shellcheck` **no estaba disponible** en el entorno de elaboracion, asi
que el analisis estatico mas profundo **no se realizo**.

---

## 3. Lo que NO esta verificado

### 3.1 Envio real de correo

> **NUNCA SE HA PROBADO EL ENVIO REAL DE CORREO DESDE ESTE KIT.**

No se sabe si el stack levanta. No se sabe si un correo llega a
destino. No se sabe si un correo externo llega al servidor. No se sabe
si Rspamd clasifica correctamente. Todo eso es **Pendiente**.

Esta limitacion debe decirse al cliente antes de cobrar la primera
factura. No es un detalle menor: es la diferencia entre "funciona" y
"deberia funcionar".

### 3.2 Digests de las imagenes de Mailu

**Pendiente.** `ghcr.io` requiere un token de acceso anonimo
para consultar el digest de una etiqueta, y el entorno de elaboracion
no puede enviar cabeceras. El digest de Redis **si** quedo resuelto.

Procedimiento para resolverlo, en `VERSION.md`, seccion 2.

### 3.3 Todo lo que requiere un servidor

| Prueba | Estado |
| --- | --- |
| `docker compose config` valida el compose | Pendiente |
| `docker compose pull` descarga las imagenes | Pendiente |
| `docker compose up -d` levanta los 8 servicios | Pendiente |
| El contenedor `admin` supera la espera del resolutor DNSSEC | Pendiente |
| La migracion `flask db upgrade` corre sin error | Pendiente |
| El panel `/admin` carga y acepta inicio de sesion | Pendiente |
| El webmail carga y permite iniciar sesion | Pendiente |
| `flask mailu dkim-test` devuelve `pass` | Pendiente |
| Alta de buzon desde el panel y desde CLI | Pendiente |
| Recibo de correo desde un servidor externo | Pendiente |
| Envio de correo a un destino externo | Pendiente |
| Envio a Gmail, que aplica las listas negras mas duras | Pendiente |
| TLS valido en SMTP, IMAP y HTTPS | Pendiente |
| `backup-mailu.sh` produce un respaldo completo | Pendiente |
| `restore-mailu.sh` restaura sobre un stack limpio | Pendiente |
| La restauracion rechaza un respaldo sin `.completo` | Pendiente |
| La restauracion rechaza un `.tar` con rutas `..` | Pendiente |
| `user-delete` borra buzon y correo | Pendiente |
| Comportamiento con el puerto 25 saliente bloqueado | Pendiente |
| Rendimiento con la carga esperada de la Pyme | Pendiente |

### 3.4 Instalacion sobre Coolify

**Pendiente.** Ver `02-INSTALACION-COOLIFY.md`. El comportamiento de
Coolify con puertos de correo no se probo.

---

## 4. Ensayo antes de la primera entrega

Este es el guion que Hefesto Studio debe ejecutar **una vez**, en un
servidor de pruebas, antes de instalar el primer cliente.

### Dia 1: montaje

- [ ] `docker compose config` no reporta errores
- [ ] Las 8 imagenes descargan
- [ ] Los 8 contenedores quedan activos
- [ ] `docker compose ps` sin reinicios en bucle
- [ ] El contenedor `admin` **no** se queda esperando al resolutor
- [ ] `/admin` carga y el login funciona
- [ ] `/webmail` carga

### Dia 2: DNS y buzones

- [ ] `dig A mail.<dominio>` devuelve la IP del servidor
- [ ] `dig MX <dominio>` apunta a `mail.<dominio>`
- [ ] SPF publicado
- [ ] DKIM publicado y `dkim-test` en `pass`
- [ ] DMARC publicado en `p=none`
- [ ] **PTR confirmado con el proveedor de VPS**
- [ ] Buzon creado y acceso al webmail confirmado

### Dia 3: correo real

> Esto es lo que nunca se ha hecho desde este kit.

- [ ] Correo **entrante** desde Gmail al buzon nuevo: llega
- [ ] El correo entrante no cae en spam en la prueba
- [ ] Correo **saliente** a Gmail: llega
- [ ] Correo saliente a Outlook/M365: llega
- [ ] **Revisados los encabezados**: SPF `pass`, DKIM `pass`, DMARC `pass`
- [ ] Enviados 10 correos seguidos sin que ninguno se marque como spam

### Dia 4: operación

- [ ] `backup-mailu.sh` completa y escribe `.completo`
- [ ] `sha256sum -c SHA256SUMS` da `OK`
- [ ] `restore-mailu.sh -n` valida sin escribir
- [ ] Restauracion real sobre un proyecto paralelo: funciona
- [ ] `user-delete -f` borra lo que debe

### Resultado

Con el guion completo en verde, el kit pasa de `kit preparado` a
**probado**, y Hefesto Studio puede vender la primera instalacion con
respaldo.

Sin ese ensayo, el estado honesto sigue siendo **kit preparado**, y hay
que decirlo.

---

## 5. Como declarar el estado ante el cliente

Formulacion correcta:

> El kit esta preparado y verificado contra la documentacion oficial de
> Mailu. El montaje en servidor, el DNS y el envio real de correo estan
> pendientes de prueba en el servidor del cliente, y forman parte de la
> instalacion.

Formulaciones que **no** se deben usar:

| No decir | Por que |
| --- | --- |
| "Listo para produccion" | No se ejecuto nunca |
| "Probado" | No se probo |
| "Garantizado" | Nada de esto se puede garantizar con un dominio recien configurado |
| "Funcionando" | No se ha enviado un correo |

---

## 6. References

- Release consultada: <https://api.github.com/repos/Mailu/Mailu/releases/latest>
- Composicion del stack: <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml>
- Valores por defecto: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/configuration.py>
- Arranque del panel: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/start.py>
- CLI: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/manage.py>
- Configuracion: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/configuration.rst>
