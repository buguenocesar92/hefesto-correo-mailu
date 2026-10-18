# 08 — Servicios comerciales: costos, riesgos y qué prometer

Este documento es para Hefesto Studio, no para el cliente final. Antes
de vender, hay que leerlo completo.

---

## 1. La verdad de fondo

**Levantar un servidor de correo no es "configurar y listo".**

Un mal dominio daña la reputación de una IP y de un dominio **ante
todo el mundo**, no solo ante el cliente. Cuando la IP queda en listas
negras, el correo no va a la carpeta de spam: **no va**. Y la
recuperacion no es un click.

Esta es la diferencia entre instalar un sitio web y un servidor de
correo. Un sitio caido se pierde tráfico. Un servidor de correo con la
IP quemada **deja de enviar**, y el cliente lo descubre cuando un
cliente suyo le escribe y no recibe respuesta.

**Si en la propuesta comercial aparece la palabra "inmediato" al lado de
"correo funcionando", hay que sacarla.**

---

## 2. El puerto 25 saliente: el riesgo número uno

### Que ocurre

La mayoria de los proveedores de VPS e internet **bloquean el puerto 25
saliente** por defecto, para frenar el spam desde cuentas de hospedaje.

Si esta bloqueado:

| | |
| --- | --- |
| El servidor **recibe** correo | Funciona |
| El servidor **envia** correo | **No funciona. En absoluto** |
| Error visible en la interfaz | **Ninguno** |
| Sintoma | El cliente escribe, Mailu muestra "enviado", y nada sale |

**Ese silencio es lo que lo hace peligroso.** Un operador sin
experiencia puede semanas pensando que el problema es del cliente o del
DNS, cuando el bloqueo estaba desde el primer dia.

### Verificarlo ANTES de prometer nada

Siempre antes de cotizar, antes de instalar:

```bash
timeout 10 bash -c 'exec 3<>/dev/tcp/mx.gmail.com/25' \
  && echo "ABIERTO" || echo "BLOQUEADO"
```

| Resultado | Diagnóstico |
| --- | --- |
| Conexión rechazada | Cortafuegos local. Revisar `ufw` y el panel del proveedor |
| Se cuelga y expira | **Bloqueo del proveedor** |
| Conecta y responde `220` | El 25 esta abierto. El problema es DNS, no el puerto |

### Como pedir el desbloqueo

Es una peticion **comercial**, por el canal de soporte del proveedor.
No hay solucion técnica:

> Necesito el puerto 25 saliente habilitado en el plan X, IP Y. Z. El
> servidor envia correo corporativo del dominio propio del cliente. Acepto
> las condiciones antispam y los limites de envio.

| Respuesta del proveedor | Que hacer |
| --- | --- |
| Habilitan sin costo | Ideal |
| Cobran | Costo mensual adicional. Sumarlo a la cotizacion |
| Niegan por tipo de plan | **No hay apelacion.** Pasar al relay de salida |

### Sobre "evadir" el bloqueo

**Este kit no incluye, no documenta y no debe incluir ninguna forma de
evadir el bloqueo.** No hay ninguna que sea legitima. Lo que circula en
internet para esto es:

- Usar cuentas personales para reenviar correo.
- Enviar por puertos o servidores que no son tuyos.
- Configuraciones que esquivan el filtro del proveedor.

Todas son **fraude contractual** con el proveedor de VPS, y todas
terminan en lo mismo: el servidor expulsado y el dominio asociado a
esa IP durante meses o años. La única salida es hablar con el
proveedor.

### Alternativa: relay de salida

Un proveedor transaccional envia el correo por ti, usando servidores
propios que si tienen acceso al puerto 25.

| | Consecuencia |
| --- | --- |
| Costo | El VPS **mas** el relay, según volumen |
| Privacidad | **Todo el correo pasa por un tercero.** Hay que informarlo al cliente |
| Reputacion | La del proveedor, no la tuya |
| SPF | Hay que agregar `include:` del proveedor |
| DKIM | **Hay que verificar** que el proveedor no borre la firma al reenviar |

Detalle operativo en `../ejemplos/relay-saliente-ejemplo.md`.

