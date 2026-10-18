# Alta de buzón de ejemplo — Mailu

> ## ESTADO: MATERIAL DE DEMOSTRACION
> Los comandos usan el dominio ficticio `ejemplo.cl` y usuarios de
> ejemplo. Para una instalación real, reemplaza el dominio y verifica
> cada paso en `docs/07-PRUEBAS-DE-ACEPTACION.md` antes de cobrar.
>
> La orden en que se hacen las cosas importa: crear el **dominio**
> primero, y solo despues el **buzón**.

---

## 1. Antes de crear nada: el dominio tiene que existir en DNS

Crear un buzon en Mailu genera claves DKIM y produce registros DNS
que hay que publicar **despues**. Si el dominio no resuelve a este
servidor, el buzon se crea igual, pero el correo se pierde.

Comprueba primero:

```bash
dig A mail.ejemplo.cl +short
```

Debe devolver la IP real del servidor. Si no, no sigas: arregla el DNS.

---

## 2. Crear el dominio

### 2.1 Desde el panel web (metodo recomendado)

1. Entra a `https://mail.ejemplo.cl/admin` (o `https://webmail.ejemplo.cl/admin`).
2. Inicia sesión con la cuenta creada por `INITIAL_ADMIN_*`.
3. Ve a **Configuración** → **Dominios** → **Agregar dominio**.
4. Escribe `ejemplo.cl` y confirma.

Crear el dominio aquí hace dos cosas a la vez: registra el dominio en
la base del panel **y genera la clave DKIM**. El paso siguiente ya
tiene material.

### 2.2 Por linea de comandos

```bash
docker compose exec admin flask mailu domain ejemplo.cl
```

Argumentos utiles:

| Argumento | Que hace |
| --- | --- |
| sin argumentos | Lista los dominios existentes |
| `-u` | Muestra también los buzones de cada dominio |
| `-a` | Muestra los alias |
| `-q` | Muestra las cuotas |

---

## 3. Publicar los registros DNS queMailu genero

Al crear el dominio, Mailu creo la clave DKIM en el volumen `dkim`.
El panel la muestra lista para copiar, en la ficha del dominio.

El registro es:

```
dkim._domainkey.ejemplo.cl.  IN TXT   "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3..."
```

Para obtenerlo desde la consola:

```bash
docker compose exec admin cat /dkim/ejemplo.cldkim.key
```

El nombre del archivo usa el selector del `.env`. Con
`DKIM_SELECTOR=dkim` y el dominio `ejemplo.cl`, el archivo es
`ejemplo.cldkim.key`.

Para ver **todos** los registros que el panel recomienda, ya con el
SPF y el DMARC incluidos:

```bash
docker compose exec admin flask mailu config-export --dns
```

> `--dns` fue agregado justamente para esto. Sin esa opcion, el
> comando exporta la configuración completa **incluyendo secretos**.

Pública los tres registros (SPF, DKIM, DMARC) antes de seguir. El
detalle esta en `dns-registros-ejemplo.md`.

### Comprobacion del DKIM

```bash
docker compose exec admin flask mailu dkim-test ejemplo.cl
```

Salida esperada: la clave usada aparece con el `s=` correcto, el
resultado de la firma en `pass` y DMARC también en `pass`. Si falla,
el registro DNS recien publicado todavia no ha propagado. Espera y
vuelve a probar.

---

## 4. Crear el primer buzón de un cliente

### 4.1 Desde el panel web

1. **Configuración** → **Usuarios** → **Agregar usuario**.
2. `Correo`: `jperez@ejemplo.cl` (el nombre antes de la arroba es el
   **localpart**).
3. `Contraseña`: una larga, distinta de la del administrador.
4. `Cuota`: 1 GB suele bastar para una pyme.

### 4.2 Por linea de comandos

```bash
docker compose exec admin flask mailu user jperez ejemplo.cl 'contraseña-larga-y-unica'
```

Orden de los argumentos: **localpart, dominio, contraseña**.

En esta versión también existe el comando `admin`, que crea la cuenta
con permisos de administrador global:

