import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

/// Estado del reloj: último resumen del iPhone + cola offline de comandos.
@MainActor
final class ModeloWatch: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var resumen: ResumenWatch
    @Published private(set) var pendientes: [ComandoWatch]
    @Published var suenoHoras: Double?
    @Published var aviso: String?

    private let cola = ColaWatch()
    private var enviadosPorUserInfo = Set<String>()
    private let almacen = HKHealthStore()
    private static let llaveResumen = "watch.resumen"

    override init() {
        resumen = UserDefaults.standard.data(forKey: Self.llaveResumen).flatMap { try? JSONDecoder().decode(ResumenWatch.self, from: $0) } ?? ResumenWatch()
        pendientes = ColaWatch().pendientes
        super.init()
    }

    // MARK: Derivados (resumen del iPhone + lo que aún no confirmó)

    private func suma(_ tool: String, _ clave: String) -> Double {
        pendientes.filter { $0.tool == tool }.reduce(0) { if case .num(let v)? = $1.args[clave] { $0 + v } else { $0 } }
    }
    var aguaMostrada: Double { resumen.aguaMl + suma("log_water", "ml") }
    var hayAguaPendiente: Bool { pendientes.contains { $0.tool == "log_water" } }
    var rutinaHoy: String? { resumen.rutina }

    // MARK: Arranque

    func arrancar() async {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        await cargarSueno()
    }

    func cargarSueno() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let tipo = HKCategoryType(.sleepAnalysis)
        try? await almacen.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [tipo, HKQuantityType(.heartRate)])
        let cal = Calendar.current
        let desde = cal.date(byAdding: .hour, value: -18, to: cal.startOfDay(for: Date())) ?? Date()
        let muestras: [HKCategorySample] = await withCheckedContinuation { c in
            almacen.execute(HKSampleQuery(sampleType: tipo, predicate: HKQuery.predicateForSamples(withStart: desde, end: Date()),
                                          limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, _ in c.resume(returning: (r as? [HKCategorySample]) ?? []) })
        }
        let dormido: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM].map(\.rawValue).reduce(into: []) { $0.insert($1) }
        let h = Sueno.horas(muestras.filter { dormido.contains($0.value) }.map { ($0.startDate, $0.endDate) })
        suenoHoras = h > 0 ? h : nil
    }

    // MARK: Enviar

    /// Encola (persistente) y trata de enviar. false si el comando es inválido o la cola está llena.
    @discardableResult
    func enviar(_ c: ComandoWatch) -> Bool {
        guard cola.encolar(c) else { aviso = c.validar() ?? "Cola llena: abre Lana en el iPhone"; return false }
        pendientes = cola.pendientes
        vaciar()
        return true
    }

    /// Quita el último +agua que aún no llegó al iPhone (el iPhone solo agrega; no se puede borrar de lejos).
    func deshacerAgua() {
        guard let c = pendientes.last(where: { $0.tool == "log_water" }) else { return }
        cola.confirmar([c.id]); pendientes = cola.pendientes
    }

    func vaciar() {
        guard WCSession.default.activationState == .activated else { return }
        for c in cola.pendientes {
            guard let d = try? JSONEncoder().encode(c) else { continue }
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(["cmd": d], replyHandler: { [weak self] _ in Task { @MainActor in self?.confirmar([c.id]) } }, errorHandler: nil)
            } else if enviadosPorUserInfo.insert(c.id).inserted {
                WCSession.default.transferUserInfo(["cmd": d])   // el iPhone deduplica por id; el ack llega en el resumen
            }
        }
    }

    private func confirmar(_ ids: [String]) { cola.confirmar(ids); pendientes = cola.pendientes }

    private func recibir(_ ctx: [String: Any]) {
        guard let d = ctx["resumen"] as? Data, let r = try? JSONDecoder().decode(ResumenWatch.self, from: d) else { return }
        resumen = r
        UserDefaults.standard.set(d, forKey: Self.llaveResumen)
        confirmar(r.aplicados)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ s: WCSession, activationDidCompleteWith st: WCSessionActivationState, error: Error?) {
        let ctx = s.receivedApplicationContext
        Task { @MainActor in
            self.recibir(ctx); self.vaciar()
            if s.isReachable { s.sendMessage(["pedir": true], replyHandler: { _ in }, errorHandler: nil) }
        }
    }
    nonisolated func session(_ s: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        nonisolated(unsafe) let c = ctx
        Task { @MainActor in self.recibir(c) }
    }
    nonisolated func sessionReachabilityDidChange(_ s: WCSession) { Task { @MainActor in self.vaciar() } }
}
