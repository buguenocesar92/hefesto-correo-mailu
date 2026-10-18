# Mailu — kit de despliegue

Correo corporativo en el dominio del cliente, autoalojado, sin
licencias por buzon.

**Estado: `kit preparado`.** Este kit fue armado y verificado contra el
código fuente de Mailu, pero **nunca se ejecutó en un servidor ni se
envió un correo real desde él**. Lo verificado y lo pendiente están
separados en `docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## Qué es esto

Mailu es un servidor de correo completo y libre, que corre como un
conjunto de contenedores Docker: recibe y entrega correo (SMTP),
permite leerlo (IMAP), trae webmail, filtra el spam y trae un panel de
administración.

Este kit no es Mailu. Es la parte de Hefesto Studio: el `compose.yaml`
con versiones fijadas, el archivo de variables, los scripts de respaldo
y la documentación de instalación y operación.

## Qué incluye

| Ruta | Qué es |
| --- | --- |
| `compose.yaml` | 8 servicios, versiones fijadas, volúmenes nombrados |
| `.env.example` | Variables de entorno con las obligatorias marcadas |
| `scripts/backup-mailu.sh` | Respaldo de correo, base del panel, DKIM y certificados |
| `scripts/restore-mailu.sh` | Restauración con validación de integridad |
| `ejemplos/` | Registros DNS, relay saliente y alta de buzón (demostración) |
| `docs/` | 10 documentos de instalación, operación y riesgos |
| `VERSION.md` | Versiones, digests y diferencias con guías viejas |
| `LICENCIAS.md` | Licencias de todo lo que se instala |
| `config/` | Puntos de montaje de configuración por servicio |

## Lo que este kit NO hace

Estas limitaciones no son detalles de forma de escribir; son
decisiones de diseño. Léelas antes de vender nada.

**No es "configurar y listo".** Levantar un servidor de correo es una
operación delicada. Un dominio mal configurado daña la reputación del
cliente ante todo el mundo, y la recuperación puede tomar meses. La
instalación incluye una fase de verificación de DNS obligatoria.

**Mailu no es multi-tenant.** Una instancia es para un cliente. Cada
cliente de Hefesto Studio necesita su propio servidor, o su propio
dominio con control separado. No se puede poner a diez empresas en una
sola instalación. Ver `docs/08-SERVICIOS-COMERCIALES.md`.

**El puerto 25 saliente puede estar bloqueado.** Muchos proveedores de
VPS lo bloquean por defecto. Si está bloqueado, el servidor **recibe**
correo pero **no puede enviarlo**, y el síntoma es que no hay ningún
error visible: simplemente nada sale. Ninguna configuración de este kit
intenta rodear ese bloqueo, porque no hay forma legítima de hacerlo. La
salida es contractual con el proveedor, o un relay de un proveedor
transaccional. Ver `docs/08-SERVICIOS-COMERCIALES.md`.

**Supabase no aplica.** Mailu gestiona su propio almacenamiento y su
propia base de datos interna (SQLite). El equipo de Mailu desaconseja
incluso usar PostgreSQL. Este kit no conecta nada a Supabase.

**No hay soporte desde este entorno.** Si algo falla, el diagnóstico es
de Hefesto Studio, leyendo la documentación.

## Requisitos del servidor

Verificados contra `docs/compose/requirements.rst` del proyecto:

- Linux con Docker Engine y el plugin `docker compose` v2.
- **Un dominio propio** que el cliente controle por completo.
- **Los 5 puertos publicados** abiertos desde Internet: 25, 465, 587,
  993, 80, 443, más 4190 para los filtros del webmail.
- Un registro DNS **A/AAAA** apuntando al servidor. Si hay CDN o proxy
  delante, no sirve: el correo necesita la IP real.
- **Resolutor DNS con validación DNSSEC.** Desde Mailu 1.9 el panel de
  administración **no arranca** sin uno. Este kit lo resuelve internamente
  con un contenedor `unbound`.

## Instalación rápida

```bash
cp .env.example .env
$EDITOR .env          # completa DOMAIN, HOSTNAMES, SECRET_KEY, POSTMASTER
docker compose up -d
docker compose ps     # todos los servicios deben salir healthy o running
```

Eso levanta el servidor. **No es el fin del proceso.** Falta la fase
que decide si el correo se entrega o no:

1. Verificar que el puerto 25 saliente esté abierto.
2. Publicar los registros DNS (SPF, DKIM, DMARC, MX, PTR).
3. Obtener el certificado TLS.
4. Crear el buzón del cliente.
5. Enviar un correo de prueba y **revisar que llegó**.
6. Recién ahí se puede llamar "instalado".

El detalle está en `docs/01-INSTALACION-DOCKER.md`.

## Documentación

| Documento | Para qué |
| --- | --- |
| `01-INSTALACION-DOCKER.md` | Instalación paso a paso, y montaje de pruebas sin abrir el 25 |
| `02-INSTALACION-COOLIFY.md` | Instalación sobre Coolify |
| `03-VARIABLES-Y-COMO-OBTENERLAS.md` | Cada variable obligatoria y cómo conseguir su valor |
| `04-PRIMERA-CUENTA-Y-USUARIOS.md` | Crear el primer buzón, altas y alias |
| `05-RESPALDOS-Y-RESTAURACION.md` | Qué respaldar, cómo verificar y cómo restaurar |
| `06-ACTUALIZACIONES-Y-REVERSION.md` | Actualizar Mailu y volver atrás |
| `07-PRUEBAS-DE-ACEPTACION.md` | Qué se verificó y qué falta probar |
| `08-SERVICIOS-COMERCIALES.md` | Riesgos, costos y qué prometer al cliente |
| `09-EXPORTACION-O-TRASPASO.md` | Cómo se exporta o traspasa el correo |
| `10-LICENCIAS-Y-FUENTES.md` | Licencias y enlaces verificados |

## Estado

```
kit preparado
```

Significa: los archivos existen, están documentados y fueron cotejados
con el código de Mailu `2024.06.64`. **No** significa que se haya
probado en producción. En particular, **nunca se ha probado el envío
real de correo desde este kit.**

## Licencia

Mailu corre bajo MIT. Este trabajo de Hefesto Studio se entrega bajo los
términos acordados con el cliente. Ver `LICENCIAS.md`.
