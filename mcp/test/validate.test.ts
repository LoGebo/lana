import { describe, expect, it } from "vitest";
import { validate } from "../src/validate";

const NOW = Date.parse("2026-11-23T12:00:00Z");
const k = { idempotency_key: "abcdefgh1234" };
const bad = (tool: string, a: object, re: RegExp) => { const r = validate(tool, { ...k, ...a }, NOW); expect(r.ok).toBe(false); expect((r as any).error).toMatch(re); };

describe("validate", () => {
  it("acepta gasto válido y limpia texto", () => {
    const r = validate("log_expense", { ...k, amount: 120.5, note: "  tacos\n al pastor " }, NOW) as any;
    expect(r.ok).toBe(true); expect(r.args.note).toBe("tacos al pastor");
  });
  it("monto: negativo, cero, NaN, Infinity, string, tope", () => {
    for (const amount of [-5, 0, NaN, Infinity, "10", 50_001]) bad("log_expense", { amount }, /amount/);
  });
  it("idempotency_key obligatoria y con formato", () => {
    expect(validate("log_water", { ml: 250 }, NOW).ok).toBe(false);
    expect(validate("log_water", { ml: 250, idempotency_key: "corta" }, NOW).ok).toBe(false);
    expect(validate("log_water", { ml: 250, idempotency_key: "con espacios y ; drop" }, NOW).ok).toBe(false);
  });
  it("campos extra rechazados", () => bad("log_water", { ml: 250, sql: "x" }, /no permitido/));
  it("rangos de agua, series, peso y comida", () => {
    bad("log_water", { ml: 0 }, /ml/); bad("log_water", { ml: 5000 }, /ml/);
    bad("log_workout_set", { exercise: "Press", reps: 0, weight_kg: 50 }, /reps/);
    bad("log_workout_set", { exercise: "Press", reps: 8.5, weight_kg: 50 }, /entero/);
    bad("log_workout_set", { exercise: "Press", reps: 8, weight_kg: 900 }, /weight_kg/);
    bad("log_workout_set", { exercise: "Press", reps: 8, weight_kg: 50, set_type: "x" }, /set_type/);
    bad("log_meal", { name: "x", kcal: -1 }, /kcal/); bad("log_weight", { kg: 5 }, /kg/);
  });
  it("fechas: futura >1 día, muy antigua, inválida", () => {
    bad("log_water", { ml: 250, occurred_at: "2026-11-30T00:00:00Z" }, /futuro/);
    bad("log_water", { ml: 250, occurred_at: "2020-01-01T00:00:00Z" }, /antigua/);
    bad("log_water", { ml: 250, occurred_at: "ayer" }, /fecha/);
    expect(validate("log_water", { ...k, ml: 250, occurred_at: "2026-11-24T00:00:00Z" }, NOW).ok).toBe(true);
  });
  it("texto demasiado largo y herramienta desconocida / entrada no objeto", () => {
    bad("log_meal", { name: "a".repeat(81), kcal: 100 }, /largo/);
    expect(validate("delete_everything", k, NOW).ok).toBe(false);
    expect(validate("log_water", null, NOW).ok).toBe(false);
    expect(validate("log_water", [1], NOW).ok).toBe(false);
  });
});
