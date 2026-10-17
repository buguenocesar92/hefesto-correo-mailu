# 09 — Exportación y traspaso de correo

Estado del kit: `kit preparado`.

---

## 1. Lo primero, para que nadie se sorprenda

> **Este kit NO incluye un conector de sincronizacion con Gmail,
> Microsoft 365 ni ningun otro servicio de correo.**

No hay migracion automatica de correo, y la razon es tecnica, no de
alcance:

**Para mover el correo hay que poder leerlo del origen.** Los correos
de Gmail o Microsoft 365 estan en cuentas del cliente, protegidas por
contrasena y, en los casos con verificacion en dos pasos, por factores
adicionales. Un kit de despliegue que se prometiera a migrarlos
automaticamente tendria que pedirle al cliente sus credenciales, y eso
no es algo que un servicio de instalacion de servidor de correo vaya a
hacer.

Lo que Mailu **si** trae son las herramientas para hacer el traspaso de
forma controlada una vez que el cliente entrego sus correos.

---

## 2. Que es "traspaso" y que es "sincronizacion"

| | Traspaso | Sincronizacion |
| --- | --- | --- |
| Que hace | Copia el correo una vez | Mantiene dos buzones al dia en ambos sentidos |
| Cuando | En la migracion | Siempre |
| Mailu lo trae | **Si** | **No** |
| Complejidad | Alta, pero se hace | Muy alta, es un producto aparte |

Si el cliente pide sincronizacion continua entre el nuevo servidor y su
Gmail personal, eso **no es una migracion**: es un proyecto distinto, y
este kit no lo cubre. Dilo claro desde el primer dia.

---

## 3. Herramientas verificadas de Mailu

### 3.1 Exportar la configuracion del servidor

Comandos tomados del codigo de `flask mailu` en el tag `2024.06.64`.

```bash
# Exportar a JSON, incluyendo secretos
docker compose exec admin flask mailu config-export -j -f -s > config.json

# Exportar a YAML, sin secretos
docker compose exec admin flask mailu config-export -y > config.yaml

# Exportar ademas los registros DNS recomendados
docker compose exec admin flask mailu config-export --dns > dns.json

# Exportar solo una parte
docker compose exec admin flask mailu config-export --without-users
docker compose exec admin flask mailu config-export --without-aliases
docker compose exec admin flask mailu config-export --without-datas
docker compose exec admin flask mailu config-export --without-fetchmails
```

Que incluye y que **no** incluye:

| Elemento | En la exportacion |
| --- | --- |
| Dominios | Si |
| Buzones (sin contrasenas, salvo `-s`) | Si |
| Alias y rutas | Si |
| Cuotas | Si |
| Claves DKIM | **Si** |
| **El correo (los mensajes)** | **No** |

`--dns` produce justamente los registros que hay que publicar para cada
dominio. Es la forma mas segura de no dejar ninguno sin publicar.

**`config-export -s` incluye secretos en texto plano.** Tratar el
archivo como una credencial.

### 3.2 Reimportar en otra maquina

```bash
docker compose exec admin flask mailu config-import -c config.json
```

Restaura dominios, buzones, alias y claves DKIM en un Mailu recien
instalado. **No restaura el correo.**

Este es el camino correcto para el **traspaso de servidor a servidor**
con Hefesto Studio: se levanta la maquina nueva con el mismo `.env`,
se importa la configuracion, y se traspasa el correo por IMAP.

### 3.3 Exportar el correo

El correo vive en Maildir, con archivos reales, en:

```
/mail/<dominio>/<buzon>/
```

Es decir, `mail/<ejemplo.cl>/jperez/`. Para exportarlo hay que copiar
ese arbol.

```bash
# Exportar un buzon completo, en un .tar
docker compose exec imap tar -C /mail/ejemplo.cl/jperez -cf - . \
  | gzip > buzon-jperez.tar.gz
```

Cada buzon son archivos `.eml` individuales. Se pueden abrir con un
cliente de correo, y tambien concatenar en un unico archivo:

```bash
docker compose exec imap sh -c \
  'cat /mail/ejemplo.cl/jperez/cur/* /mail/ejemplo.cl/jperez/new/*' \
  > jperez-completo.eml
```

**Este es el unico metodo de exportacion de correo que este kit
respalda.** Y es exactamente lo que hacen los scripts de respaldo.

---

## 4. Procedimiento de traspaso desde Gmail o Microsoft 365

> **Este procedimiento no se ha ejecutado desde este kit.** Es una
> guia, y hay que ajustarla a cada cliente.

### Fase 1 — Inventario

1. Cuantos buzones y de que tipo (personas, compartida,aliases).
2. Cuanto correo hay por buzon. Un buzon de 10 años puede tener
   varios gigabytes.
3. Que hay en las carpetas que no son la bandeja de entrada.

### Fase 2 — Servidor destino

1. Instalar Mailu limpio (`01-INSTALACION-DOCKER.md`).
2. Publicar los registros DNS.
3. Crear los buzones vacios.
4. **Verificar que el servidor nuevo envia y recibe.** Un traspaso a un
   servidor que no envia deja al cliente sin correo durante semanas.

### Fase 3 — Respaldo antes de tocar nada

