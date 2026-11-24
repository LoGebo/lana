import Foundation
import SwiftData

/// Un pesaje (kg). Uno por día: registrar de nuevo el mismo día reemplaza el valor.
@Model
final class PesoLog {
    var id: UUID = UUID()
    var dia: Date = Date()
    var kg: Double = 0
    init(dia: Date, kg: Double) { self.id = UUID(); self.dia = Calendar.current.startOfDay(for: dia); self.kg = kg }
}

enum Peso {
    static let rango = 30.0...250.0

    /// Guarda/actualiza el peso del día. Devuelve false si el valor es inválido (NaN, fuera de rango).
    @MainActor @discardableResult
    static func registrar(_ kg: Double, dia: Date = Date(), _ contexto: ModelContext) -> Bool {
        guard kg.isFinite, rango.contains(kg) else { return false }
        let d = Calendar.current.startOfDay(for: dia)
        let previos = ((try? contexto.fetch(FetchDescriptor<PesoLog>())) ?? []).filter { $0.dia == d }
        if let p = previos.first { p.kg = kg; previos.dropFirst().forEach(contexto.delete) } else { contexto.insert(PesoLog(dia: d, kg: kg)) }
        try? contexto.save()
        UserDefaults.standard.set(kg, forKey: "protocolos.perfil.peso")
        return true
    }

    /// Cambio semanal (kg/semana) por regresión lineal de los últimos `dias`; nil con menos de 3 puntos o <5 días de rango.
    static func tendenciaSemanal(_ logs: [(dia: Date, kg: Double)], dias: Int = 21, hoy: Date = Date()) -> Double? {
        let desde = Calendar.current.date(byAdding: .day, value: -dias, to: hoy) ?? hoy
        let p = logs.filter { $0.dia >= desde && $0.dia <= hoy }.sorted { $0.dia < $1.dia }
        guard p.count >= 3, let a = p.first, let b = p.last, b.dia.timeIntervalSince(a.dia) >= 5 * 86400 else { return nil }
        let x = p.map { $0.dia.timeIntervalSince(a.dia) / 86400 }, y = p.map(\.kg)
        let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
        let den = x.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        return zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / den * 7
    }

    /// Ajuste de calorías sugerido para volumen limpio (meta 0.25-0.5% del peso por semana).
    static func sugerencia(kgPorSemana: Double, pesoActual: Double) -> (kcal: Int, texto: String) {
        let pct = kgPorSemana / pesoActual * 100
        switch pct {
        case ..<0.15: return (200, "Subes muy lento (\(String(format: "%.2f", kgPorSemana)) kg/sem): +200 kcal.")
        case 0.15..<0.5: return (0, "Ritmo ideal (\(String(format: "%.2f", kgPorSemana)) kg/sem): no cambies nada.")
        default: return (-200, "Subes muy rápido (\(String(format: "%.2f", kgPorSemana)) kg/sem): -200 kcal para no ganar grasa.")
        }
    }
}
