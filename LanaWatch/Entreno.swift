import Foundation
import HealthKit
import WatchKit

/// Sesión de entrenamiento en vivo (FC) y guardado en Salud.
final class MotorEntreno: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let almacen = HKHealthStore()
    private var sesion: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    var alFC: (Double) -> Void = { _ in }

    func empezar() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let c = HKWorkoutConfiguration(); c.activityType = .traditionalStrengthTraining; c.locationType = .indoor
        guard let s = try? HKWorkoutSession(healthStore: almacen, configuration: c) else { return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: almacen, workoutConfiguration: c)
        s.delegate = self; b.delegate = self
        sesion = s; builder = b
        s.startActivity(with: Date())
        try? await b.beginCollection(at: Date())
    }

    func terminar() async {
        sesion?.end()
        try? await builder?.endCollection(at: Date())
        _ = try? await builder?.finishWorkout()
        sesion = nil; builder = nil
    }

    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {}
    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf tipos: Set<HKSampleType>) {
        guard tipos.contains(HKQuantityType(.heartRate)),
              let q = b.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity() else { return }
        let bpm = q.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        DispatchQueue.main.async { self.alFC(bpm) }
    }
}

@MainActor
final class EntrenoModelo: ObservableObject {
    @Published private(set) var activo = false
    @Published private(set) var rutina = ""
    @Published private(set) var ejercicios: [EjercicioWatch] = []
    @Published private(set) var idx = 0
    @Published private(set) var hechas: [Int] = []
    @Published var kg = 0.0
    @Published var reps = 10.0
    @Published private(set) var finDescanso: Date?
    @Published private(set) var fc = 0.0
    @Published private(set) var totalSeries = 0

    private let motor = MotorEntreno()

    var actual: EjercicioWatch? { ejercicios.indices.contains(idx) ? ejercicios[idx] : nil }
    var serieActual: Int { (hechas.indices.contains(idx) ? hechas[idx] : 0) + 1 }

    func empezar(_ r: ResumenWatch) async {
        guard let nombre = r.rutina, !r.ejercicios.isEmpty, !activo else { return }
        rutina = nombre; ejercicios = r.ejercicios; hechas = Array(repeating: 0, count: r.ejercicios.count)
        totalSeries = 0; fc = 0; activo = true
        ir(a: 0)
        motor.alFC = { [weak self] v in self?.fc = v }
        await motor.empezar()
    }

    private func ir(a i: Int) {
        idx = i
        guard let e = actual else { return }
        kg = e.kgPrevio
        reps = Double(e.reps.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? 10)
    }

    /// Registra la serie actual. Devuelve false si el comando no pasó la validación.
    @discardableResult
    func hecha(_ modelo: ModeloWatch) -> Bool {
        guard let e = actual else { return false }
        guard modelo.enviar(.serie(ejercicio: e.nombre, rutina: rutina, kg: kg, reps: Int(reps))) else { return false }
        hechas[idx] += 1; totalSeries += 1
        if hechas[idx] >= e.series, idx + 1 < ejercicios.count { ir(a: idx + 1) }
        iniciarDescanso(e.descanso)
        return true
    }

    func saltarEjercicio() { if idx + 1 < ejercicios.count { ir(a: idx + 1) } }

    private func iniciarDescanso(_ s: Int) {
        let fin = Date().addingTimeInterval(Double(max(10, s)))
        finDescanso = fin
        Task {
            try? await Task.sleep(until: .now + .seconds(max(10, s)), clock: .continuous)
            if finDescanso == fin { WKInterfaceDevice.current().play(.notification); finDescanso = nil }
        }
    }
    func saltarDescanso() { finDescanso = nil }

    func terminar() async {
        activo = false; finDescanso = nil
        await motor.terminar()
    }
}
