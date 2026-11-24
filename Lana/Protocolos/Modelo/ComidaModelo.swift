import Foundation
import SwiftData

enum TiempoComida: String, CaseIterable, Identifiable {
    case desayuno, comida, snack, cena
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .desayuno: "Desayuno"
        case .comida: "Comida"
        case .snack: "Snack"
        case .cena: "Cena"
        }
    }
    var icono: String {
        switch self {
        case .desayuno: "sunrise.fill"
        case .comida: "sun.max.fill"
        case .snack: "carrot.fill"
        case .cena: "moon.stars.fill"
        }
    }
}

/// Un alimento guardado. Los macros son por porción.
@Model
final class Alimento {
    var id: UUID = UUID()
    var nombre: String = ""
    var porcion: String = "100 g"
    var kcal: Double = 0
    var proteina: Double = 0
    var carbs: Double = 0
    var grasa: Double = 0
    var favorito: Bool = false
    var ultimoUso: Date?

    init(nombre: String, porcion: String, kcal: Double, proteina: Double, carbs: Double, grasa: Double) {
        self.id = UUID()
        self.nombre = nombre
        self.porcion = porcion
        self.kcal = kcal
        self.proteina = proteina
        self.carbs = carbs
        self.grasa = grasa
    }
}

/// Lo que comiste. Guarda una copia de los macros por porción: si editas
/// el alimento después, tu historial no cambia.
@Model
final class ComidaLog {
    var id: UUID = UUID()
    var dia: Date = Date()
    var tiempoRaw: String = TiempoComida.desayuno.rawValue
    var nombre: String = ""
    var porcionTexto: String = ""
    var porciones: Double = 1
    var kcal: Double = 0
    var proteina: Double = 0
    var carbs: Double = 0
    var grasa: Double = 0

    var tiempo: TiempoComida {
        get { TiempoComida(rawValue: tiempoRaw) ?? .snack }
        set { tiempoRaw = newValue.rawValue }
    }
    var kcalTotal: Double { kcal * porciones }
    var proteinaTotal: Double { proteina * porciones }
    var carbsTotal: Double { carbs * porciones }
    var grasaTotal: Double { grasa * porciones }

    init(dia: Date, tiempo: TiempoComida, nombre: String, porcionTexto: String, porciones: Double,
         kcal: Double, proteina: Double, carbs: Double, grasa: Double) {
        self.id = UUID()
        self.dia = Calendar.current.startOfDay(for: dia)
        self.tiempoRaw = tiempo.rawValue
        self.nombre = nombre
        self.porcionTexto = porcionTexto
        self.porciones = porciones
        self.kcal = kcal
        self.proteina = proteina
        self.carbs = carbs
        self.grasa = grasa
    }
}

@Model
final class AguaLog {
    var id: UUID = UUID()
    var dia: Date = Date()
    var ml: Double = 0

    init(dia: Date, ml: Double) {
        self.id = UUID()
        self.dia = Calendar.current.startOfDay(for: dia)
        self.ml = ml
    }
}

struct TotalesDia {
    var kcal = 0.0, proteina = 0.0, carbs = 0.0, grasa = 0.0
    init(_ logs: [ComidaLog]) {
        for l in logs {
            kcal += l.kcalTotal; proteina += l.proteinaTotal; carbs += l.carbsTotal; grasa += l.grasaTotal
        }
    }
}

enum LlavesMetas {
    static let kcal = "protocolos.meta.kcal"
    static let proteina = "protocolos.meta.proteina"
    static let carbs = "protocolos.meta.carbs"
    static let grasa = "protocolos.meta.grasa"
    static let agua = "protocolos.meta.agua"
}