```bash
docker compose exec admin flask mailu admin maria ejemplo.cl 'contraseña-larga-y-unica'
```

El modo evita que el comando falle si la cuenta ya existe:

```bash
docker compose exec admin flask mailu admin maria ejemplo.cl 'contraseña' -m ifmissing
```

| Valor de `-m` | Que hace |
| --- | --- |
| `create` | Crea la cuenta. Falla si ya existe |
| `ifmissing` | Crea solo si no existe. **El mas seguro para scripts** |
| `update` | Fija también la contrasena en cada ejecución |

> Las contrasenas se escriben en la linea de comandos, que queda
> registrada en el historial del shell del servidor. Para un
> despliegue con varios operadores, usa el panel web o borra el
> historial despues.

### Comprobacion de que el buzon existe

```bash
docker compose exec admin flask mailu domain ejemplo.cl -u
```

Debe listar `ejemplo.cl` con el buzon `jperez`.

---

## 5. Primer ingreso y cambio de contrasña

1. Entrar a `https://webmail.ejemplo.cl`.
2. Iniciar sesión con el buzon recien creado.
3. **Cambiar la contrasña desde la primera vez.**

El panel marca las cuentas que siguen usando la contrasena inicial.
Un cliente que no la cambia es un cliente con una contrasena conocida
por mas gente de la que deberia.

---

## 6. Otras operaciones de CLI

Estan extraidas del código de `flask mailu`, versión `2024.06.64`.

### Cambiar una contrasña

```bash
docker compose exec admin flask mailu password jperez ejemplo.cl 'contraseña-nueva'
```

### Borrar un buzón

```bash
docker compose exec admin flask mailu user-delete -f jperez ejemplo.cl
```

`-f` es obligatorio, y es a propósito: **borra el buzón y todo el
correo que contiene**, sin pedir confirmacion. Sin `-f` el comando se
niega a borrar.

Antes de ejecutar eso, confirma por escrito con el cliente. Correo
borrado no se recupera.

### Alias de correo

Un alias dirige mensajes de una direccion a otra u otros buzones:

```bash
docker compose exec admin flask mailu alias contacto ejemplo.cl jperez@example.cl
```

Argumentos: **alias, dominio destino, buzones que lo reciben** (se
pueden encadenar varios). Un alias puede apuntar a una direccion
externa; eso es util para recibir en el servidor y reenviar a la
casilla personal del cliente.

### Delegar la administración de un dominio

```bash
docker compose exec admin flask mailu setmanager ejemplo.cl maria@example.cl
```

### Exportar y reimportar la configuración

```bash
# Exportar a JSON, sin incluir los registros DNS
docker compose exec admin flask mailu config-export -j -f -s > config.json

# Exportar incluyendo los registros DNS recomendados
docker compose exec admin flask mailu config-export --dns > dns.json

# Reimportar
docker compose exec admin flask mailu config-import -c config.json
```

Sirve para mover el servidor a otra maquina conservando usuarios,
dominios, alias y claves DKIM. **No incluye el correo.** El correo se
traspasa aparte. Ver `../docs/09-EXPORTACION-O-TRASPASO.md`.

---

## 7. Lista de verificación del alta

Antes de declarar el buzon listo:

- [ ] `dig A mail.ejemplo.cl` devuelve la IP del servidor
- [ ] SPF publicado y verificable
- [ ] DKIM publicado y `dkim-test` en `pass`
- [ ] DMARC publicado, inicialmente en `p=none`
- [ ] PTR configurado con el proveedor de VPS
- [ ] El buzon existe en `flask mailu domain ejemplo.cl -u`
- [ ] Se pudo entrar al webmail con el buzon nuevo
- [ ] La contrasena inicial **ya se cambio**
- [ ] Se envio un correo de entrada y llego
- [ ] Se envio un correo de salida y llego a una direccion externa

---

## 8. References

- CLI de administración: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/manage.py>
- Creacion automática del administrador: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/start.py>
- Valores por defecto y rutas DKIM: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/configuration.py>
