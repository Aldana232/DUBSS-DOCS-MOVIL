# Aplicación Android (APK) y notificaciones

## Qué es y por qué así

La app Android es un **contenedor nativo (Capacitor)** que abre el sistema de la DUBSS dentro de un WebView y le agrega lo que un navegador no puede dar: **notificaciones push con la app cerrada**, icono propio, pantalla de inicio, botón «atrás» y bloqueo de navegación fuera del sistema.

* **No se reescribe nada:** es el mismo sistema (Next.js + Django). Cada mejora llega a todos los celulares sin volver a publicar el APK.
* **Por qué no un TWA/Bubblewrap:** un TWA exige un dominio **https** público y verificado desde el primer día; Capacitor funciona hoy, con tu PC en la red local, y mañana con el dominio de la universidad (solo cambia la dirección al compilar).
* El proyecto está en `mobile/`. El APK se genera con `mobile/build-apk.ps1` y queda en `mobile/dist/`.

## Generar el APK

Requisitos (ya instalados en esta máquina): JDK 17 y Android SDK (Android Studio). La primera compilación descarga Gradle y librerías (unos minutos).

```powershell
cd mobile
.\build-apk.ps1                                              # pruebas en el emulador (la PC es 10.0.2.2)
.\build-apk.ps1 -Url http://192.168.1.50:3000                # pruebas con un celular en la misma red Wi-Fi
.\build-apk.ps1 -Url https://sistema.uagrm.edu.bo -Release   # producción: APK firmado
```

La dirección queda fija dentro del APK. Si cambia (otra IP, el dominio definitivo) se vuelve a compilar.

### Instalar
* **Celular:** copia `mobile\dist\dubss-debug.apk` al teléfono (cable, WhatsApp, Drive), ábrelo y acepta «instalar apps de origen desconocido». O con cable USB y *Depuración USB*: `adb install -r mobile\dist\dubss-debug.apk`.
* **Emulador:** arrástralo a la ventana del emulador, o `adb install -r ...`.

### Para que el celular llegue al sistema (pruebas)
1. PC y celular en la **misma red Wi-Fi**.
2. Levanta el sistema en modo rápido (ya deja las cookies de sesión aptas para http): `docker compose -f docker-compose.dev.yml -f docker-compose.rapido.yml up -d`.
3. Averigua la IP de la PC (`ipconfig`, «Dirección IPv4») y compila con `-Url http://ESA-IP:3000`.
4. Si no conecta, es el **firewall de Windows**: permite el puerto 3000 (`New-NetFirewallRule -DisplayName "DUBSS 3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow`, en PowerShell como administrador).

