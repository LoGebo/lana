import Foundation
import SwiftData

// MARK: - Tipos base

/// Etapas de sueño (equivalen a HKCategoryValueSleepAnalysis; el raw es el de HealthKit).
enum EtapaSueno: Int, Codable, CaseIterable {
    case enCama = 0, sinEtapa = 1, despierto = 2, nucleo = 3, profundo = 4, rem = 5
    var dormido: Bool { self == .sinEtapa || self == .nucleo || self == .profundo || self == .rem }
    var nombre: String {
        switch self {
        case .enCama: "En cama"
        case .sinEtapa: "Dormido"
        case .despierto: "Despierto"
        case .nucleo: "Núcleo"
        case .profundo: "Profundo"
        case .rem: "REM"
        }
    }
}

/// Una muestra cruda de Salud. `fuente` = quién la escribió (Watch, iPhone, otra app).
struct MuestraSueno: Equatable {
    var inicio: Date, fin: Date, etapa: EtapaSueno, fuente: String
}

struct Segmento: Codable, Hashable {
    var inicio: Date, fin: Date, etapa: EtapaSueno
    var minutos: Double { fin.timeIntervalSince(inicio) / 60 }
}

/// Una noche (o siesta) ya resumida. Todo en minutos reales transcurridos (no reloj de pared: el DST no la deforma).
struct ResumenNoche: Identifiable, Equatable {
    var id: Date { dormido }
    var dia: Date            // día en que despertaste (inicio de día local)
    var dormido: Date, despierto: Date
    var minNucleo = 0.0, minProfundo = 0.0, minREM = 0.0, minSinEtapa = 0.0, minDespierto = 0.0, minEnCama = 0.0
    var siesta = false
    var segmentos: [Segmento] = []

    var minDormido: Double { minNucleo + minProfundo + minREM + minSinEtapa }
    var horasDormidas: Double { minDormido / 60 }
    var minSpan: Double { despierto.timeIntervalSince(dormido) / 60 }
    /// Dormido / tiempo entre dormirte y despertar, 0...1.
    var eficiencia: Double { minSpan > 0 ? min(1, minDormido / minSpan) : 0 }
    var tieneEtapas: Bool { minNucleo + minProfundo + minREM > 0 }
}

func minutosTexto(_ minutos: Double) -> String {
    let m = Int(minutos.rounded()); return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
}

// MARK: - Análisis (puro, sin HealthKit)

enum AnalisisSueno {
    static let maxManualHoras = 20.0

    /// Une muestras de varias fuentes sin doble conteo. Prioridad por tramo:
    /// fuente con etapas (Watch) > fuente sin etapas (iPhone/otras apps) > "en cama". Descarta muestras corruptas.
    // ponytail: O(muestras × límites), sobra para ~35 noches; con años de datos, barrido con heap.
    static func unificar(_ crudas: [MuestraSueno], ahora: Date = Date()) -> [Segmento] {
        let ms = crudas.filter {
            $0.fin > $0.inicio && $0.fin.timeIntervalSince($0.inicio) <= 24 * 3600
                && $0.inicio.timeIntervalSince1970.isFinite && $0.inicio <= ahora.addingTimeInterval(3600)
        }
        guard !ms.isEmpty else { return [] }
        let conEtapas = Set(ms.filter { $0.etapa == .nucleo || $0.etapa == .profundo || $0.etapa == .rem }.map(\.fuente))
        func prio(_ m: MuestraSueno) -> Int { m.etapa == .enCama ? 0 : (conEtapas.contains(m.fuente) ? 3 : 2) }
        let cortes = Array(Set(ms.flatMap { [$0.inicio, $0.fin] })).sorted()
        var out: [Segmento] = []
        for (a, b) in zip(cortes, cortes.dropFirst()) {
            let cubren = ms.filter { $0.inicio <= a && $0.fin >= b }
            guard let m = cubren.min(by: { (prio($1), $0.fuente) < (prio($0), $1.fuente) }) else { continue }
            if let u = out.last, u.fin == a, u.etapa == m.etapa { out[out.count - 1].fin = b }
            else { out.append(Segmento(inicio: a, fin: b, etapa: m.etapa)) }
        }
        return out
    }

