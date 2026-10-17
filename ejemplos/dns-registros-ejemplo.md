# Registros DNS de ejemplo — Mailu

> ## ESTADO: MATERIAL DE DEMOSTRACION
> Este archivo **NO** se aplica automáticamente. No ejecutes estos
> comandos a ciegas: los valores son de un dominio ficticio
> (`ejemplo.cl`) y una IP de ejemplo de la documentación
> (`203.0.113.10`, que es un bloque reservado y nunca enruta).
>
> Antes de aplicar cualquier registro, reemplaza **todas** las
> ocurrencias de `ejemplo.cl`, `mail.ejemplo.cl` y la IP por los
> datos reales del cliente, y confirma la zona DNS con el proveedor
> de DNS del cliente.

Todos los registros van en la zona DNS del dominio del cliente
(`ejemplo.cl`). El tipo de cada registro está indicado.

---

## 1. Resumen: qué hay que publicar y qué pasa si falta

| Registro | Para qué | Qué pasa si falta |
| --- | --- | --- |
| **A** de `mail.ejemplo.cl` | Dónde está el servidor | Nadie encuentra tu correo. Error de entrega inmediato |
| **PTR** (DNS inverso) de la IP | Que la IP se llame como el dominio | Mucha entrega va a spam. Gmail y Outlook lo penalizan |
| **MX** | A qué servidor va el correo del dominio | El correo que llega a `@ejemplo.cl` rebota |
| **SPF** | Qué servidores pueden enviar como `@ejemplo.cl` | Los correos del cliente salen marcados como fraude |
| **DKIM** | Firma criptográfica de cada mensaje | El correo del cliente es fácil de suplantar y va a spam |
| **DMARC** | Qué hacer cuando SPF o DKIM fallan | No hay defensa; el dominio queda expuesto a suplantación |

**Los tres últimos son los que hacen que el correo sea entregable.**
Son obligatorios. Un servidor de correo sin SPF, DKIM y DMARC no
funciona, aunque todo lo demás esté perfecto.

---

## 2. Registros de ubicacion

### 2.1 Registro A del servidor de correo

```
mail.ejemplo.cl.            IN A     203.0.113.10
```

- Si el servidor tiene IPv6 en el correo, agrega tambien el AAAA.
- **No pongas un CDN delante** (Cloudflare y similares): el correo
  necesita la IP real del servidor. Un registro A apuntando a un CDN
  hace que el puerto 25 termine en otro lado y nada llega.

### 2.2 Registro PTR (DNS inverso), en la zona del proveedor de VPS

Este registro **no** se pone donde está el dominio: lo controla quien
te entregó la IP, o sea tu proveedor de VPS.

```
203.0.113.10   ->   mail.ejemplo.cl.
```

Pide el PTR al proveedor de VPS. **El valor debe coincidir exacto con
el nombre del registro A.** Si el PTR dice `vps-12345.proveedor.cl` y
el A dice `mail.ejemplo.cl`, la mayoría de los receptores lo trata como
no verificable y tira el correo a spam.

En el FAQ del propio Mailu aparece el efecto de no tener esto:

> I did not set properly the reverse DNS entry for my mail server, and
> hence the SPF and DKIM checks are failing: fix it.

### 2.3 Registro MX

```
ejemplo.cl.                 IN MX    10 mail.ejemplo.cl.
```

El `10` es la prioridad. Con un solo servidor basta con un registro.
Si hay dos servidores, el segundo va con `20`.

---

## 3. SPF

**Qué es:** una lista de servidores autorizados a enviar correo como
`@ejemplo.cl`. Si un servidor que no está en la lista manda un correo
con ese remitente, los receptores lo pueden rechazar.

### Registro de ejemplo

```
ejemplo.cl.                 IN TXT   "v=spf1 mx -all"
```

### Qué significa cada parte

| Parte | Significado |
| --- | --- |
| `v=spf1` | Versión del formato |
| `mx` | Los servidores indicados en los registros MX pueden enviar |
| `-all` | Cualquier otro servidor, **rechazar**. Es lo correcto |

### Alternativa si el cliente usa un relay de salida

Si mandas el correo a través de un proveedor transaccional (ver
`relay-saliente-ejemplo.md`), ese proveedor también debe estar en el
SPF:

```
ejemplo.cl.   IN TXT   "v=spf1 mx include:proveedor-transaccional.cl -all"
```

**Nunca pongas `+all`.** Eso autoriza a cualquier servidor del mundo
a enviar como `@ejemplo.cl`, y es la vía clásica para el fraude de
suplantación de identidad.

**Regla de oro:** basta **un** registro SPF por dominio. Dos
registros SPF invalidan el chequeo.

### Cómo verificar

```bash
dig TXT ejemplo.cl +short
```

---

## 4. DKIM

**Qué es:** una firma criptográfica que el servidor pone en cada
mensaje. El receptor la verifica con la clave pública publicada en
DNS. Si alguien intenta enviar un correo falso como `@ejemplo.cl`,
no podrá generar una firma válida.

