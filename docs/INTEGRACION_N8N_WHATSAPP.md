# Integración con n8n y WhatsApp

Avisos de la DUBSS por WhatsApp (recordatorios de partidos, reprogramaciones, avisos manuales y del agente) y consultas básicas escribiendo al mismo número. n8n es el orquestador de canales; **toda la lógica de negocio sigue en Django**.

## Cómo funciona

```
                     SALIDA (avisos)
 Django ──(1)──► EventoSaliente (cola en la BD, misma transacción)
   ▲                    │ Celery cada minuto y al encolar
   │                    ▼
   │         POST firmado (HMAC) ──► n8n «DUBSS - Avisos a WhatsApp» ──► WhatsApp Cloud API ──► celular
   │
   │                    ENTRADA (consultas)
   └─(firmado)◄── n8n «DUBSS - Consultas por WhatsApp» ◄── WhatsApp Cloud API ◄── la persona escribe
```

* **Un solo punto de entrada:** `apps/notificaciones/services.py::notificar_usuarios()`. Ya lo usan los recordatorios de 24 h y 2 h, la reprogramación manual y la del agente, los avisos manuales, los cambios de estado y las alertas de resultados atípicos. Al agregar WhatsApp como tercer canal ahí, **todos** esos avisos salen también por WhatsApp sin tocar cada módulo.
* **Cola de salida (patrón outbox):** el aviso se guarda en `EventoSaliente` y un worker lo entrega. Si n8n está caído, no se pierde: se reintenta a 1, 5, 15, 60 y 180 minutos; después queda `FALLIDO` (visible en la pantalla de Avisos). Un fallo de WhatsApp **nunca** impide el correo, el push ni la operación original.
* **Garantía:** «al menos una vez». Cada evento lleva su id en `X-DUBSS-Event-Id`.

## Reglas de privacidad y consentimiento

* Solo recibe WhatsApp quien **ingresó su número y marcó que acepta**, desde *Mi perfil → Avisos por WhatsApp*. Un administrador **no** puede dar el consentimiento por otra persona (los campos son de solo lectura en la gestión de usuarios).
* Cambiar de número quita el consentimiento (había sido dado para el anterior). Se guarda la fecha de aceptación.
* Cada número identifica a **una sola cuenta** (restricción única): un mensaje entrante nunca se atribuye a otra persona.
* A n8n solo viaja el **nombre** y el **número** de cada destinatario más el texto del aviso (no el correo, rol ni facultad).
* La persona puede darse de baja escribiendo **BAJA** por WhatsApp (queda en la bitácora de auditoría) o desde su perfil.

## Seguridad

* **Firma HMAC-SHA256** en ambos sentidos con el secreto compartido: se firma `"<marca de tiempo>.<cuerpo exacto>"`. Se rechazan firmas incorrectas y mensajes de más de 5 minutos (evita repetición). Comparación de tiempo constante.
* n8n verifica la firma de los avisos (nodo «Verificar firma») y responde **401** si no es válida. Django verifica la de los mensajes entrantes y responde 401 igual.
* El canal entrante es de **solo lectura**: órdenes fijas `PARTIDOS`, `RESULTADOS`, `AYUDA` y `BAJA`. No usa un modelo de lenguaje ni puede cambiar datos, así que un texto malicioso no puede hacer nada. Límite de 20 mensajes por minuto por número y 4 KB por mensaje.
* Un delegado solo ve **sus** partidos y resultados.
* El secreto y las credenciales de Meta viven en `.env` (ignorado por git), nunca en el código ni en los flujos.

## Puesta en marcha local (modo simulado, sin cuenta de Meta)

1. En `.env` (ya viene generado en esta máquina; en otra, créalo desde `.env.example`):
   ```
   N8N_URL_EVENTOS=http://n8n:5678/webhook/dubss-eventos
   N8N_SECRETO=<64 caracteres aleatorios>          # python -c "import secrets;print(secrets.token_hex(32))"
   N8N_ENCRYPTION_KEY=<64 caracteres aleatorios>
   ```
2. Levanta n8n (es opcional: perfil `n8n`):
   ```
   docker compose -f docker-compose.dev.yml -f docker-compose.rapido.yml --profile n8n up -d n8n
   docker compose -f docker-compose.dev.yml -f docker-compose.rapido.yml up -d --force-recreate backend celery_worker celery_beat
   ```
   Editor de n8n: http://localhost:5678 (la primera vez pide crear una cuenta local). Los flujos de `n8n/workflows/` se importan y activan solos al arrancar.
