# config/ — puntos de montaje de configuración

`compose.yaml` monta estas carpetas dentro de los contenedores como
`/overrides`, en solo lectura. Mailu permite reemplazar o agregar
archivos de configuración por servicio sin reconstruir las imágenes.

Estos directorios se crean **vacíos** en el kit. Mailu funciona sin
nada dentro: si la carpeta está vacía, el servicio usa su
configuración interna sin tocar nada.

## Carpetas y a qué servicio pertenecen

| Carpeta | Servicio | Qué se puede sobrescribir |
| --- | --- | --- |
| `overrides/nginx` | `front` | `nginx.conf`, `nginx-http.conf`, `nginx-tls.conf`, `nginx-trusted.conf` |
| `overrides/dovecot` | `imap` | Archivos de configuracion de Dovecot |
| `overrides/postfix` | `smtp` | `main.cf`, `master.cf` y mapas de Postfix |
| `overrides/rspamd` | `antispam` | `worker-normal`, `worker-proxy`, `local-*` |
| `overrides/roundcube` | `webmail` | `config.inc.php` y estilos de Roundcube |
| `overrides/snappymail` | `webmail` | Solo si `WEBMAIL=snappymail` en el `.env` |

## Como se elige la carpeta del webmail

El `compose.yaml` monta:

```
./config/overrides/${WEBMAIL}:/overrides:ro
```

con `WEBMAIL` tomado del `.env`. Con `WEBMAIL=roundcube` monta
`overrides/roundcube`; con `WEBMAIL=snappymail`, la otra. Las dos
carpetas existen para que el compose no falle al arrancar.

## Reglas

1. **No edites a mano lo que no necesitas.** Cada archivo que
   sobrescribas es un archivo que pierdes en la próxima actualización
   de Mailu y que tienes que volver a revisar.
2. **Antes de sobrescribir un archivo de Mailu, copia el original.**
   Sale de la imagen, no del repositorio:
   ```bash
   docker compose exec front cat /etc/nginx/nginx.conf > /tmp/nginx.conf
   ```
3. **Un cambio de configuración en `/overrides` necesita reiniciar el
   servicio afectado**, no todo el stack:
   ```bash
   docker compose restart front
   ```
4. Un archivo con error de sintaxis puede dejar el servicio sin
   arrancar. Si algo falla, borra lo último que tocaste y reinicia.

## Esto no se respalda

`config/` se versiona en git: es configuración del kit, no del cliente.
Lo que **sí** hay que respaldar es el volumen `certs` y las claves
privadas DKIM, y eso lo hacen los scripts de respaldo.

## Por qué estas carpetas existen en el compose y no se crean al vuelo

Docker solo monta directorios que existen en el host. Si `./config/overrides/nginx`
no estuviera, `docker compose up` falla con un error de origen de
montaje inexistente. Por eso el kit las trae.
