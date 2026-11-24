import SwiftUI
import SwiftData
import Charts

struct AroPuntaje: View {
    let total: Int
    private var color: Color { total >= 80 ? .green : (total >= 60 ? .yellow : .orange) }
    var body: some View {
        ZStack {
            Circle().stroke(Color(.systemFill), lineWidth: 8)
            Circle().trim(from: 0, to: Double(total) / 100).stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(total)").font(.title2.weight(.bold).monospacedDigit())
                Text("de 100").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Puntaje de sueño \(total) de 100")
        .accessibilityIdentifier("sueno.puntaje")
    }
}

/// Hipnograma tipo Apple Sleep: una fila por etapa a lo largo de la noche.
struct HipnogramaView: View {
    let noche: ResumenNoche
    private let filas = ["Despierto", "REM", "Núcleo", "Profundo"]
    var body: some View {
        Chart(noche.segmentos.filter { $0.etapa != .sinEtapa }, id: \.self) { s in
            RectangleMark(xStart: .value("Inicio", s.inicio), xEnd: .value("Fin", s.fin), y: .value("Etapa", s.etapa.nombre), height: 14)
                .foregroundStyle(s.etapa.color).cornerRadius(3)
        }
        .chartYScale(domain: filas)
        .chartYAxis { AxisMarks(preset: .aligned, position: .leading) { AxisValueLabel().font(.caption2) } }
        .chartXScale(domain: noche.dormido...noche.despierto)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.hour()) } }
        .frame(height: 120)
        .accessibilityLabel("Hipnograma de la noche")
    }
}

/// Barra apilada con minutos y porcentaje por etapa.
struct EtapasBarra: View {
    let noche: ResumenNoche
    private var partes: [(EtapaSueno, Double)] {
        [(.profundo, noche.minProfundo), (.nucleo, noche.minNucleo), (.rem, noche.minREM), (.despierto, noche.minDespierto)].filter { $0.1 > 0 }
    }
    var body: some View {
        let total = max(partes.reduce(0) { $0 + $1.1 }, 1)
        VStack(spacing: 8) {
            Chart(partes, id: \.0) { e, m in
                BarMark(x: .value("min", m), y: .value("", "Noche")).foregroundStyle(e.color)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden).frame(height: 18)
            HStack {
                ForEach(partes, id: \.0) { e, m in
                    VStack(spacing: 1) {
                        HStack(spacing: 4) { Circle().fill(e.color).frame(width: 8, height: 8); Text(e.nombre).font(.caption2) }
                        Text(minutosTexto(m)).font(.caption.weight(.semibold))
                        Text("\(Int((m / total * 100).rounded())) %").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct TendenciaMini: View {
    let titulo: String
    let datos: [(Date, Double)]
    let color: Color
    var body: some View {
        if datos.count >= 2 {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.caption.weight(.medium))
                Chart(datos, id: \.0) { d, v in
                    LineMark(x: .value("Día", d, unit: .day), y: .value(titulo, v)).interpolationMethod(.monotone).foregroundStyle(color)
                    PointMark(x: .value("Día", d, unit: .day), y: .value(titulo, v)).foregroundStyle(color).symbolSize(14)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden).frame(height: 60)
            }
        }
    }
}

struct NocheManualView: View {
    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var contexto
    @State private var dormido: Date
    @State private var despierto: Date

    init() {
        // Por defecto: 8 h que terminan hoy a las 7 (o ahora, si todavía no son las 7).
        let cal = Calendar.current, ahora = Date()
        let siete = cal.date(bySettingHour: 7, minute: 0, second: 0, of: ahora) ?? ahora
        let fin = min(siete, ahora.addingTimeInterval(-300))
        _despierto = State(initialValue: fin)
        _dormido = State(initialValue: fin.addingTimeInterval(-8 * 3600))
    }

    private var error: AnalisisSueno.ErrorManual? { AnalisisSueno.validar(dormido: dormido, despierto: despierto) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Me dormí", selection: $dormido, in: ...Date())
                    DatePicker("Desperté", selection: $despierto, in: ...Date())
                } footer: {
                    if let e = error { Text(e.rawValue).foregroundStyle(.red) }
                    else { Text("Duración: \(minutosTexto(despierto.timeIntervalSince(dormido) / 60)). Si Salud tiene datos de ese día, ganan los de Salud.") }
                }
            }
            .navigationTitle("Noche manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { if (try? NocheSueno.registrarManual(dormido: dormido, despierto: despierto, contexto)) != nil { cerrar() } }
                        .disabled(error != nil).accessibilityIdentifier("sueno.guardar")
                }
            }
        }
    }
}