**El relay es la salida legitima cuando el bloqueo es permanente.**
No es una trampa, es la respuesta correcta.

---

## 3. El riesgo de las listas negras

### La magnitud

Un dominio en una lista negra **deja de enviar correo**. No es "llego
a spam": es "no llega".

La recuperacion depende de la lista y suele tomar:

| Lista | Tiempo tipico de salida |
| --- | --- |
| Listas de envio masivo | Horas a dias |
| Listas de spam activas | Dias a semanas |
| Bloqueos por IP en un proveedor grande | Semanas a **meses** |

Y **no hay garantia**. Algunos bloqueos son permanentes.

### Como se llega ahi

| Causa | Prevencion |
| --- | --- |
| Abrir el 25 sin SPF, DKIM ni DMARC | No publicar hasta tener los registros |
| Enviar spam desde un buzon comprometido | `MESSAGE_RATELIMIT`, contrasenas unicas |
| `RELAYNETS` con contenido | **Siempre vacio** |
| Nombre de remitente o enlaces que parecen spam | Educacion del cliente |
| Comprar bases de datos de correos | No es un servicio que Hefesto Studio ofrezca |
| Muchos dominios en una misma IP | Un cliente por instalación |

### Como salir de una lista negra

1. Identificar la lista exacta que bloquea. Herramientas online de
   reputacion de IP.
2. Solicitar la retirada siguiendo el procedimiento de esa lista.
3. **Esperar.** Mientras espera, el correo sigue sin entregar.
4. Revisar que SPF, DKIM y DMARC esten correctos. Sin eso, la
   reincorporacion no se sostiene.

**Por eso la mitigacion es preventiva.** Una vez quemada la IP, no hay
plan B.

---

## 4. Mailu no es multi-tenant

**Una instancia de Mailu es para un cliente.**

No es un problema de configuración que se pueda ajustar: es la
arquitectura. No existe el concepto de "organizaciones" separadas dentro
de una instancia, y agregarlo por encima seria un desarrollo a medida
que Hefesto Studio no ofrece.

| Necesidad del cliente | Que hacer |
| --- | --- |
| Un dominio, su propio servidor | **Esto.** Una instancia por cliente |
| Varios dominios del mismo cliente | Una instancia con varios dominios. Funciona |
| Varias empresas en un servidor | **No.** Instancia separada por empresa |

### Consecuencia comercial

Cada cliente de Hefesto Studio necesita **su propio VPS**. No es una
decisión técnica: es la única forma de que la separacion entre los
correos de clientes distintos sea real, tanto tecnicamente como frente
a la normativa de protección de datos.

Un servidor compartido con dos empresas seria, ademas, un problema de
cumplimiento: el correo de una seria accesible desde la instalación de
la otra.

---

## 5. Ley 19.628 — responsabilidad del cliente

**Esto es responsabilidad del cliente. No es una función del kit.**

La Ley 19.628 de protección de datos personales obliga a quien trata
datos personales. Un buzón de correo corporativo contiene nombres,
apellidos, correos, y a veces datos de salud, remuneracion o credenciales.

| Lo que hace Mailu | Lo que NO hace Mailu |
| --- | --- |
| Almacena el correo en el servidor | No decide para que se usa ese correo |
| Aplica limite de intentos de autenticación | No evalua la licitud del tratamiento |
| Registra accesos al panel | No genera el consentimiento |
| Firma los correos con DKIM | No clasifica el contenido |

### Que hay que dejar dicho por escrito

- El cliente es el **responsable del tratamiento** de los datos
  personales de sus empleados y clientes.
- Mailu **no aporta las medidas técnicas y organizativas** que la ley
  exige en materia de seguridad.
- El cliente debe:
  - Informar a sus empleados y clientes sobre el cambio de plataforma.
  - Tener una política de respaldo y su custodia.
  - Cumplir los plazos de conservacion y los derechos de los titulares.
  - Designar un responsable del tratamiento.
- Hefesto Studio instala el servidor. **No es el responsable del
  tratamiento de los datos del cliente.**

Esta separacion tiene que quedar por escrito en el contrato. Es lo que
protege a Hefesto Studio y lo que el cliente necesita para cumplir.