    /// Parte en sesiones (hueco > `hueco` entre segmentos), recorta a dormido→despierto y asigna cada una al día en que despertaste.
    /// Menos de 3 h dormido = siesta; si hay varias "noches" el mismo día, la más larga es la noche y las demás siestas.
    static func sesiones(_ segs: [Segmento], cal: Calendar = .current, hueco: TimeInterval = 2 * 3600) -> [ResumenNoche] {
        var grupos: [[Segmento]] = []
        for s in segs.sorted(by: { $0.inicio < $1.inicio }) {
            if let u = grupos.last?.last, s.inicio.timeIntervalSince(u.fin) <= hueco { grupos[grupos.count - 1].append(s) }
            else { grupos.append([s]) }
        }
        var res: [ResumenNoche] = grupos.compactMap { g in
            guard let a = g.first(where: { $0.etapa.dormido }), let z = g.last(where: { $0.etapa.dormido }) else { return nil }
            var n = ResumenNoche(dia: cal.startOfDay(for: z.fin), dormido: a.inicio, despierto: z.fin)
            for s in g {
                let m = s.minutos
                switch s.etapa {
                case .nucleo: n.minNucleo += m
                case .profundo: n.minProfundo += m
                case .rem: n.minREM += m
                case .sinEtapa: n.minSinEtapa += m
                case .enCama: n.minEnCama += m
                case .despierto:
                    let i = max(s.inicio, a.inicio), f = min(s.fin, z.fin)
                    if f > i { n.minDespierto += f.timeIntervalSince(i) / 60 }
                }
            }
            n.segmentos = g.filter { $0.fin > a.inicio && $0.inicio < z.fin && $0.etapa != .enCama }
            n.siesta = n.minDormido < 180
            return n
        }
        for dia in Set(res.filter { !$0.siesta }.map(\.dia)) {
            let noches = res.indices.filter { res[$0].dia == dia && !res[$0].siesta }
            for i in noches.sorted(by: { res[$0].minDormido > res[$1].minDormido }).dropFirst() { res[i].siesta = true }
        }
        return res.sorted { $0.despierto > $1.despierto }
    }

    // MARK: Métricas

    private static func minutoDelDia(_ d: Date, _ cal: Calendar) -> Double {
        let c = cal.dateComponents([.hour, .minute], from: d); return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
    private static func desviacion(_ x: [Double]) -> Double {
        let m = x.reduce(0, +) / Double(x.count)
        return (x.reduce(0) { $0 + pow($1 - m, 2) } / Double(x.count)).squareRoot()
    }

    /// Desviación estándar (min) de la hora de dormir y de despertar. nil con menos de 3 noches. 1 am cuenta como 25:00.
    static func regularidad(_ ns: [ResumenNoche], cal: Calendar = .current) -> (dormir: Double, despertar: Double)? {
        let r = ns.filter { !$0.siesta }
        guard r.count >= 3 else { return nil }
        let d = r.map { n -> Double in let m = minutoDelDia(n.dormido, cal); return m < 12 * 60 ? m + 1440 : m }
        return (desviacion(d), desviacion(r.map { minutoDelDia($0.despierto, cal) }))
    }

    /// Promedio de horas dormidas en los últimos `dias` días (incluye hoy). nil si no hay noches.
    static func promedioHoras(_ ns: [ResumenNoche], dias: Int, hoy: Date = Date(), cal: Calendar = .current) -> Double? {
        let desde = cal.date(byAdding: .day, value: -(dias - 1), to: cal.startOfDay(for: hoy)) ?? hoy
        let v = ns.filter { !$0.siesta && $0.dia >= desde && $0.dia <= hoy }.map(\.horasDormidas)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    /// Horas que debes de la última semana. Las noches sin dato no cuentan (no se inventa deuda).
    static func deuda(_ ns: [ResumenNoche], metaHoras: Double, hoy: Date = Date(), cal: Calendar = .current) -> (horas: Double, noches: Int) {
        let desde = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: hoy)) ?? hoy
        let r = ns.filter { !$0.siesta && $0.dia >= desde && $0.dia <= hoy }
        return (r.reduce(0) { $0 + max(0, metaHoras - $1.horasDormidas) }, r.count)
    }