### Versión de producción
`-Release` crea una llave de firma en `mobile\keystore\` y su contraseña en `mobile\keystore.properties` (ambos fuera de Git). **Guárdalas**: sin esa llave no se pueden publicar actualizaciones de la misma app. Para subir a Play Store hace falta una cuenta de desarrollador (pago único de 25 USD) y el dominio https.

## Cómo funciona la app (lógica móvil)

| Situación | Qué pasa |
|---|---|
| Abrir la app | Entra a `/planilla`. Sin sesión, va al login y vuelve a la planilla. Un delegado o jugador (que no puede entrar a la planilla) cae directo en su propio inicio. |
| Sesión | Cookies seguras (httpOnly) que se renuevan solas; sigue iniciada al cerrar y abrir la app. |
| Botón «atrás» | Retrocede dentro del sistema; en la primera pantalla cierra la app. |
| Sin servidor al abrir | Pantalla local «No se pudo conectar» con **Reintentar**; reintenta sola al volver la red. |
| Se corta el internet llenando una planilla | Todo se guarda en el celular y se envía solo al volver (sin duplicar). |
| Enlaces fuera del sistema | No se abren dentro de la app (solo navega por el dominio del sistema). |
| Cerrar sesión | Se invalida la sesión y se **desvincula el celular** de las notificaciones de esa cuenta. |
| Instalar la app | El botón «Instalar» de la planilla se oculta dentro de la app (ya está instalada). |

## Notificaciones: qué hay y cómo se garantiza

Un aviso pasa por un único punto (`notificar_usuarios`) y sale por **cuatro canales** independientes. Si uno falla, los demás no se afectan.

| Canal | Quién lo recibe | Necesita |
|---|---|---|
| **Campana dentro de la app** | **Todos** los destinatarios, siempre | Nada. Es el canal que no falla: queda guardado y se puede releer. |
| **Correo** | Todos con correo | Servidor de correo (variables `EMAIL_*`) |
| **Push (app Android)** | Quien tenga la app y no sea rol Jugador | Firebase (ver abajo) |
| **WhatsApp** | Quien lo activó y aceptó, desde su perfil | n8n y Meta (ver `INTEGRACION_N8N_WHATSAPP.md`) |

### La campana
* Insignia con la cantidad **sin leer**; se actualiza cada 30 s **solo mientras la pantalla está visible** y al volver a la app (no gasta batería ni datos en segundo plano).
* Al llegar una nueva aparece un aviso emergente. Tocar una notificación la marca como leída y abre el partido (`/partidos/<id>`).
* Pantalla completa en **Notificaciones** (filtro «Sin leer», paginada, «Marcar todas como leídas»). Funciona para todos los roles, incluido Jugador.
* Cada persona ve solo **las suyas**; intentar leer la de otra da 404. Se limpian solas: las leídas a los 30 días, todas a los 90.

### Push (con la app cerrada)
El servidor ya enviaba a Firebase (FCM v1), pero **faltaba el lado del celular** (nadie registraba el token), por eso nunca llegó un push real. Ahora la app Android pide permiso, obtiene el token y lo registra; al tocar el aviso abre la pantalla correcta. Reglas:
* **Un celular pertenece a una sola cuenta:** si otra persona inicia sesión en el mismo celular, el token se retira de la anterior (antes los avisos de una persona podían llegar al celular de otra). Al cerrar sesión también se retira.
* Un token muerto (app desinstalada) se limpia solo.
* Sin Firebase configurado, la app funciona igual: avisos en la campana (y por correo o WhatsApp si los activaron). Solo falta el push con la app cerrada.
* **Importante (error real encontrado en las pruebas):** pedir el token sin Firebase *cierra la app* con una excepción nativa que JavaScript no puede capturar. Por eso `build-apk.ps1` solo marca el APK como «listo para push» (`DUBSSPush` en su user-agent) si existe `google-services.json`, y el sistema no intenta registrar el celular si esa marca no está.

**Activar el push (una vez, requiere tu cuenta de Google gratuita):**
1. https://console.firebase.google.com → crear proyecto → *Agregar app Android* con el nombre de paquete **`bo.edu.uagrm.dubss`**.
2. Descarga `google-services.json` y cópialo a `mobile/android/app/` (está en `.gitignore`).
3. En *Configuración del proyecto → Cuentas de servicio* genera una **clave privada** (JSON), cópiala a `backend/secrets/firebase.json` y en `.env` pon `FCM_CREDENTIALS_FILE=/app/secrets/firebase.json`. Recrea backend y celery.
4. Recompila el APK (`build-apk.ps1`). El resto es automático.

## Requisitos del celular
* Android 5.1 o superior (la app se instala desde ahí).
* **Android System WebView / Chrome al día.** La app funciona incluso con el WebView de fábrica de Android 11 (Chrome 83, probado), pero conviene actualizarlo desde Play Store: los celulares con Play Store lo hacen solos. Para soportar los viejos, el sistema transpila la librería de datos (usa métodos privados de clase) y repite en CSS la propiedad `inset`.

## Pruebas realizadas
Ver la sección 17 de `ANEXO_PLAN_FASES.md`.
