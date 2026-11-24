import SwiftUI
import SwiftData

extension Programa {
    static let llave = "protocolos.programa.semana"
    static let llaveInicio = "protocolos.programa.inicio"

    /// Semana que toca según la fecha de inicio (1...12); nil si el programa no se ha iniciado.
    static func semanaPorFecha(_ hoy: Date = Date()) -> Int? {
        let t = UserDefaults.standard.double(forKey: llaveInicio)
        guard t > 0 else { return nil }
        let dias = Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: t), to: Calendar.current.startOfDay(for: hoy)).day ?? 0
        return min(max(dias / 7 + 1, 1), 12)
    }
    /// 0 = programa no iniciado.
    static var semana: Int { UserDefaults.standard.integer(forKey: llave) }

    /// Nombre de la rutina que toca en `fecha` (programa de 5 días si está activo; si no, torso/pierna L-M-J-V).
    static func rutinaDe(_ fecha: Date) -> String? {
        let d = Calendar.current.component(.weekday, from: fecha)
        if semana > 0 { return [2: "Upper", 3: "Lower", 5: "Pull", 6: "Push", 7: "Legs"][d].map { "BTS \($0)" } }
        return [2: "Torso A", 3: "Pierna A", 5: "Torso B", 6: "Pierna B"][d]
    }

    /// Día de la semana (Calendar weekday) en que toca cada rutina del programa; nil si no es del programa.
    static func diaDe(_ rutina: String) -> String? {
        ["BTS Upper": "Lun", "BTS Lower": "Mar", "BTS Pull": "Jue", "BTS Push": "Vie", "BTS Legs": "Sáb"][rutina]
            ?? (rutina.hasPrefix("BTS Brazos") ? "Extra" : nil)
    }

    static func fase(de semana: Int) -> ProgFase? { fases.first { $0.desde <= semana && semana <= $0.hasta } }

    static func calentamiento(_ n: String) -> String {
        switch n.last.map(String.init) ?? "" {
        case "1": "1 serie al ~60% del peso de trabajo, 6-10 reps"
        case "2": "2 series: ~50% × 6-10 y ~70% × 4-6"
        case "3": "3 series: ~45% × 6-10, ~65% × 4-6, ~85% × 3-4"
        default: "4 series: ~45% × 6-10, ~60% × 4-6, ~75% × 3-5, ~85% × 2-4"
        }
    }

    /// Pirámide de calentamiento del programa (% del peso de trabajo, reps objetivo), según cuántas series pide la tabla.
    private static let piramides: [Int: [(pct: Double, reps: Int)]] = [
        1: [(0.60, 8)],
        2: [(0.50, 8), (0.70, 5)],
        3: [(0.45, 8), (0.65, 5), (0.85, 3)],
        4: [(0.45, 8), (0.60, 5), (0.75, 4), (0.85, 3)]]

    /// `rango` viene de la tabla ("2-3" → 3 series, el máximo). Pesos redondeados a 2.5 kg; sin peso de trabajo previo quedan en 0.
    static func seriesDeCalentamiento(_ rango: String?, pesoTrabajo: Double) -> [(peso: Double, reps: Int)] {
        guard let n = rango?.compactMap({ $0.wholeNumberValue }).max(), let p = piramides[min(n, 4)] else { return [] }
        return p.map { (pesoTrabajo > 0 ? max((pesoTrabajo * $0.pct / 2.5).rounded() * 2.5, 0) : 0, $0.reps) }
    }

    static func grupo(de n: String) -> String {
        let t = n.lowercased()
        let tabla: [(String, [String])] = [
            ("Pantorrilla", ["calf"]), ("Core", ["crunch", "rollout", "plank", "candlestick", "leg raise"]),
            ("Tríceps", ["tricep", "skull", "katana", "dip"]),
            ("Isquios", ["leg curl", "ham", "rdl", "hyperext", "pull-through", "nordic"]), ("Bíceps", ["curl"]),
            ("Piernas", ["squat", "lunge", "leg press", "leg extension", "hip ", "step-up", "sissy", "nordic", "band walk", "copenhagen"]),
            ("Hombro", ["lateral", "shoulder", "rear delt", "face pull", "pec deck"]),
            ("Espalda", ["row", "pull", "shrug", "pulldown", "lat "]),
            ("Pecho", ["press", "flye", "crossover", "bench"])]
        if t.contains("reverse pec") { return "Hombro" }
        if t.contains("pec deck") { return "Pecho" }
        return tabla.first { $0.1.contains { t.contains($0) } }?.0 ?? "Otro"
    }

    static func rir(desdeRPE rpe: String) -> String {
        let nums = rpe.split { !$0.isNumber }.compactMap { Int($0) }
        guard let lo = nums.min(), let hi = nums.max() else { return "0" }
        return lo == hi ? "\(10 - lo)" : "\(10 - hi)-\(10 - lo)"
    }

    static let brazos: [(String, Int, String)] = [
        ("Bayesian Cable Curl", 3, "10-12"), ("Overhead Cable Triceps Extension (Bar)", 3, "10-12"),
        ("Cable Rope Hammer Curl", 2, "12-15"), ("Triceps Pressdown (Bar)", 2, "15-20"),
        ("High-Cable Lateral Raise", 3, "12-15"), ("1-Arm 45° Cable Rear Delt Flye", 2, "12-15"),
        ("Standing Calf Raise", 3, "12-15")]

    /// Reescribe las rutinas "BTS …" con la fase de esa semana y crea los ejercicios que falten.
    @MainActor static func aplicar(semana: Int, fijarInicio: Bool = true, _ contexto: ModelContext) {
        guard let fase = fase(de: semana) else { return }
        if fijarInicio {
            let inicio = Calendar.current.date(byAdding: .day, value: -(semana - 1) * 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
            UserDefaults.standard.set(inicio.timeIntervalSince1970, forKey: llaveInicio)
        }
        UserDefaults.standard.set(semana, forKey: llave)
        UserDefaults.standard.set(semana, forKey: llave + ".aplicada")
        var defs = Set(((try? contexto.fetch(FetchDescriptor<EjercicioDef>())) ?? []).map(\.nombre))
        let rutinas = (try? contexto.fetch(FetchDescriptor<Rutina>())) ?? []
        func poner(_ nombre: String, _ orden: Int, _ items: [(String, ItemPlan)]) {
            for (n, p) in items where !defs.contains(n) { contexto.insert(EjercicioDef(nombre: n, grupo: p.grupo)); defs.insert(n) }
            let r = rutinas.first { $0.nombre == nombre } ?? { let r = Rutina(nombre: nombre, ejercicios: [], orden: orden); contexto.insert(r); return r }()
            r.ejercicios = items.map(\.0)
            r.plan = Dictionary(items.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        }
        for (i, (dia, ejs)) in fase.dias.enumerated() {
            poner("BTS \(dia)", 10 + i, ejs.map { x in
                (x.n, ItemPlan(series: x.s, reps: x.r, rir: rir(desdeRPE: x.l), descanso: x.d, grupo: grupo(de: x.n),
                               rpe: "\(x.e) → \(x.l)", tecnica: x.t, calentamiento: x.w))
            })
        }
        poner("BTS Brazos + puntos débiles (extra)", 20, brazos.map { n, s, r in
            (n, ItemPlan(series: s, reps: r, rir: "0", descanso: 90, grupo: grupo(de: n),
                         rpe: "~8-9 → 10", tecnica: "al fallo", calentamiento: "1"))
        })
        // Es la única rutina: quito las de la versión anterior si nunca las editaste.
        for viejo in Biblioteca.rutinasCiencia {
            if let r = rutinas.first(where: { $0.nombre == viejo.nombre }), r.ejercicios == viejo.items.map(\.0) { contexto.delete(r) }
        }
        try? contexto.save()
    }

    /// Si la semana guardada cambió o las rutinas no existen, las regenera.
    @MainActor static func sincronizar(_ contexto: ModelContext) {
        // Listo de fábrica: si nunca lo iniciaste, arranca en la semana 1 (se cambia con el selector).
        if semana == 0 && UserDefaults.standard.double(forKey: llaveInicio) == 0 && !UserDefaults.standard.bool(forKey: llave + ".sin") { aplicar(semana: 1, contexto); return }
        guard let s = semanaPorFecha() ?? (semana > 0 ? semana : nil),
              UserDefaults.standard.integer(forKey: llave + ".aplicada") != s else { return }
        aplicar(semana: s, fijarInicio: false, contexto)
    }
}

struct TarjetaPrograma: View {
    @Environment(\.modelContext) private var contexto
    @AppStorage(Programa.llave) private var semana = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Programa Nippard · Bodybuilding Transformation System").font(.headline)
            if semana == 0 {
                Text("12 semanas, 5 días (Upper, Lower, Pull, Push, Legs) con RPE, video y alternativas por ejercicio.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Empezar semana 1") { UserDefaults.standard.set(false, forKey: Programa.llave + ".sin"); Programa.aplicar(semana: 1, contexto) }
                    .buttonStyle(.borderedProminent).tint(.green)
            } else {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Semana \(semana) de 12").font(.title3.weight(.bold))
                        Text(Programa.fase(de: semana)?.titulo ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper("Semana", value: Binding(get: { semana }, set: { Programa.aplicar(semana: $0, contexto) }), in: 1...12)
                        .labelsHidden()
                }
                Button("Terminar programa y usar rutinas propias", role: .destructive) {
                    UserDefaults.standard.set(true, forKey: Programa.llave + ".sin")
                    UserDefaults.standard.set(0, forKey: Programa.llave)
                    UserDefaults.standard.set(0.0, forKey: Programa.llaveInicio)
                }.font(.caption)
                Text("Lun Upper · Mar Lower · Jue Pull · Vie Push · Sáb Legs. Última serie al fallo desde la semana 2. El día de brazos es un extra opcional mío (no es de Nippard).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct InfoEjercicioView: View {
    @Environment(\.dismiss) private var cerrar
    @Bindable var ejercicio: EjercicioLog

    var body: some View {
        NavigationStack {
            List {
                if let i = Programa.catalogo[ejercicio.nombre] {
                    Section {
                        if let u = URL(string: i.url) { Link(destination: u) { Label("Ver video de demostración", systemImage: "play.rectangle.fill") } }
                        if !i.nota.isEmpty { Text(i.nota) }
                        if !ejercicio.nota.isEmpty { Text(ejercicio.nota).font(.footnote).foregroundStyle(.secondary) }
                    }
                    if !i.alt.isEmpty {
                        Section("Alternativas") {
                            ForEach(i.alt, id: \.0) { nombre, url in
                                HStack {
                                    if let u = URL(string: url) { Link(destination: u) { Image(systemName: "play.rectangle") }.accessibilityLabel("Video de \(nombre)") }
                                    Text(nombre)
                                    Spacer()
                                    Button("Usar") { ejercicio.nombre = nombre; cerrar() }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(ejercicio.nombre).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
    }
}
