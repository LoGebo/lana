# Agente persistente + MCP para Lana

Investigación del 2026-11-23. Marcado: [V] = verificado en doc oficial; [NV] = no verificado / inferido.

## 0. Qué son Hermes y MUS/Muse

- **Hermes Agent** (Nous Research): cliente MCP. Config en `~/.hermes/config.yaml`, clave `mcp_servers`. Soporta stdio (`command/args/env`) y HTTP streamable (`url` + `headers`), SSE legado (`transport: sse`), OAuth (`auth: oauth`), y filtro de herramientas (`tools.include` / `tools.exclude`, globs). [V] https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp
- **MUS/Muse**: no hay certeza. Lo más probable es **Meta Muse** (agente de Meta). Solo hay fuentes de terceros: dicen que no tiene menú MCP pero que se le da la URL de un servidor MCP y construye el cliente (o usa "custom connectors"). [NV] https://parallel.ai/articles/best-mcp-servers-for-meta-muse y https://composio.dev/toolkits/composio/framework/muse.md . Confirma qué es exactamente lo que usa el dueño. Para Muse asume que solo sirve un servidor **HTTPS público** (no stdio, no localhost).
- Consecuencia: el servidor MCP debe ser **HTTP remoto (Streamable HTTP) con bearer token**; funciona con ambos.

## 1. Arquitecturas

Hecho clave: SwiftData vive en el iPhone, que no es un servidor. Ningún agente externo escribe ahí directo; siempre hay un puente.

### (a) Backend "buzón" + MCP encima + la app tira de comandos
- Viabilidad: alta. Latencia: segundos si la app está abierta; minutos u horas si está cerrada (silent push o BGAppRefresh no están garantizados). Esfuerzo: medio.
- Seguridad: el servidor ve los comandos en claro (el agente los necesita). Mitigación: borrar al confirmar (TTL corto), guardar solo agregados para lectura.
- Offline: el agente escribe siempre (se encola); el iPhone aplica al abrir. Lecturas = última foto subida por la app.
- Variantes de backend:
  - **Cloudflare Worker + D1/KV** o **Supabase** (Postgres + RLS): gratis/barato, un solo token. Recomendado.
  - **CloudKit + CKSyncEngine**: sin servidor propio y datos en iCloud del usuario, pero requiere cuenta de pago de Apple Developer [NV], y un agente en un servidor no puede leer CloudKit privado fácilmente (haría falta un helper en Mac o CloudKit Web Services con token de usuario). Más complejo; no lo recomiendo para un dev solo.
  - Servidor propio (VPS): igual que Worker pero con mantenimiento.

### (b) App Intents / Shortcuts desde el agente
- `shortcuts run "Nombre" -i input` existe en macOS [V, CLI conocida]; el Mac dispara un atajo. Pero el atajo debe ejecutar el App Intent de Lana, y esos intents viven en el iPhone. Que un Mac ejecute un intent de una app solo-iOS [NV, probablemente no]: hay que tener la app instalada en el Mac (Apple silicon "Designed for iPhone", o Catalyst) y entonces escribiría en OTRA base de datos.
- Desde el iPhone: automatizaciones personales (hora, NFC, Apple Pay) funcionan, pero un agente remoto no puede dispararlas. Esquema `shortcuts://run-shortcut?name=..` abre la app en el iPhone y pide interacción: no sirve para un agente en un servidor.
- Veredicto: bueno para entrada manual/automática en el teléfono (ya lo usas con Apple Pay), malo como canal del agente. Latencia: inmediata en el teléfono, inexistente desde fuera. Esfuerzo: bajo, utilidad: nula para este fin.

### (c) Servidor MCP dentro de la app iOS
- Técnicamente se puede abrir un socket mientras la app está en primer plano, pero iOS suspende la app en segundo plano en segundos, no hay IP pública (NAT/celular) y habría que exponer un túnel. Inviable para un agente "persistente". Descartado. [V en general: límites de background de iOS; detalle NV]

