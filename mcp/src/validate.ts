// Validación estricta de cada herramienta de escritura. Pura: sin I/O.
export type Args = Record<string, unknown>;
type Res = { ok: true; args: Args } | { ok: false; error: string };

const DIA = 86_400_000;
const KEY = /^[A-Za-z0-9_-]{8,64}$/;
const MEALS = ["desayuno", "comida", "snack", "cena"];
const SET_TYPES = ["normal", "calentamiento", "drop", "fallo"];

type Campo =
  | { t: "num"; min: number; max: number; int?: boolean; req?: boolean; minExcl?: boolean }
  | { t: "str"; max: number; req?: boolean }
  | { t: "enum"; vals: string[]; req?: boolean }
  | { t: "date" };

const ESQUEMAS: Record<string, Record<string, Campo>> = {
  log_expense: {
    amount: { t: "num", min: 0, max: 50_000, minExcl: true, req: true },
    category: { t: "str", max: 40 }, merchant: { t: "str", max: 60 }, note: { t: "str", max: 120 }, occurred_at: { t: "date" },
  },
  log_water: { ml: { t: "num", min: 1, max: 2000, req: true }, occurred_at: { t: "date" } },
  log_meal: {
    name: { t: "str", max: 80, req: true }, kcal: { t: "num", min: 0, max: 5000, req: true },
    protein_g: { t: "num", min: 0, max: 500 }, carbs_g: { t: "num", min: 0, max: 1000 }, fat_g: { t: "num", min: 0, max: 500 },
    meal: { t: "enum", vals: MEALS }, occurred_at: { t: "date" },
  },
  log_workout_set: {
    exercise: { t: "str", max: 60, req: true }, reps: { t: "num", min: 1, max: 100, int: true, req: true },
    weight_kg: { t: "num", min: 0, max: 500, req: true }, set_type: { t: "enum", vals: SET_TYPES },
    workout_name: { t: "str", max: 60 }, occurred_at: { t: "date" },
  },
  log_weight: { kg: { t: "num", min: 30, max: 300, req: true }, occurred_at: { t: "date" } },
};
export const WRITE_TOOLS = Object.keys(ESQUEMAS);

// Quita caracteres de control y espacios sobrantes (el texto libre llega al LLM y a la app).
export const limpia = (s: string) => s.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();

export function validate(tool: string, input: unknown, now = Date.now()): Res {
  const esq = ESQUEMAS[tool];
  if (!esq) return { ok: false, error: `herramienta desconocida: ${tool}` };
  if (typeof input !== "object" || input === null || Array.isArray(input)) return { ok: false, error: "argumentos deben ser un objeto" };
  const inp = input as Args;
  const key = inp.idempotency_key;
  if (typeof key !== "string" || !KEY.test(key)) return { ok: false, error: "idempotency_key requerido (8-64 chars A-Za-z0-9_-)" };
  for (const k of Object.keys(inp)) if (k !== "idempotency_key" && !(k in esq)) return { ok: false, error: `campo no permitido: ${k}` };
  const out: Args = { idempotency_key: key };
  for (const [k, c] of Object.entries(esq)) {
    const v = inp[k];
    if (v === undefined || v === null) {
      if ("req" in c && c.req) return { ok: false, error: `falta ${k}` };
      continue;
    }
    if (c.t === "num") {
      if (typeof v !== "number" || !Number.isFinite(v)) return { ok: false, error: `${k} debe ser número finito` };
      if (c.int && !Number.isInteger(v)) return { ok: false, error: `${k} debe ser entero` };
      if (v > c.max || v < c.min || (c.minExcl && v <= c.min)) return { ok: false, error: `${k} fuera de rango` };
      out[k] = v;
    } else if (c.t === "str") {
      if (typeof v !== "string") return { ok: false, error: `${k} debe ser texto` };
      const s = limpia(v);
      if (s.length > c.max) return { ok: false, error: `${k} demasiado largo (máx ${c.max})` };
      if (s === "" && c.req) return { ok: false, error: `falta ${k}` };
      if (s !== "") out[k] = s;
    } else if (c.t === "enum") {
      if (typeof v !== "string" || !c.vals.includes(v)) return { ok: false, error: `${k} inválido (${c.vals.join("|")})` };
      out[k] = v;
    } else {
      const t = typeof v === "string" ? Date.parse(v) : NaN;
      if (Number.isNaN(t)) return { ok: false, error: `${k} no es fecha ISO válida` };
      if (t > now + DIA) return { ok: false, error: `${k} está en el futuro` };
      if (t < now - 366 * DIA) return { ok: false, error: `${k} demasiado antigua` };
      out[k] = new Date(t).toISOString();
    }
  }
  return { ok: true, args: out };
}
