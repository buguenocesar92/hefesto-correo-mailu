# 03 — Variables de entorno y cómo obtenerlas

Estado del kit: `kit preparado`.

Todos los valores por defecto de este documento se leyeron del codigo
de `core/admin/mailu/configuration.py` y de `docs/configuration.rst` en
el tag `2024.06.64`.

---

## 1. Las cinco que no se pueden improvisar

Si algo sale mal en la instalación, el error esta casi siempre en una
de estas.

### `SECRET_KEY`

**Que es:** la clave con la que Mailu firma las sesiones del panel y
los tokens de la API.

**Como obtenerla:**
```bash
openssl rand -hex 16
```

**Reglas, en orden de importancia:**

1. **Una sola vez.** Si la cambias, todas las sesiones abiertas se
   invalidan y el panel pide iniciar sesion de nuevo.
2. **Distinta en cada instalacion.** Dos servidores con la misma clave
   comparten sesiones. En una Pyme con varios clientes, eso es un
   problema de aislamiento.
3. **No la reutilices para otro servicio.** Es una clave de firma.

### `DOMAIN`

**Que es:** el dominio principal del cliente, en minusculas.

```
DOMAIN=ejemplo.cl
```

**No** escribas `mail.ejemplo.cl` ni `https://ejemplo.cl`. El valor es
el dominio raiz tal como lo entregaria la interfaz.

Se usa para: los buzones por defecto, los certificados internos y la
aplicacion del DMARC.

### `HOSTNAMES`

**Que es:** la lista de nombres que este servidor responde,
separados por coma.

```
HOSTNAMES=mail.ejemplo.cl,autoconfig.ejemplo.cl,autodiscover.ejemplo.cl
```

**El primero es el principal** y es el que aparece en el certificado
TLS.

Cuando se agrega un nombre aqui hay que hacer dos cosas: publicarlo en
DNS **y** reiniciar todo el stack. Un nombre en `HOSTNAMES` sin
registro A correspondiente hace que el servidor se anuncie con un
nombre que no resuelve.

### `SUBNET` y `RESOLVER_IP`

**Que es:** la red interna de Docker de Mailu, y la direccion del
resolutor DNS con validacion DNSSEC.

```
SUBNET=192.168.203.0/24
RESOLVER_IP=192.168.203.9
```

**Por que son obligatorias.** Desde Mailu 1.9, el contenedor `admin`
prueba al arrancar que tiene un resolutor que valida DNSSEC. El
proyecto lo dice sin rodeos:

> Mailu 1.9 introduces a requirement that the host machine is running a
> DNSS validating resolver, since some DNS entries are DNSS signed and
> required for the mail server to work correctly.

Si no la encuentra, el `admin` **se queda esperando en un bucle** y no
termina de arrancar. Este kit lo resuelve con su propio contenedor
`unbound`, que es la razon de que `resolver` no sea opcional aqui.

**La regla practica:** estas dos variables van siempre juntas.
`RESOLVER_IP` tiene que estar **dentro** de `SUBNET`.

| SUBNET | RESOLVER_IP valida |
| --- | --- |
| `192.168.203.0/24` | `192.168.203.9` |
| `10.42.0.0/16` | `10.42.0.9` |
| `172.28.9.0/24` | `172.28.9.9` |

**No cambies `SUBNET` despues de instalar.** Si lo cambias con el
volumen de red ya creado, hay que borrar la red de Docker y volver a
crearla:

```bash
docker compose down
docker network rm mailu_default
docker compose up -d
```

### `TLS_FLAVOR`

**Que es:** como se obtiene el certificado TLS.

| Valor | Como funciona | Cuando usarlo |
| --- | --- | --- |
| `cert` | Tu certificado entra a mano en el volumen `certs` | **Produccion.** Control total, sin dependencia externa |
| `letsencrypt` | El contenedor `front` lo pide solo, cada 90 dias | Instalaciones pequenas con puerto 80 abierto |
| `notls` | Sin TLS | **Solo pruebas. Nunca en produccion** |

**Recomendacion para venta a Pymes: `cert`.** Con Let's Encrypt se
depende de un tercero para una funcion critica, y si el DNS o el puerto
80 fallan en una renovacion, el correo deja de entregar para todos los
clientes de correo de la empresa.

Con `cert` tambien hay que entregar dos archivos al cliente:

