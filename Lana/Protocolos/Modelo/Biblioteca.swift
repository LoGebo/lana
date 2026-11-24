import Foundation
import SwiftData

/// Datos iniciales de Protocolos. Todo es editable y se siembra una sola vez.
enum Biblioteca {
    static let ejercicios: [(String, String)] = [
        ("Press de banca con barra", "Pecho"), ("Press inclinado con mancuernas", "Pecho"),
        ("Press de banca con mancuernas", "Pecho"), ("Aperturas en polea", "Pecho"),
        ("Fondos en paralelas", "Pecho"), ("Press en máquina de pecho", "Pecho"),
        ("Dominadas", "Espalda"), ("Jalón al pecho", "Espalda"), ("Remo con barra", "Espalda"),
        ("Remo con mancuerna", "Espalda"), ("Remo en polea baja", "Espalda"), ("Peso muerto", "Espalda"),
        ("Face pull", "Hombro"), ("Press militar con barra", "Hombro"), ("Press militar con mancuernas", "Hombro"),
        ("Elevaciones laterales", "Hombro"), ("Pájaros con mancuernas", "Hombro"),
        ("Curl con barra", "Bíceps"), ("Curl con mancuernas", "Bíceps"), ("Curl martillo", "Bíceps"), ("Curl predicador", "Bíceps"),
        ("Extensión de tríceps en polea", "Tríceps"), ("Press francés", "Tríceps"), ("Fondos en banco", "Tríceps"),
        ("Sentadilla con barra", "Cuádriceps"), ("Prensa de pierna", "Cuádriceps"), ("Extensión de cuádriceps", "Cuádriceps"),
        ("Sentadilla búlgara", "Cuádriceps"), ("Zancadas", "Cuádriceps"), ("Sentadilla hack", "Cuádriceps"),
        ("Peso muerto rumano", "Isquios"), ("Curl femoral acostado", "Isquios"), ("Curl femoral sentado", "Isquios"),
        ("Hip thrust", "Glúteo"), ("Abducción en máquina", "Glúteo"),
        ("Elevación de talones de pie", "Pantorrilla"), ("Elevación de talones sentado", "Pantorrilla"),
        ("Crunch en polea", "Core"), ("Plancha", "Core"), ("Elevación de piernas colgado", "Core")
    ]

    /// Rutinas que traía la versión anterior (para actualizarlas solo si no las has tocado).
    static let rutinasViejas: [String: String] = [
        "Torso A": "Press de banca con barra|Remo con barra|Press militar con mancuernas|Jalón al pecho|Elevaciones laterales|Curl con barra|Extensión de tríceps en polea",
        "Pierna A": "Sentadilla con barra|Peso muerto rumano|Prensa de pierna|Curl femoral acostado|Elevación de talones de pie|Crunch en polea",
        "Torso B": "Press inclinado con mancuernas|Dominadas|Remo con mancuerna|Fondos en paralelas|Face pull|Curl martillo",
        "Pierna B": "Peso muerto|Sentadilla búlgara|Hip thrust|Extensión de cuádriceps|Curl femoral sentado|Elevación de talones sentado"
    ]

