import Foundation
import SwiftData
import SwiftUI
import Security

enum ResultadoAgente: Equatable { case aplicado, duplicado, rechazado(String) }

/// Aplica un comando del agente (bajado del buzón) a las dos bases. Revalida todo: el servidor no es de confianza.
/// Solo agrega registros; nunca edita ni borra.
@MainActor
enum AplicadorAgente {
    static let llaveAplicados = "agente.aplicados"
    private static let tope = 5000 // ids recordados; ponytail: si se llena, los más viejos se olvidan (el servidor ya no los reenvía tras el ack)

    static func aplicar(id: String, tool: String, args a: [String: Any], finanzas: ModelContext, protocolos: ModelContext,
                        defaults: UserDefaults = .standard, ahora: Date = Date()) -> ResultadoAgente {
        var vistos = defaults.stringArray(forKey: llaveAplicados) ?? []
        if vistos.contains(id) { return .duplicado }

        func num(_ k: String) -> Double? { (a[k] as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } }
        func txt(_ k: String, _ max: Int) -> String? { (a[k] as? String).map { String($0.prefix(max)) } }
        var fecha = ahora
        if let s = a["occurred_at"] as? String {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let d = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return .rechazado("fecha inválida") }
            guard d <= ahora.addingTimeInterval(86_400) else { return .rechazado("fecha futura") }
            fecha = min(d, ahora)
        }

        switch tool {
        case "log_expense":
            guard let m = num("amount"), m > 0, m <= 50_000 else { return .rechazado("monto inválido") }
            let cuentas = (try? finanzas.fetch(FetchDescriptor<Cuenta>())) ?? []
            guard let cuenta = Preferencias.cuentaInicial(entre: cuentas) else { return .rechazado("no hay cuentas") }
            let cats = (try? finanzas.fetch(FetchDescriptor<Categoria>())) ?? []
            let cat = txt("category", 40).flatMap { n in cats.first { $0.nombre.localizedCaseInsensitiveCompare(n) == .orderedSame } }
            let origen = (a["source"] as? String) == "watch" ? "watch" : "agente"
            let nota = ["[\(origen)]", txt("note", 120)].compactMap { $0 }.joined(separator: " ")
            finanzas.insert(Movimiento(monto: m, fecha: fecha, tipo: .gasto, comercio: txt("merchant", 60) ?? "", nota: nota,
                                       cuenta: cuenta, categoria: cat, creadoPorAtajo: true))
            try? finanzas.save()
        case "log_water":
            guard let ml = num("ml"), ml >= 1, ml <= 2000 else { return .rechazado("ml inválido") }
            protocolos.insert(AguaLog(dia: fecha, ml: ml)); try? protocolos.save()
        case "log_meal":
            guard let n = txt("name", 80), !n.isEmpty, let k = num("kcal"), k >= 0, k <= 5000 else { return .rechazado("comida inválida") }
            let t = (a["meal"] as? String).flatMap(TiempoComida.init(rawValue:)) ?? .snack
            protocolos.insert(ComidaLog(dia: fecha, tiempo: t, nombre: n, porcionTexto: "1 porción", porciones: 1, kcal: k,
                                        proteina: num("protein_g") ?? 0, carbs: num("carbs_g") ?? 0, grasa: num("fat_g") ?? 0))
            try? protocolos.save()
        case "log_workout_set":
            guard let ej = txt("exercise", 60), !ej.isEmpty, let r = num("reps"), r >= 1, r <= 100, r == r.rounded(),
                  let kg = num("weight_kg"), kg >= 0, kg <= 500 else { return .rechazado("serie inválida") }
            let nombre = txt("workout_name", 60) ?? "Agente"
            let cal = Calendar.current
            let ses = ((try? protocolos.fetch(FetchDescriptor<SesionGym>())) ?? [])
                .first { $0.nombre == nombre && cal.isDate($0.inicio, inSameDayAs: fecha) }
                ?? { let s = SesionGym(nombre: nombre); s.inicio = fecha; s.fin = fecha; protocolos.insert(s); return s }()
            let log = ses.ejerciciosOrdenados.first { $0.nombre == ej }
                ?? { let e = EjercicioLog(nombre: ej, grupo: Programa.grupo(de: ej), orden: ses.ejercicios?.count ?? 0)
                     protocolos.insert(e); e.sesion = ses; return e }()
            let tipo = (a["set_type"] as? String).flatMap(TipoSerie.init(rawValue:)) ?? .normal
            let serie = Serie(orden: log.series?.count ?? 0, peso: kg, reps: Int(r), tipo: tipo)
            serie.hecha = true
            protocolos.insert(serie); serie.ejercicio = log
            try? protocolos.save()
        case "log_weight":
            guard let kg = num("kg"), Peso.registrar(kg, dia: fecha, protocolos) else { return .rechazado("peso inválido") }
        default:
            return .rechazado("herramienta desconocida")
        }
        vistos.append(id)
        defaults.set(Array(vistos.suffix(tope)), forKey: llaveAplicados)
        return .aplicado
    }
}

