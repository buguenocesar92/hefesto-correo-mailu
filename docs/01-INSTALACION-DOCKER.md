# 01 — Instalación con Docker

Estado del kit: `kit preparado`. **Ninguno de los pasos de este
documento se ha ejecutado desde este kit.** Ver
`07-PRUEBAS-DE-ACEPTACION.md`.

---

## 0. Antes de instalar: las cuatro condiciones de bloqueo

Esta instalación no se puede empezar si alguna de estas falla. No son
recomendaciones.

| Condición | Por qué es bloqueante |
| --- | --- |
| El cliente tiene un **dominio propio** | Sin control del DNS no hay correo confiable |
| El **puerto 25 saliente** está abierto | Si no, el servidor recibe y **no envía**. Es el fallo clásico |
| El **puerto 25 entrante** está abierto al mundo | Si no, nadie puede entregar correo al cliente |
| Hay un **resolutor DNS con DNSSEC** | Mailu lo resuelve solo con su contenedor `unbound`. Si lo quitas, el panel no arranca |

Verifica el punto 2 **antes** de instalar nada:

```bash
timeout 10 bash -c 'exec 3<>/dev/tcp/mx.gmail.com/25' \
  && echo "Puerto 25 saliente: ABIERTO" \
  || echo "Puerto 25 saliente: BLOQUEADO"
```

Si está bloqueado, **para acá** y resuelve el punto con el cliente.
Detalle y alternativas en `08-SERVICIOS-COMERCIALES.md`.

---

## 1. Requisitos del servidor

Verificados contra `docs/compose/requirements.rst` de Mailu
`2024.06.64`.

| Requisito | Detalle |
| --- | --- |
| Sistema | Linux con Docker Engine y el plugin `docker compose` v2 |
| CPU y RAM | 2 vCPU y 2 GB de RAM como minimo comodo para 20 buzones |
| Disco | 20 GB para el sistema, mas lo que ocupen los buzones |
| Puertos | 25, 465, 587, 993, 4190, 80 y 443 abiertos desde Internet |
| DNS | Registro A de `mail.<dominio>` apuntando a la IP **real** del servidor |

### Sobre el CDN

**No pongas un CDN delante del correo.** Un registro A de
`mail.<dominio>` apuntando a Cloudflare o similar hace que el puerto 25
termine en otro servidor y nada llega. El correo necesita la IP del
servidor, sin intermediarios.

### Sobre la IP pública

Si el proveedor de VPS entrega la maquina con IP pública propia, pon
esa IP en `BIND4` del `.env` en lugar de `0.0.0.0`. Si el proveedor
NATea la maquina, el SPF del servidor falla, porque la IP de salida no
coincide con la del dominio. El FAQ del propio Mailu lo advierte:

> If you are behind a NAT ... the SPF check will fail because the
> reverse DNS does not match.

---

## 2. Preparar el sistema

### 2.1 Zona horaria

```bash
timedatectl set-timezone America/Santiago
```

No afecta al correo, pero sí a las marcas de tiempo de los registros.

### 2.2 Cortafuegos del sistema

Abre los puertos que Mailu pública. **No abras** los puertos internos de
los contenedores: la red de Docker ya los aísla.

