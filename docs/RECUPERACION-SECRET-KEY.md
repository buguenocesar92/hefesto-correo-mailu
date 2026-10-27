# Recuperación del `SECRET_KEY` de Mailu

Estado: vigente desde 2026-10-20. Procedimiento para el operador del kit.

## 1. Qué es y qué se pierde

El `SECRET_KEY` de Mailu (variable `SECRET_KEY` del `.env`) cifra las sesiones
del panel de administracion y algunas claves que Mailu guarda cifradas (por
ejemplo las credenciales SMTP relayadas).

| Si se pierde el `SECRET_KEY` | Efecto |
|---|---|
| Sesiones del panel | Se invalidan: hay que volver a iniciar sesion. |
| Cuentas, dominios, alias, cuotas | **NO se pierden**: viven en la base `data`. |
| Claves SMTP cifradas | Quedan ilegibles: hay que volver a configurarlas. |
| Correo ya recibido | **NO se pierde**: vive en los volumenes `mail`. |

Perderlo **no** es una perdida de datos de correo, pero sí obliga a rehacer
parte de la configuracion.

## 2. Cómo NO perderlo

1. **Cifralo con el receptor del respaldo**, nunca en claro:

   ```bash
   AGE_RECIPIENTE=age1... ./scripts/cifrar-env.sh
   ```

   Genera `.env.age` y `.env.age.sha256` **al lado** del `.env`. El original no
   se borra: decidir cuando borrarlo es decision del operador.

2. **Guárdalo en el gestor de secretos del cliente** (Infisical, Vaultwarden o
   un sobre cifrado fuera del servidor). La clave privada `age` vive ahi, no en
   el servidor de correo.

3. **Verifica el ciclo** antes de depender de el:

   ```bash
   age -d -i CLAVE_PRIVADA .env.age > /tmp/env.prueba
   cmp /tmp/env.prueba .env && echo "OK: el .env se recupera byte a byte"
   ```

   Los respaldos hechos **antes** de la cifrado con `age` siguen en claro:
   migrarlos es manual, archivo por archivo, y nunca borra el original.

## 3. Recuperación cuando ya se perdió

1. **Comprueba si existe una copia cifrada**: en el gestor de secretos o en un
   respaldo con `.env.age`. Si existe, recuperar es inmediato:

   ```bash
   age -d -i CLAVE_PRIVADA .env.age > .env
   ```

2. **Si no existe copia**, genera uno nuevo:

   ```bash
   openssl rand -base64 32
   ```

   y ponlo en `SECRET_KEY` del `.env`. **Esto invalida las sesiones del panel y
   las claves SMTP cifradas**, pero NO pierde correos ni cuentas.

3. **Reinicia los servicios** para que todos约而同 el valor nuevo:

   ```bash
   docker compose up -d
   ```

4. **Reconfigura a mano** lo que dependia del `SECRET_KEY` viejo (credenciales
   SMTP relayadas, tokens de la API del panel).

## 4. Rotación

Rotar el `SECRET_KEY` es una operación con impacto (ver la tabla de la
seccion 1). Antes de rotar:

- respalda el `.env` actual **cifrado**;
- comprueba que el respaldo nuevo descifra byte a byte;
- rota en una ventana de mantenimiento.

Los respaldos ya cifrados con la clave vieja **siguen ligados a esa clave**:
para descifrarlos hay que usar la clave privada con la que se hicieron.

## 5. Lo que nunca hay que hacer

- No versionar el `.env` ni pegarlo en un ticket o en un chat.
- No enviar el `.env` por correo: es un documento de claves.
- No borrar el `.env` original hasta verificar que la copia cifrada descifra.
