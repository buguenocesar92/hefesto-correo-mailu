# Política de tratamiento de datos personales — Mailu (Hefesto Studio)

Estado: vigente desde 2026-10-20. Responsable del tratamiento: el cliente que
opera el kit.

## 1. Alcance

Mailu procesa **datos personales sensibles**: direcciones de correo electrónico,
nombres, alias, listas de distribucion, cabeceras de mensajes, adjuntos,
metadatos de entrega y el contenido de los buzones. Este kit es el de mayor
exposicion de datos personales de Hefesto Studio.

## 2. Roles

| Rol | Que ve | Quien |
|---|---|---|
| Administrador de la instancia | Todos los dominios, alias y quotas. Acceso al panel. | Maximo 2 personas de plataforma |
| Usuario de buzon | Su propio buzon y sus alias | Personal autorizado por el cliente |
| Soporte tecnico | Metadatos de entrega (NO el contenido) | Personal de soporte con acuerdo de confidencialidad |

El soporte tecnico que diagnostica un problema de entrega **no** necesita leer
el contenido del correo: los logs de Postfix, Rspamd y Dovecot bastan.

## 3. Finalidades y base legal

- **Finalidad**: correo electronico corporativo del cliente.
- **Base legal**: la relacion laboral o contractual del titular con el cliente.
- El cliente es el responsable del tratamiento; este kit solo provee la
  infraestructura.

## 4. Minimizacion

- No se activan registros de contenido: solo metadatos de entrega.
- El `SECRET_KEY` de Mailu cifra las sesiones del panel: es material sensible
  y se trata como tal.
- Los alias evitan exponer la direccion real cuando no hace falta.

## 5. Retencion

| Dato | Retencion | Quien la define |
|---|---|---|
| Correo en los buzones | While la cuenta exista. La supresion la ejecuta el cliente en el servidor. | El cliente |
| Logs de entrega (postfix/rspamd/dovecot) | Volumenes `filter`, `mailqueue` y logs del contenedor. | El cliente |
| Respaldos (`respaldos/`) | Mientras el operador los conserve. **El kit no borra respaldos**: borrarlos es irreversible y es decision del operador. | El cliente |
| `.env` (contiene `SECRET_KEY`) | Mientras viva el despliegue. Se rota regenerando el `SECRET_KEY`. | El cliente |

## 6. Seguridad del `SECRET_KEY`

El `SECRET_KEY` de Mailu cifra las sesiones del panel de administracion. Si se
pierde:

- se invalidan todas las sesiones abiertas del panel;
- los datos de las cuentas **NO** se pierden: sobreviven en la base de datos;
- pero las claves cifradas con ese `SECRET_KEY` (por ejemplo las claves SMTP
  cifradas que guarda Mailu) quedan ilegibles.

Ver `docs/RECUPERACION-SECRET-KEY.md` para el procedimiento.

El `.env` **no entra al respaldo** y se cifra aparte con
`scripts/cifrar-env.sh` (age). Sin receptor, no se transfiere en claro.

## 7. Derechos del titular

Acceso, rectificacion y supresion se ejecutan **en el servidor del cliente**
(panel de administracion o CLI del contenedor `admin`), no en este kit. Lo que
el kit garantiza es que el respaldo es restaurable, para que un titular pueda
recibir la copia de sus datos.

## 8. Auditoria

- Los accesos al panel y las entregas quedan en los logs de los servicios.
- `scripts/backup-mailu.sh` escribe `manifiesto.txt`, `SHA256SUMS` y el
  marcador `.completo` **al final**: si el respaldo se corta a la mitad, no
  hay marcador y el paquete no es restaurable.
- La restauracion deja `logs/restore.log` (origen, sha256, destino, resultado;
  nunca valores de secretos) cuando el kit esta configurado para auditar.

## 9. Superficie expuesta

El compose publica `ports` con variables (25, 465, 587, 110, 143, 993, 4190,
80 y 443 segun el plan). TLS lo termina el borde o el propio nginx con los
certificados de `certs/`. El `SECRET_KEY` y las contrasenas viven **solo** en
el `.env`, que nunca se versiona.
