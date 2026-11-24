import Foundation
import SwiftData

/// Un hábito marcado como hecho en un día. Si existe la fila, está hecho.
@Model
final class HabitoLog {
    var id: UUID = UUID()
    /// Inicio del día (00:00) al que pertenece.
    var dia: Date = Date()
    var clave: String = ""

    init(dia: Date, clave: String) {
        self.id = UUID()
        self.dia = dia
        self.clave = clave
    }
}

/// Base propia de Protocolos: archivo aparte, no toca la de finanzas.
enum ContenedorProtocolos {
    static let compartido: ModelContainer = {
        let esquema = Schema([HabitoLog.self, EjercicioDef.self, Rutina.self, SesionGym.self, EjercicioLog.self, Serie.self,
                               Alimento.self, ComidaLog.self, AguaLog.self, PesoLog.self, NocheSueno.self, MetricaDia.self])
        let config = ModelConfiguration("Protocolos", schema: esquema)
        do {
            return try ModelContainer(for: esquema, configurations: config)
        } catch {
            fatalError("No se pudo abrir la base de Protocolos: \(error)")
        }
    }()
}

// MARK: - Hábitos del checklist

enum Habito: String, CaseIterable, Identifiable {
    case luz, agua, cafeina, pantallas, suplementos, estudio, gym, comidas

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .luz: "Luz al despertar"
        case .agua: "Agua"
        case .cafeina: "Cafeína dentro del corte"
        case .pantallas: "Pantallas apagadas a tiempo"
        case .suplementos: "Suplementos"
        case .estudio: "Estudio AI/ML (2 h)"
        case .gym: "Gym"
        case .comidas: "4 comidas con proteína"
        }
    }

    var icono: String {
        switch self {
        case .luz: "sun.max.fill"
        case .agua: "drop.fill"
        case .cafeina: "cup.and.saucer.fill"
        case .pantallas: "iphone.slash"
        case .suplementos: "pills.fill"
        case .estudio: "brain.head.profile"
        case .gym: "dumbbell.fill"
        case .comidas: "fork.knife"
        }
    }

    /// Gym lunes, martes, jueves, viernes (y sábado si el programa de 5 días está activo).
    func aplica(en fecha: Date, calendario: Calendar = .current) -> Bool {
        guard self == .gym else { return true }
        let d = calendario.component(.weekday, from: fecha)
        return [2, 3, 5, 6].contains(d) || (d == 7 && Programa.semana > 0)
    }
}

// MARK: - Rampa de sueño

struct PasoRampa: Identifiable {
    let semana: Int
    /// Minutos desde medianoche.
    let despertar: Int
    let dormir: Int
    var id: Int { semana }
}

enum Rampa {
    static let pasos = [
        PasoRampa(semana: 1, despertar: 7 * 60 + 30, dormir: 23 * 60),
        PasoRampa(semana: 2, despertar: 6 * 60 + 45, dormir: 22 * 60 + 30),
        PasoRampa(semana: 3, despertar: 6 * 60, dormir: 22 * 60),
        PasoRampa(semana: 4, despertar: 5 * 60 + 15, dormir: 21 * 60 + 30)
    ]

    static func paso(_ semana: Int) -> PasoRampa {
        pasos.first { $0.semana == semana } ?? pasos[0]
    }

    static let llaveSemana = "protocolos.semana"
    static let llaveRecordatorios = "protocolos.recordatorios"
}

func horaTexto(minutos: Int) -> String {
    let m = ((minutos % 1440) + 1440) % 1440
    let h12 = m / 60 % 12 == 0 ? 12 : m / 60 % 12
    return String(format: "%d:%02d %@", h12, m % 60, m / 60 < 12 ? "am" : "pm")
}
