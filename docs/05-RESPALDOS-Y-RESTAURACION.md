# 05 — Respaldos y restauración

Estado del kit: `kit preparado`. Los scripts existen y su sintaxis fue
validada, pero **no se ejecutó un ciclo real de respaldo y
restauración**. Ver `07-PRUEBAS-DE-ACEPTACION.md`.

---

## 1. Lo que hay que entender antes de respaldar

**El correo es lo único irreemplazable.** Todo lo demas se puede
reconstruir o volver a crear: los usuarios se pueden volver a dar de
alta, los certificados se vuelven a pedir, la configuracion se copia de
un `.env`.

El correo no. Si un buzon se pierde, esos correos **no existen en
ningun otro lado**. El cliente no los tiene en otra parte: por eso esta
compra, para no depender de la nube.

De ahi una regla: **el respaldo tiene que existir antes de que exista
el primer correo**. Un servidor que recibe correo sin respaldo configurado
es un riesgo asumido a ciegas.

---

## 2. Que se respalda

| Volumen | Contenido | Criticidad |
| --- | --- | --- |
| `mail` | **Maildir: todo el correo** | **Irreemplazable** |
| `data` | Base del panel (SQLite: usuarios, dominios, alias, cuotas) y de Roundcube | Alta |
| `dkim` | Claves privadas DKIM | Alta |
| `certs` | Certificados TLS | Alta |
| `mailqueue` | Correo en cola, no entregado | Media |
| `filter` | Aprendizaje del antispam | Media |
| `webmail` | Datos de Roundcube | Media |
| `redis` | Cache de sesiones | **No se respalda** |

### Por que no se respalda Redis

Es cache pura: sesiones y contador de intentos de autenticacion. Se
reconstruye sola al arrancar. Incluirla agranda el respaldo sin
aportar nada recuperable.

### El `.env` no se respalda, y hay que guardarlo aparte

`.env` tiene `SECRET_KEY` y contrasenas **en texto plano**. Por eso el
script no lo copia: un respaldo guardado sin cifrar se convierte en una
via de acceso al servidor.

Aun asi, **sin `.env` la restauracion esta incompleta**: sin
`SECRET_KEY` se invalidan las sesiones del panel, y sin
`INITIAL_ADMIN_*` no se puede crear el administrador inicial.

Guardalo en un gestor de contrasenas del equipo, no en el mismo disco
del servidor.

---

## 3. Ejecutar un respaldo

```bash
cd /opt/mailu
chmod +x scripts/backup-mailu.sh scripts/restore-mailu.sh
./scripts/backup-mailu.sh /var/backups/mailu
```

> El permiso de ejecucion hay que Otorgarlo en el servidor. Este kit
> se escribio en un sistema de archivos que no guarda ese permiso, asi
> que `chmod +x` es un paso obligatorio de la instalacion, no opcional.

Que hace, en orden:

1. Verifica que `docker` y el plugin Compose esten disponibles.
2. Lee `.env` para saber el nombre real del proyecto.
3. **Detiene todos los servicios** de Mailu. Sin esto, un correo que
   llega mientras se copia deja el respaldo inconsistente.
4. Verifica que cada volumen exista y **no este vacio**. Si el volumen
   de correo esta vacio, **aborta**: seria una senal de que el servidor
   no se inicializo bien.
5. Comprime cada volumen en un `.tar`.
6. Calcula el SHA-256 de cada `.tar` en `SHA256SUMS`.
7. Escribe `manifiesto.txt` con el inventario.
8. **Escribe `.completo` al final**, como unica senal de que termino.
9. Relanza los servicios.

### Opciones

```bash
# Destino por defecto: ./respaldos/mailu-<fecha>
./scripts/backup-mailu.sh

# Sin detener los servicios (INSEGURO)
./scripts/backup-mailu.sh --sin-parar /var/backups/mailu

# Ayuda
./scripts/backup-mailu.sh --help
```

`--sin-parar` solo es aceptable con trafico de lectura bajo. En un
servidor con correo entrando, produce respaldos que pueden no
restaurar.

### El marcador `.completo`

Es lo mas importante del respaldo. Se escribe **al final y unico**
cuando todo lo demas termino bien.

Si el respaldo se corto a la mitad, **no** hay `.completo`, y el
`restore-mailu.sh` **se niega a restaurar**. Es intencional: un respaldo
incompleto restaurado encima de un servidor sano es peor que no
restaurar.

Comprobar:

```bash
ls -la /var/backups/mailu/
# debe listar: manifiesto.txt, SHA256SUMS, .completo, y los .tar
```

---

## 4. Verificar que el respaldo sirve

Un respaldo que nunca se restaura no es un respaldo.

### 4.1 Verificar integridad

```bash
cd /var/backups/mailu
sha256sum -c SHA256SUMS
```

Todas las lineas deben decir `OK`.

### 4.2 Verificar que el archivo se puede abrir

```bash
tar -tf mail.tar | head
```

Debe mostrar la estructura del Maildir.

### 4.3 Ensayo de restauracion, en otra parte

Es el unico modo de saber que funciona. **Nunca** pruebes la
restauracion en un servidor de pruebas.