### (d) Otras
- **Mac siempre encendido como puente**: la app sincroniza por iCloud a una app Mac con el mismo SwiftData/CloudKit y el MCP stdio corre ahí. Funciona solo si tienes app Mac y CloudKit; más piezas que (a). No.
- **Exportar a archivo en iCloud Drive/Google Drive** (la app escribe JSON de resumen; el agente lo lee; el agente deja un archivo de "comandos" que la app ingiere): barato y sin backend propio, pero latencia errática, sin auth fina ni scopes. Aceptable como prototipo, no como diseño final.

## 2. Recomendación: (a) con Cloudflare Worker + D1, "buzón de comandos"

```
Hermes/Muse --HTTPS+Bearer--> MCP server (Worker) --> D1: tabla commands (pending/applied), tabla summaries
iPhone (Lana) <-- GET /commands?status=pending  (al abrir, BGAppRefresh, silent push opcional)
iPhone --> POST /ack {ids}, PUT /summary (solo agregados)
```
La app valida cada comando y lo inserta en SwiftData. El servidor nunca tiene la base completa.

### Herramientas MCP mínimas (todas append-only; ninguna borra ni edita)
Escritura (encolan un comando; devuelven `queued`, no confirmación definitiva):
- `log_expense(amount, currency, category, note?, occurred_at?, idempotency_key)`
- `log_water(ml, occurred_at?, idempotency_key)`
- `log_food(name, kcal?, protein_g?, occurred_at?, idempotency_key)`
- `start_workout(name, idempotency_key)` -> devuelve `workout_id` (UUID generado por el servidor)
- `log_set(workout_id, exercise, reps, weight_kg, idempotency_key)`
- `finish_workout(workout_id, idempotency_key)`
Lectura (solo desde `summaries`, que sube la app):
- `get_today_summary()` : gasto del día, agua, kcal, sesión en curso.
- `get_week_summary(kind: "gym"|"food"|"water"|"spend")`: agregados por día, sin movimientos individuales.
- `get_command_status(idempotency_key)`: pending/applied/rejected.
No existe: delete, update, "list all", exportar, ni lectura de cuentas/saldos. Anotaciones MCP `readOnlyHint`/`destructiveHint:false` en cada herramienta (son solo pistas, no seguridad). [NV: nombres exactos en 2026-07-28; confirma en el SDK]

### Auth y límites
- Token bearer largo y aleatorio (>=32 bytes), guardado como hash en D1; solo en secretos del Worker y `~/.hermes/.env` (`Authorization: Bearer ${LANA_MCP_TOKEN}`). Nada en el repo público.
- Scopes por token: `write:log`, `read:summary`. Tokens separados para el agente y para la app (la app NO usa el del agente). Revocable.
- Rate limit: p. ej. 60 escrituras/hora y tope por comando (monto máx., ml máx.), rechazo si excede.
- Idempotencia: `idempotency_key` UNIQUE en D1; la app guarda IDs aplicados (también UNIQUE en SwiftData) para no duplicar si reintenta.
- Auditoría: cada llamada (herramienta, args, hora, resultado) en tabla `audit`; la app muestra una pantalla "Cambios del agente" y puede rechazar/borrar a mano lo que el agente creó (marca `source = agent` en cada registro).
- OAuth 2.1: solo vale la pena si Muse lo exige; para uso personal, bearer estático basta. [Spec exige OAuth solo para clientes que lo usen; Hermes soporta `auth: oauth` si hace falta.]
- Datos: TTL de 7 días para comandos aplicados; resúmenes sin notas libres.

### Plan de construcción (pequeño)
1. Worker + D1 con tablas `commands`, `summaries`, `audit`, `tokens`; un endpoint REST para la app (`/pending`, `/ack`, `/summary`).
2. MCP en el mismo Worker con las 6+3 herramientas (SDK abajo). Probar con `npx @modelcontextprotocol/inspector`.
3. App: `CommandSyncService` (URLSession) que al pasar a foreground descarga pendientes, valida (esquema, topes), inserta con `source=agent` y hace ack. Token de la app en Keychain.
4. App: subir `summary` tras cambios locales relevantes (agregados diarios).
5. Pantalla de auditoría en la app (lista de registros del agente, borrar a mano).
6. Configurar Hermes (abajo) con `tools.include` explícito y probar `log_water`.
7. Opcional después: silent push o BGAppRefresh para latencia menor.