---

## 6. Estado tecnologico

| Tema | Estado |
| --- | --- |
| Versión | Mailu `2024.06.64`, con commit fijo |
| Licencia | MIT. Se puede vender y dar soporte |
| Multi-tenant | **No.** Un cliente por instalación |
| Cluster o alta disponibilidad | **No.** Un VPS, un servidor |
| Cifrado en reposo del correo | **No.** El Maildir es texto plano en el volumen |
| Cifrado en transito | Si, TLS obligatorio |
| Panel de administración | Si, en `/admin` |
| Busqueda de texto completo | Parcial. Requiere `fts_attachments`, que este kit no instala |
| Sincronización con el celular | Via IMAP, sin Exchange ni ActiveSync |

Sobre el cifrado en reposo: los volumenes estan en el disco del
servidor sin cifrar. Si el servidor se compromete, el correo se lee.
**No prometas cifrado en reposo.** Si el cliente lo exige, es un
requisito que este kit no cumple.

---

## 7. Costos para el cliente

| Concepto | Detalle |
| --- | --- |
| VPS | Minimo 2 vCPU, 2 GB RAM, 20 GB de disco. Mas el correo que acumule |
| Dominio | Anual,Roughamente 10.000 a 25.000 CLP según la extension |
| Puerto 25 | Puede tener costo adicional según el proveedor |
| Relay de salida | Según volumen, si el 25 esta bloqueado |
| Certificado TLS | Gratis con Let's Encrypt, o pagado con `cert` |
| Respaldo externo | Imprescindible. Otro almacenamiento, no el mismo disco |
| Soporte | Contrato mensual de Hefesto Studio |

Lo que **no** aparece en la lista de costos de una licencia por buzon:
el VPS, el dominio, la migración, el soporte y el tiempo del cliente
para configurar DNS. **La migración y el DNS son horas de Hefesto
Studio que hay que cotizar aparte.**

---

## 8. Sobre vender

### Lo que si se puede prometer

- Mailu es software libre bajo licencia MIT, sin costo de licencia.
- El correo queda en un servidor del cliente, en su dominio.
- Se paga por la instalación y el soporte, no por buzon.
- Se hace un respaldo y se documenta como se restaura.
- Los registros DNS que el cliente necesita, explicados paso a paso.

### Lo que NO se puede prometer

| No prometer | Por que |
| --- | --- |
| "Correo funcionando de inmediato" | El DNS y la propagacion demoran, y el 25 puede estar bloqueado |
| "Garantizado" | El resultado depende del DNS y de la reputacion, que no controlamos |
| "Sin riesgo" | Montar un servidor de correo tiene riesgo real de reputacion |
| "Nunca se pierde correo" | Depende del respaldo, y el respaldo depende del cliente |
| "Funciona igual que Gmail" | No hay busqueda avanzada, ni calendario, ni contactos sincronizados |
| "El 25 se puede abrir" | Depende del proveedor, no de nosotros |

### El discurso honesto

>_INSTALamos el servidor en su maquina, con su dominio. El correo deja
> de depender de una licencia por buzon. A cambio, hay trabajo de su
> parte: configurar los registros DNS y revisar que el servidor envia
> correctamente. El envio de correo depende de que su proveedor de
> hosting tenga el puerto 25 abierto; si no lo tiene, hay dos salidas y
> se las explicamos antes de empezar. La reputacion del dominio
> depende de que la configuración se haga bien, y por eso la dejamos
> documentada y acompañada en la entrega._

Al cliente final le queda claro desde el primer dia que el cambio de
plataforma tiene una parte de trabajo de su lado.

---

## 9. References

- Bloqueo del 25 y efectos: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/faq.rst>
- Requisitos y puertos: <https://github.com/Mailu/Mailu/blob/2024.06.64/docs/compose/requirements.rst>
- Plantilla del compose: <https://github.com/Mailu/Mailu/blob/2024.06.64/setup/flavors/compose/docker-compose.yml>
- Licencia MIT: <https://raw.githubusercontent.com/Mailu/Mailu/2024.06.64/LICENSE.md>