```bash
# Restauracion simulada: no escribe nada
./scripts/restore-mailu.sh /var/backups/mailu -n
```

Y, en un servidor de pruebas con un `.env` aparte:

```bash
COMPOSE_PROJECT_NAME=mailu-prueba ./scripts/restore-mailu.sh /var/backups/mailu
```

---

## 5. Restaurar

### 5.1 Antes de restaurar

- [ ] Confirmar que el respaldo tiene `.completo`
- [ ] `sha256sum -c SHA256SUMS` da `OK` en todos
- [ ] Tener el `.env` del servidor original
- [ ] Confirmar que la version de Mailu del `.env` es compatible
- [ ] Los registros DNS del dominio siguen vigentes
- [ ] **Un respaldo verificado del estado actual**, por si la
      restauracion va mal

### 5.2 Procedimiento

```bash
cd /opt/mailu
./scripts/restore-mailu.sh /var/backups/mailu
```

### Que hace, y que **no** hace

| Si | No |
| --- | --- |
| Verifica `.completo` y `SHA256SUMS` **antes de tocar nada** | No borra volumenes |
| Rechaza rutas absolutas o con `..` dentro de los `.tar` | No ejecuta `DROP` de la base |
| Aborta si el volumen de destino tiene datos | No sobrescribe por su cuenta |
| Extrae conservando permisos | No borra lo que hubiera antes |
| Deja los servicios **detenidos** | No borra nada del servidor |

### 5.3 Sobre `--force`

Sin `--force`, si un volumen de destino tiene contenido, el script
**aborta**. No es un tecnicismo: evita pisar correo que el cliente
todavia no tiene respaldado.

Si hay que restaurar de verdad sobre volumenes con datos, las salidas
legitimas son:

```bash
# a) Restaurar en un proyecto aparte, para comparar
COMPOSE_PROJECT_NAME=mailu-prueba ./scripts/restore-mailu.sh /ruta

# b) Conservar los volumenes actuales antes de restaurar
docker volume rename mailu_mail mailu_mail-antes-de-restaurar
docker volume rename mailu_data mailu_data-antes-de-restaurar

# c) Pisar, aceptando la perdida
./scripts/restore-mailu.sh /ruta --force
```

### 5.4 Opciones

```bash
--simula, -n    No escribe nada. Muestra que pasaria
--force         Restaura aunque el destino tenga datos
--help, -h      Ayuda
```

**Empieza siempre por `--simula`.**

---

## 6. El servidor queda apagado, a proposito

Al terminar, el script **no levanta los servicios**.

Una restauracion necesita revision manual antes de volver a recibir.
Si el script levantara el servidor solo, un error de restauracion se
convierte en perdida de correo entrante.

```bash
docker compose up -d
```

Solo cuando ya se reviso todo.

---

## 7. Automatizar respaldos

Un respaldo manual que depende de que alguien se acuerde, no existe.
Y uno guardado en el mismo disco que los datos, tampoco: el mismo
fallo de hardware que se lleva los datos se lleva el respaldo.

```cron
# Todos los dias a las 03:17, cuando el trafico es bajo
17 3 * * * /opt/mailu/scripts/backup-mailu.sh /var/backups/mailu/%Y%m%d >> /var/log/mailu-backup.log 2>&1
```

**Con eso no basta.** El respaldo tiene que **salir del servidor**:

| Opcion | Nivel |
| --- | --- |
| Copia a otro disco del mismo servidor | Basicamente ninguno. El mismotero fallo pierde todo |
| Sincronizacion a almacenamiento remoto | Bueno |
| Copia offline o cifrada fuera del servidor | Correcto |

Borrado de respaldos viejos: **conserva siempre el ultimo respaldo
completo**, ademas del diario. Si el de hoy esta corrupto, el de ayer
es la red de seguridad.

---

## 8. Restauracion de emergencia: el peor escenario

El servidor murio y no hay nada que arranque.

1. **No intentes arreglar el disco.** Reconstruye la maquina desde cero.
2. Provisiona un VPS nuevo. **El puerto 25 saliente es lo primero que
   hay que asegurar**: sin el, el correo restaurado no sale.
3. Instala el kit de cero (`01-INSTALACION-DOCKER.md`).
4. Recupera el `.env` original del gestor de contrasenas.
5. **Borra los volumenes nuevos que creo la instalacion limpia:**
   ```bash
   docker volume rm mailu_mail mailu_data mailu_dkim mailu_certs
   ```
   Solo si se creations despues del respaldo.
6. Restaura:
   ```bash
   ./scripts/restore-mailu.sh /ruta/al/respaldo
   ```
7. Levanta y verifica buzones y correo:
   ```bash
   docker compose up -d
   docker compose exec admin flask mailu domain ejemplo.cl -u
   ```

**El punto 2 es el que se salta la gente.** Un VPS nuevo con el 25
bloqueado deja el servidor lleno de correo que no puede enviar nada.

---

## 9. Referencias

- Respaldos del proyecto: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/compose/backup.rst>
- Estructura de volumenes: <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml>
- Comandos del panel: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/manage.py>
