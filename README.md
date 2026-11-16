# DUBSS — Documentación y aplicación móvil

Repositorio **complementario** del sistema de gestión deportiva de la DUBSS (UAGRM).
El **sistema** (backend, frontend y despliegue) vive en otro repositorio: `DUBSS-GESTION-DEPORTIVA`.

| Carpeta | Contenido |
|---|---|
| `mobile/` | App Android (Capacitor): carga el sistema en un WebView con notificaciones push. Ver `docs/APP_ANDROID.md`. |
| `docs/` | Plan de fases y anexo técnico, guías (n8n/WhatsApp, app Android, sitio corporativo, datos de prueba), experimento de red neuronal, capturas de pantalla y evidencia de pruebas. |

## Generar el APK
```powershell
cd mobile
.\build-apk.ps1 -Url https://TU-DOMINIO -Release
```
Necesita JDK 17 y Android SDK. La llave de firma (`mobile/keystore/`) **no se guarda en Git**: respáldala aparte.

## Por qué está separado
Esta carpeta no se despliega en el servidor: el servidor solo necesita el sistema. Mantenerla aparte deja el repositorio de despliegue liviano y sin documentos ni archivos de la app móvil.