3. Entra como administrador → **Avisos**: la tarjeta *WhatsApp (n8n)* debe decir **Conectado**. Pulsa *Enviar prueba a n8n*.
4. Sin credenciales de Meta, el flujo está en **modo simulado**: n8n recibe y valida el aviso y lo deja registrado en sus ejecuciones (editor de n8n → *Executions*, rama «Registrar (modo simulado)»), pero no envía nada.

> Los flujos del repositorio son la fuente de verdad: al arrancar, n8n **sobrescribe** los flujos con el contenido de `n8n/workflows/`. Para cambiarlos, edita el JSON (o duplica el flujo en el editor).

## Conectar WhatsApp real (Cloud API de Meta)

1. Crea una app en https://developers.facebook.com (tipo *Business*) y agrega el producto **WhatsApp**. Meta te da un número de prueba y un **Phone number ID**.
2. Genera un **token** (el temporal dura 24 h; para uso continuo crea un *usuario del sistema* con token permanente).
3. En *Configuración de la API* agrega tu número como destinatario de prueba (con el número de prueba de Meta solo se puede escribir a hasta 5 números verificados).
4. **Plantilla:** los avisos que inicia el sistema fuera de una conversación requieren una plantilla aprobada. Crea una de categoría *Utilidad*, idioma *Español*, nombre `dubss_aviso`, cuerpo:
   ```
   DUBSS: {{1}}
   ```
   (Las respuestas a quien escribe primero son texto libre dentro de las 24 h, sin plantilla.)
5. En `.env`:
   ```
   WHATSAPP_TOKEN=...
   WHATSAPP_PHONE_ID=...
   WHATSAPP_PLANTILLA=dubss_aviso
   WHATSAPP_VERIFY_TOKEN=<texto aleatorio que tú inventas>
   ```
   y recrea n8n (`up -d --force-recreate n8n`).
6. **Mensajes entrantes:** Meta necesita una URL pública. Expón n8n con HTTPS (en pruebas: `cloudflared tunnel --url http://localhost:5678` o ngrok; en producción, el dominio de la universidad) y en *WhatsApp → Configuración → Webhook* pon `https://TU-DOMINIO/webhook/whatsapp` con el `WHATSAPP_VERIFY_TOKEN` y suscríbete al campo `messages`.

## Uso

| Quién | Qué hace |
|---|---|
| Cualquier usuario con panel | *Mi perfil → Avisos por WhatsApp*: número + «Acepto». Recibe avisos y puede escribir `PARTIDOS`, `RESULTADOS`, `AYUDA` o `BAJA`. |
| Administrador | *Avisos*: ve el estado de n8n, la cola (en cola / entregados / fallidos), los últimos eventos y puede enviar una prueba. |
| Organizador / Administrador | *Avisos → Nuevo aviso*: el mensaje sale por correo, push y WhatsApp a quienes lo activaron. |

## Pruebas realizadas (evidencia)

* **53 pruebas automáticas** (`backend/apps/integraciones/tests/`): firma, número, consentimiento, cola, reintentos, recuperación de un worker caído, estado, prueba, mensajes entrantes y límites.
* **De punta a punta con n8n real** y un WhatsApp simulado: Django → n8n → mensaje con el formato de la API de Meta; firma incorrecta o ausente → 401; solo recibe quien aceptó; saltos de línea limpiados; consulta entrante `PARTIDOS` respondida; número no registrado → instrucciones; `BAJA` → deja de recibir y queda en bitácora; **con n8n detenido el aviso queda en cola y se entrega al volver**.
* Lo único no probado es el envío a los servidores reales de Meta (requiere tu cuenta y tus credenciales).

## Operación y problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| La tarjeta dice *Sin configurar* | Faltan `N8N_URL_EVENTOS` o `N8N_SECRETO` en `.env`, o no recreaste backend/celery tras cambiarlos. |
| Eventos `FALLIDO` con «Sin conexión con n8n» | n8n no estaba levantado. Levántalo; los nuevos avisos funcionan. Los fallidos no se reintentan solos (se conservan 90 días para investigarlos). |
| n8n responde 401 | El secreto de `.env` (`N8N_SECRETO`) no coincide con el que cargó n8n: recrea n8n tras cambiarlo. |
| Se entregó a n8n pero no llegó el WhatsApp | Mira las ejecuciones en http://localhost:5678. Causas típicas: token vencido (el temporal dura 24 h), plantilla no aprobada, o el número no está en la lista de prueba de Meta. |
| La primera consulta por WhatsApp tarda | El servidor de desarrollo carga todo en la primera petición; n8n espera hasta 30 s y reintenta. |

El panel de administración de Django (`/admin/`) muestra todos los eventos (solo lectura) para auditar.
