import { beforeEach, describe, expect, it } from "vitest";
import { handle, type Env } from "../src/index";
import { memDB } from "./db";

let env: Env;
const NOW = Date.parse("2026-11-23T12:00:00Z");
const call = (tok: string | null, path: string, method = "GET", body?: unknown, raw?: string) =>
  handle(new Request("https://x" + path, { method, headers: tok ? { authorization: "Bearer " + tok } : {}, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)) }), env, NOW);
const tool = (name: string, args: object) => call("agent-tok", "/mcp", "POST", { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }).then((r) => r.json() as any);
const water = (key: string, ml = 250) => tool("log_water", { idempotency_key: key, ml });

beforeEach(() => { env = { DB: memDB(), AGENT_TOKEN: "agent-tok", APP_TOKEN: "app-tok" }; });

describe("auth", () => {
  it("sin token o token malo → 401", async () => {
    expect((await call(null, "/mcp", "POST", {})).status).toBe(401);
    expect((await call("mal", "/app/pending")).status).toBe(401);
  });
  it("tokens no son intercambiables", async () => {
    expect((await call("app-tok", "/mcp", "POST", {})).status).toBe(403);
    expect((await call("agent-tok", "/app/pending")).status).toBe(403);
  });
});

describe("mcp", () => {
  it("tools/list: solo append y lecturas; sin borrar/editar", async () => {
    const r = await call("agent-tok", "/mcp", "POST", { jsonrpc: "2.0", id: 1, method: "tools/list" }).then((x) => x.json() as any);
    const names = r.result.tools.map((t: any) => t.name);
    expect(names).toEqual(expect.arrayContaining(["log_expense", "log_water", "log_meal", "log_workout_set", "log_weight", "resumen_mes", "ultimos_entrenos", "macros_hoy"]));
    expect(names.some((n: string) => /delete|update|edit|remove/.test(n))).toBe(false);
  });
  it("escritura válida se encola; duplicado idéntico no duplica", async () => {
    const a = await water("key-0000001"); expect(JSON.parse(a.result.content[0].text)).toMatchObject({ queued: true });
    const b = await water("key-0000001"); expect(JSON.parse(b.result.content[0].text)).toMatchObject({ queued: false, duplicate: true });
    const p = await call("app-tok", "/app/pending").then((x) => x.json() as any);
    expect(p.commands).toHaveLength(1);
  });
  it("misma key con datos distintos → error", async () => {
    await water("key-0000002", 250);
    expect((await water("key-0000002", 500)).result.isError).toBe(true);
  });
  it("datos inválidos → isError y nada encolado", async () => {
    expect((await tool("log_expense", { idempotency_key: "key-0000003", amount: -1 })).result.isError).toBe(true);
    expect((await call("app-tok", "/app/pending").then((x) => x.json() as any)).commands).toHaveLength(0);
  });
  it("herramienta inexistente / método raro / JSON inválido", async () => {
    expect((await tool("drop_tables", {})).error.code).toBe(-32602);
    expect((await call("agent-tok", "/mcp", "POST", { jsonrpc: "2.0", id: 1, method: "resources/read" }).then((x) => x.json() as any)).error.code).toBe(-32601);
    expect((await call("agent-tok", "/mcp", "POST", undefined, "{no json")).status).toBe(400);
  });
  it("payload gigante → 413", async () => {
    expect((await call("agent-tok", "/mcp", "POST", undefined, JSON.stringify({ x: "a".repeat(9000) }))).status).toBe(413);
  });
  it("rate limit: la escritura 61 en una hora se rechaza", async () => {
    for (let i = 0; i < 60; i++) await water(`key-rl-${String(i).padStart(4, "0")}`);
    const r = await water("key-rl-9999");
    expect(r.result.isError).toBe(true); expect(r.result.content[0].text).toMatch(/límite/);
  });
  it("audit registra éxitos y rechazos", async () => {
    await water("key-0000004"); await tool("log_water", { idempotency_key: "key-0000005", ml: -3 });
    const a = await env.DB.prepare("SELECT ok FROM audit ORDER BY id").all<{ ok: number }>();
    expect(a.results.map((x) => x.ok)).toEqual([1, 0]);
  });
});

describe("app", () => {
  it("pending → ack applied/rejected; ya no sale en pending", async () => {
    await water("key-0000006"); await water("key-0000007");
    const ack = await call("app-tok", "/app/ack", "POST", { results: [{ id: "key-0000006", status: "applied" }, { id: "key-0000007", status: "rejected", reason: "x" }] });
    expect(ack.status).toBe(200);
    expect((await call("app-tok", "/app/pending").then((x) => x.json() as any)).commands).toHaveLength(0);
    const dup = await water("key-0000006"); expect(JSON.parse(dup.result.content[0].text).status).toBe("applied");
  });
  it("ack inválido → 400", async () => {
    expect((await call("app-tok", "/app/ack", "POST", { results: [{ id: 1, status: "applied" }] })).status).toBe(400);
    expect((await call("app-tok", "/app/ack", "POST", { results: [{ id: "a", status: "hack" }] })).status).toBe(400);
  });
  it("summary → lectura del agente", async () => {
    expect(JSON.parse((await tool("macros_hoy", {})).result.content[0].text).data).toBeNull();
    await call("app-tok", "/app/summary", "PUT", { macros_hoy: { kcal: 2000, proteina: 150 }, otra: 1 });
    expect(JSON.parse((await tool("macros_hoy", {})).result.content[0].text).data).toEqual({ kcal: 2000, proteina: 150 });
  });
});
