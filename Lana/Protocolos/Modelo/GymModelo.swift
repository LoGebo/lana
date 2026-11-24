import Foundation
import SwiftData

enum TipoSerie: String, CaseIterable, Identifiable {
    case normal, calentamiento, drop, fallo
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .normal: "Normal"
        case .calentamiento: "Calentamiento"
        case .drop: "Drop set"
        case .fallo: "Al fallo"
        }
    }
    /// Letra que se muestra en lugar del número de serie.
    var letra: String? {
        switch self {
        case .normal: nil
        case .calentamiento: "C"
        case .drop: "D"
        case .fallo: "F"
        }
    }
    /// Los calentamientos no suman al volumen ni a los récords.
    var cuentaVolumen: Bool { self != .calentamiento }
}

@Model
final class Serie {
    var id: UUID = UUID()
    var tipoRaw: String = TipoSerie.normal.rawValue
    var peso: Double = 0
    var reps: Int = 0
    var hecha: Bool = false
    var orden: Int = 0
    var ejercicio: EjercicioLog?

    var tipo: TipoSerie {
        get { TipoSerie(rawValue: tipoRaw) ?? .normal }
        set { tipoRaw = newValue.rawValue }
    }

    init(orden: Int, peso: Double = 0, reps: Int = 0, tipo: TipoSerie = .normal) {
        self.id = UUID()
        self.orden = orden
        self.peso = peso
        self.reps = reps
        self.tipoRaw = tipo.rawValue
    }
}

@Model
final class EjercicioLog {
    var id: UUID = UUID()
    var nombre: String = ""
    var grupo: String = ""
    var orden: Int = 0
    var descansoSeg: Int = 90
    var nota: String = ""
    /// Mismo número distinto de 0 = van en superserie.
    var grupoSuper: Int = 0
    /// Meta de la rutina, p. ej. "3 × 6-10 · RIR 1-2".
    var objetivo: String = ""
    var sesion: SesionGym?

    @Relationship(deleteRule: .cascade, inverse: \Serie.ejercicio)
    var series: [Serie]? = []

    var seriesOrdenadas: [Serie] { (series ?? []).sorted { $0.orden < $1.orden } }

    init(nombre: String, grupo: String, orden: Int, descansoSeg: Int = 90) {
        self.id = UUID()
        self.nombre = nombre
        self.grupo = grupo
        self.orden = orden
        self.descansoSeg = descansoSeg
    }
}

@Model
final class SesionGym {
    var id: UUID = UUID()
    var nombre: String = "Entrenamiento"
    var inicio: Date = Date()
    /// nil = entrenamiento en curso (sobrevive si cierras la app).
    var fin: Date?
    var notas: String = ""

    @Relationship(deleteRule: .cascade, inverse: \EjercicioLog.sesion)
    var ejercicios: [EjercicioLog]? = []

    var ejerciciosOrdenados: [EjercicioLog] { (ejercicios ?? []).sorted { $0.orden < $1.orden } }
    var duracion: TimeInterval { (fin ?? Date()).timeIntervalSince(inicio) }

    var seriesHechas: [Serie] {
        ejerciciosOrdenados.flatMap { $0.seriesOrdenadas }.filter(\.hecha)
    }
    var volumen: Double {
        seriesHechas.filter { $0.tipo.cuentaVolumen }.reduce(0) { $0 + $1.peso * Double($1.reps) }
    }

    init(nombre: String = "Entrenamiento") {
        self.id = UUID()
        self.nombre = nombre
        self.inicio = Date()
    }
}

@Model
final class EjercicioDef {
    var id: UUID = UUID()
    var nombre: String = ""
    var grupo: String = ""
    var propio: Bool = false

    init(nombre: String, grupo: String, propio: Bool = false) {
        self.id = UUID()
        self.nombre = nombre
        self.grupo = grupo
        self.propio = propio
    }
}