```bash
sudo ufw allow 25/tcp
sudo ufw allow 465/tcp
sudo ufw allow 587/tcp
sudo ufw allow 993/tcp
sudo ufw allow 4190/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

> `ufw` con Docker interactúa mal en algunas versiones: si `ufw status`
> no muestra los puertos, abre el cortafuegos del panel del proveedor
> de VPS. Es la fuente mas comun de "el puerto esta abierto en el
> sistema pero no llega nada".

### 2.3 Desactivar el envio de correo del sistema

La maquina no debe enviar correo por su cuenta; todo el correo pasa
por Mailu:

```bash
sudo systemctl stop postfix 2>/dev/null || true
sudo systemctl disable postfix 2>/dev/null || true
```

---

## 3. Instalar Mailu con este kit

### 3.1 Copiar los archivos

```bash
mkdir -p /opt/mailu
cd /opt/mailu
# Copiar aqui: compose.yaml, .env.example, config/, scripts/
```

### 3.2 Crear el `.env`

```bash
cp .env.example .env
chmod 600 .env
```

`.env` guarda la clave de firma y las contrasenas. Que solo el root lo
lea.

### 3.3 Generar la clave de firma

```bash
openssl rand -hex 16
```

Pega el resultado en `SECRET_KEY` del `.env`. **Una sola vez.** Cambiar
despues invalida las sesiones del panel.

### 3.4 Completar las variables obligatorias

Minimo indispensable:

| Variable | Valor |
| --- | --- |
| `SECRET_KEY` | La generada arriba |
| `DOMAIN` | `ejemplo.cl`, sin `https://` ni subdominio |
| `HOSTNAMES` | `mail.ejemplo.cl` al menos |
| `SUBNET` | `192.168.203.0/24` |
| `RESOLVER_IP` | `192.168.203.9` (última IP de la subred) |
| `TLS_FLAVOR` | `cert` o `letsencrypt` |
| `POSTMASTER` | `postmaster@ejemplo.cl` |
| `INITIAL_ADMIN_DOMAIN` | `ejemplo.cl` |
| `INITIAL_ADMIN_PW` | Una contrasena fuerte |

Detalle de cada una en `03-VARIABLES-Y-COMO-OBTENERLAS.md`.

**`SUBNET` y `RESOLVER_IP` van juntos.** Si cambias una, cambias la
otra. Un resolutor fuera de la subred deja al contenedor `admin` sin
poder arrancar, y su único sintoma es un bucle de errores en el log.

### 3.5 Levantar

```bash
docker compose up -d
```

La primera descarga todas las imagenes: puede tardar varios minutos.

### 3.6 Verificar que todo arranco

```bash
docker compose ps
```

Los ocho servicios deben estar activos:

| Servicio | Si no arranca, mira |
| --- | --- |
| `redis` | Casi nunca falla |
| `resolver` | Debe estar activo antes que `admin` |
| `admin` | `docker compose logs admin` — el sintoma clasico es que espera un resolutor DNSSEC |
| `front` | `docker compose logs front` |
| `imap`, `smtp` | `docker compose logs imap smtp` |
| `antispam` | `docker compose logs antispam` |
| `webmail` | `docker compose logs webmail` |

> **Este kit no define `healthcheck` en ningún servicio.** Es una
> decisión consciente: la plantilla oficial tampoco los define, y no
> se verificó qué herramientas de diagnóstico hay dentro de cada
> imagen. Agregar uno sin verificarlo produce falsos negativos. La
> verificación real es la de esta seccion mas las pruebas de
> `07-PRUEBAS-DE-ACEPTACION.md`.

---

## 4. Montaje de prueba (sin abrir el puerto 25)

**Este es el único camino aceptado para pruebas.** Abrir el 25 en un
servidor sin DNS, DKIM, DMARC y PTR listos quema la reputacion de la
IP, y la recuperacion puede tomar meses.

El `compose.yaml` permite mover el puerto del host sin editarlo. En el
`.env`, comenta las lineas de la seccion 6 y activa estas:

```bash
PUERTO_SMTP=2525
PUERTO_SUBMIT=2587
PUERTO_SUBMITS=2465
PUERTO_IMAPS=2993
```

Con eso:

| Servicio | Puerto en el host | Puerto real |
| --- | --- | --- |
| SMTP | **2525** | 25 |
| Submission | **2587** | 587 |
| SMTPS | **2465** | 465 |
| IMAPS | **2993** | 993 |

El 25 del contenedor sigue escuchando, pero **no hay nada publicado en
el 25 del host**: nadie de Internet puede alcanzarlo.

### Lo que funciona y lo que no en el montaje de prueba

| Se puede probar | No se puede probar |
| --- | --- |
| Que el panel abre | Recepción de correo real |
| Que el webmail abre | Entrega de correo a terceros |
| Que un buzon se crea | Entrega desde el 25 |
| Que el TLS se emite | Reputacion e IP |

