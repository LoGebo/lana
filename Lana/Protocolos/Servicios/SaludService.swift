import Foundation
import HealthKit
import SwiftData

struct DatosMetricaDia: Equatable {
    var dia: Date
    var fcReposo: Double?, hrv: Double?, pasos: Double?, energia: Double?
}

/// Fuente de datos de salud. HealthKit en producción; un falso para pruebas y simulador.
protocol ProveedorSalud {
    var disponible: Bool { get }
    func pedirPermisoSiHaceFalta() async
    func muestrasSueno(desde: Date, hasta: Date) async -> [MuestraSueno]
    func metricas(desde: Date, hasta: Date, cal: Calendar) async -> [DatosMetricaDia]
    func pesos(desde: Date, hasta: Date, cal: Calendar) async -> [(dia: Date, kg: Double)]
}

/// Lee Salud (Apple Watch + iPhone). Solo lectura: no escribe nada.
/// iOS no dice si negaste un permiso de lectura: se ve como "sin datos" y la UI explica cómo darlo.
struct ProveedorHealthKit: ProveedorSalud {
    private let almacen = HKHealthStore()
    var disponible: Bool { HKHealthStore.isHealthDataAvailable() }

    private var tipos: Set<HKObjectType> {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN),
         HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.bodyMass)]
    }

    func pedirPermisoSiHaceFalta() async {
        let estado = try? await almacen.statusForAuthorizationRequest(toShare: [], read: tipos)
        if estado != .unnecessary { try? await almacen.requestAuthorization(toShare: [], read: tipos) }
    }

    func muestrasSueno(desde: Date, hasta: Date) async -> [MuestraSueno] {
        let tipo = HKCategoryType(.sleepAnalysis)
        let r: [HKCategorySample] = await withCheckedContinuation { cont in
            almacen.execute(HKSampleQuery(sampleType: tipo, predicate: HKQuery.predicateForSamples(withStart: desde, end: hasta),
                                          limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, _ in
                cont.resume(returning: (r as? [HKCategorySample]) ?? [])
            })
        }
        return r.compactMap { m in
            guard let e = EtapaSueno(rawValue: m.value) else { return nil }   // valor desconocido = se ignora
            return MuestraSueno(inicio: m.startDate, fin: m.endDate, etapa: e, fuente: m.sourceRevision.source.bundleIdentifier)
        }
    }

    private func diario(_ id: HKQuantityTypeIdentifier, _ unidad: HKUnit, suma: Bool, _ desde: Date, _ hasta: Date, _ cal: Calendar) async -> [Date: Double] {
        let opciones: HKStatisticsOptions = suma ? .cumulativeSum : .discreteAverage
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: HKQuantityType(id),
                                                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: desde, end: hasta),
                                                options: opciones, anchorDate: cal.startOfDay(for: desde),
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, r, _ in
                var out: [Date: Double] = [:]
                r?.enumerateStatistics(from: desde, to: hasta) { s, _ in
                    if let v = suma ? s.sumQuantity() : s.averageQuantity() { out[cal.startOfDay(for: s.startDate)] = v.doubleValue(for: unidad) }
                }
                cont.resume(returning: out)
            }
            almacen.execute(q)
        }
    }

    func metricas(desde: Date, hasta: Date, cal: Calendar) async -> [DatosMetricaDia] {
        async let fc = diario(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), suma: false, desde, hasta, cal)
        async let hrv = diario(.heartRateVariabilitySDNN, .secondUnit(with: .milli), suma: false, desde, hasta, cal)
        async let pasos = diario(.stepCount, .count(), suma: true, desde, hasta, cal)
        async let energia = diario(.activeEnergyBurned, .kilocalorie(), suma: true, desde, hasta, cal)
        let (a, b, c, d) = await (fc, hrv, pasos, energia)
        return Set(a.keys).union(b.keys).union(c.keys).union(d.keys).sorted()
            .map { DatosMetricaDia(dia: $0, fcReposo: a[$0], hrv: b[$0], pasos: c[$0], energia: d[$0]) }
    }

    func pesos(desde: Date, hasta: Date, cal: Calendar) async -> [(dia: Date, kg: Double)] {
        let r: [HKQuantitySample] = await withCheckedContinuation { cont in
            almacen.execute(HKSampleQuery(sampleType: HKQuantityType(.bodyMass), predicate: HKQuery.predicateForSamples(withStart: desde, end: hasta),
                                          limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, r, _ in
                cont.resume(returning: (r as? [HKQuantitySample]) ?? [])
            })
        }
        // Último pesaje de cada día.
        var porDia: [Date: Double] = [:]
        for m in r { porDia[cal.startOfDay(for: m.startDate)] = m.quantity.doubleValue(for: .gramUnit(with: .kilo)) }
        return porDia.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

/// Orquesta: pide permiso, lee, unifica y guarda en caché (SwiftData). La UI solo lee la caché.
@MainActor
final class SaludService: ObservableObject {
    @Published var cargando = false
    @Published var ultimaSync: Date?
    let proveedor: ProveedorSalud
    var disponible: Bool { proveedor.disponible }

    /// `-DatosSuenoFake` (pruebas de UI) usa datos de ejemplo; si no, HealthKit.
    init(proveedor: ProveedorSalud? = nil) {
        self.proveedor = proveedor ?? (CommandLine.arguments.contains("-DatosSuenoFake") ? ProveedorSaludFalso() : ProveedorHealthKit())
    }

    static let diasHistorial = 35

    func sincronizar(_ contexto: ModelContext, ahora: Date = Date(), cal: Calendar = .current) async {
        guard disponible, !cargando else { return }
        cargando = true
        defer { cargando = false }
        await proveedor.pedirPermisoSiHaceFalta()
        let desde = cal.startOfDay(for: cal.date(byAdding: .day, value: -Self.diasHistorial, to: ahora) ?? ahora)

        let segs = AnalisisSueno.unificar(await proveedor.muestrasSueno(desde: desde, hasta: ahora), ahora: ahora)
        // ponytail: si Salud no devuelve nada (sin permiso, sin datos) no borramos la caché; las noches borradas en Salud tardan en irse solo si hay otras.
        if !segs.isEmpty {
            for n in ((try? contexto.fetch(FetchDescriptor<NocheSueno>())) ?? []) where !n.manual && n.dia >= desde { contexto.delete(n) }
            for r in AnalisisSueno.sesiones(segs, cal: cal) where r.dia >= desde { contexto.insert(NocheSueno(r)) }
        }

        let existentes = Dictionary(((try? contexto.fetch(FetchDescriptor<MetricaDia>())) ?? []).map { ($0.dia, $0) }, uniquingKeysWith: { a, _ in a })
        for m in await proveedor.metricas(desde: desde, hasta: ahora, cal: cal) {
            if let e = existentes[m.dia] { e.fcReposo = m.fcReposo; e.hrv = m.hrv; e.pasos = m.pasos; e.energia = m.energia }
            else { contexto.insert(MetricaDia(dia: m.dia, fcReposo: m.fcReposo, hrv: m.hrv, pasos: m.pasos, energia: m.energia)) }
        }

        // Peso de Salud solo siembra días sin captura propia: nunca pisa lo que escribiste en Lana.
        let conPeso = Set(((try? contexto.fetch(FetchDescriptor<PesoLog>())) ?? []).map(\.dia))
        for p in await proveedor.pesos(desde: desde, hasta: ahora, cal: cal) where !conPeso.contains(p.dia) && Peso.rango.contains(p.kg) {
            contexto.insert(PesoLog(dia: p.dia, kg: p.kg))
        }
        try? contexto.save()
        ultimaSync = ahora
    }
}