```bash
TLS_CERT_FILENAME=cert.pem
TLS_KEYPAIR_FILENAME=key.pem
```

Los nombres importan. Y **no uses enlaces simbolicos**: la
documentacion del proyecto advierte que rompen la deteccion.

### `POSTMASTER`

**Que es:** la direccion que recibe los mensajes de rebote y los avisos
del sistema.

```
POSTMASTER=postmaster@ejemplo.cl
```

Tiene que ser una casilla **real y monitoreada**. Si nadie mira esa
bandeja, los rebotes se acumulan y los problemas aparecen semanas
despues, cuando ya no se pueden diagnosticar.

---

## 2. Variables de puertos

### `PORTS`: donde escucha nginx

```
PORTS=25,80,443,465,587,993,4190
```

Lista de puertos **dentro del contenedor**. Modificarla no publica ni
despublica nada en el host: eso lo hace `compose.yaml`.

**Upstream no puede quitar 25, 465 ni 993.** Son obligatorios.

**El 587 no viene por defecto.** Este es el cambio que mas confunde
respecto a las guias viejas:

| Version | `PORTS` por defecto |
| --- | --- |
| Mailu 2024.06 | `25,80,443,465,993,995,4190` |
| Este kit | `25,80,443,465,587,993,4190` |

El kit agrega el **587** porque casi todos los clientes de correo hoy lo
usan para enviar, y ademas deja fuera el **995** (POP3 cifrado), que
esta en desuso y agrega superficie sin necesidad.

| Puerto | Nombre | Estado en este kit |
| --- | --- | --- |
| 25 | SMTP | Obligatorio. Entrada y salida |
| 465 | Submission con TLS | Obligatorio |
| 587 | Submission con STARTTLS | Agregado por el kit |
| 993 | IMAPS | Obligatorio |
| 4190 | ManageSieve | Incluido para los filtros del webmail |
| 80 | HTTP | Para ACME y redireccion |
| 443 | HTTPS | Panel y webmail |
| 995 | POPS | **Excluido.** Se agrega si el cliente lo pide |
| 110 | POP3 sin cifrar | **Nunca.** Riesgo inutil |
| 143 | IMAP sin cifrar | **Nunca.** Riesgo inutil |

### `BIND4`: en que direccion se publican

```
BIND4=0.0.0.0
```

`0.0.0.0` publica en todas las interfaces del servidor. Si el servidor
tiene una IP publica propia, **pon esa IP**:

```
BIND4=200.54.12.34
```

La razon esta en el FAQ del proyecto: si el proveedor NATea la maquina
y tu correo sale por una IP que no es la del dominio, **el SPF falla**.

---

## 3. Variables de primeros pasos

### `INITIAL_ADMIN_*`

El contenedor `admin` crea la cuenta del administrador en el primer
arranque.

| Variable | Valor de ejemplo | Que hace |
| --- | --- | --- |
| `INITIAL_ADMIN_ACCOUNT` | `admin` | Nombre de la cuenta |
| `INITIAL_ADMIN_DOMAIN` | `ejemplo.cl` | Debe coincidir con `DOMAIN` |
| `INITIAL_ADMIN_PW` | (una larga) | Contrasena inicial |
| `INITIAL_ADMIN_MODE` | `ifmissing` | Cuando crearla |

| Modo | Comportamiento |
| --- | --- |
| `create` | Crea la cuenta. **Falla** si ya existe |
| `ifmissing` | Crea solo si no existe |
| `update` | Fija la contrasena en **cada** arranque |

**Usa `ifmissing` y borra `INITIAL_ADMIN_PW` del `.env` despues del
primer arranque.** Con `update`, la contrasena queda escrita en un
archivo de texto plano para siempre, y cambiar la contrasena desde el
panel la sobreescribiria en el siguiente reinicio.

### `MESSAGE_RATELIMIT`

```
MESSAGE_RATELIMIT=200
```

Mensajes por usuario por dia. `0` desactiva el limite.

Es una proteccion real: un buzon comprometido que empieza a enviar
spam se corta solo. Con 200, una Pyme normal no lo nota y un abuso se
contiene en horas.

### `DEFAULT_QUOTA` y `MESSAGE_SIZE_LIMIT`

