# Lana MCP (buzón de comandos)

Worker de Cloudflare + D1. El agente (Hermes, etc.) habla MCP por `POST /mcp` con el token del agente; la app baja los comandos con el token de la app. Ver `docs/mcp-agente.md`.

- Herramientas de escritura (solo agregan; todas exigen `idempotency_key`): `log_expense`, `log_water`, `log_meal`, `log_workout_set`, `log_weight`.
- Lecturas (solo números, de lo que sube la app con `PUT /app/summary`): `resumen_mes`, `ultimos_entrenos`, `macros_hoy`.
- App: `GET /app/pending`, `POST /app/ack`, `PUT /app/summary`. Tokens distintos e intercambiables no.
- Límites: 60 escrituras/hora, body ≤ 8 KB, fechas no más de 1 día en el futuro ni de más de 366 días atrás, monto ≤ 50 000.

## Pruebas
`npm install && npm test` (Node ≥ 22: usa `node:sqlite` como D1 falso).

## Desplegar (a mano; nada de esto está hecho)
```
cd mcp
npx wrangler login
npx wrangler d1 create lana-mcp          # copia database_id a wrangler.toml
npx wrangler d1 execute lana-mcp --remote --file=schema.sql
openssl rand -hex 32 | npx wrangler secret put AGENT_TOKEN
openssl rand -hex 32 | npx wrangler secret put APP_TOKEN   # otro distinto; guárdalos en tu gestor de contraseñas
npx wrangler deploy
```
App: Ajustes → Agente (MCP): URL del Worker (https), token de la app y activar. Agente: `url: https://<worker>/mcp`, `Authorization: Bearer $AGENT_TOKEN`, `tools.include` explícito.

## Falta
- La app aún no sube resúmenes (`PUT /app/summary`), así que las lecturas devuelven `data: null`.
- Sincroniza al abrir la app / volver a primer plano; sin push ni BGAppRefresh.
- Limpieza de comandos viejos (TTL) en D1.
- No probado contra Cloudflare real ni con el Inspector de MCP.