**No subas a producción una IP que abriste el 25 sin la configuración
DNS completa.** En el mejor de los casos, la usaste sin querer; en el
peor, esa IP ya esta en una lista negra y no se puede volver atras.

---

## 5. Después de levantar: la fase que decide todo

Levantar el servidor es la parte facil. Lo que sigue es lo que separa
un correo que funciona de uno que va a spam.

### 5.1 Certificado TLS

Según `TLS_FLAVOR`:

**`letsencrypt`** — el contenedor `front` pide el certificado solo.
Necesita el puerto 80 abierto y el DNS apuntando. El log esta en:

```bash
docker compose logs front | grep -i letsencrypt
```

**`cert`** — el certificado lo trae el cliente. Va en el volumen
`certs`, dentro del contenedor, con nombres exactos:

```bash
docker compose cp cert.pem front:/certs/cert.pem
docker compose cp key.pem  front:/certs/key.pem
docker compose restart front
```

Los archivos **deben** llamarse `cert.pem` y `key.pem`, salvo que
cambies `TLS_CERT_FILENAME` y `TLS_KEYPAIR_FILENAME`.

> **No uses enlaces simbolicos.** La documentacion del proyecto lo
> advierte: los enlaces simbolicos hacen que el servidor no encuentre
> el certificado. Copia los archivos de verdad.

### 5.2 Registros DNS

Seguir `../ejemplos/dns-registros-ejemplo.md`. Sin SPF, DKIM y DMARC
publicados, el correo del cliente no se entrega.

### 5.3 Primer buzón

Seguir `../ejemplos/alta-buzon-ejemplo.md`.

### 5.4 Prueba de ida y vuelta

Esto **no se ha ejecutado nunca desde este kit**:

```bash
# Enviar desde el panel a una direccion externa
# Revisar el log de salida
docker compose logs --tail=50 smtp
# Confirmar que llego, incluida la carpeta de spam
```

Si no llega, el diagnóstico esta en `08-SERVICIOS-COMERCIALES.md`.

---

## 6. Instalación alternativa: el asistente web de Mailu

El proyecto ofrece un asistente en `setup.mailu.io` que genera el
compose y el `.env`. **Este kit esta basado en esa plantilla**, así que
las dos vias producen un resultado equivalente.

Cual usar:

| | Asistente web | Este kit |
| --- | --- | --- |
| Requiere abrir un puerto extra (8080) mientras se instala | Sí | No |
| Genera el `.env` solo | Sí | No, se completa a mano |
| Versión fijada a una release concreta | No, sigue `master` | Sí |
| Documentacion asociada | La del proyecto | La de este kit |
| Facilita el primer arranque | Sí | Requiere completar el `.env` |

**No uses los dos metodos en el mismo servidor.** Si ya copiaste
`compose.yaml` y `.env` de este kit, no ejecutes también el asistente:
las dos instalaciones parten variables distintas y el resultado es
impredecible.

---

## 7. Problemas frecuentes en la instalación

| Sintoma | Causa probable | Que hacer |
| --- | --- | --- |
| `admin` reinicia en bucle | Resolutor sin DNSSEC o `RESOLVER_IP` fuera de `SUBNET` | Revisar `SUBNET` y `RESOLVER_IP` juntos; ver `logs admin` |
| No entra al panel | TLS sin emitir, o puerto 443 cerrado | `logs front`, probar `https://` y no `http://` |
| El webmail no carga | `front` no encuentra al contenedor `webmail` | Verificar que `WEBMAIL` del `.env` coincida con la carpeta de `overrides` |
| No llega correo **de entrada** | Puerto 25 entrante cerrado, o MX mal publicado | `dig MX ejemplo.cl`, revisar firewall |
| No llega correo **de salida** | **Puerto 25 saliente bloqueado** | `08-SERVICIOS-COMERCIALES.md` |
| Un cambio en el `.env` no surte efecto | Las variables se leen solo al arrancar | `docker compose down && docker compose up -d` |

---

## 8. References

- Requisitos: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/compose/requirements.rst>
- Instalación oficial: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/compose/setup.rst>
- Preguntas frecuentes: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/faq.rst>
- Plantilla del compose: <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml>