```bash
./scripts/backup-mailu.sh /var/backups/antes-del-traspaso
```

En el origen: exporta las etiquetas, filtros y contactos del cliente
desde su interfaz actual. Gmail permite "Exportar datos"; Microsoft 365
tiene "Solicitar la exportación de datos". **Que lo hagan ellos**, no
Hefesto Studio.

### Fase 4 — Traspaso del correo

**Opcion A: IMAPcopy desde la maquina del cliente**

`IMAPCopy` es una herramienta libre que copia buzones IMAP de un
servidor a otro sin tocar los originales. Se instala en una maquina
cualquiera, con acceso IMAP a ambos lados:

```bash
imapcopy \
  -s imaps://usuario@servidor-origen:993 \
  -d imaps://usuario@servidor-destino:993 \
  -u usuario -p contrasena \
  -n -a
```

| Opcion | Que hace |
| --- | --- |
| `-s` | Servidor origen |
| `-d` | Servidor destino |
| `-n` | No mover, solo copiar |
| `-a` | Copiar tambien los adjuntos |

**Copia, nunca mueve.** Con `-n`, el original queda intacto, y eso es lo
correcto en un traspaso.

Requiere que la cuenta del origen tenga IMAP habilitado y una
**contrasena de aplicacion**. En cuentas con verificacion en dos pasos,
la contrasena normal no sirve.

**Opcion B: fetchmail, desde Mailu**

Mailu trae un servicio `fetchmail` que puede traer correo desde otro
servidor, pero **este kit no lo incluye** (ver `VERSION.md`, seccion 4).
Es una opcion valida para una mudanza temporal y acotada; para un
traspaso completo, IMAPCopy es mejor porque se puede controlar desde
fuera y probar sin tocar el destino.

### Fase 5 — Verificacion

Por cada buzon, comparar el origen y el destino:

- [ ] Numero de mensajes similar
- [ ] Carpetas especiales conservadas
- [ ] Adjuntos abren correctamente
- [ ] Correos enviados en un periodo de pruebas, desde Mailu, llegan
- [ ] Correos de una direccion externa llegan a Mailu
- [ ] Las carpetas del cliente existen en el webmail

### Fase 6 — Corte

1. **No borrar nada del origen.** El periodo de gracia minimo
   recomendado es de 30 dias.
2. Publicar los registros DNS definitivos.
3. Avisar al equipo del cliente que la bandeja antigua es de solo
   lectura.

---

## 5. Sobre Supabase y otros servicios externos

> **Supabase no aplica a Mailu.**

Mailu gestiona su propio almacenamiento y su propia base de datos
interna (SQLite en el volumen `data`). Upstream admite PostgreSQL y
MariaDB, pero **el equipo de Mailu desaconseja ambos**:

> Mailu is tested with SQLite and PostgreSQL/MariaDB. However the
> development team recommends against the use of PostgreSQL and
> MariaDB.

Este kit se queda con SQLite, la opcion por defecto del proyecto y la
recomendada para el volumen de una Pyme.

Tampoco se conecta a ningun servicio externo de objetos, backups o
correo. Mailu es autocontenido en su almacenamiento.

---

## 6. Importar buzones desde un archivo CSV

Mailu tiene un comando de importacion masiva. Este kit **no lo usa**
para migrar correo, porque no migra correo: crea buzones vacios.

```bash
docker compose exec admin flask mailu user-import [opciones] archivo host email scheme password_hash
```

| Opcion | Que hace |
| --- | --- |
| `--dry-run` | **Prueba sin escribir nada. Usar siempre primero** |
| `--sep` | Separador del CSV |
| `--quote` | Caracter de comillas |
| `--skip-header` | La primera linea es una cabecera |
| `--skip-existing` | No tocar buzones que ya existen |
| `--skip-invalid` | Saltar las lineas invalidas |
| `--yes` | No pedir confirmacion |

El campo `scheme` define como se interpretan las contrasenas: `plain`,
`md5`, `bcrypt`, `sha512crypt` y otros.

Procedimiento seguro:

```bash
# 1. Siempre en simulacion primero
docker compose exec admin flask mailu user-import --dry-run --skip-header \
  --sep ';' buzones.csv

# 2. Revisar lo que reporta

# 3. Recien despues, con --skip-existing
docker compose exec admin flask mailu user-import --yes --skip-header \
  --sep ';' --skip-existing buzones.csv
```

Con `--dry-run` primero, un CSV mal formado se detecta antes de tocar
la base.

---

## 7. Lo que este kit NO hace

| No hace | Por que |
| --- | --- |
| Sincronizacion continua | Es otro producto. Ver seccion 2 |
| Migrar desde Gmail o M365 automaticamente | Requiere las credenciales del cliente |
| Conectar Mailu a Supabase | Mailu no lo necesita. Ver seccion 5 |
| Exportar el correo desde el panel | Hay que copiar el Maildir. Ver seccion 3.3 |
| Respaldar hacia almacenamiento externo | El kit respalda a disco; la copia externa se configura aparte |

---

## 8. References

- CLI de administracion: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/manage.py>
- Base de datos y recomendacion de SQLite: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/configuration.rst>
- Topologia y volumenes: <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml>
- Traspaso del proyecto: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/compose/migration.rst>