    struct Componente: Identifiable, Equatable {
        var id: String { nombre }
        let nombre: String, puntos: Double, max: Double, detalle: String
    }
    struct Puntaje: Equatable { let total: Int; let componentes: [Componente] }

    private static func tramo(_ x: Double, _ a: Double, _ b: Double) -> Double { Swift.min(1, Swift.max(0, (x - a) / (b - a))) }

    /// 0-100, explicable: duración 50 · eficiencia 25 · profundo+REM 15 · regularidad 10.
    /// Lo que no se puede medir (sin etapas, pocas noches) se quita del máximo en vez de regalar o castigar puntos.
    static func puntaje(_ n: ResumenNoche, metaHoras: Double, desvDormir: Double?) -> Puntaje {
        var c = [Componente(nombre: "Duración", puntos: 50 * Swift.min(1, n.horasDormidas / Swift.max(metaHoras, 1)), max: 50,
                            detalle: "\(minutosTexto(n.minDormido)) de tu meta de \(String(format: "%g", metaHoras)) h"),
                 Componente(nombre: "Eficiencia", puntos: 25 * tramo(n.eficiencia, 0.75, 0.95), max: 25,
                            detalle: "\(Int((n.eficiencia * 100).rounded())) % del tiempo en cama dormido (ideal ≥ 90 %)")]
        if n.tieneEtapas {
            let r = (n.minProfundo + n.minREM) / Swift.max(n.minDormido, 1)
            c.append(Componente(nombre: "Reparador", puntos: 15 * tramo(r, 0.25, 0.40), max: 15,
                                detalle: "\(Int((r * 100).rounded())) % profundo + REM (ideal ≥ 40 %)"))
        }
        if let d = desvDormir {
            c.append(Componente(nombre: "Regularidad", puntos: 10 * (1 - tramo(d, 30, 90)), max: 10,
                                detalle: "hora de dormir ±\(Int(d.rounded())) min (ideal ≤ 30)"))
        }
        let total = c.reduce(0) { $0 + $1.puntos } / c.reduce(0) { $0 + $1.max } * 100
        return Puntaje(total: Int(total.rounded()), componentes: c)
    }

    /// Puntaje de una noche usando su regularidad de los 7 días previos.
    static func puntaje(de n: ResumenNoche, entre todas: [ResumenNoche], metaHoras: Double, cal: Calendar = .current) -> Puntaje {
        let desde = cal.date(byAdding: .day, value: -6, to: n.dia) ?? n.dia
        let ventana = todas.filter { !$0.siesta && $0.dia >= desde && $0.dia <= n.dia }
        return puntaje(n, metaHoras: metaHoras, desvDormir: regularidad(ventana, cal: cal)?.dormir)
    }

    // MARK: Registro manual

    enum ErrorManual: String, Error {
        case orden = "Despertar debe ser después de dormir."
        case larga = "Una noche no puede durar más de 20 h."
        case corta = "Menos de 30 min no cuenta como noche."
        case futuro = "No puedes registrar sueño en el futuro."
        case antigua = "Solo se registran los últimos 30 días."
    }