### 4.1 Generar la clave

Mailu la crea sola la primera vez que se pide, y la guarda en el
volumen `dkim`. La ruta dentro del contenedor `admin` es
`/dkim/<dominio><selector>.key`, y el selector sale de la variable
`DKIM_SELECTOR` del `.env` (`dkim` por defecto).

Para que Mailu genere la clave, hay que **crear el dominio desde el
panel** (ver `alta-buzon-ejemplo.md`). Después se lee:

```bash
# Nombre de la clave publica, tal como lo muestra el panel
docker compose exec admin cat /dkim/ejemplo.cldkim.key
```

### 4.2 Registro de ejemplo

El registro **no** se escribe a mano: se pega el contenido exacto que
entrega el panel.

```
dkim._domainkey.ejemplo.cl.  IN TXT   "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEB..."
```

| Parte | Significado |
| --- | --- |
| `dkim._domainkey` | Subdominio fijo de la clave |
| `v=DKIM1` | Versión del formato DKIM |
| `k=rsa` | Tipo de clave |
| `p=...` | La clave pública, sin saltos de línea |

El nombre del registro usa el valor de `DKIM_SELECTOR`. Si en el
`.env` dejaste `DKIM_SELECTOR=correo`, el registro sería
`correo._domainkey.ejemplo.cl`.

### 4.3 Cómo verificar

```bash
dig TXT dkim._domainkey.ejemplo.cl +short
```

También hay una prueba de extremo a extremo que indica la clave usada,
el resultado de la firma y si DMARC pasa:

```bash
docker compose exec admin flask mailu dkim-test ejemplo.cl
```

El comando **debe ejecutarse después** de publicar el registro DNS:
antes de eso va a fallar, y es lo normal.

---

## 5. DMARC

**Qué es:** le dice al receptor qué hacer cuando un correo que dice
ser de `@ejemplo.cl` **no pasa** las pruebas de SPF y DKIM. Es la
defensa final contra la suplantación de identidad.

### Registro de ejemplo

```
_dmarc.ejemplo.cl.           IN TXT   "v=DMARC1; p=none; rua=mailto:postmaster+dmarc@ejemplo.cl"
```

| Parte | Significado |
| --- | --- |
| `v=DMARC1` | Versión del formato |
| `p=none` | Qué hacer con los que fallan: solo observar y reportar |
| `rua=mailto:...` | A donde llegan los reportes de fraude |

### Los tres valores de `p`

| Valor | Que hace | Cuando usarlo |
| --- | --- | --- |
| `p=none` | Solo observa y reporta | **Primeros dias.** Sirve para ver si algo falla sin romper entregas |
| `p=quarantine` | Manda a la carpeta de spam | Cuando ya no hay errores |
| `p=reject` | Rechaza el correo | Estado final de un dominio bien configurado |

**El orden correcto es `none` primero.** Publicar `p=reject` antes de
verificar que SPF y DKIM están bien hace que se rechace correo
legítimo, y esa falla cuesta mucho más de arreglar que unos días de
espera.

Los informes que llegan a `rua` se revisan en el panel de Mailu, en la
sección de DMARC.

### Cómo verificar

```bash
dig TXT _dmarc.ejemplo.cl +short
```

---

## 6. Configuracion automatica de clientes (opcional pero recomendado)

Si el HOSTNAMES del `.env` incluye `autoconfig.ejemplo.cl` y
`autodiscover.ejemplo.cl`, Mailu responde en esos subdominios y
Thunderbird u Outlook configuran el buzón solos:

```
autoconfig.ejemplo.cl.       IN A     203.0.113.10
autodiscover.ejemplo.cl.     IN A     203.0.113.10
```

Están marcados como opcionales a propósito. **Confirma en la versión
que vas a instalar** si la detección automática está disponible:
depende de que los subdominios estén en `HOSTNAMES` **y** de que los
registros A existan.

Si el cliente usa un proveedor de correo anterior, conviene configurar
el buzón a mano una vez y no depender de esto.

---

## 7. Comprobacion final, toda junta

```bash
dig A     mail.ejemplo.cl +short      # debe devolver la IP real del servidor
dig MX    ejemplo.cl +short           # debe devolver "10 mail.ejemplo.cl."
dig TXT   ejemplo.cl +short           # registro SPF
dig TXT   dkim._domainkey.ejemplo.cl +short   # registro DKIM
dig TXT   _dmarc.ejemplo.cl +short    # registro DMARC
dig -x    203.0.113.10 +short         # PTR: debe devolver mail.ejemplo.cl.
```

Los seis tienen que responder bien **antes** de mandar el primer
correo. Publicar el correo sin esto es la causa mas comun de que un
dominio completo entre en una lista negra.

---

## 8. References

- Registros DNS del proyecto: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/dns.rst>
- Configuracion y variables: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/configuration.rst>
- Generacion de claves DKIM: <https://github.com/Mailu/Mailu/blob/2024.06.64/core/admin/mailu/configuration.py>