## 3. MCP a fines de 2026

- Última revisión: **2026-07-28** [V] https://modelcontextprotocol.io/specification/2026-07-28/changelog . Cambios: sin sesiones ni `Mcp-Session-Id`, sin handshake `initialize` (stateless; `server/discover`), cabeceras `Mcp-Method`/`Mcp-Name` obligatorias en POST, tasks pasan a extensión, **HTTP+SSE deprecado**, Roots/Sampling/Logging deprecados, el DCR (RFC 7591) se deprecó a favor de Client ID Metadata Documents, validación del `iss` (RFC 9207). Los servidores nuevos deben ser stateless: encaja con un Worker.
- Transporte: **Streamable HTTP** para remoto; stdio solo si el cliente corre en la misma máquina. Muse/Hermes en la nube -> HTTP.
- Auth: OAuth 2.1 para servidores remotos públicos; bearer estático es válido para uso personal (Hermes lo soporta con `headers`).
- SDK: TypeScript v2 (`@modelcontextprotocol/server`, `createMcpHandler`, por-petición, ideal para Workers) o Python v2 (paquete `mcp`, `FastMCP` renombrado `MCPServer`). Ambos Tier 1 y responden a 2025 y 2026 desde un endpoint. [NV: números exactos de versión; las fuentes se contradicen] https://blog.modelcontextprotocol.io/posts/sdk-betas-2026-07-28/ , https://py.sdk.modelcontextprotocol.io/whats-new/ . Elegiría **TypeScript** (mismo runtime que el Worker). Fija versiones al empezar.
- Hermes, ejemplo [V] (formato de la doc):
```yaml
mcp_servers:
  lana:
    url: "https://lana-mcp.<tu-subdominio>.workers.dev/mcp"
    headers:
      Authorization: "Bearer ${LANA_MCP_TOKEN}"
    timeout: 30
    tools:
      include: [log_expense, log_water, log_food, start_workout, log_set,
                finish_workout, get_today_summary, get_week_summary, get_command_status]
      resources: false
      prompts: false
```
  `/reload-mcp` recarga en sesión. Token en `~/.hermes/.env`.

## 4. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Prompt injection: texto en notas/nombres de alimentos o en web que el agente lee le ordena abusar de herramientas | Las lecturas devuelven solo números y enumeraciones, no texto libre; el agente no tiene herramientas destructivas, así que el peor caso es ruido, no pérdida |
| Herramientas con demasiado permiso | Solo append; sin delete/update; `include` explícito en Hermes; tope por valor y por hora en el servidor (no confiar en el agente) |
| Fuga del token | Scopes mínimos, rotación, revocar en D1, token no reutilizado por la app, sin secretos en el repo (usar `wrangler secret`) |
| Datos falsos o duplicados del agente | `source=agent`, pantalla de auditoría, idempotencia, borrado manual solo en la app |
| Privacidad en el servidor | Comandos se borran tras ack/TTL; resúmenes agregados; HTTPS; sin logs de cuerpo en claro más allá de la auditoría necesaria |
| Exposición de lo leído al proveedor del LLM | Todo lo que el agente lee viaja a su modelo; por eso las lecturas son agregados, no el detalle |
| "Confused deputy" del servidor MCP | Validar cada llamada con esquema estricto (zod), sin ejecutar SQL dinámico |

## Incertidumbres abiertas
- Identidad exacta de MUS/Muse y cómo configura MCP (solo fuentes de terceros).
- Si un Mac puede ejecutar App Intents de una app solo iOS (no verificado; irrelevante para la opción recomendada).
- Versiones exactas de los SDK y nombres de anotaciones de herramientas en 2026-07-28.
- Coste/requisitos actuales de CloudKit (cuenta de pago) y límites de BGAppRefresh en iOS 18: no verificados en esta pasada.
