import Foundation
import SwiftData
import WatchConnectivity

/// Puente con el Apple Watch: recibe comandos (idempotentes, por id) y publica el resumen del día.
@MainActor
final class PuenteWatch: NSObject, WCSessionDelegate {
    static let shared = PuenteWatch()
    private var sesion: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func iniciar() { sesion?.delegate = self; sesion?.activate() }

    // MARK: Resumen

    static func construirResumen(finanzas: ModelContext, protocolos: ModelContext, defaults: UserDefaults = .standard, hoy: Date = Date()) -> ResumenWatch {
        let dia = Calendar.current.startOfDay(for: hoy)
        var r = ResumenWatch(dia: dia)
        let comidas = ((try? protocolos.fetch(FetchDescriptor<ComidaLog>())) ?? []).filter { $0.dia == dia }
        r.kcal = comidas.reduce(0) { $0 + $1.kcalTotal }
        r.proteina = comidas.reduce(0) { $0 + $1.proteinaTotal }
        r.kcalMeta = defaults.double(forKey: LlavesMetas.kcal)
        r.proteinaMeta = defaults.double(forKey: LlavesMetas.proteina)
        r.aguaMl = ((try? protocolos.fetch(FetchDescriptor<AguaLog>())) ?? []).filter { $0.dia == dia }.reduce(0) { $0 + $1.ml }
        if defaults.object(forKey: LlavesMetas.agua) != nil { r.aguaMeta = defaults.double(forKey: LlavesMetas.agua) }
        r.pesoKg = ((try? protocolos.fetch(FetchDescriptor<PesoLog>())) ?? []).max { $0.dia < $1.dia }?.kg
        r.categorias = ((try? finanzas.fetch(FetchDescriptor<Categoria>())) ?? [])
            .filter { !$0.esIngreso }.sorted { $0.orden < $1.orden }.prefix(8).map(\.nombre)
        if let nombre = Programa.rutinaDe(hoy),
           let rut = ((try? protocolos.fetch(FetchDescriptor<Rutina>())) ?? []).first(where: { $0.nombre == nombre }) {
            r.rutina = rut.nombre
            let sesiones = ((try? protocolos.fetch(FetchDescriptor<SesionGym>())) ?? []).filter { $0.fin != nil }.sorted { $0.inicio > $1.inicio }
            r.ejercicios = rut.ejercicios.map { n in
                let p = rut.plan[n]
                let previo = sesiones.lazy.compactMap { $0.ejerciciosOrdenados.first { $0.nombre == n }?.seriesOrdenadas.last { $0.hecha }?.peso }.first ?? 0
                return EjercicioWatch(nombre: n, series: max(1, p?.series ?? 3), reps: p?.reps ?? "8-12", descanso: p?.descanso ?? 90, kgPrevio: previo)
            }
        }
        r.aplicados = Array((defaults.stringArray(forKey: AplicadorAgente.llaveAplicados) ?? []).suffix(100))
        return r
    }

    func enviarResumen() {
        guard let s = sesion, s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let r = Self.construirResumen(finanzas: ContenedorLana.compartido.mainContext, protocolos: ContenedorProtocolos.compartido.mainContext)
        if let d = try? JSONEncoder().encode(r) { try? s.updateApplicationContext(["resumen": d]) }
    }

    // MARK: Comandos

    /// Aplica un comando del reloj. Devuelve el estado para el reply ("aplicado" | "duplicado" | "rechazado").
    func procesar(_ datos: Data) -> String {
        guard let c = try? JSONDecoder().decode(ComandoWatch.self, from: datos), c.validar() == nil else { return "rechazado" }
        let res = AplicadorAgente.aplicar(id: c.id, tool: c.tool, args: c.argsAny,
                                          finanzas: ContenedorLana.compartido.mainContext, protocolos: ContenedorProtocolos.compartido.mainContext)
        enviarResumen()
        switch res { case .aplicado: return "aplicado"; case .duplicado: return "duplicado"; case .rechazado: return "rechazado" }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.enviarResumen() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.enviarResumen() } }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let datos = message["cmd"] as? Data
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            if let d = datos { reply(["estado": self.procesar(d)]) } else { self.enviarResumen(); reply(["estado": "resumen"]) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let d = userInfo["cmd"] as? Data else { return }
        Task { @MainActor in _ = self.procesar(d) }
    }
}
