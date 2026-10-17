# 04 — Primera cuenta y gestión de usuarios

Estado del kit: `kit preparado`. Los comandos de este documento están
verificados contra el código de `flask mailu` en el tag `2024.06.64`,
pero **no se han ejecutado**.

---

## 1. La cuenta de administrador se crea sola

No hay que crearla a mano. En el primer arranque, el contenedor `admin`
la crea a partir de las variables `INITIAL_ADMIN_*` del `.env`:

```
INITIAL_ADMIN_ACCOUNT=admin
INITIAL_ADMIN_DOMAIN=ejemplo.cl
INITIAL_ADMIN_PW=<contrasena fuerte>
INITIAL_ADMIN_MODE=ifmissing
```

Si el `.env` tiene esos valores vacios, el panel arranca **sin
administrador** y no hay forma de crear el primero por interfaz. Por
eso son obligatorios en la primera ejecucion.

### Ingreso

```
https://mail.ejemplo.cl/admin
```

La ruta del panel es **`/admin`**, en el mismo host que el webmail. No
hay un subdominio aparte para el panel.

### Inmediatamente despues de entrar

1. **Cambia la contrasena** del administrador inicial.
2. Crea un administrador propio para el cliente, en vez de usar la
   cuenta `admin` todo el tiempo:
   ```bash
   docker compose exec admin flask mailu admin maria ejemplo.cl 'contraseña-fuerte'
   ```
3. En el `.env`, pon `INITIAL_ADMIN_MODE=ifmissing` y **borra**
   `INITIAL_ADMIN_PW`. Si queda en `update`, cada reinicio del servidor
   vuelve a fijar la contrasena inicial y deshace el cambio.

---

## 2. Orden correcto: dominio antes que buzón

Este orden importa y mucha gente lo hace al reves.

```bash
# 1. El dominio primero
docker compose exec admin flask mailu domain ejemplo.cl

# 2. Publicar los registros DNS que Mailu genero

# 3. Verificar que el DKIM funciona
docker compose exec admin flask mailu dkim-test ejemplo.cl

# 4. Ahora si, el buzón
docker compose exec admin flask mailu user jperez ejemplo.cl 'contraseña'
```

Si se crea el buzón antes de publicar los registros DNS, todo funciona
desde la interfaz y **nada llega a ningun lado**. Es la falla mas
frecuente de instalacion y la mas cara de diagnosticar, porque el
cliente ve que "el correo esta listo".

Detalle completo en `../ejemplos/alta-buzon-ejemplo.md`.

---

## 3. Comandos de administracion

Todos verificados en `core/admin/mailu/manage.py`, version `2024.06.64`.

### Dominios

```bash
# Listar dominios
docker compose exec admin flask mailu domain

# Crear un dominio
docker compose exec admin flask mailu domain ejemplo.cl

# Ver buzones y alias de cada dominio
docker compose exec admin flask mailu domain -u -a -q
```

| Opcion | Que muestra |
| --- | --- |
| `-u` | Buzones de cada dominio |
| `-a` | Alias |
| `-q` | Cuotas |

### Usuarios

```bash
# Crear un buzón: localpart, dominio, contraseña
docker compose exec admin flask mailu user jperez ejemplo.cl 'contraseña'

# Crear un administrador global
docker compose exec admin flask mailu admin maria ejemplo.cl 'contraseña'

# Crear sin fallar si ya existe
docker compose exec admin flask mailu admin maria ejemplo.cl 'contraseña' -m ifmissing

# Cambiar una contraseña
docker compose exec admin flask mailu password jperez ejemplo.cl 'contraseña-nueva'
```

> **Ojo con la linea de comandos.** La contrasena queda en el historial
> del shell del servidor. Para una entrega con varios operadores, usa
> el panel web.

### Borrar un buzón

```bash
docker compose exec admin flask mailu user-delete -f jperez ejemplo.cl
```