```
DEFAULT_QUOTA=1000000000      # 1 GB por buzon
MESSAGE_SIZE_LIMIT=50000000   # ~47 MB por mensaje
```

Con la cuota de 1 GB, un buzon lleno **deja de aceptar correo**. El
remitente recibe un rebote y el cliente pierde ese correo. Conviene
avisarle al cliente que revise la cuota antes de que se llene.

### `RECIPIENT_DELIMITER`

```
RECIPIENT_DELIMITER=+
```

Permite `jperez+ventas@ejemplo.cl` como direccion distinta que llega al
mismo buzon. Practico para clientes que dejan direcciones
publicas. Vacio lo desactiva.

---

## 4. Variables de seguridad

### `AUTH_RATELIMIT_*`

```
AUTH_RATELIMIT_IP=5
AUTH_RATELIMIT_USER=50
```

Intentos de autenticacion permitidos por IP y por usuario en una
ventana de 5 minutos.

> **En guias viejas aparece `LOGIN_RATELIMIT_IP`.** Ese nombre ya no
> existe en 2024.06. Copiar una guia vieja con ese nombre deja el
> limite sin aplicar, y el panel de administracion queda expuesto a
> ataques de fuerza bruta.

### `RELAYNETS`

**Vacio. Siempre vacio.**

Es la lista de redes autorizadas a usar el servidor sin autenticarse.
Rellenarla convierte el servidor en un **relay abierto**: cualquiera
en el mundo podra mandar correo a traves de el, y la consecuencia la
paga tu cliente con su reputacion.

### `IMAP_AUTH_LAN` e `IMAP_FORCE_TLS`

Vacias en produccion. Definen redes internas donde se permite IMAP sin
TLS. Son utiles en una red de oficina controlada, y son un riesgo en
cualquier otro caso.

---

## 5. Variables de relay

Ver `../ejemplos/relay-saliente-ejemplo.md` para el caso completo.

```
RELAYHOST=[203.0.113.25]:587
RELAYUSER=usuario
RELAYPASSWORD=secreto
```

El formato de `RELAYHOST` **lleva corchetes alrededor de la IP**. Es lo
que espera Postfix; sin ellos la variable no se interpreta bien.

Vacias = envio directo desde la IP del propio servidor.

---

## 6. Valores por defecto relevantes

Extraidos del codigo de `configuration.py`. No hace falta ponerlos en el
`.env` si el valor te sirve.

| Variable | Valor por defecto |
| --- | --- |
| `API` | `false` |
| `ADMIN` | `true` |
| `WEBMAIL` | `roundcube` |
| `RECIPIENT_DELIMITER` | `+` |
| `DEFAULT_QUOTA` | `1000000000` |
| `MESSAGE_SIZE_LIMIT` | `50000000` |
| `MESSAGE_RATELIMIT` | `200` |
| `DKIM_SELECTOR` | `dkim` |
| `SQLALCHEMY_DATABASE_URI` | `sqlite:////data/main.db` |
| `TLS_FLAVOR` | `cert` |
| `PORTS` | `25,80,443,465,993,995,4190` |

---

## 7. Sobre la base de datos

**Este kit no configura ninguna base de datos externa, y Supabase no
aplica.**

Mailu usa por defecto **SQLite** (`sqlite:////data/main.db`), dentro del
volumen `data`. Upstream admite PostgreSQL y MariaDB, pero el equipo de
Mailu **desaconseja** usarlos:

> Mailu is tested with SQLite and PostgreSQL/MariaDB. However the
> development team recommends against the use of PostgreSQL and
> MariaDB.

Razones: mas superficie de ataque, mas componentes que mantener, y
SQLite aguanta bien el volumen de una Pyme.

Para una Pyme con menos de 50 buzones, SQLite va sobrado. Este kit se
queda con la recomendacion del propio proyecto.

---

## 8. Cambiar el `.env` despues de instalar

Las variables se leen **una vez, al arrancar el contenedor**. Reiniciar
un servicio no basta:

```bash
docker compose down
docker compose up -d
```

Es el comportamiento que el propio proyecto documenta:

> If you change the configuration of Mailu (in the .env), you need to
> restart the containers.

---

## 9. References

- Referencia completa: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/configuration.rst>
- Valores por defecto: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/configuration.py>
- Plantilla del `.env`: <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/mailu.env>
- Creacion del administrador: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/start.py>