/// Baja comandos pendientes, los aplica y hace ack. Apagado por defecto.
@MainActor
enum SincronizadorAgente {
    static let llaveActivo = "agente.activo", llaveURL = "agente.url"

    static func guardarToken(_ t: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "lana.agente"]
        SecItemDelete(q as CFDictionary)
        if !t.isEmpty { SecItemAdd(q.merging([kSecValueData as String: Data(t.utf8)]) { $1 } as CFDictionary, nil) }
    }
    static func token() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "lana.agente",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Devuelve cuántos comandos procesó (0 si está apagado o sin red).
    @discardableResult
    static func sincronizar(finanzas: ModelContext, protocolos: ModelContext) async -> Int {
        let d = UserDefaults.standard
        guard d.bool(forKey: llaveActivo), let base = d.string(forKey: llaveURL), let tok = token(),
              let url = URL(string: base), url.scheme == "https" else { return 0 }
        func pedir(_ ruta: String, _ metodo: String, _ cuerpo: Data? = nil) async -> Data? {
            var r = URLRequest(url: url.appendingPathComponent(ruta)); r.httpMethod = metodo; r.httpBody = cuerpo; r.timeoutInterval = 15
            r.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            guard let (data, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        }
        guard let data = await pedir("app/pending", "GET"),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmds = obj["commands"] as? [[String: Any]] else { return 0 }
        var resultados: [[String: String]] = []
        for c in cmds {
            guard let id = c["id"] as? String, let tool = c["tool"] as? String, let args = c["args"] as? [String: Any] else { continue }
            switch AplicadorAgente.aplicar(id: id, tool: tool, args: args, finanzas: finanzas, protocolos: protocolos) {
            case .aplicado, .duplicado: resultados.append(["id": id, "status": "applied"])
            case .rechazado(let why): resultados.append(["id": id, "status": "rejected", "reason": why])
            }
        }
        if !resultados.isEmpty, let body = try? JSONSerialization.data(withJSONObject: ["results": resultados]) {
            _ = await pedir("app/ack", "POST", body)
        }
        return resultados.count
    }
}

struct AjustesAgenteView: View {
    @AppStorage(SincronizadorAgente.llaveActivo) private var activo = false
    @AppStorage(SincronizadorAgente.llaveURL) private var url = ""
    @State private var token = SincronizadorAgente.token() ?? ""
    var body: some View {
        Form {
            Section {
                Toggle("Recibir registros del agente", isOn: $activo)
                TextField("https://…workers.dev", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Token de la app", text: $token).onChange(of: token) { _, t in SincronizadorAgente.guardarToken(t) }
            } footer: { Text("El agente solo puede agregar gastos, agua, comidas y series; nunca editar ni borrar. Los gastos llevan [agente] en la nota para que los puedas revisar.") }
        }
        .navigationTitle("Agente")
    }
}