    /// Valores aproximados (tablas tipo USDA) por la porción indicada. Edítalos si tu marca es distinta.
    static let alimentos: [(String, String, Double, Double, Double, Double)] = [
        ("Pechuga de pollo cocida", "100 g", 165, 31, 0, 3.6),
        ("Huevo entero", "1 pieza", 72, 6.3, 0.4, 4.8),
        ("Arroz blanco cocido", "100 g", 130, 2.7, 28, 0.3),
        ("Avena cruda", "100 g", 389, 16.9, 66, 6.9),
        ("Plátano", "1 mediano", 105, 1.3, 27, 0.4),
        ("Leche entera", "1 taza", 149, 7.7, 11.7, 7.9),
        ("Proteína whey", "1 scoop", 120, 24, 3, 1.5),
        ("Tortilla de maíz", "1 pieza", 57, 1.4, 12, 0.7),
        ("Frijoles cocidos", "100 g", 127, 8.7, 22.8, 0.5),
        ("Aguacate", "100 g", 160, 2, 8.5, 14.7),
        ("Atún en agua", "100 g", 116, 25.5, 0, 0.8),
        ("Carne molida de res cocida", "100 g", 217, 26, 0, 12),
        ("Yogurt griego natural", "100 g", 59, 10, 3.6, 0.4),
        ("Pan de caja", "1 rebanada", 79, 2.7, 14.3, 1),
        ("Crema de cacahuate", "1 cda", 94, 3.6, 3.2, 8),
        ("Papa cocida", "100 g", 87, 1.9, 20, 0.1),
        ("Camote cocido", "100 g", 90, 2, 21, 0.2),
        ("Salmón cocido", "100 g", 206, 22, 0, 12),
        ("Almendras", "28 g", 164, 6, 6, 14.2),
        ("Manzana", "1 mediana", 95, 0.5, 25, 0.3),
        ("Pasta cocida", "100 g", 158, 5.8, 31, 0.9)
    ]

    /// Ejercicios de las rutinas nuevas que aún no estén en la biblioteca.
    @MainActor
    static func asegurarEjercicios(_ contexto: ModelContext) {
        let existentes = Set(((try? contexto.fetch(FetchDescriptor<EjercicioDef>())) ?? []).map(\.nombre))
        for r in rutinasCiencia {
            for (n, p) in r.items where !existentes.contains(n) {
                contexto.insert(EjercicioDef(nombre: n, grupo: p.grupo))
            }
        }
    }

    @MainActor
    static func sembrarSiHaceFalta(_ contexto: ModelContext) {
        let d = UserDefaults.standard

        if !d.bool(forKey: "protocolos.semilla.v1") {
            for (n, g) in ejercicios { contexto.insert(EjercicioDef(nombre: n, grupo: g)) }
            for a in alimentos {
                contexto.insert(Alimento(nombre: a.0, porcion: a.1, kcal: a.2, proteina: a.3, carbs: a.4, grasa: a.5))
            }
            d.set(true, forKey: "protocolos.semilla.v1")
        }

        // v2: rutina basada en investigación + ejercicios nuevos + ~200 alimentos USDA.
        if !d.bool(forKey: "protocolos.semilla.v2") {
            asegurarEjercicios(contexto)
            try? contexto.save()
            let rutinas = (try? contexto.fetch(FetchDescriptor<Rutina>())) ?? []
            for (i, nueva) in rutinasCiencia.enumerated() {
                let plan = Dictionary(uniqueKeysWithValues: nueva.items.map { ($0.0, $0.1) })
                let nombres = nueva.items.map(\.0)
                if let r = rutinas.first(where: { $0.nombre == nueva.nombre }) {
                    // Solo la reemplazo si sigue igual que la que traía la app.
                    if r.ejerciciosRaw == rutinasViejas[nueva.nombre] || r.ejerciciosRaw.isEmpty {
                        r.ejercicios = nombres; r.plan = plan
                    }
                } else if rutinas.isEmpty || !rutinas.contains(where: { $0.nombre == nueva.nombre }) {
                    let r = Rutina(nombre: nueva.nombre, ejercicios: nombres, orden: i)
                    r.plan = plan
                    contexto.insert(r)
                }
            }
            let tiene = Set(((try? contexto.fetch(FetchDescriptor<Alimento>())) ?? []).map { $0.nombre.lowercased() })
            for a in alimentosUSDA where !tiene.contains(a.0.lowercased()) {
                contexto.insert(Alimento(nombre: a.0, porcion: a.1, kcal: a.2, proteina: a.3, carbs: a.4, grasa: a.5))
            }
            d.set(true, forKey: "protocolos.semilla.v2")
        }
        try? contexto.save()
    }
}
