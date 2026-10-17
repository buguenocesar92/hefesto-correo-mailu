# LICENCIAS.md — Mailu, kit de despliegue Hefesto Studio

Este documento lista el software que este kit instala, de donde sale y
bajo que licencia corre. Todo se lee desde los repositorios oficiales.
Fuentes al final de cada bloque.

---

## 1. Mailu — MIT

El servidor de correo que este kit despliega.

**Licencia: MIT.** Leida directamente del archivo `LICENSE.md` del tag
`2024.06.64`:

> MIT License
> Copyright (c) 2016 All Mailu contributors at the date

El README del proyecto confirma el alcance:

> All components are free software and compatible with the MIT
> license. All specific configuration files, Dockerfiles and code are
> placed under the MIT license.

Fuente: <https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/LICENSE.md>
y <https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/README.md>

### Que significa para Hefesto Studio

La licencia MIT permite usar, modificar, vender y dar soporte a este
software, incluidos los servicios de administracion. La unica
obligacion es conservar el aviso de copyright y el texto de la licencia
en las copias o partes sustanciales que se distribuyan.

Distribuir Mailu **no** obliga a abrir el codigo del kit de Hefesto
Studio, porque son obras distintas.

---

## 2. Redis — BSD de 3 clausulas

**Licencia: BSD-3-Clause.** Imagen oficial `redis:7.2.16-alpine`.

Se usa solo como cache de sesiones y limitador de intentos de
autenticacion. No almacena correo ni datos de usuario de forma
relevante, y por eso el kit no la respalda.

---

## 3. Componentes incluidos dentro de Mailu

Estas licencias aplican a los componentes que Mailu empaqueta dentro de
sus propias imagenes. **Este kit no los modifica ni los distribuye por
separado**, pero se listan para que el cliente sepa que corre.

| Componente | Funcion | Licencia |
| --- | --- | --- |
| Nginx | Servidor web, TLS y proxy de los puertos de correo | BSD-2-Clause |
| Postfix | Agente de transferencia de correo (SMTP) | IBM Public License 1.0 y Eclipse Public License 2.0 (dual) |
| Dovecot | Servidor IMAP | GPL-2.0-or-later (con componentes MIT) |
| Rspamd | Antispam | MIT |
| Roundcube | Webmail | GPL-3.0-or-later |
| Redis (en Mailu) | Cache interna, en imagen de Mailu | BSD-3-Clause |
| Unbound | Resolutor DNS con DNSSEC | BSD-2-Clause |
| Python, Flask, SQLAlchemy, Alembic | Panel de administracion | MIT, BSD-3-Clause y LGPL-3.0 respectivamente |
| SQLite | Base de datos interna del panel | Dominio publico |
| Rspamd / clamav (opcional) | Antispam y antivirus | MIT / GPL-2.0 |

La lista anterior resume la tecnologia. Para el detalle exacto de cada
componente, se debe consultar el `COPYRIGHT` o el archivo de licencia
dentro del repositorio correspondiente. Mailu publica esa informacion
en su documentacion y en sus imagenes.

**Nota importante sobre GPL.** Roundcube es GPL-3.0. El kit lo usa como
webmail tal cual, sin modificarlo. Eso es correcto y no obliga a nada.
Si en el futuro se modifica Roundcube, habria que revisar las
obligaciones de distribucion del codigo modificado. Este kit no lo hace.

---

## 4. Licencia del kit de despliegue

El trabajo de Hefesto Studio que acompaña a Mailu —este `compose.yaml`,
los scripts de respaldo, la documentacion y los ejemplos— es obra
propia de Hefesto Studio y se entrega bajo los terminos acordados
comercialmente con el cliente.

El kit se distribuye **junto con** Mailu bajo MIT. No modifica Mailu ni
alguna de sus imagenes.

---

## 5. Software que este kit NO incluye

Para evitar confusiones, esto no se instala:

- **Supabase ni ningun servicio de base de datos en la nube.** Mailu
  usa su propia base interna y su propio almacenamiento. Ver
  `docs/09-EXPORTACION-O-TRASPASO.md`.
- **ClamAV, Radicale (webdav), fetchmail, Tika y oletools.** Son
  servicios opcionales de Mailu que este kit no despliega. Ver
  `VERSION.md`, seccion 4.
- **Fail2Ban.** Mailu no lo incluye y este kit tampoco. El limite de
  autenticacion lo hace la propia Mailu con `AUTH_RATELIMIT_IP`.
- **Certificados de pago.** El kit no emite ni revende certificados.
  Con `TLS_FLAVOR=cert` el cliente compra el suyo donde quiera; con
  `TLS_FLAVOR=letsencrypt` obtiene uno gratis y automatico de Let's
  Encrypt.

---

## 6. Marcas

Mailu, Postfix, Dovecot, Rspamd, Roundcube, SnappyMail, Nginx, Redis,
Unbound y SQLite son marcas de sus respectivos titulares. El uso en esta
documentacion es solo para identificar el software instalado. Este kit
no reclama ninguna de ellas.

---

## 7. Fuentes

| Dato | Fuente |
| --- | --- |
| Licencia MIT de Mailu | <https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/LICENSE.md> |
| Alcance de la licencia | <https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/README.md> |
| Version `2024.06.64` | <https://api.github.com/repos/Mailu/Mailu/releases/latest> |
| Topologia de contenedores | <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml> |
| Variables y valores por defecto | <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/configuration.py> |
| Referencia de configuracion | <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/configuration.rst> |
| Etiqueta y digest de Redis | <https://hub.docker.com/v2/repositories/library/redis/tags/7.2.16-alpine> |
