import Foundation

/// Valor de un argumento (lo que cabe en un JSON/plist de WatchConnectivity).
enum ArgWatch: Codable, Equatable {
    case num(Double), txt(String)
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .num(n) } else { self = .txt(try c.decode(String.self)) }
    }
    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); switch self { case .num(let n): try c.encode(n); case .txt(let t): try c.encode(t) } }
    var any: Any { switch self { case .num(let n): n as NSNumber; case .txt(let t): t } }
}

/// Comando del reloj hacia el iPhone. Mismo vocabulario (`tool`/`args`) que el agente MCP para reusar el aplicador idempotente.
struct ComandoWatch: Codable, Equatable, Identifiable {
    var id: String
    var tool: String
    var args: [String: ArgWatch]

    var argsAny: [String: Any] { args.mapValues(\.any) }

    private static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    private static func base(_ tool: String, _ args: [String: ArgWatch], _ ahora: Date, _ id: String) -> ComandoWatch {
        var a = args; a["source"] = .txt("watch"); a["occurred_at"] = .txt(iso(ahora))
        return ComandoWatch(id: id, tool: tool, args: a)
    }
    static func agua(ml: Double, ahora: Date = Date(), id: String = UUID().uuidString) -> ComandoWatch { base("log_water", ["ml": .num(ml)], ahora, id) }
    static func gasto(monto: Double, categoria: String?, ahora: Date = Date(), id: String = UUID().uuidString) -> ComandoWatch {
        var a: [String: ArgWatch] = ["amount": .num(monto), "merchant": .txt("Apple Watch")]
        if let c = categoria { a["category"] = .txt(c) }
        return base("log_expense", a, ahora, id)
    }
    static func serie(ejercicio: String, rutina: String, kg: Double, reps: Int, ahora: Date = Date(), id: String = UUID().uuidString) -> ComandoWatch {
        base("log_workout_set", ["exercise": .txt(ejercicio), "workout_name": .txt(rutina), "weight_kg": .num(kg), "reps": .num(Double(reps))], ahora, id)
    }
    static func peso(kg: Double, ahora: Date = Date(), id: String = UUID().uuidString) -> ComandoWatch { base("log_weight", ["kg": .num(kg)], ahora, id) }

    /// Validación previa en el reloj (el iPhone vuelve a validar todo). nil = válido.
    func validar() -> String? {
        func n(_ k: String) -> Double? { if case .num(let v)? = args[k], v.isFinite { return v }; return nil }
        switch tool {
        case "log_water": guard let v = n("ml"), (1...2000).contains(v) else { return "ml inválido" }
        case "log_expense": guard let v = n("amount"), v > 0, v <= 50_000 else { return "monto inválido" }
        case "log_workout_set":
            guard case .txt(let e)? = args["exercise"], !e.isEmpty, let r = n("reps"), (1...100).contains(r), r == r.rounded(),
                  let kg = n("weight_kg"), (0...500).contains(kg) else { return "serie inválida" }
        case "log_weight": guard let v = n("kg"), (30.0...250.0).contains(v) else { return "peso inválido" }
        default: return "comando desconocido"
        }
        return nil
    }
}

/// Cola persistente de comandos aún no confirmados por el iPhone. Reenviar es seguro: el iPhone deduplica por id.
struct ColaWatch {
    static let tope = 1000
    private let defaults: UserDefaults, llave: String
    init(defaults: UserDefaults = .standard, llave: String = "watch.cola") { self.defaults = defaults; self.llave = llave }

    var pendientes: [ComandoWatch] {
        defaults.data(forKey: llave).flatMap { try? JSONDecoder().decode([ComandoWatch].self, from: $0) } ?? []
    }
    private func guardar(_ c: [ComandoWatch]) { defaults.set(try? JSONEncoder().encode(c), forKey: llave) }

    /// false si es inválido o la cola está llena (no se pierde nada en silencio: quien llama avisa).
    @discardableResult
    func encolar(_ c: ComandoWatch) -> Bool {
        guard c.validar() == nil else { return false }
        var p = pendientes
        if p.contains(where: { $0.id == c.id }) { return true }
        guard p.count < Self.tope else { return false }
        p.append(c); guardar(p); return true
    }
    func confirmar(_ ids: some Sequence<String>) {
        let s = Set(ids); guard !s.isEmpty else { return }
        guardar(pendientes.filter { !s.contains($0.id) })
    }
}

struct EjercicioWatch: Codable, Equatable { var nombre: String; var series: Int; var reps: String; var descanso: Int; var kgPrevio: Double }

/// Resumen del día que el iPhone manda al reloj (applicationContext).
struct ResumenWatch: Codable, Equatable {
    var dia = Date()
    var kcal = 0.0, kcalMeta = 0.0, proteina = 0.0, proteinaMeta = 0.0
    var aguaMl = 0.0, aguaMeta = 3000.0
    var rutina: String?
    var ejercicios: [EjercicioWatch] = []
    var categorias: [String] = []
    var pesoKg: Double?
    /// Ids de comandos ya aplicados en el iPhone (para limpiar la cola del reloj).
    var aplicados: [String] = []
}

enum Sueno {
    /// Horas dormidas uniendo intervalos traslapados (iPhone + Watch miden lo mismo).
    static func horas(_ intervalos: [(Date, Date)]) -> Double {
        var u: [(Date, Date)] = []
        for i in intervalos.filter({ $0.1 > $0.0 }).sorted(by: { $0.0 < $1.0 }) {
            if let l = u.last, i.0 <= l.1 { u[u.count - 1].1 = max(l.1, i.1) } else { u.append(i) }
        }
        return u.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) } / 3600
    }
}