@Model
final class Rutina {
    var id: UUID = UUID()
    var nombre: String = ""
    var orden: Int = 0
    /// Nombres separados por "|" (suficiente para una plantilla).
    var ejerciciosRaw: String = ""
    /// JSON { nombre: ItemPlan } con series, reps, RIR y descanso objetivo.
    var planRaw: String = ""

    var plan: [String: ItemPlan] {
        get { (try? JSONDecoder().decode([String: ItemPlan].self, from: Data(planRaw.utf8))) ?? [:] }
        set { planRaw = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "" }
    }

    var ejercicios: [String] {
        get { ejerciciosRaw.split(separator: "|").map(String.init) }
        set { ejerciciosRaw = newValue.joined(separator: "|") }
    }

    init(nombre: String, ejercicios: [String], orden: Int = 0) {
        self.id = UUID()
        self.nombre = nombre
        self.orden = orden
        self.ejerciciosRaw = ejercicios.joined(separator: "|")
    }
}

// MARK: - Cálculos

enum TipoRecord: String, CaseIterable {
    case peso, e1rm, reps, volumen
    var titulo: String {
        switch self {
        case .peso: "Peso máximo"
        case .e1rm: "1RM estimado"
        case .reps: "Más repeticiones"
        case .volumen: "Volumen de serie"
        }
    }
    var corto: String {
        switch self {
        case .peso: "peso"
        case .e1rm: "1RM"
        case .reps: "reps"
        case .volumen: "volumen"
        }
    }
}

/// Mejores marcas de un ejercicio (solo series de trabajo hechas, sin calentamiento).
struct MarcasEjercicio {
    var peso = 0.0
    var e1rm = 0.0
    var volumen = 0.0
    /// peso×100 → máximo de repeticiones con ese peso.
    var reps: [Int: Int] = [:]

    static func llave(_ peso: Double) -> Int { Int((peso * 100).rounded()) }

    mutating func absorber(_ s: Serie) {
        guard s.reps > 0 else { return }
        peso = max(peso, s.peso)
        e1rm = max(e1rm, GymCalculos.e1RM(peso: s.peso, reps: s.reps))
        volumen = max(volumen, s.peso * Double(s.reps))
        reps[Self.llave(s.peso)] = max(reps[Self.llave(s.peso)] ?? 0, s.reps)
    }

    /// Qué récords rompe esta serie frente a estas marcas.
    func records(de s: Serie) -> [TipoRecord] {
        guard s.reps > 0 else { return [] }
        var r: [TipoRecord] = []
        if s.peso > peso { r.append(.peso) }
        if GymCalculos.e1RM(peso: s.peso, reps: s.reps) > e1rm + 0.001 { r.append(.e1rm) }
        if let previas = reps[Self.llave(s.peso)], s.reps > previas { r.append(.reps) }
        if s.peso * Double(s.reps) > volumen + 0.001 { r.append(.volumen) }
        return r
    }
}

enum GymCalculos {
    /// 1RM estimado (Epley), el mismo que usa Hevy.
    static func e1RM(peso: Double, reps: Int) -> Double {
        guard reps > 0, peso > 0 else { return 0 }
        return reps == 1 ? peso : peso * (1 + Double(reps) / 30)
    }

    static func validas(_ e: EjercicioLog) -> [Serie] {
        e.seriesOrdenadas.filter { $0.hecha && $0.tipo.cuentaVolumen && $0.reps > 0 }
    }

    static func mejor1RM(_ e: EjercicioLog) -> Double {
        validas(e).map { e1RM(peso: $0.peso, reps: $0.reps) }.max() ?? 0
    }

    static func mejorPeso(_ e: EjercicioLog) -> Double {
        validas(e).map(\.peso).max() ?? 0
    }

    /// Series de trabajo de la última vez que hiciste este ejercicio (sin calentamientos; más reciente primero).
    static func anterior(de nombre: String, en historial: [SesionGym], excepto actual: SesionGym? = nil) -> [Serie] {
        for s in historial where s.fin != nil && s.id != actual?.id {
            if let e = s.ejerciciosOrdenados.first(where: { $0.nombre == nombre }) {
                let hechas = e.seriesOrdenadas.filter { $0.hecha && $0.tipo != .calentamiento }
                if !hechas.isEmpty { return hechas }
            }
        }
        return []
    }

