import Foundation

/// Datos de ejemplo deterministas para pruebas de UI (`-DatosSuenoFake`) y unitarias. No toca HealthKit.
struct ProveedorSaludFalso: ProveedorSalud {
    var disponible = true
    var sueno: [MuestraSueno]?
    var pesosFalsos: [(dia: Date, kg: Double)] = []
    var ahora = Date()
    var cal = Calendar.current

    func pedirPermisoSiHaceFalta() async {}
    func pesos(desde: Date, hasta: Date, cal: Calendar) async -> [(dia: Date, kg: Double)] { pesosFalsos }

    func muestrasSueno(desde: Date, hasta: Date) async -> [MuestraSueno] {
        if let s = sueno { return s }
        var out: [MuestraSueno] = []
        let hoy = cal.startOfDay(for: ahora)
        for i in 0..<10 {
            // Se durmió entre 22:45 y 23:25 la noche anterior al día i.
            let dia = cal.date(byAdding: .day, value: -i, to: hoy)!
            let dormir = cal.date(byAdding: .minute, value: 22 * 60 + 45 + (i * 13) % 40, to: cal.date(byAdding: .day, value: -1, to: dia)!)!
            var t = dormir
            func tramo(_ min: Double, _ e: EtapaSueno, _ f: String = "watch") { out.append(MuestraSueno(inicio: t, fin: t.addingTimeInterval(min * 60), etapa: e, fuente: f)); t = t.addingTimeInterval(min * 60) }
            tramo(5, .despierto); tramo(80, .nucleo); tramo(45, .profundo); tramo(15, .nucleo); tramo(25, .rem)
            tramo(3, .despierto); tramo(70, .nucleo); tramo(20, .profundo); tramo(30, .rem); tramo(60, .nucleo); tramo(40, .rem); tramo(60, .nucleo)
            // El iPhone grabó "en cama" y "dormido" sin etapas encima: no debe duplicar el tiempo.
            out.append(MuestraSueno(inicio: dormir.addingTimeInterval(-20 * 60), fin: t, etapa: .enCama, fuente: "iphone"))
            out.append(MuestraSueno(inicio: dormir, fin: t, etapa: .sinEtapa, fuente: "iphone"))
        }
        // Una siesta de ayer por la tarde (40 min).
        let siesta = cal.date(byAdding: .hour, value: 15, to: cal.date(byAdding: .day, value: -1, to: hoy)!)!
        out.append(MuestraSueno(inicio: siesta, fin: siesta.addingTimeInterval(40 * 60), etapa: .nucleo, fuente: "watch"))
        return out
    }

    func metricas(desde: Date, hasta: Date, cal: Calendar) async -> [DatosMetricaDia] {
        var out: [DatosMetricaDia] = []
        let hoy = cal.startOfDay(for: ahora)
        for i in 0..<14 {
            let d = Double(i)
            let pasos: Double = 7000 + Double(i * 311 % 3000)
            let energia: Double = 420 + Double(i * 17 % 150)
            out.append(DatosMetricaDia(dia: cal.date(byAdding: .day, value: -i, to: hoy)!,
                                       fcReposo: 56 + Double(i % 4), hrv: 55 - Double(i % 5) * 2, pasos: pasos + d, energia: energia))
        }
        return out
    }
}
