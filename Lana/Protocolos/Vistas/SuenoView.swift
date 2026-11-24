import SwiftUI

struct SuenoView: View {
    @ObservedObject var salud: SaludService
    @AppStorage(Rampa.llaveSemana) private var semana = 1
    @AppStorage(Rampa.llaveRecordatorios) private var recordatorios = false

    /// Qué tan dispersa fue tu hora de dormir en las últimas noches, en minutos.
    private var variacionMinutos: Int? {
        let minutos = salud.noches.prefix(7).map { n -> Double in
            let c = Calendar.current.dateComponents([.hour, .minute], from: n.dormido)
            let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            return m < 12 * 60 ? m + 1440 : m   // 1 am cuenta como 25:00
        }
        guard minutos.count >= 3 else { return nil }
        let media = minutos.reduce(0, +) / Double(minutos.count)
        let varianza = minutos.reduce(0) { $0 + pow($1 - media, 2) } / Double(minutos.count)
        return Int(varianza.squareRoot().rounded())
    }

    var body: some View {
        List {
            Section {
                ForEach(Rampa.pasos) { p in
                    HStack {
                        Text("Semana \(p.semana)").fontWeight(p.semana == semana ? .bold : .regular)
                        Spacer()
                        Text("\(horaTexto(minutos: p.despertar)) · \(horaTexto(minutos: p.dormir))")
                            .foregroundStyle(.secondary)
                        if p.semana == semana { Image(systemName: "checkmark").foregroundStyle(.green) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { cambiarSemana(p.semana) }
                }
            } header: {
                Text("Rampa (despertar · dormir)")
            } footer: {
                Text("Toca para cambiar de semana. No avances hasta lograr dormirte a tiempo la semana actual.")
            }

            Section("Últimas noches") {
                if salud.noches.isEmpty {
                    Text("Sin datos. Revisa Ajustes → Salud → Acceso a datos → Lana.").foregroundStyle(.secondary)
                }
                ForEach(salud.noches.prefix(7)) { n in
                    HStack {
                        Text(n.despierto.formatted(.dateTime.weekday(.abbreviated).day()))
                        Spacer()
                        Text("\(n.dormido.formatted(date: .omitted, time: .shortened)) → \(n.despierto.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f h", n.horas)).fontWeight(.semibold)
                    }
                }
                if let v = variacionMinutos {
                    LabeledContent("Variación de hora de dormir", value: "±\(v) min")
                }
            }

            Section {
                Toggle("Recordatorios", isOn: $recordatorios)
                    .onChange(of: recordatorios) { _, activo in
                        Task {
                            if activo { await Recordatorios.programar(paso: Rampa.paso(semana)) }
                            else { await Recordatorios.apagar() }
                        }
                    }
            } footer: {
                Text("Despertar, gym, corte de cafeína, cena, estudio, modo fin de día y hora de dormir, según la semana de la rampa.")
            }

            Section {
                Text("Si te sigue costando dormir tras varias semanas de buenos hábitos, consulta a un médico.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func cambiarSemana(_ nueva: Int) {
        semana = nueva
        if recordatorios { Task { await Recordatorios.programar(paso: Rampa.paso(nueva)) } }
    }
}