    /// Marcas del ejercicio en sesiones terminadas anteriores a `fecha`. nil = nunca lo habías hecho (línea base, no hay récord).
    static func marcasPrevias(de nombre: String, historial: [SesionGym], antesDe fecha: Date,
                              excepto actual: SesionGym? = nil) -> MarcasEjercicio? {
        var m = MarcasEjercicio()
        var hay = false
        for s in historial where s.fin != nil && s.id != actual?.id && s.inicio <= fecha {
            for e in s.ejerciciosOrdenados where e.nombre == nombre {
                for x in validas(e) { m.absorber(x); hay = true }
            }
        }
        return hay ? m : nil
    }

    /// Récords que rompe `serie` frente al historial previo y a las series ya hechas antes en este ejercicio.
    /// Una misma marca no se cuenta dos veces: la segunda serie igual de pesada ya no es récord.
    static func records(de serie: Serie, en e: EjercicioLog, previas: MarcasEjercicio?) -> [TipoRecord] {
        guard var m = previas, serie.hecha, serie.tipo.cuentaVolumen, serie.reps > 0 else { return [] }
        for x in e.seriesOrdenadas where x.orden < serie.orden && x.hecha && x.tipo.cuentaVolumen { m.absorber(x) }
        return m.records(de: serie)
    }

    struct Record: Identifiable {
        let id = UUID()
        let ejercicio: String
        let tipo: TipoRecord
        let detalle: String
    }

    /// Récords de una sesión frente a todo lo anterior. Un renglón por tipo y ejercicio.
    static func records(de sesion: SesionGym, historial: [SesionGym]) -> [Record] {
        var lista: [Record] = []
        var vistos: [String] = []
        for e0 in sesion.ejerciciosOrdenados where !vistos.contains(e0.nombre) {
            vistos.append(e0.nombre)
            let nombre = e0.nombre
            guard let previas = marcasPrevias(de: nombre, historial: historial, antesDe: sesion.inicio, excepto: sesion)
            else { continue }   // la primera vez no es récord, es línea base
            var hoy = MarcasEjercicio()
            for e in sesion.ejerciciosOrdenados where e.nombre == nombre { for x in validas(e) { hoy.absorber(x) } }
            if hoy.peso > previas.peso {
                lista.append(Record(ejercicio: nombre, tipo: .peso, detalle: "Peso máximo: \(kg(hoy.peso)) (antes \(kg(previas.peso)))"))
            }
            if hoy.e1rm > previas.e1rm + 0.001 {
                lista.append(Record(ejercicio: nombre, tipo: .e1rm, detalle: "1RM estimado: \(kg(hoy.e1rm)) (antes \(kg(previas.e1rm)))"))
            }
            // Reps: la mejora en el peso más alto que ya habías usado.
            let mejoras = hoy.reps.compactMap { k, r -> (Int, Int, Int)? in
                guard let antes = previas.reps[k], r > antes else { return nil }
                return (k, r, antes)
            }
            if let m = mejoras.max(by: { $0.0 < $1.0 }) {
                lista.append(Record(ejercicio: nombre, tipo: .reps,
                                    detalle: "Más repeticiones: \(m.1) con \(kg(Double(m.0) / 100)) (antes \(m.2))"))
            }
            if hoy.volumen > previas.volumen + 0.001 {
                lista.append(Record(ejercicio: nombre, tipo: .volumen,
                                    detalle: "Volumen de serie: \(kg(hoy.volumen)) (antes \(kg(previas.volumen)))"))
            }
        }
        return lista
    }
}

func kg(_ v: Double) -> String {
    (v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)) + " kg"
}

func numeroLimpio(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

func duracionTexto(_ t: TimeInterval) -> String {
    let m = Int(t) / 60
    return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
}