    static func validar(dormido: Date, despierto: Date, ahora: Date = Date()) -> ErrorManual? {
        guard despierto > dormido else { return .orden }
        let h = despierto.timeIntervalSince(dormido) / 3600
        if h > maxManualHoras { return .larga }
        if h < 0.5 { return .corta }
        if despierto > ahora.addingTimeInterval(300) { return .futuro }
        if dormido < ahora.addingTimeInterval(-30 * 86400) { return .antigua }
        return nil
    }
}

// MARK: - Caché SwiftData

/// Noche o siesta guardada para abrir sin esperar a Salud. `manual` = capturada a mano (respaldo si Salud no tiene ese día).
@Model
final class NocheSueno {
    var id: UUID = UUID()
    var dia: Date = Date()
    var dormido: Date = Date()
    var despierto: Date = Date()
    var minNucleo: Double = 0
    var minProfundo: Double = 0
    var minREM: Double = 0
    var minSinEtapa: Double = 0
    var minDespierto: Double = 0
    var minEnCama: Double = 0
    var siesta: Bool = false
    var manual: Bool = false
    var segmentosRaw: Data?

    init(_ r: ResumenNoche, manual: Bool = false) {
        id = UUID(); dia = r.dia; dormido = r.dormido; despierto = r.despierto
        minNucleo = r.minNucleo; minProfundo = r.minProfundo; minREM = r.minREM; minSinEtapa = r.minSinEtapa
        minDespierto = r.minDespierto; minEnCama = r.minEnCama; siesta = r.siesta; self.manual = manual
        segmentosRaw = try? JSONEncoder().encode(r.segmentos)
    }

    var resumen: ResumenNoche {
        var r = ResumenNoche(dia: dia, dormido: dormido, despierto: despierto, minNucleo: minNucleo, minProfundo: minProfundo,
                             minREM: minREM, minSinEtapa: minSinEtapa, minDespierto: minDespierto, minEnCama: minEnCama, siesta: siesta)
        r.segmentos = segmentosRaw.flatMap { try? JSONDecoder().decode([Segmento].self, from: $0) } ?? []
        return r
    }

    /// Una noche por día (Salud gana a la manual), más reciente primero. Sin siestas.
    static func mejorPorDia(_ ns: [NocheSueno]) -> [ResumenNoche] {
        var porDia: [Date: NocheSueno] = [:]
        for n in ns where !n.siesta {
            guard let p = porDia[n.dia] else { porDia[n.dia] = n; continue }
            if p.manual && !n.manual { porDia[n.dia] = n }
        }
        return porDia.values.map(\.resumen).sorted { $0.dia > $1.dia }
    }

    /// Guarda una noche manual (reemplaza la manual de ese día). Lanza si no pasa validación.
    @MainActor
    static func registrarManual(dormido: Date, despierto: Date, _ contexto: ModelContext, ahora: Date = Date(), cal: Calendar = .current) throws {
        if let e = AnalisisSueno.validar(dormido: dormido, despierto: despierto, ahora: ahora) { throw e }
        let dia = cal.startOfDay(for: despierto)
        for n in ((try? contexto.fetch(FetchDescriptor<NocheSueno>())) ?? []) where n.manual && n.dia == dia { contexto.delete(n) }
        var r = ResumenNoche(dia: dia, dormido: dormido, despierto: despierto)
        r.minSinEtapa = despierto.timeIntervalSince(dormido) / 60
        r.siesta = false
        contexto.insert(NocheSueno(r, manual: true))
        try? contexto.save()
    }
}

/// Métricas del día que lee Salud. nil = ese dato no existe (distinto de 0).
@Model
final class MetricaDia {
    var dia: Date = Date()
    var fcReposo: Double?
    var hrv: Double?
    var pasos: Double?
    var energia: Double?
    init(dia: Date, fcReposo: Double? = nil, hrv: Double? = nil, pasos: Double? = nil, energia: Double? = nil) {
        self.dia = dia; self.fcReposo = fcReposo; self.hrv = hrv; self.pasos = pasos; self.energia = energia
    }
}
