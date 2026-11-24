import Foundation
import HealthKit

/// Lee el sueño que ya mide el Apple Watch. No escribe nada en Salud.
@MainActor
final class SaludService: ObservableObject {
    struct Noche: Identifiable {
        var id: Date { despierto }
        let dormido: Date
        let despierto: Date
        /// Horas realmente dormidas (sin los ratos despierto).
        let horas: Double
    }

    @Published var noches: [Noche] = []
    @Published var cargando = false

    private let almacen = HKHealthStore()
    private let tipo = HKCategoryType(.sleepAnalysis)

    var disponible: Bool { HKHealthStore.isHealthDataAvailable() }

    func cargar() async {
        guard disponible else { return }
        cargando = true
        defer { cargando = false }
        try? await almacen.requestAuthorization(toShare: [], read: [tipo])

        let desde = Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date()
        let predicado = HKQuery.predicateForSamples(withStart: desde, end: Date())
        let muestras: [HKCategorySample] = await withCheckedContinuation { cont in
            let consulta = HKSampleQuery(sampleType: tipo, predicate: predicado, limit: HKObjectQueryNoLimit,
                                         sortDescriptors: [NSSortDescriptor(keyPath: \HKSample.startDate, ascending: true)]) { _, r, _ in
                cont.resume(returning: (r as? [HKCategorySample]) ?? [])
            }
            almacen.execute(consulta)
        }

        let dormidos: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                  HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                  HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                  HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let intervalos = muestras.filter { dormidos.contains($0.value) }.map { ($0.startDate, $0.endDate) }
        noches = Self.agrupar(intervalos)
    }

    /// Une intervalos traslapados (iPhone + Watch) y parte las noches
    /// donde hay un hueco de más de 3 horas.
    static func agrupar(_ crudos: [(Date, Date)]) -> [Noche] {
        var unidos: [(Date, Date)] = []
        for i in crudos.sorted(by: { $0.0 < $1.0 }) {
            if let ultimo = unidos.last, i.0 <= ultimo.1 {
                unidos[unidos.count - 1].1 = max(ultimo.1, i.1)
            } else {
                unidos.append(i)
            }
        }
        var noches: [Noche] = []
        var inicio: Date?, fin: Date?, total = 0.0
        for (a, b) in unidos {
            if let f = fin, a.timeIntervalSince(f) > 3 * 3600, let i = inicio {
                noches.append(Noche(dormido: i, despierto: f, horas: total / 3600))
                inicio = nil; total = 0
            }
            if inicio == nil { inicio = a }
            fin = b
            total += b.timeIntervalSince(a)
        }
        if let i = inicio, let f = fin { noches.append(Noche(dormido: i, despierto: f, horas: total / 3600)) }
        // Siestas sueltas (< 3 h) no cuentan como noche.
        return noches.filter { $0.horas >= 3 }.sorted { $0.despierto > $1.despierto }
    }
}
