import Foundation
import UserNotifications

/// Notificaciones locales de los protocolos. Todas llevan el prefijo
/// "protocolos." para poder reprogramarlas sin tocar otras.
enum Recordatorios {
    private static let prefijo = "protocolos."

    static func programar(paso: PasoRampa) async {
        let centro = UNUserNotificationCenter.current()
        guard (try? await centro.requestAuthorization(options: [.alert, .sound])) == true else { return }
        await apagar()

        let entreSemana = [2, 3, 4, 5, 6]
        let gym = [2, 3, 5, 6]
        let cena = 18 * 60 + 30

        let lista: [(String, String, String, Int, [Int]?)] = [
            ("despertar", "Buenos días", "Luz fuerte y agua. Hoy toca despertar a las \(horaTexto(minutos: paso.despertar)).", paso.despertar, nil),
            ("gym", "Gym", "Sal al gym: tu bloque de fuerza de hoy.", paso.despertar + 30, gym),
            ("cafeina", "Corte de cafeína", "Ya no más cafeína si quieres dormir a las \(horaTexto(minutos: paso.dormir)).", paso.dormir - 10 * 60, nil),
            ("cena", "Cena", "Hora de cenar: última comida ~3 h antes de dormir.", cena, nil),
            ("estudio", "Bloque de estudio", "AI/ML: arranca tu bloque de 2 h.", 18 * 60 + 45, entreSemana),
            ("findia", "Modo fin de día", "Pantallas fuera. Cuarto fresco y oscuro.", paso.dormir - 60, nil),
            ("dormir", "A dormir", "Hora de acostarte.", paso.dormir, nil)
        ]

        for (id, titulo, cuerpo, minutos, dias) in lista {
            let contenido = UNMutableNotificationContent()
            contenido.title = titulo
            contenido.body = cuerpo
            contenido.sound = .default

            let m = ((minutos % 1440) + 1440) % 1440
            // Si el recordatorio cruza la medianoche, el día de la semana no aplica.
            let aplicaDias = minutos >= 0 && minutos < 1440 ? dias : nil
            for dia in aplicaDias ?? [0] {
                var partes = DateComponents(hour: m / 60, minute: m % 60)
                if dia != 0 { partes.weekday = dia }
                let disparador = UNCalendarNotificationTrigger(dateMatching: partes, repeats: true)
                try? await centro.add(UNNotificationRequest(identifier: "\(prefijo)\(id).\(dia)",
                                                            content: contenido, trigger: disparador))
            }
        }
    }

    static func apagar() async {
        let centro = UNUserNotificationCenter.current()
        let ids = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefijo) }
        centro.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Descanso entre series

    static func avisarDescanso(en segundos: Int) {
        let centro = UNUserNotificationCenter.current()
        Task {
            _ = try? await centro.requestAuthorization(options: [.alert, .sound])
            let c = UNMutableNotificationContent()
            c.title = "Descanso terminado"
            c.body = "A la siguiente serie."
            c.sound = .default
            let t = UNTimeIntervalNotificationTrigger(timeInterval: max(1, Double(segundos)), repeats: false)
            try? await centro.add(UNNotificationRequest(identifier: "\(prefijo)descanso", content: c, trigger: t))
        }
    }

    static func cancelarDescanso() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(prefijo)descanso"])
    }
}
