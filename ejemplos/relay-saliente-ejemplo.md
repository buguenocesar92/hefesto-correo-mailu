# Relay saliente de ejemplo — Mailu

> ## ESTADO: MATERIAL DE DEMOSTRACION
> Los hosts, usuarios y contrasenas de este archivo **no existen**.
> `relay.transaccional.example` es un dominio reservado por la
> documentación. Sustituye todo por los datos que entregue el
> proveedor contratado, y verifica los puertos: no todos los
> proveedores usan 587.

---

## 1. Por que existo esta configuracion

El servidor recibe correo correctamente en el puerto 25 **entrante**
mientras el **saliente** este bloqueado por el proveedor de VPS.

El sintoma es silencioso, y por eso confunde tanto:

- El cliente escribe el correo.
- Mailu lo acepta y lo muestra como enviado.
- El correo **nunca sale**.
- No hay error en la interfaz, ni rebote inmediato, ni aviso en el
  panel.

Los rebotes, cuando aparecen, llegan por el buzón del remitente
como un mensaje de "no se pudo entregar" emitido mucho despues. Esa es
la unica senal.

### Que hay que hacer primero: verificar, no suponer

Antes de contratar un relay, hay que confirmar que el bloqueo es real
y que no es otra cosa. Desde el servidor:

```bash
# Intento de conexion al puerto 25 de salida.
# Si se queda colgado hasta "Connection timed out", esta bloqueado.
timeout 10 bash -c 'exec 3<>/dev/tcp/mx.gmail.com/25' && echo "Puerto 25 abierto" || echo "Bloqueado o sin ruta"
```

| Sintoma | Diagnostico |
| --- | --- |
| Conexion rechazada de inmediato | Hay un firewall local. Revisar `ufw`, `firewalld` y el panel del proveedor |
| Se queda colgado y expira | El bloqueo es del proveedor o de un nodo intermedio |
| Se conecta y dice `220 ...` | El puerto 25 **esta abierto**. El problema es otro: SPF, DKIM o PTR |

Tambien sirve la vista de Mailu, que muestra el ultimo error concreto
de cada envio:

```bash
docker compose logs --tail=100 smtp
```

### Como pedir el desbloqueo

Es una peticion comercial al proveedor. No hay truco tecnico que la
reemplace, y este kit **no incluye ningun metodo para evadir el
bloqueo**. La peticion va por el canal de soporte del proveedor y dice
mas o menos:

> Necesito el puerto 25 saliente (SMTP) habilitado en el plan X, IP
> Y. Z. El servidor envia correo corporativo del dominio propio del
> cliente a traves de esta maquina. Acepto las condiciones de uso
> antispam y los limites de envio.

| Si el proveedor... | Que hacer |
| --- | --- |
| Lo habilita sin costo | Es lo ideal |
| Lo cobra | Costo mensual extra. Sumarlo a la cotizacion del cliente |
| Lo niega por ser pyme o plan compartido | No hay apelacion tecnica. Pasar al relay de salida |

---

## 2. Que es un relay de salida

Un proveedor transaccional (de correo para aplicaciones) envia el
correo **por ti** usando sus propios servidores, que tienen reputacion
y acceso al puerto 25.

| | Servidor propio | Con relay |
| --- | --- | --- |
| Quien entrega el correo | Tu servidor | El proveedor |
| Puerto 25 saliente | Necesario | No necesario |
| PTR y reputacion | Tuyos, hay que cuidarlos | Del proveedor |
| Costo | Costo del VPS | Costo del VPS mas el del relay, segun volumen |
| Datos que salen del pais | Todo el correo | Todo el correo pasa por el proveedor |

**Ultima fila, en negrita.** Ese es el punto que hay que hablar con el
cliente antes de contratar un relay: el proveedor externo va a ver el
contenido del correo. Si el cliente tiene datos personales o secretos
comerciales, es una decision comercial y de cumplimiento, no tecnica.

---

## 3. Configuracion en Mailu

Las tres variables van en el `.env`. El formato de `RELAYHOST` lleva
corchetes alrededor de la IP.

```bash
RELAYHOST=[203.0.113.25]:587
RELAYUSER=APXXXXXX
RELAYPASSWORD=clave-secreta-del-proveedor
```

| Variable | Que es |
| --- | --- |
| `RELAYHOST` | Servidor del relay, con puerto. El formato con corchetes es el que espera Postfix |
| `RELAYUSER` | Usuario que entrega el proveedor |
| `RELAYPASSWORD` | Su contrasena. **Es un secreto**: vive solo en el `.env`, nunca en git |

Si el proveedor usa el puerto 465 (TLS directo) en vez de 587
(STARTTLS), se escribe igual:

```bash
RELAYHOST=[203.0.113.25]:465
```

### Aplicar el cambio

Un cambio en el `.env` **no** se aplica reiniciando el servicio:

```bash
docker compose down
docker compose up -d
```

Este detalle esta documentado por el propio proyecto:

> If you change the configuration of Mailu (in the .env), you need to
> restart the containers. The environment variables are read at
> container startup.

Reiniciar a mano un solo servicio no basta: el valor se lee una vez,
al arrancar el contenedor.

---

## 4. Lo que hay que cambiar ademas en DNS

Al mandar el correo por un relay, el SPF **tiene que incluir** al
proveedor. Si no, los correos salen marcados como no autorizados y van
directo a spam.

```
ejemplo.cl.   IN TXT   "v=spf1 mx include:proveedor-transaccional.cl -all"
```

El resto de los registros no cambia: DKIM sigue lo firma Mailu, DMARC
sigue igual, el MX sigue apuntando al servidor de Mailu porque es el
que **recibe**.

### Aclaracion sobre DKIM con relay

Mailu sigue **firmando** los mensajes salientes con su clave DKIM, y
esa firma se sigue validando. Lo que cambia es que ahora la
**entrega** la hace el proveedor. Hay proveedores que, por omision,
reescriben o eliminan la cabecera de autenticacion al reenviar: si el
proveedor lo hace, la firma se pierde y hay que pedirle que la
preserve. **Esto hay que verificarlo con un envio de prueba real**, no
se puede asumir.

---

## 5. Lo que NO hay que hacer

Hay soluciones circulating en internet para el puerto 25 bloqueado
que **no son legitimas** y que este kit no incluye por ningun motivo:

- Enviar por el puerto 587 de otro servidor ajeno.
- Reenviar correo a traves de cuentas personales.
- Cualquier configuracion que parezca "escalar privilegios" en el
  puerto 25.

Salvo una excepcion, **todo relay exige credenciales que el proveedor
te da**. Un relay sin autenticacion es, por definicion, un relay
abierto: cualquiera puede mandar spam a traves de el, y la
consecuencia la paga tu cliente con su reputacion.

---

## 6. Comprobacion de que funciona

1. Enviar un correo desde el panel a una direccion externa.
2. Revisar que sale de inmediato:
   ```bash
   docker compose logs --tail=50 smtp
   ```
   Con relay configurado, la linea de estado debe mostrar la entrega
   al relay.
3. Confirmar en la bandeja del destinatario, **incluyendo la carpeta
   de spam**.
4. Revisar los encabezados del correo recibido. Deben mostrar SPF,
   DKIM y DMARC en `pass`.

Nada de esto se ha probado desde este kit. Ver
`../docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## 7. References

- Variables de relay: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/configuration.rst>
- Reinicio tras cambiar el `.env`: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/faq.rst>
- Registros DNS: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/dns.rst>
