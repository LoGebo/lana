import SwiftUI
import SwiftData
import Charts

struct TarjetaPeso: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \PesoLog.dia) private var logs: [PesoLog]
    @AppStorage(LlavesMetas.kcal) private var metaKcal: Double = 0
    @State private var texto = ""
    @State private var error = false

    private var datos: [(dia: Date, kg: Double)] { logs.map { ($0.dia, $0.kg) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Peso").font(.headline)
                Spacer()
                if let u = logs.last { Text(String(format: "%.1f kg", u.kg)).font(.title3.weight(.bold)) }
            }
            if logs.count >= 2 {
                Chart(logs.suffix(60)) { LineMark(x: .value("Día", $0.dia), y: .value("kg", $0.kg)).interpolationMethod(.monotone)
                    PointMark(x: .value("Día", $0.dia), y: .value("kg", $0.kg)) }
                    .chartYScale(domain: .automatic(includesZero: false)).frame(height: 110)
            }
            if let t = Peso.tendenciaSemanal(datos), let u = logs.last {
                let s = Peso.sugerencia(kgPorSemana: t, pesoActual: u.kg)
                Text(s.texto + (s.kcal == 0 ? "" : " Tu meta pasaría a \(Int(metaKcal) + s.kcal) kcal."))
                    .font(.caption).foregroundStyle(.secondary)
                if s.kcal != 0 && metaKcal > 0 { Button("Aplicar ajuste") { metaKcal += Double(s.kcal) }.font(.caption.weight(.semibold)) }
            } else {
                Text("Pésate en ayunas 3+ veces por semana: con 5 días de datos te digo la tendencia.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("kg de hoy", text: $texto).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                Button("Guardar") {
                    if let v = Double(texto.replacingOccurrences(of: ",", with: ".")), Peso.registrar(v, contexto) { texto = ""; error = false } else { error = true }
                }.buttonStyle(.borderedProminent).tint(.green)
            }
            if error { Text("Escribe un peso válido (30-250 kg).").font(.caption).foregroundStyle(.red) }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
