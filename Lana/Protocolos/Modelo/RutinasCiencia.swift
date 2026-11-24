import Foundation

// Rutina torso/pierna de 4 días, basada en la investigación (ver docs del proyecto). Series, reps, RIR y descanso por ejercicio.
struct ItemPlan: Codable { var series: Int; var reps: String; var rir: String; var descanso: Int; var grupo: String
    var rpe: String? = nil; var tecnica: String? = nil; var calentamiento: String? = nil }

extension Biblioteca {
    static let rutinasCiencia: [(nombre: String, dia: String, items: [(String, ItemPlan)])] = [
        ("Torso A", "Lunes", [
            ("Press inclinado con mancuernas", ItemPlan(series: 3, reps: "6-10", rir: "1-2", descanso: 150, grupo: "Pecho")),
            ("Jalón al pecho agarre prono", ItemPlan(series: 3, reps: "8-12", rir: "1-2", descanso: 120, grupo: "Espalda")),
            ("Remo en máquina con pecho apoyado", ItemPlan(series: 3, reps: "8-12", rir: "1-2", descanso: 120, grupo: "Espalda")),
            ("Press de hombro sentado", ItemPlan(series: 2, reps: "8-12", rir: "1-2", descanso: 120, grupo: "Hombro")),
            ("Extensión de tríceps sobre la cabeza en polea", ItemPlan(series: 3, reps: "10-15", rir: "0-1", descanso: 90, grupo: "Tríceps")),
            ("Curl inclinado con mancuernas", ItemPlan(series: 3, reps: "10-15", rir: "0-1", descanso: 90, grupo: "Bíceps")),
            ("Elevaciones laterales en polea", ItemPlan(series: 3, reps: "12-20", rir: "0-1", descanso: 60, grupo: "Hombro"))
        ]),
        ("Pierna A", "Martes", [
            ("Sentadilla hack", ItemPlan(series: 3, reps: "6-10", rir: "1-2", descanso: 150, grupo: "Cuádriceps")),
            ("Peso muerto rumano", ItemPlan(series: 3, reps: "6-10", rir: "1-2", descanso: 150, grupo: "Isquios")),
            ("Curl femoral sentado", ItemPlan(series: 3, reps: "8-12", rir: "0-1", descanso: 90, grupo: "Isquios")),
            ("Extensión de cuádriceps", ItemPlan(series: 2, reps: "10-15", rir: "0-1", descanso: 90, grupo: "Cuádriceps")),
            ("Elevación de talones de pie en máquina", ItemPlan(series: 4, reps: "8-12", rir: "0-1", descanso: 90, grupo: "Pantorrilla")),
            ("Crunch en polea", ItemPlan(series: 2, reps: "10-15", rir: "1-2", descanso: 60, grupo: "Core"))
        ]),
        ("Torso B", "Jueves", [
            ("Press plano con mancuernas", ItemPlan(series: 3, reps: "8-12", rir: "1-2", descanso: 150, grupo: "Pecho")),
            ("Remo con barra", ItemPlan(series: 3, reps: "8-12", rir: "1-2", descanso: 120, grupo: "Espalda")),
            ("Jalón al pecho agarre neutro", ItemPlan(series: 3, reps: "8-12", rir: "1-2", descanso: 120, grupo: "Espalda")),
            ("Aperturas en polea cruzada", ItemPlan(series: 2, reps: "10-15", rir: "0-1", descanso: 75, grupo: "Pecho")),
            ("Elevaciones laterales con mancuernas", ItemPlan(series: 3, reps: "12-20", rir: "0-1", descanso: 60, grupo: "Hombro")),
            ("Jalón de tríceps con cuerda", ItemPlan(series: 3, reps: "10-15", rir: "0-1", descanso: 75, grupo: "Tríceps")),
            ("Curl predicador", ItemPlan(series: 4, reps: "8-12", rir: "0-1", descanso: 75, grupo: "Bíceps")),
            ("Pájaros en máquina", ItemPlan(series: 2, reps: "12-20", rir: "0-1", descanso: 60, grupo: "Hombro"))
        ]),
        ("Pierna B", "Viernes", [
            ("Prensa de piernas 45 grados", ItemPlan(series: 3, reps: "8-12", rir: "1-2", descanso: 150, grupo: "Cuádriceps")),
            ("Hip thrust", ItemPlan(series: 3, reps: "8-12", rir: "1-2", descanso: 120, grupo: "Glúteo")),
            ("Curl femoral acostado", ItemPlan(series: 3, reps: "8-12", rir: "0-1", descanso: 90, grupo: "Isquios")),
            ("Sentadilla búlgara", ItemPlan(series: 2, reps: "8-12", rir: "1-2", descanso: 120, grupo: "Glúteo")),
            ("Elevación de talones sentado", ItemPlan(series: 3, reps: "10-15", rir: "0-1", descanso: 75, grupo: "Pantorrilla")),
            ("Elevación de piernas colgado", ItemPlan(series: 2, reps: "10-15", rir: "1-2", descanso: 60, grupo: "Core"))
        ])
    ]
}
