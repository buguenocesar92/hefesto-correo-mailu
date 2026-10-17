# 02 — Instalación sobre Coolify

Estado del kit: `kit preparado`. **Esta vía no se ha probado desde este
kit.** Coolify mueve recursos y abre puertos de maneras que cambian el
comportamiento del correo. Ver `07-PRUEBAS-DE-ACEPTACION.md`.

---

## 1. Por qué Coolify y Mailu no se llevan bien

Coolify es un panel de despliegue pensado para HTTP. Trae proxy
inverso, certificados automaticos y un modelo de puertos que no fue
diseñado para un servidor de correo. De ahi las cuatro consecuencias
que hay que tener presentes:

| Consecuencia | Que hacer |
| --- | --- |
| **El proxy inverso de Coolify reescribe las cabeceras** | Mailu no debe pasar por el proxy. Los puertos de correo se publican **directos** |
| **Coolify administra los puertos**, no el `compose.yaml` | El bloque `ports` se define en el panel, no en el archivo |
| **Los certificados automaticos son de Coolify, no de Mailu** | Desactiva los de Coolify para este proyecto y usa `TLS_FLAVOR=cert` o `letsencrypt` |
| **El despliegue se hace con `git pull` y reconstruye** | Un despliegue reconstruido a ciegas puede perder el correo si el volumen no es persistente real |

**Conclusion:** en Coolify, Mailu se despliega como un proyecto Docker
de una sola instancia, con puertos directos y sin proxy inverso. No
como una aplicacion web mas.

---

## 2. Requisitos previos

Los mismos de `01-INSTALACION-DOCKER.md`, mas:

- Un servidor dedicado. **No** pongas Mailu en el mismo servidor que
  otras apps de Coolify: comparten CPU, memoria y ancho de banda, y el
  correo es lo ultimo que deberia sufrir por eso.
- El dominio apuntando **directamente** a la IP del servidor, sin CDN.

---

## 3. Crear el proyecto

1. **New Project** → **Docker Compose**.
2. Nombre: `mailu`.
3. Apunta al repositorio donde vive este kit, o sube los archivos con
   la opcion de compose pegado en el panel.

### Variables de entorno

Coolify lee las variables del panel y las inyecta. Copia aqui el
contenido de `.env.example`, completo. Marcas como secretas, al menos:

| Variable | Secreta |
| --- | --- |
| `SECRET_KEY` | Sí |
| `INITIAL_ADMIN_PW` | Sí |
| `RELAYPASSWORD` | Sí |
| `API_TOKEN` | Sí |

Coolify **reconstruye** el proyecto cuando cambian las variables. Un
cambio en `.env` sin reconstruccion no se aplica, que es el mismo
comportamiento documentado por Mailu.

---

## 4. Puertos

Aqui es donde Coolify se aparta del kit. El `compose.yaml` trae un
bloque `ports` con siete puertos; **en Coolify el panel es la fuente de
verdad** y hay que replicarlos ahi.

| Puerto | Servicio | Publicar |
| --- | --- | --- |
| 25 | SMTP entrante | **Sí, obligatorio** |
| 465 | Submission TLS | Sí |
| 587 | Submission STARTTLS | Sí |
| 993 | IMAPS | **Sí, obligatorio** |
| 4190 | ManageSieve | Sí |
| 80 | HTTP, para ACME y redireccion | Sí |
| 443 | HTTPS, panel y webmail | Sí |
| 8080 | Panel de Coolify | No. Nunca lo publiques |

Si el panel de Coolify **no** permite publicar puertos fuera de HTTP y
HTTPS, **Mailu no se puede desplegar correctamente en esa
instalacion**. Es una limitacion del panel, no del kit. Usa la
instalacion directa de `01-INSTALACION-DOCKER.md`.

---

## 5. Proxy inverso y certificados

### 5.1 No pasar el correo por el proxy

Si creas un dominio en la seccion de proxy de Coolify, este va a
capturar el trafico web y lo va a mandar al contenedor equivocado.

Lo que hay que hacer:

- **No** crees entradas de proxy inverso para `mail.<dominio>`.
- Deja que el `front` de Mailu atienda directamente los puertos 80 y
  443.

### 5.2 Si detras hay un proxy inverso externo

Solo aplica al trafico **web** (panel y webmail), nunca a los puertos de
correo. El `front` de Mailu acepta reenvio de IP real con:

```bash
REAL_IP_HEADER=X-Real-IP
REAL_IP_FROM=192.0.2.0/24
```

Con eso, nginx registra y aplica las reglas de bloqueo usando la IP
real del visitante en vez de la del proxy.

Los puertos 25, 465, 587 y 993 **nunca** van por proxy. No hay proxy
que los soporte.

---

## 6. Volúmenes

Los volúmenes nombrados son la parte que mas se daña cuando se despliega
en un panel. Deben quedar **persistentes y con nombre estable**.

El `compose.yaml` los declara:

| Volumen | Contiene |
| --- | --- |
| `mail` | **Todo el correo.** Irreemplazable |
| `data` | Base del panel (SQLite) y de Roundcube |
| `dkim` | Claves privadas DKIM |
| `certs` | Certificados TLS |
| `mailqueue` | Cola de salida |
| `filter` | Aprendizaje del antispam |
| `webmail` | Datos del webmail |
| `redis` | Cache. No se respalda |

En Coolify, **verifica que los volúmenes son persistentes antes del
primer despliegue.** Un volumen que se recrea en cada despliegue borra
el correo del cliente.

Comprobacion desde el servidor:

```bash
docker volume ls | grep mail
docker inspect mailu_mail --format '{{ .Mountpoint }}'
```

Si el punto de montaje cae dentro de un directorio que Coolify borra en
cada despliegue, hay que mover los volúmenes a disco persistente antes
de continuar.

---

## 7. Webmail y composicion del proyecto

### Sin webmail

Roundcube no es necesario para todos los clientes. Para quitarlo:

1. Comenta el servicio `webmail` completo en el `compose.yaml`.
2. Pon `WEBMAIL=none` en el `.env`.
3. Quita el volumen `webmail` de la seccion `volumes`.

Los usuarios conectaran su cliente de correo por IMAP. El panel de
administracion sigue en `/admin`.

---

## 8. Atualizaciones en Coolify

Coolify despliega con `git pull` y reconstruye. Para Mailu eso es
arriesgado por dos motivos:

1. Si el `.env` regenerado cambia `SECRET_KEY`, **se invalidan todas
   las sesiones** del panel.
2. Si la version de Mailu cambia sin querer, se actualiza a algo que
   nadie probo.

Procedimiento correcto, en `06-ACTUALIZACIONES-Y-REVERSION.md`:

1. Respaldo con `scripts/backup-mailu.sh` y **confirmar** que
   termino bien.
2. Cambiar `MAILU_VERSION` a mano en el `.env`.
3. Desplegar.
4. Verificar.

Nunca uses "reconstruir" como atajo a una actualizacion.

---

## 9. Respaldo en Coolify

Los scripts de este kit se ejecutan en el servidor, no en Coolify:

```bash
cd /opt/mailu
./scripts/backup-mailu.sh /var/backups/mailu
```

El respaldo **debe** salir del servidor a un destino externo. Un
respaldo que vive en el mismo disco que los datos no es un respaldo.

---

## 10. References

- Documentacion de Coolify: <https://coolify.io/docs/>
- Topologia y puertos de Mailu: <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml>
- Cambios de IP real con proxy: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/configuration.rst>
