import { validate, WRITE_TOOLS } from "./validate";

// Subconjunto de D1 que usamos (así los tests pueden usar node:sqlite).
export interface Stmt { bind(...v: unknown[]): Stmt; first<T = any>(): Promise<T | null>; all<T = any>(): Promise<{ results: T[] }>; run(): Promise<unknown>; }
export interface DB { prepare(sql: string): Stmt; }
export interface Env { DB: DB; AGENT_TOKEN: string; APP_TOKEN: string; }

const MAX_BODY = 8 * 1024;
const MAX_POR_HORA = 60;
const READS = ["resumen_mes", "ultimos_entrenos", "macros_hoy"];

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });

// Comparación en tiempo constante.
function igual(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
const quien = (req: Request, env: Env): "agent" | "app" | null => {
  const t = (req.headers.get("authorization") ?? "").replace(/^Bearer /, "");
  return igual(t, env.AGENT_TOKEN) ? "agent" : igual(t, env.APP_TOKEN) ? "app" : null;
};

async function audit(env: Env, actor: string, tool: string, ok: boolean, detail: string) {
  await env.DB.prepare("INSERT INTO audit(ts,actor,tool,ok,detail) VALUES(?,?,?,?,?)").bind(Date.now(), actor, tool, ok ? 1 : 0, detail.slice(0, 200)).run();
}

const TOOLS = [
  ...WRITE_TOOLS.map((name) => ({ name, description: `Encola un registro (${name}); la app lo aplica después. Solo agrega, no edita ni borra. Requiere idempotency_key.`,
    inputSchema: { type: "object", properties: { idempotency_key: { type: "string" } }, required: ["idempotency_key"], additionalProperties: true },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true } })),
  ...READS.map((name) => ({ name, description: `Lectura agregada (${name}); solo números, de la última foto que subió la app.`,
    inputSchema: { type: "object", properties: {}, additionalProperties: false }, annotations: { readOnlyHint: true } })),
];

async function llamar(env: Env, tool: string, args: unknown, now: number) {
  if (READS.includes(tool)) {
    const r = await env.DB.prepare("SELECT json, updated_at FROM summaries WHERE key=?").bind(tool).first<{ json: string; updated_at: number }>();
    await audit(env, "agent", tool, true, "read");
    return r ? { data: JSON.parse(r.json), updated_at: r.updated_at } : { data: null, note: "la app aún no ha subido datos" };
  }
  const v = validate(tool, args, now);
  if (!v.ok) { await audit(env, "agent", tool, false, v.error); throw new Error(v.error); }
  const id = v.args.idempotency_key as string;
  const { idempotency_key: _k, ...resto } = v.args;
  const canon = JSON.stringify({ tool, resto });
  const prev = await env.DB.prepare("SELECT tool, args, status FROM commands WHERE id=?").bind(id).first<{ tool: string; args: string; status: string }>();
  if (prev) {
    if (JSON.stringify({ tool: prev.tool, resto: JSON.parse(prev.args) }) !== canon) {
      await audit(env, "agent", tool, false, "idempotency_key reutilizada con otros datos");
      throw new Error("idempotency_key ya usada con datos distintos");
    }
    return { queued: false, duplicate: true, status: prev.status };
  }
  const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM commands WHERE created_at > ?").bind(now - 3_600_000).first<{ n: number }>();
  if ((n?.n ?? 0) >= MAX_POR_HORA) { await audit(env, "agent", tool, false, "rate limit"); throw new Error("límite de escrituras por hora alcanzado"); }
  await env.DB.prepare("INSERT INTO commands(id,tool,args,created_at) VALUES(?,?,?,?)").bind(id, tool, JSON.stringify(resto), now).run();
  await audit(env, "agent", tool, true, id);
  return { queued: true, status: "pending" };
}

async function mcp(env: Env, body: any, now: number) {
  const id = body?.id ?? null;
  const ok = (result: unknown) => json({ jsonrpc: "2.0", id, result });
  const err = (code: number, message: string) => json({ jsonrpc: "2.0", id, error: { code, message } });
  if (body?.jsonrpc !== "2.0" || typeof body.method !== "string") return err(-32600, "request inválido");
  switch (body.method) {
    case "initialize": return ok({ protocolVersion: "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "lana-mcp", version: "0.1.0" } });
    case "ping": return ok({});
    case "notifications/initialized": return new Response(null, { status: 202 });
    case "tools/list": return ok({ tools: TOOLS });
    case "tools/call": {
      const { name, arguments: a } = body.params ?? {};
      if (!TOOLS.some((t) => t.name === name)) return err(-32602, `herramienta desconocida: ${name}`);
      try { return ok({ content: [{ type: "text", text: JSON.stringify(await llamar(env, name, a, now)) }] }); }
      catch (e) { return ok({ isError: true, content: [{ type: "text", text: (e as Error).message }] }); }
    }
    default: return err(-32601, "método no soportado");
  }
}

export async function handle(req: Request, env: Env, now = Date.now()): Promise<Response> {
  const url = new URL(req.url);
  const actor = quien(req, env);
  if (!actor) return json({ error: "no autorizado" }, 401);
  const len = Number(req.headers.get("content-length") ?? 0);
  if (len > MAX_BODY) return json({ error: "payload demasiado grande" }, 413);
  let body: any = null;
  if (req.method === "POST" || req.method === "PUT") {
    const txt = await req.text();
    if (txt.length > MAX_BODY) return json({ error: "payload demasiado grande" }, 413);
    try { body = JSON.parse(txt); } catch { return json({ error: "JSON inválido" }, 400); }
  }

  if (url.pathname === "/mcp" && req.method === "POST") {
    if (actor !== "agent") return json({ error: "token de la app no sirve aquí" }, 403);
    return mcp(env, body, now);
  }
  if (url.pathname.startsWith("/app/")) {
    if (actor !== "app") return json({ error: "token del agente no sirve aquí" }, 403);
    if (url.pathname === "/app/pending" && req.method === "GET") {
      const r = await env.DB.prepare("SELECT id, tool, args FROM commands WHERE status='pending' ORDER BY created_at LIMIT 50").all<{ id: string; tool: string; args: string }>();
      return json({ commands: r.results.map((c) => ({ id: c.id, tool: c.tool, args: JSON.parse(c.args) })) });
    }
    if (url.pathname === "/app/ack" && req.method === "POST") {
      const items = body?.results;
      if (!Array.isArray(items) || items.length > 100) return json({ error: "results inválido" }, 400);
      for (const it of items) {
        if (typeof it?.id !== "string" || !["applied", "rejected"].includes(it.status)) return json({ error: "resultado inválido" }, 400);
        await env.DB.prepare("UPDATE commands SET status=?, reason=?, done_at=? WHERE id=? AND status='pending'")
          .bind(it.status, typeof it.reason === "string" ? it.reason.slice(0, 120) : null, now, it.id).run();
      }
      return json({ ok: true });
    }
    if (url.pathname === "/app/summary" && req.method === "PUT") {
      // Solo claves conocidas y solo números/arrays/objetos: nada de texto libre del usuario.
      for (const k of READS) if (body?.[k] !== undefined)
        await env.DB.prepare("INSERT INTO summaries(key,json,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET json=excluded.json, updated_at=excluded.updated_at")
          .bind(k, JSON.stringify(body[k]), now).run();
      return json({ ok: true });
    }
  }
  return json({ error: "no encontrado" }, 404);
}

export default { fetch: (req: Request, env: Env) => handle(req, env) };