`-f` es obligatorio y no pide confirmacion. **Borra el buzon y todo el
correo que contiene.** Sin respaldo previo, ese correo no existe en
ningun otro lado.

### Alias

```bash
docker compose exec admin flask mailu alias contacto ejemplo.cl jperez@example.cl
```

Un alias puede apuntar a varios buzones encadenando el ultimo
argumento, y puede apuntar a una direccion **externa**, util para
recibir en el servidor y reenviar a la casilla que el cliente ya
tiene.

### Delegar un dominio

```bash
docker compose exec admin flask mailu setmanager ejemplo.cl maria@example.cl
```

Da a `maria` control sobre un dominio sin darle control de todo el
servidor. Es la forma correcta cuando el cliente va a administrar su
propio dominio.

---

## 4. Permisos y cuentas

Mailu tiene tres niveles:

| Nivel | Que puede hacer |
| --- | --- |
| Administrador global | Todo el servidor, todos los dominios |
| Delegado de dominio | Solo los dominios que le asignaron |
| Usuario | Su buzon y nada mas |

**Da siempre la minima permisos que el trabajo requiere.** Que el
cliente administre su propio dominio no implica que deba poder tocar
los demas.

---

## 5. Politica de contrasenas para el cliente

Con traspaso de correo corporativo, la contrasena de un buzon es
dato personal. Como minimo, en la entrega:

- [ ] Contrasenas unicas por buzon. **Nunca** una compartida para todos
- [ ] Longitud minima de 12 caracteres
- [ ] Sin reutilizar la contrasena de otro servicio
- [ ] Cambiar la contrasena inicial en el primer ingreso
- [ ] El cliente sabe que puede usar un gestor de contrasenas

## 6. Cierre de sesion del administrador

La sesion del panel depende de `SECRET_KEY`. Si un operador pierde su
dispositivo, la sesion sigue viva hasta que expire.

Para cortarla de inmediato, **cambiar `SECRET_KEY`** y reiniciar el
stack. Efecto colateral: se invalidan **todas** las sesiones abiertas,
de todos los operadores.

```bash
# 1. Generar y poner la nueva clave en el .env
openssl rand -hex 16
# 2. Aplicar
docker compose down && docker compose up -d
```

---

## 7. Importacion masiva de buzones

Mailu trae una funcion de importacion que acepta CSV. **Este kit no
incluye un importador**, y la razon es concreta: la migracion desde
Gmail o Microsoft 365 requiere **exportar las contrasenas** en el
formato que la plataforma origen entregue, y cada proveedor lo hace de
una manera distinta, muchas veces con una clave de API de por medio.

Sin acceso a los correos del origen, no hay importacion posible. Por
eso el procedimiento esta en `09-EXPORTACION-O-TRASPASO.md` y es
manual.

**Lo que si puede automatizar Hefesto Studio** es la creacion de los
buzones vacios, a partir de una lista de correos que el propio cliente
entrega:

```bash
# Lee una lista "nombre@dominio" y crea cada buzón
while read -r linea; do
  [ -z "$linea" ] && continue
  localpart="${linea%@*}"
  pass="$(openssl rand -base64 18 | tr -d '/+=' | head -c 16)"
  docker compose exec admin \
    flask mailu user "$localpart" ejemplo.cl "$pass"
  printf '%s,%s\n' "$linea" "$pass"
done < lista-de-correos.csv > credenciales-nuevas.csv
```

Salida `credenciales-nuevas.csv` con las contrasenas iniciales.
**Esa variable de seguridad es del cliente**: es una credencial en texto
plano en disco.

```bash
chmod 600 credenciales-nuevas.csv
```

Recomendacion: pedir al cliente que cambie cada contrasena en el primer
ingreso, en vez de entregarle la lista.

---

## 8. Referencias

- CLI de administracion: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/manage.py>
- Alta completa de un buzon: `../ejemplos/alta-buzon-ejemplo.md`
- Creacion del administrador: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/start.py>
